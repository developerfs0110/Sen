# scripts/Sen.Governance.psm1 - Sen v0.5.0 Governance & State Seal Engine
$ErrorActionPreference = "Stop"
function Resolve-SenWorkspaceRoot {
[CmdletBinding()] param([string]$StartPath = $PWD.Path)
if ([string]::IsNullOrWhiteSpace($StartPath)) { return $PWD.Path }
$cur = try { [IO.Path]::GetFullPath($StartPath).TrimEnd('\', '/') } catch { <# Fallback #> $StartPath.TrimEnd('\', '/') }
if ([string]::IsNullOrWhiteSpace($cur)) { return "/" }
if ((Test-Path -LiteralPath $cur -PathType Leaf) -and ($cur -ne "/")) { $cur = Split-Path -Parent $cur }
for ($d = 0; $d -lt 12; $d++) {
if ([string]::IsNullOrWhiteSpace($cur) -or $cur -eq "/") { break }
if ((Test-Path -LiteralPath (Join-Path $cur ".agents")) -or (Test-Path -LiteralPath (Join-Path $cur "plugin.json")) -or (Test-Path -LiteralPath (Join-Path $cur ".agents-plugin/plugin.json"))) { return $cur }
$p = Split-Path -Parent $cur; if ([string]::IsNullOrWhiteSpace($p) -or $p -eq $cur -or $p -eq "/") { break }; $cur = $p
}
return $cur
}
function Test-SenSafeWorkspacePath {
[CmdletBinding()]
param([Parameter(Mandatory)][string]$TargetPath, [string[]]$WorkspaceList = @(), [string]$ToolName = "write_file")
$normRaw = $TargetPath.Replace('\', '/').Trim()
$sensRe = '(?i)(^|/)(\.ssh|\.aws|\.gnupg|\.kube)(/|$)|(^|/)(id_rsa|id_ed25519|\.npmrc|\.pypirc|\.netrc)$'
if ($normRaw -match $sensRe) { return [pscustomobject]@{ Allowed = $false; Reason = "Sensitive host credential path blocked: $TargetPath"; NormalizedPath = $normRaw; IsSymlinkEscape = $false } }
$ft = try { [IO.Path]::GetFullPath($TargetPath).TrimEnd('\', '/') } catch { <# Fallback #> $normRaw }
if ($ft.Replace('\', '/') -match $sensRe) { return [pscustomobject]@{ Allowed = $false; Reason = "Sensitive host credential path blocked: $ft"; NormalizedPath = $ft; IsSymlinkEscape = $false } }
$rWs = [Collections.Generic.List[string]]::new()
foreach ($w in $WorkspaceList) { if ($w) { $rw = Resolve-SenWorkspaceRoot -StartPath $w; if (-not $rWs.Contains($rw)) { $rWs.Add($rw) } } }
if ($rWs.Count -gt 0 -and (Test-SenSymlinkEscape -FullTarget $ft -ResolvedWorkspaces $rWs.ToArray())) {
return [pscustomobject]@{ Allowed = $false; Reason = "Symlink or junction escape outside workspace blocked: $ft"; NormalizedPath = $ft; IsSymlinkEscape = $true }
}
if ($ToolName -in @("write_file", "edit_file") -and $rWs.Count -gt 0) {
$ok = $false; $cmp = [StringComparison]::OrdinalIgnoreCase; $sep = [IO.Path]::DirectorySeparatorChar
foreach ($rw in $rWs) { if ($ft.Equals($rw, $cmp) -or $ft.StartsWith($rw + $sep, $cmp) -or $ft.StartsWith($rw + '/', $cmp)) { $ok = $true; break } }
if (-not $ok -and $env:USERPROFILE) {
$gd = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE ".gemini")).TrimEnd('\', '/')
if ($ft.StartsWith($gd + $sep, $cmp)) { $ok = $true }
}
if (-not $ok) { return [pscustomobject]@{ Allowed = $false; Reason = "File write outside active workspace blocked: $ft"; NormalizedPath = $ft; IsSymlinkEscape = $false } }
}
return [pscustomobject]@{ Allowed = $true; Reason = $null; NormalizedPath = $ft; IsSymlinkEscape = $false }
}
function Invoke-SenGovMutex {
param([string]$LockTarget, [scriptblock]$Callback, [int]$TimeoutMs = 5000)
$normTarget = try { [IO.Path]::GetFullPath($LockTarget).Replace('\', '/').ToLowerInvariant() } catch { <# Fallback #> $LockTarget.Replace('\', '/').ToLowerInvariant() }
$keyHex = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($normTarget)))).Replace("-", "").Substring(0, 24).ToLowerInvariant()
$govMtx = [Threading.Mutex]::new($false, "Local\SenStateMutex_$keyHex"); $acquired = $false
try {
try { $acquired = $govMtx.WaitOne($TimeoutMs) } catch [Threading.AbandonedMutexException] { $acquired = $true }
if (-not $acquired) { throw "Concurrency lock timeout acquiring governance mutex 'Local\SenStateMutex_$keyHex' on '$LockTarget'." }
return (& $Callback)
}
finally { if ($acquired) { try { $govMtx.ReleaseMutex() } catch { <# Ignore #> } }; $govMtx.Dispose() }
}
function Register-SenRequirement {
[CmdletBinding()]
param(
[Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
[Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Title,
[ValidateSet("Functional", "NonFunctional", "Security", "Legal")][string]$Category = "Functional",
[ValidateSet("Confirmed", "Inferred")][string]$Source = "Confirmed",
[ValidateSet("Identified", "Planned", "Implemented", "Tested", "Verified", "NEEDS_CLARIFICATION", "SUPERSEDED")][string]$Status = "Planned",
[string[]]$DependsOn = @(), [string[]]$ConflictWith = @(), [string[]]$DesignIds = @(),
[string[]]$TaskIds = @(), [string[]]$CodePaths = @(), [string[]]$TestIds = @(), [string[]]$EvidenceIds = @()
)
$reqPath = Join-Path $Workspace ".agents/office/requirements.json"
$hasStatusParam = $PSBoundParameters.ContainsKey('Status')
return (Invoke-SenGovMutex -LockTarget $reqPath -Callback {
$loaded = Read-SenSafeJson -Path $reqPath
$list = [Collections.Generic.List[object]]::new()
$existingArr = if ($null -eq $loaded) { @() } elseif ($loaded.PSObject.Properties.Name -contains "requirements") { @($loaded.requirements) } else { @($loaded) }
$normTitle = $Title.Trim().ToLowerInvariant(); $dedup = $false; $ver = 1; $targetId = $Id
foreach ($item in $existingArr) {
if (-not $item) { continue }
if ([string]$item.id -eq $Id) { $ver = if ($item.PSObject.Properties['version']) { [int]$item.version + 1 } else { 2 }; continue }
if (([string]$item.title).Trim().ToLowerInvariant() -eq $normTitle) {
$dedup = $true; $targetId = [string]$item.id; $ver = if ($item.PSObject.Properties['version']) { [int]$item.version + 1 } else { 2 }; continue
}
$list.Add($item)
}
if (-not $hasStatusParam -and ($Title -match '(?i)\b(TODO|TBD)\b|\?\?\?')) { $Status = "NEEDS_CLARIFICATION" }
$effStatus = if ($Source -eq "Inferred" -and $Status -eq "Identified") { "NEEDS_CLARIFICATION" } else { $Status }
$now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
$reqObj = [pscustomobject]@{
id = $targetId; title = $Title.Trim(); category = $Category; source = $Source; status = $effStatus
dependsOn = @($DependsOn | Where-Object { $_ }); conflictWith = @($ConflictWith | Where-Object { $_ })
designIds = @($DesignIds | Where-Object { $_ }); taskIds = @($TaskIds | Where-Object { $_ })
codePaths = @($CodePaths | Where-Object { $_ }); testIds = @($TestIds | Where-Object { $_ })
evidenceIds = @($EvidenceIds | Where-Object { $_ }); version = $ver; updatedAt = $now
}
$list.Add($reqObj)
Write-SenAtomicJson -Path $reqPath -InputObject ([ordered]@{ updatedAt = $now; requirements = @($list.ToArray()) }) -Depth 8
return [pscustomobject]@{ Requirement = $reqObj; Deduplicated = $dedup; HasConflict = ($reqObj.conflictWith.Count -gt 0) }
})
}
function Register-SenEvidence {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [Alias("Id")][string]$EvidenceId = "", [string]$RequirementId = "", [string]$TaskId = "", [Alias("Category")][ValidateSet("unit", "integration", "e2e", "security", "performance", "build", "lint", "test")][string]$Type = "unit", [ValidateSet("PASS", "FAIL", "STALE")][string]$Status = "PASS", [string]$Source = "TestRunner", [string]$Command = "tests/run.ps1", [int]$ExitCode = 0, [Alias("ArtifactPaths", "Files")][string[]]$CodePaths = @(), [string]$SubjectPath = "", [int]$TTLMinutes = 1440, [string]$Output = "", [switch]$ExecuteCommand, [string]$ExecutionId = "", [int]$ProcessId = 0, [string]$OutputHash = "", [switch]$ClaimedOnly)
if ($Type -eq "test") { $Type = "unit" }
if ([string]::IsNullOrWhiteSpace($EvidenceId)) { $EvidenceId = "EV-" + [DateTime]::UtcNow.ToString("HHmmss") + "-" + ([Guid]::NewGuid().ToString("N").Substring(0, 4)) }
$evPath = Join-Path $Workspace ".agents/office/evidence.json"
return (Invoke-SenGovMutex -LockTarget $evPath -Callback {
$loaded = Read-SenSafeJson -Path $evPath
$existing = if ($null -eq $loaded) { @() } elseif ($loaded.PSObject.Properties.Name -contains "evidence") { @($loaded.evidence) } else { @($loaded) }
$list = [Collections.Generic.List[object]]::new(); foreach ($e in $existing) { if ($e -and [string]$e.evidence_id -ne $EvidenceId) { $list.Add($e) } }
$cPaths = [Collections.Generic.List[string]]::new(); foreach ($cp in @($CodePaths)) { if (-not [string]::IsNullOrWhiteSpace($cp)) { $cPaths.Add($cp) } }
if (-not [string]::IsNullOrWhiteSpace($SubjectPath) -and (-not $cPaths.Contains($SubjectPath))) { $cPaths.Insert(0, $SubjectPath) }
$sRel = if (-not [string]::IsNullOrWhiteSpace($SubjectPath)) { $SubjectPath } elseif ($cPaths.Count -gt 0) { $cPaths[0] } else { "" }
$sFull = if (-not $sRel) { "" } elseif ([IO.Path]::IsPathRooted($sRel)) { $sRel } else { Join-Path $Workspace $sRel }
$sHash = if ($sFull -and (Test-Path -LiteralPath $sFull -PathType Leaf)) { (Get-FileHash -LiteralPath $sFull -Algorithm SHA256).Hash.ToLowerInvariant() } else { "" }
$runMeta = Invoke-SenLiveEvidenceRunner -Workspace $Workspace -Command $Command -ProvidedExitCode $ExitCode -ProvidedOutput $Output -ExecuteCommand:$ExecuteCommand.IsPresent -ClaimedOnly:$ClaimedOnly.IsPresent -ExecutionId $ExecutionId -ProcessId $ProcessId -OutputHash $OutputHash
$ExitCode = [int]$runMeta.ExitCode; $gitC = [string]$runMeta.CodeRevision; $now = [string]$runMeta.CompletedAt
$expIso = (Get-Date).ToUniversalTime().AddMinutes($TTLMinutes).ToString("o")
$ver = ($Status -eq "PASS" -and $ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($Command) -and (-not $ClaimedOnly.IsPresent))
$entry = [pscustomobject]@{ evidence_id = $EvidenceId; requirement_id = $RequirementId; task_id = $TaskId; type = $Type; evidenceType = $runMeta.EvidenceType; status = $(if ($ver) { "PASS" } elseif ($Status -eq "STALE") { "STALE" } else { "FAIL" }); source = $Source; command = $Command; exitCode = $ExitCode; executionId = $runMeta.ExecutionId; processId = $runMeta.ProcessId; startedAt = $runMeta.StartedAt; completedAt = $runMeta.CompletedAt; outputHash = $runMeta.OutputHash; codePaths = @($cPaths.ToArray()); subjectPath = $sRel; subjectHash = $sHash; gitCommit = $gitC; commitSha = $gitC; codeRevision = $gitC; ttlMinutes = $TTLMinutes; expiresAt = $expIso; timestamp = $now; verified = [bool]$ver }
$list.Add($entry); Write-SenAtomicJson -Path $evPath -InputObject ([ordered]@{ updatedAt = $now; evidence = @($list.ToArray()) }) -Depth 8; return $entry
})
}
function Test-SenEvidenceValidity {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string[]]$InvalidatedTaskIds = @(), [string[]]$ModifiedFiles = @())
$evPath = Join-Path $Workspace ".agents/office/evidence.json"; $loaded = Read-SenSafeJson -Path $evPath
if ($null -eq $loaded) { return [pscustomobject]@{ TotalEvidence = 0; ValidCount = 0; StaleCount = 0; AllValid = $true; StaleEvidenceIds = @(); StaleReasons = @{} } }
$list = if ($loaded.PSObject.Properties.Name -contains "evidence") { @($loaded.evidence) } else { @($loaded) }
$staleIds = [Collections.Generic.List[string]]::new(); $staleReasons = [ordered]@{}
$validCount = 0; $changed = $false; $nowDto = [DateTimeOffset]::UtcNow
$invSet = [Collections.Generic.HashSet[string]]::new([string[]]@($InvalidatedTaskIds | Where-Object { $_ }), [StringComparer]::OrdinalIgnoreCase)
foreach ($ev in $list) {
if (-not $ev) { continue }
$isStale = ([string]$ev.status -eq "STALE"); $sReason = if ($ev.PSObject.Properties['staleReason']) { [string]$ev.staleReason } else { "" }
$expDto = [DateTimeOffset]::MinValue
if (-not $isStale -and $ev.PSObject.Properties['expiresAt'] -and [DateTimeOffset]::TryParse([string]$ev.expiresAt, [ref]$expDto) -and ($expDto -lt $nowDto)) { $isStale = $true; $sReason = "TTL_EXPIRED" }
if (-not $isStale -and $ev.PSObject.Properties['subjectHash'] -and (-not [string]::IsNullOrWhiteSpace([string]$ev.subjectHash))) {
$sp = if ($ev.PSObject.Properties['subjectPath'] -and $ev.subjectPath) { [string]$ev.subjectPath } elseif (@($ev.codePaths).Count -gt 0) { [string]$ev.codePaths[0] } else { "" }
$sf = if (-not $sp) { "" } elseif ([IO.Path]::IsPathRooted($sp)) { $sp } else { Join-Path $Workspace $sp }
if ($sf -and (Test-Path -LiteralPath $sf -PathType Leaf) -and ((Get-FileHash -LiteralPath $sf -Algorithm SHA256).Hash.ToLowerInvariant() -ne ([string]$ev.subjectHash).ToLowerInvariant())) {
$isStale = $true; $sReason = "SHA256_MISMATCH"
}
}
if (-not $isStale -and $ev.task_id -and $invSet.Contains([string]$ev.task_id)) { $isStale = $true; $sReason = "TASK_INVALIDATED" }
if (-not $isStale -and $ModifiedFiles.Count -gt 0 -and (Test-SenPathOverlap -PathsA @($ev.codePaths) -PathsB $ModifiedFiles)) { $isStale = $true; $sReason = "MODIFIED_AFTER_EVIDENCE" }
$evDt = [DateTime]::MinValue; if ($ev.timestamp) { [void][DateTime]::TryParse([string]$ev.timestamp, [Globalization.CultureInfo]::InvariantCulture, ([Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal), [ref]$evDt) }
if ((-not $isStale) -and ($evDt -gt [DateTime]::MinValue) -and @($ev.codePaths).Count -gt 0) {
$newer = @($ev.codePaths | Where-Object { $f = if ([IO.Path]::IsPathRooted([string]$_)) { [string]$_ } else { Join-Path $Workspace ([string]$_) }; (Test-Path -LiteralPath $f -PathType Leaf) -and (Get-Item -LiteralPath $f).LastWriteTimeUtc -gt $evDt.AddSeconds(1) })
if ($newer.Count -gt 0) { $isStale = $true; $sReason = "MODIFIED_AFTER_EVIDENCE" }
}
if ($isStale) {
if ([string]$ev.status -ne "STALE" -or [bool]$ev.verified -or [string]$ev.staleReason -ne $sReason) {
$ev.status = "STALE"; $ev.verified = $false; $ev | Add-Member -NotePropertyName "staleReason" -NotePropertyValue $sReason -Force; $changed = $true
}
$staleIds.Add([string]$ev.evidence_id); $staleReasons[[string]$ev.evidence_id] = $sReason
}
elseif ([bool]$ev.verified -and [string]$ev.status -eq "PASS") { $validCount++ }
}
if ($changed) { Write-SenAtomicJson -Path $evPath -InputObject ([ordered]@{ updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); evidence = $list }) -Depth 8 }
return [pscustomobject]@{ TotalEvidence = $list.Count; ValidCount = $validCount; StaleCount = $staleIds.Count; AllValid = ($staleIds.Count -eq 0); StaleEvidenceIds = @($staleIds.ToArray()); StaleReasons = $staleReasons }
}
function Get-SenRequirementTraceability {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
[void](Test-SenEvidenceValidity -Workspace $Workspace)
$reqObj = Read-SenSafeJson -Path (Join-Path $Workspace ".agents/office/requirements.json")
$reqs = if ($null -eq $reqObj) { @() } elseif ($reqObj.PSObject.Properties.Name -contains "requirements") { @($reqObj.requirements | Where-Object { $_ -and [string]$_.status -ne "SUPERSEDED" }) } else { @($reqObj) }
$evObj = Read-SenSafeJson -Path (Join-Path $Workspace ".agents/office/evidence.json")
$evList = if ($null -eq $evObj) { @() } elseif ($evObj.PSObject.Properties.Name -contains "evidence") { @($evObj.evidence) } else { @($evObj) }
$tasks = @(Get-SenTasks -Workspace $Workspace)
$missImpl = [Collections.Generic.List[string]]::new(); $missTest = [Collections.Generic.List[string]]::new()
$unver = [Collections.Generic.List[string]]::new(); $clarif = [Collections.Generic.List[string]]::new(); $confl = [Collections.Generic.List[string]]::new()
$implCnt = 0; $testCnt = 0; $verCnt = 0
foreach ($r in $reqs) {
$rid = [string]$r.id
if ([string]$r.status -eq "NEEDS_CLARIFICATION" -or ([string]$r.source -eq "Inferred" -and [string]$r.status -eq "Identified")) { $clarif.Add($rid) }
if (@($r.conflictWith).Count -gt 0) { $confl.Add($rid) }
$hasImpl = (@($r.codePaths).Count -gt 0) -or (@($r.taskIds).Count -gt 0) -or ([string]$r.status -in @("Implemented", "Tested", "Verified"))
if ($hasImpl) { $implCnt++ } else { $missImpl.Add($rid) }
$validEvs = @($evList | Where-Object { ([string]$_.requirement_id -eq $rid -or (@($r.evidenceIds) -contains [string]$_.evidence_id) -or (@($r.taskIds) -contains [string]$_.task_id)) -and [bool]$_.verified -and [string]$_.status -eq "PASS" })
$doneTasks = @($tasks | Where-Object { (@($r.taskIds) -contains [string]$_.id) -and [string]$_.status -eq "done" -and $_.evidence -and [int]$_.evidence.exitCode -eq 0 })
$hasTest = (@($r.testIds).Count -gt 0) -or ($validEvs.Count -gt 0) -or ($doneTasks.Count -gt 0)
if ($hasTest) { $testCnt++ } else { $missTest.Add($rid) }
$staleEvs = @($evList | Where-Object { ([string]$_.requirement_id -eq $rid -or (@($r.evidenceIds) -contains [string]$_.evidence_id)) -and [string]$_.status -eq "STALE" })
$isVer = ($staleEvs.Count -eq 0) -and (($validEvs.Count -gt 0) -or ($doneTasks.Count -gt 0) -or ([string]$r.status -eq "Verified")) -and ($hasImpl -and $hasTest)
if ($isVer) { $verCnt++ } else { $unver.Add($rid) }
}
$accepted = ($reqs.Count -gt 0) -and ($missImpl.Count -eq 0) -and ($missTest.Count -eq 0) -and ($unver.Count -eq 0) -and ($clarif.Count -eq 0) -and ($confl.Count -eq 0)
$finalSt = if ($accepted) { "ACCEPTED" } else { "NOT_ACCEPTED" }
$rep = "PROJECT ACCEPTANCE REPORT`nTotal Requirements: $($reqs.Count) | Implemented: $implCnt | Tested: $testCnt | Verified: $verCnt`nMissing Implementation: $($missImpl.Count) | Missing Tests: $($missTest.Count) | Unverified: $($unver.Count)`nFINAL STATUS: $finalSt"
return [pscustomobject]@{
TotalRequirements = $reqs.Count; Identified = $reqs.Count; Planned = $reqs.Count; Implemented = $implCnt; Tested = $testCnt; Verified = $verCnt
MissingImplementation = @($missImpl.ToArray()); MissingTestCoverage = @($missTest.ToArray()); UnverifiedRequirements = @($unver.ToArray())
NeedsClarification = @($clarif.ToArray()); Conflicts = @($confl.ToArray()); FinalStatus = $finalSt; Accepted = $accepted; ReportText = $rep
}
}
function Invoke-SenTaskTransition {
[CmdletBinding()]
param(
[Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [Parameter(Mandatory)][string]$Id,
[Parameter(Mandatory)][ValidateSet("backlog", "todo", "pending", "ready", "in_progress", "reviewing", "needs_verification", "verified", "done", "blocked", "failed", "cancelled", "retrying", "superseded", "stale")][string]$ToStatus,
[string]$Actor = "pm", [string]$Reason = "", [int]$LockMinutes = 30
)
$tasks = @(Get-SenTasks -Workspace $Workspace)
$target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
if ($null -eq $target) { return [pscustomobject]@{ Transitioned = $false; FromStatus = $null; ToStatus = $ToStatus; Task = $null; Reason = "Task '$Id' not found" } }
$from = [string]$target.status
if (($from -in @("backlog", "todo", "pending", "ready", "stale", "failed")) -and ($ToStatus -in @("done", "verified"))) {
return [pscustomobject]@{ Transitioned = $false; FromStatus = $from; ToStatus = $ToStatus; Task = $target; Reason = "Invalid transition '$from -> $ToStatus': task must pass through in_progress/reviewing first." }
}
$now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
$hist = [Collections.Generic.List[object]]::new()
if ($target.PSObject.Properties['history'] -and $target.history) { foreach ($h in @($target.history)) { $hist.Add($h) } }
$hist.Add([ordered]@{ from = $from; to = $ToStatus; actor = $Actor; timestamp = $now; reason = $Reason })
$target.status = $ToStatus; $target.updatedAt = $now
$target | Add-Member -NotePropertyName "history" -NotePropertyValue @($hist.ToArray()) -Force
$expIso = if ($ToStatus -eq "in_progress") { [DateTime]::UtcNow.AddMinutes($LockMinutes).ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }
$target | Add-Member -NotePropertyName "lockExpiresAt" -NotePropertyValue $expIso -Force
$curRev = if ($target.PSObject.Properties.Name -contains "_rev") { [int]$target._rev } else { 1 }
$target | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
[void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
return [pscustomobject]@{ Transitioned = $true; FromStatus = $from; ToStatus = $ToStatus; Task = $target; Reason = $null }
}
function Invoke-SenChangeImpactAnalysis {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$RequirementId = "", [string]$TaskId = "", [string]$Reason = "Upstream requirement or task changed")
$tasks = @(Get-SenTasks -Workspace $Workspace); $reqPath = Join-Path $Workspace ".agents/office/requirements.json"; $reqObj = Read-SenSafeJson -Path $reqPath
$reqs = if ($null -eq $reqObj) { @() } elseif ($reqObj.PSObject.Properties.Name -contains "requirements") { @($reqObj.requirements) } else { @($reqObj) }
$seedTasks = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($TaskId) { [void]$seedTasks.Add($TaskId) }
$impReqs = [Collections.Generic.List[string]]::new()
foreach ($r in $reqs) {
if ($r -and $RequirementId -and ([string]$r.id -eq $RequirementId -or @($r.dependsOn) -contains $RequirementId)) {
$impReqs.Add([string]$r.id); $r.status = "Planned"
foreach ($tid in @($r.taskIds)) { if ($tid) { [void]$seedTasks.Add([string]$tid) } }
}
}
$added = $true
while ($added) {
$added = $false
foreach ($t in $tasks) {
if (-not $t -or $seedTasks.Contains([string]$t.id)) { continue }
foreach ($d in @($t.dependsOn)) { if ($seedTasks.Contains([string]$d)) { [void]$seedTasks.Add([string]$t.id); $added = $true; break } }
}
}
$now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); $impFiles = [Collections.Generic.List[string]]::new()
foreach ($t in $tasks) {
if ($t -and $seedTasks.Contains([string]$t.id)) {
foreach ($ap in @($t.allowedPaths)) { if ($ap -and -not $impFiles.Contains([string]$ap)) { $impFiles.Add([string]$ap) } }
if ([string]$t.status -in @("done", "verified", "reviewing")) {
$t.status = "stale"; $t.updatedAt = $now; $t | Add-Member -NotePropertyName "needsReverification" -NotePropertyValue $true -Force
}
}
}
[void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
if ($reqs.Count -gt 0) { Write-SenAtomicJson -Path $reqPath -InputObject ([ordered]@{ updatedAt = $now; requirements = $reqs }) -Depth 8 }
$evRes = Test-SenEvidenceValidity -Workspace $Workspace -InvalidatedTaskIds @($seedTasks)
$chgId = "CR-" + [DateTime]::UtcNow.ToString("HHmmss")
Write-SenAtomicJson -Path (Join-Path $Workspace ".agents/office/change-log.json") -InputObject ([ordered]@{ changeId = $chgId; requirementId = $RequirementId; taskId = $TaskId; reason = $Reason; impactedTasks = @($seedTasks); updatedAt = $now }) -Depth 6
return [pscustomobject]@{ ChangedId = if ($RequirementId) { $RequirementId } else { $TaskId }; ChangeRequestId = $chgId; ImpactedTasks = @($seedTasks); ImpactedRequirements = @($impReqs.ToArray()); InvalidatedEvidence = $evRes.StaleEvidenceIds; ImpactedFiles = @($impFiles.ToArray()) }
}
function Invoke-SenCheckpointResume {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string[]]$SimulatedDirtyFiles = @())
$tasks = @(Get-SenTasks -Workspace $Workspace); $expired = [Collections.Generic.List[string]]::new(); $nowUtc = [DateTime]::UtcNow
foreach ($t in $tasks) {
if ($t -and [string]$t.status -eq "in_progress" -and $t.PSObject.Properties['lockExpiresAt'] -and $t.lockExpiresAt) {
$expDt = [DateTime]::MinValue
if ([DateTime]::TryParse([string]$t.lockExpiresAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$expDt) -and $expDt -lt $nowUtc) {
$expired.Add([string]$t.id); [void](Unlock-SenTask -Workspace $Workspace -Id ([string]$t.id))
}
}
}
$dirty = [Collections.Generic.List[string]]::new()
foreach ($sf in $SimulatedDirtyFiles) { if (-not [string]::IsNullOrWhiteSpace($sf)) { $dirty.Add($sf) } }
if ($dirty.Count -eq 0 -and (Test-Path -LiteralPath (Join-Path $Workspace ".git"))) {
try {
foreach ($gl in @(& git -C $Workspace status --porcelain 2>$null)) { if ($gl -and $gl.Length -gt 3) { $dirty.Add($gl.Substring(3).Trim()) } }
}
catch { <# Ignore git status error #> }
}
$evCheck = Test-SenEvidenceValidity -Workspace $Workspace -ModifiedFiles $SimulatedDirtyFiles
$rec = Get-SenRecoveryState -Workspace $Workspace
return [pscustomobject]@{
CompletedTasks = @($rec.doneIds); ActiveTasks = @($rec.inProgressIds); ReadyTasks = @($rec.readyIds)
ExpiredLocks = @($expired.ToArray()); UncommittedFiles = @($dirty.ToArray()); StaleEvidence = @($evCheck.StaleEvidenceIds)
SafeToResume = $true; PreventDuplicateIds = @($rec.doneIds)
}
}
function Test-SenMidTaskEscalation {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string[]]$ModifiedFiles = @())
$auditPath = Join-Path $Workspace ".agents/office/process-audit.json"; $audit = Read-SenSafeJson -Path $auditPath
$curTier = if ($null -ne $audit -and $audit.PSObject.Properties['tier']) { [int]$audit.tier } else { 1 }
$tTier = $curTier; $rsn = $null; $critRe = '(?i)(auth|login|password|oauth|jwt|rbac|sso|security|crypto|payment|billing|stripe|vnpay|momo|checkout|wallet|schema|migration|database|prisma|\.sql$|secret|guard\.(ps1|sh))'
foreach ($mf in $ModifiedFiles) { if ($mf -match $critRe) { $tTier = 3; $rsn = "Critical path: $mf"; break } }
if ($tTier -lt 2 -and $ModifiedFiles.Count -ge 3) { $tTier = 2; $rsn = "File count ($($ModifiedFiles.Count)) >= 3" }
$esc = ($tTier -gt $curTier)
if ($esc -and $null -ne $audit) {
$audit | Add-Member -NotePropertyName "escalatedFrom" -NotePropertyValue $curTier -Force
$audit.tier = $tTier; $audit.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); Write-SenAtomicJson -Path $auditPath -InputObject $audit -Depth 8
}
return [pscustomobject]@{ Escalated = $esc; PreviousTier = $curTier; NewTier = $tTier; Reason = $rsn }
}
function Test-SenSuiteIntegrity {
[CmdletBinding()] param([string]$TestsPath = "", [int]$MinFiles = 1, [int]$MinAssertions = 1)
$tDir = if ($TestsPath) { $TestsPath } else { Join-Path $PSScriptRoot "../tests" }
if (-not (Test-Path -LiteralPath $tDir)) { return [pscustomobject]@{ Passed = $false; FileCount = 0; AssertionCount = 0; MinAssertions = $MinAssertions; Reason = "Missing: $tDir" } }
$files = @(Get-ChildItem -LiteralPath $tDir -Filter "*.Tests.ps1" -File -EA SilentlyContinue); $aCnt = 0; $emp = [Collections.Generic.List[string]]::new()
foreach ($f in $files) { $c = [regex]::Matches([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8), '\bAssert-[A-Za-z]+\b').Count; if ($c -eq 0) { $emp.Add($f.Name) }; $aCnt += $c }
$ok = ($files.Count -ge $MinFiles) -and ($aCnt -ge $MinAssertions) -and ($emp.Count -eq 0)
return [pscustomobject]@{ Passed = $ok; FileCount = $files.Count; AssertionCount = $aCnt; MinAssertions = $MinAssertions; Reason = $(if ($ok) { "OK" } else { "Suite integrity failed" }) }
}
function Measure-SenTokenEstimate {
[CmdletBinding()] param([AllowEmptyString()][string]$Text = "", [string]$Path = "", [int]$TokenBudget = 1500)
$c = if ($Path -and (Test-Path -LiteralPath $Path)) { [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) } else { $Text }
if ([string]::IsNullOrEmpty($c)) { return [pscustomobject]@{ EstimatedTokens = 0; ByteCount = 0; CharCount = 0; NonAsciiCount = 0; TokenBudget = $TokenBudget; WithinBudget = $true } }
$b = [Text.Encoding]::UTF8.GetByteCount($c); $na = [regex]::Matches($c, '[^\x00-\x7F]').Count; $p = [regex]::Matches($c, '[\{\}\[\]\(\);:,<>=\+\-\*/\|\\]').Count
$est = [int][Math]::Ceiling(($c.Length / 3.8) + ($na * 0.45) + ($p * 0.15))
return [pscustomobject]@{ EstimatedTokens = $est; ByteCount = $b; CharCount = $c.Length; NonAsciiCount = $na; TokenBudget = $TokenBudget; WithinBudget = ($est -le $TokenBudget) }
}
function Set-SenEdition {
[CmdletBinding()] param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [Parameter(Mandatory)][ValidateSet("core", "full")][string]$Edition)
$cfg = Set-SenOfficeConfig -Workspace $Workspace -Mode $(if ($Edition -eq "core") { "off" } else { "eco" })
$cfg["edition"] = $Edition; $cfg["telemetryEnabled"] = ($Edition -eq "full"); $cfg["creativePacksEnabled"] = ($Edition -eq "full")
Write-SenAtomicJson -Path (Join-Path $Workspace ".agents/office/config.json") -InputObject $cfg -Depth 5; return [pscustomobject]$cfg
}
function Get-SenDeferredItems {
[CmdletBinding()] param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
$defPath = Join-Path $Workspace ".agents/office/deferred-items.json"; $loaded = Read-SenSafeJson -Path $defPath
if ($null -ne $loaded -and $loaded.PSObject.Properties['items']) { return @($loaded.items) }
$items = @(
[ordered]@{ id = "W-09"; source = "Grok"; title = "Tone down marketing style in README.md"; status = "pending_user_confirmation"; mitigation = "Pending user confirmation" },
[ordered]@{ id = "W-26 / IMP-19"; source = "Claude"; title = "Hide public contact/donate info in README.md"; status = "pending_user_confirmation"; mitigation = "Pending owner confirmation" },
[ordered]@{ id = "IMP-13 / IMP-05"; source = "Grok"; title = "Rewrite PowerShell runtime into Node/Python"; status = "disagreed_rejected"; mitigation = "Solved via POSIX .sh scripts" },
[ordered]@{ id = "IMP-10 / IMP-29"; source = "Grok/Claude"; title = "Split Sen.Legal and sen-office into separate repos"; status = "disagreed_rejected"; mitigation = "Solved via Set-SenEdition" }
)
Write-SenAtomicJson -Path $defPath -InputObject ([ordered]@{ version = "0.5.0"; updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); items = $items }) -Depth 6
return @($items | ForEach-Object { [pscustomobject]$_ })
}
function Uninstall-SenSelf {
[CmdletBinding()] param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [switch]$RemovePluginDir, [switch]$DryRun)
$tName = "Sen update check ($(Split-Path -Path $Workspace -Leaf))"; $sRem = $false
if (-not $DryRun.IsPresent) { try { if (Get-Command Unregister-ScheduledTask -EA SilentlyContinue) { Unregister-ScheduledTask -TaskName $tName -Confirm:$false -EA SilentlyContinue; $sRem = $true } } catch { <# Ignore #> } }
$hRem = if (-not $DryRun.IsPresent -and (Get-Command Uninstall-SenHarness -EA SilentlyContinue)) { @((Uninstall-SenHarness -Workspace $Workspace -Harness @("all")).Uninstalled) } else { @() }
$pDir = Join-Path $Workspace ".agents/plugins/sen-method"
if ($RemovePluginDir.IsPresent -and (-not $DryRun.IsPresent) -and (Test-Path -LiteralPath $pDir)) { Remove-Item -LiteralPath $pDir -Recurse -Force -EA SilentlyContinue }
return [pscustomobject]@{ Uninstalled = $true; Workspace = $Workspace; ScheduledTaskName = $tName; ScheduledTaskRemoved = $sRem; HarnessesRemoved = $hRem; DryRun = [bool]$DryRun.IsPresent }
}
function Add-SenExecutionLesson {
[CmdletBinding()]
param(
[Parameter(Mandatory)][string]$Workspace, [Parameter(Mandatory)][string]$Category,
[Parameter(Mandatory)][string]$Problem, [Parameter(Mandatory)][string]$Solution,
[string]$RootCause = "", [bool]$VerifiedByUser = $true, [string]$Stack = "general", [double]$Confidence = 1.0,
[ValidateSet("active", "deprecated", "archived")][string]$Status = "active", [string]$ExpiresAt = ""
)
if ("$Problem`n$Solution`n$RootCause" -match '(?i)(ignore\s+(all\s+)?previous\s+instructions|disregard\s+.*rules|SEN_TRUSTED_HOOK|SEN_TRUSTED_INSTALLER|Sync-SenOfficeState\s+.*-UpdateSeal|Set-ExecutionPolicy\s+.*CurrentUser)') {
Write-Warning "Lesson poisoning blocked: prompt-injection or guard-bypass directive detected in lesson."; return $null
}
$lessonsPath = Join-Path $Workspace ".agents/office/lessons.json"
$existing = [Collections.Generic.List[object]]::new(); $raw = Read-SenSafeJson -Path $lessonsPath
if ($null -ne $raw) { foreach ($item in $raw) { if ($item) { $existing.Add($item) } } }
$entry = [pscustomobject]@{
id = "LES-" + ([DateTime]::UtcNow.ToString("yyyyMMddHHmmss")) + "-" + ([Guid]::NewGuid().ToString("N").Substring(0, 4))
category = $Category; stack = $Stack; problem = $Problem; rootCause = $RootCause; solution = $Solution
confidence = $Confidence; confidenceTier = "verified"; source = "runtime"; status = $Status; verifiedByUser = $VerifiedByUser
expiresAt = if ($ExpiresAt) { $ExpiresAt } else { [DateTime]::UtcNow.AddDays(180).ToString("yyyy-MM-ddTHH:mm:ssZ") }
createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
}
$existing.Add($entry); Write-SenAtomicJson -Path $lessonsPath -InputObject @($existing.ToArray()) -Depth 5; return $entry
}
function Get-SenExecutionLessons {
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Workspace, [string]$Stack = '', [switch]$IncludeExpired)
$lp = Join-Path $Workspace ".agents/office/lessons.json"
if (-not (Test-Path -LiteralPath $lp)) { $lp = Join-Path $Workspace ".agents/office/execution-memory.json" }
$loaded = Read-SenSafeJson -Path $lp
if ($null -eq $loaded) { return @() }
$nowDto = [DateTimeOffset]::UtcNow; $res = [Collections.Generic.List[object]]::new()
foreach ($it in $loaded) {
if (-not $it) { continue }
$dto = [DateTimeOffset]::MinValue
$expOk = $IncludeExpired.IsPresent -or [string]::IsNullOrWhiteSpace([string]$it.expiresAt) -or (-not [DateTimeOffset]::TryParse([string]$it.expiresAt, [ref]$dto)) -or ($dto -ge $nowDto)
$stackOk = [string]::IsNullOrWhiteSpace($Stack) -or ([string]$it.stack -eq 'all') -or ([string]$it.stack -ieq $Stack)
if ($expOk -and $stackOk) { $res.Add($it) }
}
return @($res.ToArray())
}
function Get-SenMemorySnapshot {
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Workspace)
$lessons = @(Get-SenExecutionLessons -Workspace $Workspace)
$tasks = if (Get-Command Get-SenTasks -EA SilentlyContinue) { @(Get-SenTasks -Workspace $Workspace) } else { @() }
$doneT = @($tasks | Where-Object { $_ -and [string]$_.status -eq "done" })
$fpCnt = @($doneT | Where-Object { [int]$_.reworkCount -eq 0 }).Count
$fpPct = if ($doneT.Count -gt 0) { [int][Math]::Round(($fpCnt * 100.0) / $doneT.Count) } else { 100 }
$rwSum = 0; foreach ($tk in $tasks) { if ($tk -and $tk.PSObject.Properties['reworkCount']) { $rwSum += [int]$tk.reworkCount } }
$evFile = Join-Path $Workspace ".agents/office/events.jsonl"
$evLines = if (Test-Path -LiteralPath $evFile) { @([IO.File]::ReadAllLines($evFile)) } else { @() }
$blkCnt = @($evLines | Where-Object { $_ -match 'guard-denied|BLOCKED:' }).Count
$bypCnt = @($evLines | Where-Object { $_ -match '(?i)(override|just do it|lam luon)' }).Count
$bm = [pscustomobject][ordered]@{ TotalTasks = $tasks.Count; DoneTasks = $doneT.Count; FirstPassRatePct = $fpPct; TotalReworkCount = $rwSum; GuardBlockedCount = $blkCnt; BypassOverrideCount = $bypCnt }
return [pscustomobject]@{
userMemory      = [ordered]@{ present = (Test-Path -LiteralPath (Join-Path $Workspace ".agents/profile.md")); path = ".agents/profile.md" }
projectMemory   = [ordered]@{ hasAgentsMd = (Test-Path -LiteralPath (Join-Path $Workspace "AGENTS.md")); hasContextMd = (Test-Path -LiteralPath (Join-Path $Workspace "docs/CONTEXT.md")); hasTodoMd = (Test-Path -LiteralPath (Join-Path $Workspace "docs/TODO.md")) }
executionMemory = [ordered]@{ lessonCount = $lessons.Count; lessons = $lessons }
BaselineMetrics = $bm
}
}
function Sync-SenOfficeState {
[CmdletBinding()]
param([Parameter(Mandatory)][Alias("WorkspacePath", "Path")][string]$Workspace, [switch]$PruneStale, [switch]$VerifySeal, [switch]$UpdateSeal)
$offDir = Join-Path $Workspace ".agents/office"
if (-not (Test-Path -LiteralPath $offDir)) { [IO.Directory]::CreateDirectory($offDir) | Out-Null }
$prunedCnt = 0; $staleEvs = @(); $unlockedIds = @()
if ($PruneStale.IsPresent) {
$lp = Join-Path $offDir "lessons.json"; if (-not (Test-Path -LiteralPath $lp)) { $lp = Join-Path $offDir "execution-memory.json" }
if (Test-Path -LiteralPath $lp) {
$allL = @(Get-SenExecutionLessons -Workspace $Workspace -IncludeExpired); $actL = @(Get-SenExecutionLessons -Workspace $Workspace)
$prunedCnt = [Math]::Max(0, $allL.Count - $actL.Count)
if ($prunedCnt -gt 0) { Write-SenAtomicJson -Path $lp -InputObject $actL -Depth 6 }
}
$staleEvs = @((Test-SenEvidenceValidity -Workspace $Workspace).StaleEvidenceIds)
$unlockedIds = @((Invoke-SenCheckpointResume -Workspace $Workspace).ExpiredLocks)
}
$sealPath = Join-Path $offDir "state-seal.json"
return (Invoke-SenGovMutex -LockTarget $sealPath -Callback {
$savedSeal = if ($VerifySeal.IsPresent -and (Test-Path -LiteralPath $sealPath)) { Read-SenSafeJson -Path $sealPath } else { $null }
$fileHashes = [ordered]@{}
foreach ($jf in @(Get-ChildItem -LiteralPath $offDir -Filter "*.json" -File -EA SilentlyContinue | Where-Object { $_.Name -notin @("state-seal.json", "config.json") } | Sort-Object Name)) {
$fileHashes[$jf.Name] = (Get-FileHash -LiteralPath $jf.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$rawPairs = ($fileHashes.Keys | ForEach-Object { "$_=$($fileHashes[$_])" }) -join ";"
$compHash = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($rawPairs)))).Replace("-", "").ToLowerInvariant()
$tamperedFiles = [Collections.Generic.List[string]]::new(); $tampered = ($null -ne $savedSeal) -and ([string]$savedSeal.compositeHash -ne $compHash)
if ($null -ne $savedSeal -and $null -ne $savedSeal.fileHashes) {
foreach ($p in $savedSeal.fileHashes.PSObject.Properties) {
$curH = if ($fileHashes.Contains($p.Name)) { [string]$fileHashes[$p.Name] } else { "" }
if ($curH -ne [string]$p.Value) { $tamperedFiles.Add([string]$p.Name) }
}
}
if ($UpdateSeal.IsPresent) { Write-SenAtomicJson -Path $sealPath -InputObject ([ordered]@{ timestamp = [DateTime]::UtcNow.ToString("o"); compositeHash = $compHash; fileHashes = $fileHashes }) -Depth 6 }
return [pscustomobject]@{
Workspace = $Workspace; Synced = (-not $tampered); Tampered = [bool]$tampered; TamperedFiles = @($tamperedFiles.ToArray())
CompositeHash = $compHash; FileHashes = $fileHashes; SealPath = $sealPath
PrunedLessons = $prunedCnt; StaleEvidenceIds = $staleEvs; UnlockedTaskIds = $unlockedIds
RemediationCommand = "Sync-SenOfficeState -Workspace '$Workspace' -PruneStale -UpdateSeal"
}
})
}
function Initialize-SenIntake {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [Alias("Prompt", "Title")][Parameter(Mandatory)][string]$Request, [int]$FileCount = 1, [string[]]$Files = @(), [string]$UserName = "", [string]$TaskId = "", [int]$Tier = 0, [string]$SessionId = "", [string]$RequestId = "", [switch]$EnforceDeliveryGate, [switch]$SkipOfficeLaunch)
$uName = $UserName
if ([string]::IsNullOrWhiteSpace($uName)) {
foreach ($pf in @((Join-Path $Workspace ".agents/rules/profile.md"), (Join-Path $Workspace ".agents/profile.md"), (Join-Path $Workspace "AGENTS.md"))) {
if (Test-Path -LiteralPath $pf) {
$m = [regex]::Match([IO.File]::ReadAllText($pf, [Text.Encoding]::UTF8), '(?m)^-\s*\*?\*?Name:\*?\*?\s*([^\r\n]+)')
if ($m.Success) { $uName = $m.Groups[1].Value.Trim(); break }
}
}
}
if ([string]::IsNullOrWhiteSpace($uName)) { $uName = "User" }
$risk = if (Get-Command Get-SenTaskRiskScore -EA SilentlyContinue) { Get-SenTaskRiskScore -Request $Request -FileCount ([Math]::Max($FileCount, $Files.Count)) -Files $Files } else { [pscustomobject]@{ Tier = 2; LabelVi = "[Cap 2 - Xac nhan phuong an]"; LabelEn = "[Tier 2 - Confirming the approach]" } }
$t = if ($Tier -in 1..3) { [Math]::Max($Tier, [int]$risk.Tier) } else { [int]$risk.Tier }; $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
if ((-not $SkipOfficeLaunch.IsPresent) -and (Get-Command Start-SenOfficeIfIdle -EA SilentlyContinue)) { [void](Start-SenOfficeIfIdle -Workspace $Workspace) }
if ($t -ge 2 -and (Get-Command Initialize-SenProcessAudit -EA SilentlyContinue)) { [void](Initialize-SenProcessAudit -Workspace $Workspace -Tier $t -PreserveLatched) }
$sessId = if ($SessionId) { $SessionId } else { "sess-" + [DateTime]::UtcNow.ToString("yyyyMMddHHmmss") + "-" + ([Guid]::NewGuid().ToString("N").Substring(0, 6)) }
$reqId = if ($RequestId) { $RequestId } else { "req-" + ([Guid]::NewGuid().ToString("N").Substring(0, 8)) }
$oblReg = @("OBL-01:IntakeInitialized", $(if ($t -ge 2) { "OBL-02:RestorePointCaptured" }), "OBL-03:OfficeShowcasePhase1", "OBL-04:TasksTracked", "OBL-05:TestEvidenceVerified", "OBL-06:StateSealIntact") | Where-Object { $_ }
$obj = [pscustomobject]@{
sessionId = $sessId; requestId = $reqId; taskId = $TaskId; userName = $uName; request = $Request; tier = $t; tierLabelVi = [string]$risk.LabelVi; tierLabelEn = [string]$risk.LabelEn
codeRevision = (Get-SenRepoCodeRevision -Workspace $Workspace); obligations = @($oblReg); enforceDeliveryGate = [bool]$EnforceDeliveryGate.IsPresent
requiresDialecticalProof = ($t -ge 2); requiresResourceCostTable = ($t -ge 2); requiresRestorePoint = ($t -ge 2)
requiresSubagentInTurn1 = ($t -ge 2); requiresMermaidDiagrams = ($t -eq 3); createdAt = $now
}
Write-SenAtomicJson -Path (Join-Path $Workspace ".agents/office/current-intake.json") -InputObject $obj -Depth 6
return $obj
}
function Test-SenIntakeCompleteness {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [Alias("ResponseText")][string]$DraftResponse = "", [int]$Tier = 0, [switch]$EnforceAllObligations)
$inObj = Read-SenSafeJson -Path (Join-Path $Workspace ".agents/office/current-intake.json")
$tier = if ($Tier -in 1..3) { $Tier } elseif ($null -ne $inObj -and $inObj.PSObject.Properties['tier']) { [int]$inObj.tier } else { 1 }
$uName = if ($null -ne $inObj -and $inObj.PSObject.Properties['userName']) { [string]$inObj.userName } else { "" }
$miss = [Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($DraftResponse)) {
if ($DraftResponse -notmatch '(?i)\[(Tier|C.p)\s*[123]\b') { $miss.Add("MissingTierLabel") }
if ($uName -and $uName -ne "User" -and $DraftResponse.IndexOf($uName, [StringComparison]::OrdinalIgnoreCase) -lt 0) { $miss.Add("MissingUserNameAck:$uName") }
if ($tier -ge 2 -and $DraftResponse -notmatch '(?i)(Resource Cost|T.i nguy.n ti.u t.n|Best-of-the-Best)') { $miss.Add("MissingDialecticalCostTable") }
}
$rpDir = Join-Path $Workspace ".agents/.sen-restore"
$hasRp = (Test-Path -LiteralPath $rpDir) -and (@(Get-ChildItem -LiteralPath $rpDir -Directory -EA SilentlyContinue).Count -gt 0)
if ($tier -ge 2 -and (-not $hasRp)) { $miss.Add("MissingRestorePoint") }
$sc = Read-SenSafeJson -Path (Join-Path $Workspace ".agents/office/showcase.json")
$ev = Read-SenSafeJson -Path (Join-Path $Workspace ".agents/office/evidence.json")
$evArr = if ($null -eq $ev) { @() } elseif ($ev.PSObject.Properties['evidence']) { @($ev.evidence) } else { @($ev) }
$validEvCnt = @($evArr | Where-Object { $_ -and [string]$_.status -eq "PASS" -and [bool]$_.verified }).Count
$sf = Join-Path $Workspace ".agents/office/state-seal.json"
$sOk = (Test-Path -LiteralPath $sf) -and (-not (Sync-SenOfficeState -Workspace $Workspace -VerifySeal).Tampered)
$tCnt = if (Get-Command Get-SenTasks -EA SilentlyContinue) { @(Get-SenTasks -Workspace $Workspace | Where-Object { $_ -and (-not ($_.PSObject.Properties['isTelemetryOnly'] -and [bool]$_.isTelemetryOnly)) }).Count } else { 0 }
$obl = @(
[pscustomobject]@{ id = "OBL-01:IntakeInitialized"; status = $(if ($null -ne $inObj) { "PASS" } else { "MISSING" }); trigger = $true; execution = ($null -ne $inObj); result = ($null -ne $inObj); evidence = "current-intake.json" },
[pscustomobject]@{ id = "OBL-02:RestorePointCaptured"; status = $(if ($hasRp -or $tier -lt 2) { "PASS" } else { "MISSING" }); trigger = ($tier -ge 2); execution = $hasRp; result = $hasRp; evidence = ".agents/.sen-restore" },
[pscustomobject]@{ id = "OBL-03:OfficeShowcasePhase1"; status = $(if ($sc -and $sc.phase1) { "PASS" } elseif ($sc) { "PARTIAL" } else { "MISSING" }); trigger = $true; execution = ($null -ne $sc); result = [bool]($sc -and $sc.phase1); evidence = "showcase.json" },
[pscustomobject]@{ id = "OBL-04:TasksTracked"; status = $(if ($tCnt -gt 0) { "PASS" } else { "MISSING" }); trigger = $true; execution = ($tCnt -gt 0); result = ($tCnt -gt 0); evidence = "tasks.json" },
[pscustomobject]@{ id = "OBL-05:TestEvidenceVerified"; status = $(if ($validEvCnt -gt 0) { "PASS" } elseif ($ev) { "PARTIAL" } else { "MISSING" }); trigger = $true; execution = ($null -ne $ev); result = ($validEvCnt -gt 0); evidence = "evidence.json" },
[pscustomobject]@{ id = "OBL-06:StateSealIntact"; status = $(if ($sOk) { "PASS" } elseif (Test-Path -LiteralPath $sf) { "PARTIAL" } else { "MISSING" }); trigger = $true; execution = (Test-Path -LiteralPath $sf); result = $sOk; evidence = "state-seal.json" }
)
if ([string]::IsNullOrWhiteSpace($DraftResponse) -or $EnforceAllObligations.IsPresent) {
foreach ($o in $obl) { if ([bool]$o.trigger -and [string]$o.status -ne "PASS" -and (-not $miss.Contains("MissingObligation:$($o.id)"))) { $miss.Add("MissingObligation:$($o.id)") } }
}
$bm = (Get-SenMemorySnapshot -Workspace $Workspace).BaselineMetrics
return [pscustomobject]@{ Passed = ($miss.Count -eq 0); Tier = $tier; UserName = $uName; MissingElements = @($miss.ToArray()); ObligationMatrix = $obl; BaselineMetrics = $bm; ReminderText = "[SEN WATCHDOG] Verify Tier $tier requirements: $($miss -join ', ')" }
}
Export-ModuleMember -Function Resolve-SenWorkspaceRoot, Test-SenSafeWorkspacePath, Register-SenRequirement, Register-SenEvidence, Test-SenEvidenceValidity, Get-SenRequirementTraceability, Invoke-SenTaskTransition, Invoke-SenChangeImpactAnalysis, Invoke-SenCheckpointResume, Test-SenMidTaskEscalation, Test-SenSuiteIntegrity, Measure-SenTokenEstimate, Set-SenEdition, Get-SenDeferredItems, Uninstall-SenSelf, Add-SenExecutionLesson, Get-SenExecutionLessons, Get-SenMemorySnapshot, Sync-SenOfficeState, Initialize-SenIntake, Test-SenIntakeCompleteness
