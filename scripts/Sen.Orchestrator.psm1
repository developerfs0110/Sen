# scripts/Sen.Orchestrator.psm1 - Sen Orchestrator, Task DAG, Lock, Restore & Code Health
$ErrorActionPreference = "Stop"
function Save-SenTasks {
[CmdletBinding()]
param([Parameter(Mandatory)][Alias("WorkspacePath", "Path")][string]$Workspace, [AllowEmptyCollection()][Parameter(Mandatory)][object[]]$Tasks, [switch]$Internal)
$tasksPath = Join-Path $Workspace ".agents/office/tasks.json"
$canonPath = [IO.Path]::GetFullPath($tasksPath).Replace('\', '/').ToLowerInvariant()
$shaHex = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($canonPath)))).Replace("-", "").Substring(0, 24).ToLowerInvariant()
$mtxName = "Local\SenTasksMutex_" + $shaHex
$mtx = [Threading.Mutex]::new($false, $mtxName); $hasLock = $false
try {
try { $hasLock = $mtx.WaitOne(5000) } catch [Threading.AbandonedMutexException] { $hasLock = $true }
if (-not $hasLock) { throw "Concurrency lock timeout acquiring '$mtxName' on '$tasksPath'." }
$finalList = [Collections.Generic.List[object]]::new()
$diskObj = if (Test-Path -LiteralPath $tasksPath) { Read-SenSafeJson -Path $tasksPath } else { $null }
$diskArr = if ($null -ne $diskObj -and $diskObj.PSObject.Properties['tasks']) { @($diskObj.tasks) } else { @() }
$diskMap = @{}; $seenIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($dt in $diskArr) { if ($dt -and $dt.id) { $diskMap[[string]$dt.id] = $dt } }
foreach ($t in $Tasks) {
if (-not $t) { continue }
$tid = [string]$t.id; [void]$seenIds.Add($tid)
$tRev = if ($t.PSObject.Properties['_rev']) { [int]$t._rev } else { 1 }
$dt = if ($diskMap.ContainsKey($tid)) { $diskMap[$tid] } else { $null }
$dRev = if ($null -ne $dt -and $dt.PSObject.Properties['_rev']) { [int]$dt._rev } else { 0 }
if ($null -ne $dt -and $dRev -gt $tRev) { $finalList.Add($dt); continue }
$changed = ($null -ne $dt) -and (([string]$t.status -ne [string]$dt.status) -or ([string]$t.title -ne [string]$dt.title) -or ([string]$t.assignee -ne [string]$dt.assignee))
$newRev = if ($changed) { [Math]::Max($tRev, $dRev + 1) } else { $tRev }
$t | Add-Member -NotePropertyName "_rev" -NotePropertyValue $newRev -Force
$finalList.Add($t)
}
if (-not $Internal) { foreach ($dk in $diskMap.Keys) { if (-not $seenIds.Contains($dk)) { $finalList.Add($diskMap[$dk]) } } }
$payload = [ordered]@{ version = 1; updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); tasks = @($finalList.ToArray()) }
Write-SenAtomicJson -Path $tasksPath -InputObject $payload -Depth 8
return @($finalList.ToArray())
}
finally {
if ($hasLock) { try { $mtx.ReleaseMutex() } catch { <# Ignore #> } }
$mtx.Dispose()
}
}
function Get-SenTasks {
[CmdletBinding()] param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
$obj = Read-SenSafeJson -Path (Join-Path $Workspace ".agents/office/tasks.json")
if ($null -eq $obj) { return @() }
$list = if ($obj.PSObject.Properties['tasks']) { @($obj.tasks) } elseif ($obj -is [array]) { @($obj) } else { @() }
$doneIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($t in $list) { if ($t -and [string]$t.status -eq "done") { [void]$doneIds.Add([string]$t.id) } }
$changed = $false
foreach ($t in $list) {
if (-not $t -or [string]$t.status -ne "pending") { continue }
$allDone = $true
foreach ($d in @($t.dependsOn | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
if (-not $doneIds.Contains([string]$d)) { $allDone = $false; break }
}
if ($allDone) {
$t.status = "ready"
$curRev = if ($t.PSObject.Properties['_rev']) { [int]$t._rev } else { 1 }
$t | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
$changed = $true
}
}
if ($changed) { [void](Save-SenTasks -Workspace $Workspace -Tasks $list -Internal) }
return @($list)
}
function Clear-SenTasks {
[CmdletBinding()] param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
$tasksPath = Join-Path $Workspace ".agents/office/tasks.json"
if (Test-Path -LiteralPath $tasksPath) { Remove-Item -LiteralPath $tasksPath -Force -EA SilentlyContinue }
}
function New-SenTask {
[CmdletBinding()]
param(
[Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$Id = "", [Parameter(Mandatory)][string]$Title,
[int]$Tier = 2, [string]$RiskLevel = "medium", [string]$Module = "Core", [string]$Assignee = "dev_be",
[string[]]$DependsOn = @(), [Alias("Files")][string[]]$AllowedPaths = @(), [string[]]$ForbiddenActions = @("delete_database", "force_push"),
[bool]$ApprovalRequired = $false, [string[]]$AcceptanceCriteria = @(),
[ValidateSet("auto", "backlog", "pending", "ready", "todo", "in_progress", "reviewing", "done", "blocked", "failed")][string]$Status = "auto"
)
if ([string]::IsNullOrWhiteSpace($Id)) { $Id = "TASK-" + [DateTime]::UtcNow.ToString("HHmmss") }
$tasks = [Collections.Generic.List[object]]::new(); $prevRev = 0
foreach ($existing in @(Get-SenTasks -Workspace $Workspace)) {
if ($existing -and [string]$existing.id -ne $Id) { $tasks.Add($existing) }
elseif ($existing -and $existing.PSObject.Properties['_rev']) { $prevRev = [int]$existing._rev }
}
$cleanDeps = @($DependsOn | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$cleanPaths = @($AllowedPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$cleanForbidden = @($ForbiddenActions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$cleanCriteria = @($AcceptanceCriteria | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$resolvedStatus = $Status
if ($resolvedStatus -eq "auto") {
if ($cleanDeps.Count -eq 0) { $resolvedStatus = "ready" }
else {
$doneIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($t in $tasks) { if ([string]$t.status -eq "done") { [void]$doneIds.Add([string]$t.id) } }
$allDepsDone = $true
foreach ($d in $cleanDeps) { if (-not $doneIds.Contains([string]$d)) { $allDepsDone = $false; break } }
$resolvedStatus = if ($allDepsDone) { "ready" } else { "pending" }
}
}
$now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
$newTask = [pscustomobject][ordered]@{
id = $Id; title = $Title; tier = $Tier; riskLevel = $RiskLevel; module = $Module; assignee = $Assignee
dependsOn = $cleanDeps; allowedPaths = $cleanPaths; forbiddenActions = $cleanForbidden
approvalRequired = $ApprovalRequired; acceptanceCriteria = $cleanCriteria; status = $resolvedStatus; reworkCount = 0
evidence = [pscustomobject][ordered]@{ command = ""; exitCode = $null; reviewer = ""; verifiedAt = $null; notes = "" }
createdAt = $now; updatedAt = $now; _rev = ($prevRev + 1)
}
$tasks.Add($newTask)
[void](Save-SenTasks -Workspace $Workspace -Tasks $tasks.ToArray())
return $newTask
}
function Get-SenReadyTasks {
[CmdletBinding()] param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
$tasks = @(Get-SenTasks -Workspace $Workspace)
$activeTasks = @($tasks | Where-Object { [string]$_.status -eq "in_progress" })
$results = [Collections.Generic.List[object]]::new()
foreach ($t in $tasks) {
if ([string]$t.status -notin @("ready", "todo")) { continue }
$conflictId = $null
foreach ($act in $activeTasks) {
if ([string]$act.id -eq [string]$t.id) { continue }
if (Test-SenPathOverlap -PathsA @($t.allowedPaths) -PathsB @($act.allowedPaths)) { $conflictId = [string]$act.id; break }
}
$results.Add([pscustomobject]@{ Task = $t; Id = [string]$t.id; IsReady = ($null -eq $conflictId); FileConflictWith = $conflictId })
}
return @($results.ToArray())
}
function Start-SenTask {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [Parameter(Mandatory)][string]$Id, [Alias("Actor")][string]$Assignee = "", [Alias("Notes")][string]$Note = "")
$tasks = @(Get-SenTasks -Workspace $Workspace)
$target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
if ($null -eq $target) { return [pscustomobject]@{ Started = $false; Status = "not_found"; ConflictTaskId = $null; Reason = "Task '$Id' not found" } }
$doneIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($t in $tasks) { if ([string]$t.status -eq "done") { [void]$doneIds.Add([string]$t.id) } }
$missingDeps = [Collections.Generic.List[string]]::new()
foreach ($d in @($target.dependsOn)) {
if (-not [string]::IsNullOrWhiteSpace([string]$d) -and -not $doneIds.Contains([string]$d)) { $missingDeps.Add([string]$d) }
}
if ($missingDeps.Count -gt 0) {
return [pscustomobject]@{ Started = $false; Status = "blocked_dependency"; ConflictTaskId = $null; Reason = "Task '$Id' is waiting on dependencies: $($missingDeps -join ', ')" }
}
foreach ($t in $tasks) {
if ([string]$t.id -eq $Id -or [string]$t.status -ne "in_progress") { continue }
if (Test-SenPathOverlap -PathsA @($target.allowedPaths) -PathsB @($t.allowedPaths)) {
return [pscustomobject]@{ Started = $false; Status = "blocked_file_lock"; ConflictTaskId = [string]$t.id; Reason = "File lock conflict: '$Id' shares allowedPaths with active task '$($t.id)' ($($t.assignee))" }
}
}
$target.status = "in_progress"
if (-not [string]::IsNullOrWhiteSpace($Assignee)) { $target.assignee = $Assignee }
$curRev = if ($target.PSObject.Properties['_rev']) { [int]$target._rev } else { 1 }
$target | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
$target.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
[void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
return [pscustomobject]@{ Started = $true; Status = "in_progress"; ConflictTaskId = $null; Task = $target; Reason = $null }
}
function Unlock-SenTask {
[CmdletBinding()] param([Parameter(Mandatory)][string]$Workspace, [Parameter(Mandatory)][string]$Id)
$tasks = @(Get-SenTasks -Workspace $Workspace)
$target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
if ($null -eq $target) { return [pscustomobject]@{ Unlocked = $false; Status = "not_found"; Reason = "Task '$Id' not found" } }
$target.status = "ready"
$curRev = if ($target.PSObject.Properties['_rev']) { [int]$target._rev } else { 1 }
$target | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
$target.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
[void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
return [pscustomobject]@{ Unlocked = $true; Status = "ready"; Task = $target }
}
function Submit-SenTaskForReview {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [Parameter(Mandatory)][string]$Id, [Alias("Note")][string]$Notes = "", [string]$Actor = "")
$tasks = @(Get-SenTasks -Workspace $Workspace)
$target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
if ($null -eq $target) { return [pscustomobject]@{ Submitted = $false; Reason = "Task '$Id' not found" } }
$target.status = "reviewing"
if (-not [string]::IsNullOrWhiteSpace($Notes) -and $target.evidence) { $target.evidence.notes = $Notes }
$curRev = if ($target.PSObject.Properties['_rev']) { [int]$target._rev } else { 1 }
$target | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
$target.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
[void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
return [pscustomobject]@{ Submitted = $true; Status = "reviewing"; Task = $target }
}
function Complete-SenTaskReview {
[CmdletBinding()]
param(
[Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
[Parameter(Mandatory)][string]$Id, [bool]$Passed = $true,
[string]$Reviewer = "tester", [string]$EvidenceCommand = "", [int]$ExitCode = 0,
[Alias("Note")][string]$Notes = "", [string]$Verdict = "", [switch]$FromTodoSync, [switch]$ExecuteCommand
)
if ($Verdict -match '(?i)^(REJECT|FAIL)') { $Passed = $false }
$tasks = @(Get-SenTasks -Workspace $Workspace)
$target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
if ($null -eq $target) { return [pscustomobject]@{ Completed = $false; Status = "not_found"; Reason = "Task '$Id' not found" } }
$validRoles = @("reviewer", "tester", "qa", "sec", "security", "owner-judge", "judge", "pm", "arch", "lead", "techlead", "tech_lead")
if ($validRoles -notcontains $Reviewer.Trim().ToLowerInvariant()) {
return [pscustomobject]@{ Completed = $false; Status = [string]$target.status; Reason = "Unrecognized or unauthenticated Reviewer role '$Reviewer'." }
}
$now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
$curRev = if ($target.PSObject.Properties['_rev']) { [int]$target._rev } else { 1 }
$placeholderRe = '^(?i)(subagent-verified|verified-in-session|session-verified|hook-telemetry|subagent-report|subagent-closed|(echo|write-host|write-output|true|rem|::)\b.*|.*fake-pass.*)$'
if ($Passed) {
if ((-not $FromTodoSync.IsPresent) -and ([string]$target.status -notin @("in_progress", "reviewing", "done"))) {
return [pscustomobject]@{ Completed = $false; Status = [string]$target.status; Reason = "State transition blocked: task '$Id' is '$($target.status)' and must be started (in_progress/reviewing) before completion." }
}
if ([string]::IsNullOrWhiteSpace($EvidenceCommand) -or $EvidenceCommand -notmatch '[A-Za-z0-9]{3,}' -or $EvidenceCommand -match $placeholderRe -or $ExitCode -ne 0) {
return [pscustomobject]@{ Completed = $false; Status = [string]$target.status; Reason = "Integration & Testing gate requires a valid non-placeholder executable EvidenceCommand and ExitCode = 0 to mark '$Id' done." }
}
if ($ExecuteCommand.IsPresent -or ($env:SEN_ENFORCE_LIVE_EVIDENCE -eq "1")) {
$pwshBin = if (Get-Command pwsh -EA SilentlyContinue) { "pwsh" } else { "powershell" }
$liveOut = "" | & $pwshBin -NoProfile -NonInteractive -Command $EvidenceCommand 2>&1
$ExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 1 }
$outTxt = ($liveOut | ForEach-Object { [string]$_ }) -join "`n"
$outHash = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($outTxt)))).Replace("-", "").Substring(0, 16).ToLowerInvariant()
$Notes = if ($Notes) { "$Notes [liveHash=$outHash]" } else { "liveHash=$outHash" }
if ($ExitCode -ne 0) {
return [pscustomobject]@{ Completed = $false; Status = [string]$target.status; ExitCode = $ExitCode; Reason = "Live execution of EvidenceCommand failed with ExitCode = $ExitCode." }
}
}
$target.status = "done"
$target.evidence = [pscustomobject][ordered]@{ command = $EvidenceCommand; exitCode = $ExitCode; reviewer = $Reviewer; verifiedAt = $now; notes = $Notes }
$target | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
$target.updatedAt = $now
[void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
[void](Get-SenTasks -Workspace $Workspace)
if (Get-Command Sync-SenTasksToMarkdown -EA SilentlyContinue) { [void](Sync-SenTasksToMarkdown -Workspace $Workspace) }
return [pscustomobject]@{ Completed = $true; Status = "done"; Task = $target; Reason = $null }
}
else {
$target.reworkCount = [int]$target.reworkCount + 1; $target.status = "in_progress"
$target.evidence = [pscustomobject][ordered]@{ command = $EvidenceCommand; exitCode = $ExitCode; reviewer = $Reviewer; verifiedAt = $now; notes = $Notes }
$target | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
$target.updatedAt = $now
[void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
return [pscustomobject]@{ Completed = $false; Status = "in_progress"; ReworkCount = [int]$target.reworkCount; Task = $target; Reason = "Review failed; returned to in_progress for rework (#$($target.reworkCount))." }
}
}
function Get-SenHungProcessIds {
param([string]$Workspace, [int]$MaxProcessSeconds = 120, [bool]$HasActiveLongRunning = $false)
$hungPids = [Collections.Generic.List[int]]::new()
$maxSec = [Math]::Max(5, $MaxProcessSeconds); $procCutoff = (Get-Date).ToUniversalTime().AddSeconds(-1 * $maxSec)
$isTempWs = $Workspace -match '(?i)([\\/](temp|tmp|T)[\\/]|sen-(orch|harness|gov|adv|.*-test|test_)|TestDrive)'
$normWs = $Workspace.Replace('\', '/').TrimEnd('/')
try {
$winProcs = if ($env:OS -eq 'Windows_NT' -and (Get-Command Get-CimInstance -EA SilentlyContinue)) { @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -EA SilentlyContinue) } else { @() }
$anc = [Collections.Generic.HashSet[int]]::new(); $curP = $PID
for ($k = 0; $k -lt 4; $k++) { [void]$anc.Add($curP); $pe = $winProcs | Where-Object { [int]$_.ProcessId -eq $curP } | Select-Object -First 1; if ($pe -and [int]$pe.ParentProcessId -gt 0) { $curP = [int]$pe.ParentProcessId } else { break } }
$hiddenOffices = @($winProcs | Where-Object { [string]$_.CommandLine -match '(?i)start-office\.ps1' -and [string]$_.CommandLine -match '(?i)-WindowStyle\s+Hidden' } | Sort-Object CreationDate -Descending)
$keepPid = if ($hiddenOffices.Count -gt 0) { [int]$hiddenOffices[0].ProcessId } else { 0 }
foreach ($wp in $winProcs) {
$wpId = if ($wp) { [int]$wp.ProcessId } else { 0 }; $cmd = [string]$wp.CommandLine
if ($wpId -le 0 -or $anc.Contains($wpId) -or $wpId -eq $keepPid -or ($cmd -match '(?i)(shellIntegration\.ps1|PowerShellEditorServices|\bvite\b|\bnpm(\.cmd)?\s+run\s+(dev|start|serve|preview)\b)')) { continue }
if ($isTempWs -and ($cmd.Replace('\', '/').IndexOf($normWs, [StringComparison]::OrdinalIgnoreCase) -lt 0)) { continue }
$isTarget = ($cmd -match '(?i)(Test-SenDeliveryGate|Invoke-SenPostCodePipeline|Get-SenRemoteCiStatus|Measure-SenCodeHealth|Invoke-SenVnLawScan|Invoke-SenCiPushLoop)') -or (($cmd -match '(?i)start-office\.ps1') -and ($wpId -ne $keepPid)) -or ((-not $HasActiveLongRunning) -and ($cmd -match '(?i)(-Command\s+"try\s*\{\s*\$OutputEncoding|Sen\.psm1)') -and ($cmd -notmatch '(?i)\brun\.ps1\b'))
$proc = if ($isTarget) { Get-Process -Id $wpId -EA SilentlyContinue } else { $null }
if ($null -ne $proc -and $proc.StartTime.ToUniversalTime() -lt $procCutoff) { $hungPids.Add($wpId) }
}
$psLines = if ($env:OS -ne 'Windows_NT' -and (Get-Command ps -EA SilentlyContinue)) { @(& ps -eo pid,etimes,args 2>$null) } else { @() }
foreach ($line in $psLines) {
if ($line -match '^\s*(\d+)\s+(\d+)\s+(.+)$' -and [int]$matches[1] -ne $PID -and [int]$matches[2] -gt $maxSec -and $matches[3] -match '(?i)(Sen\.psm1|Invoke-SenCiPushLoop|Test-SenDeliveryGate|Invoke-SenPostCodePipeline)') {
if ((-not $isTempWs) -or ($matches[3].Replace('\', '/').IndexOf($normWs, [StringComparison]::OrdinalIgnoreCase) -ge 0)) { $hungPids.Add([int]$matches[1]) }
}
}
}
catch { <# Ignore #> }
return $hungPids.ToArray()
}
function Test-SenHungTasks {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [int]$StaleMinutes = 15, [Alias("TimeoutSeconds")][int]$MaxProcessSeconds = 120, [string]$LogContent = "")
$cutoff = (Get-Date).ToUniversalTime().AddMinutes(-1 * [Math]::Max(1, $StaleMinutes))
$inv = [Globalization.CultureInfo]::InvariantCulture; $utcSt = [Globalization.DateTimeStyles]::AdjustToUniversal
$staleTasks = [Collections.Generic.List[string]]::new(); $activeLongRunning = [Collections.Generic.List[string]]::new()
$staleSubs = [Collections.Generic.List[string]]::new(); $idleSubs = [Collections.Generic.List[string]]::new()
$deadlocked = [Collections.Generic.List[string]]::new()
$probeLog = Join-Path $Workspace ".agents/office/hung-probes.log"
$rawLog = $LogContent + "`n" + $(if (Test-Path -LiteralPath $probeLog) { [IO.File]::ReadAllText($probeLog) } else { "" })
foreach ($m in [regex]::Matches($rawLog, '(?i)(Supply values for the following parameters:|\[Y/n\]|Press any key to continue|Overwrite\s*\?)')) { $deadlocked.Add($m.Value.Trim()) }
$subFile = Join-Path $Workspace ".agents/office/subagents.json"
$subObj = if (Test-Path -LiteralPath $subFile) { Read-SenSafeJson -Path $subFile } else { $null }
$subList = if ($null -eq $subObj) { @() } elseif ($subObj.PSObject.Properties['subagents']) { @($subObj.subagents) } else { @($subObj) }
foreach ($t in @(Get-SenTasks -Workspace $Workspace)) {
if (-not $t -or [string]$t.status -ne "in_progress") { continue }
$rawTs = if ($t.PSObject.Properties['updatedAt'] -and $t.updatedAt) { [string]$t.updatedAt } elseif ($t.PSObject.Properties['createdAt'] -and $t.createdAt) { [string]$t.createdAt } else { "" }
$parsed = [DateTime]::MinValue
$isOld = [string]::IsNullOrWhiteSpace($rawTs) -or (-not [DateTime]::TryParse($rawTs, $inv, $utcSt, [ref]$parsed)) -or ($parsed -lt $cutoff)
if (-not $isOld) { continue }
$hbRaw = if ($t.PSObject.Properties['heartbeatAt'] -and $t.heartbeatAt) { [string]$t.heartbeatAt } else { "" }
$hbDt = [DateTime]::MinValue
$hasHb = (-not [string]::IsNullOrWhiteSpace($hbRaw)) -and [DateTime]::TryParse($hbRaw, $inv, $utcSt, [ref]$hbDt) -and ($hbDt -ge $cutoff)
$hasFileMod = $false
foreach ($ap in @($t.allowedPaths)) {
if ([string]::IsNullOrWhiteSpace([string]$ap) -or [string]$ap -match '^(?i)(\.|/|\*|\.agents.*|Code|node_modules)$') { continue }
$apFull = Join-Path $Workspace ([string]$ap)
if (Test-Path -LiteralPath $apFull -PathType Leaf) { if ((Get-Item -LiteralPath $apFull).LastWriteTimeUtc -ge $cutoff) { $hasFileMod = $true; break } }
elseif (Test-Path -LiteralPath $apFull -PathType Container) { if (@(Get-ChildItem -LiteralPath $apFull -File -EA SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -ge $cutoff }).Count -gt 0) { $hasFileMod = $true; break } }
}
$hasSubProg = $false
foreach ($s in $subList) {
$sState = if ($s.PSObject.Properties['state'] -and $s.state) { [string]$s.state } else { [string]$s.status }
$sStepRaw = if ($s.PSObject.Properties['lastStepTime'] -and $s.lastStepTime) { [string]$s.lastStepTime } elseif ($s.PSObject.Properties['heartbeatAt'] -and $s.heartbeatAt) { [string]$s.heartbeatAt } else { "" }
$sStepDt = [DateTime]::MinValue
$sMatch = ($s.PSObject.Properties['taskId'] -and [string]$s.taskId -eq [string]$t.id) -or ($s.PSObject.Properties['role'] -and [string]$s.role -eq [string]$t.assignee)
if ($sState -eq "running" -and $sMatch -and (-not [string]::IsNullOrWhiteSpace($sStepRaw)) -and [DateTime]::TryParse($sStepRaw, $inv, $utcSt, [ref]$sStepDt) -and ($sStepDt -ge $cutoff)) { $hasSubProg = $true; break }
}
if ($hasHb -or $hasFileMod -or $hasSubProg) { $activeLongRunning.Add([string]$t.id) } else { $staleTasks.Add([string]$t.id) }
}
foreach ($s in $subList) {
if (-not $s) { continue }
$sid = if ($s.PSObject.Properties['id'] -and $s.id) { [string]$s.id } elseif ($s.PSObject.Properties['conversationId']) { [string]$s.conversationId } else { "unknown-subagent" }
$sState = if ($s.PSObject.Properties['state'] -and $s.state) { [string]$s.state } else { [string]$s.status }
if ($sState -in @("idle", "completed")) { $idleSubs.Add($sid); continue }
if ($sState -notin @("running", "active", "in_progress")) { continue }
$sTs = if ($s.PSObject.Properties['lastStepTime'] -and $s.lastStepTime) { [string]$s.lastStepTime } elseif ($s.PSObject.Properties['heartbeatAt'] -and $s.heartbeatAt) { [string]$s.heartbeatAt } elseif ($s.PSObject.Properties['updatedAt'] -and $s.updatedAt) { [string]$s.updatedAt } elseif ($s.PSObject.Properties['startedAt'] -and $s.startedAt) { [string]$s.startedAt } else { "" }
$sParsed = [DateTime]::MinValue
$sOld = [string]::IsNullOrWhiteSpace($sTs) -or (-not [DateTime]::TryParse($sTs, $inv, $utcSt, [ref]$sParsed)) -or ($sParsed -lt $cutoff)
$ownsActive = ($s.PSObject.Properties['taskId'] -and ($activeLongRunning -contains [string]$s.taskId))
if ($sOld -and (-not $ownsActive)) { $staleSubs.Add($sid) }
}
$hungPids = @(Get-SenHungProcessIds -Workspace $Workspace -MaxProcessSeconds $MaxProcessSeconds -HasActiveLongRunning ($activeLongRunning.Count -gt 0))
foreach ($hp in $hungPids) { $deadlocked.Add("OSHungProcess:PID=$hp") }
return [pscustomobject][ordered]@{
Healthy = ($staleTasks.Count -eq 0 -and $staleSubs.Count -eq 0 -and $deadlocked.Count -eq 0 -and $hungPids.Count -eq 0); StaleMinutes = $StaleMinutes; MaxProcessSeconds = $MaxProcessSeconds
StaleTaskIds = @($staleTasks.ToArray()); StaleSubagents = @($staleSubs.ToArray()); ActiveLongRunningIds = @($activeLongRunning.ToArray())
IdleSubagents = @($idleSubs.ToArray()); DeadlockedItems = @($deadlocked.ToArray()); HungProcessIds = $hungPids; CheckedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
}
}
function Clear-SenHungTasks {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [int]$StaleMinutes = 15, [Alias("TimeoutSeconds")][int]$MaxProcessSeconds = 120, [ValidateSet("reset_to_todo", "mark_blocked", "ready", "blocked")][string]$Resolution = "reset_to_todo", [string]$LogContent = "")
$check = Test-SenHungTasks -Workspace $Workspace -StaleMinutes $StaleMinutes -MaxProcessSeconds $MaxProcessSeconds -LogContent $LogContent
$killedPids = [Collections.Generic.List[int]]::new()
foreach ($hp in @($check.HungProcessIds)) {
if ($hp -and [int]$hp -ne $PID) { Stop-Process -Id ([int]$hp) -Force -EA SilentlyContinue; $killedPids.Add([int]$hp) }
}
$newStatus = if ($Resolution -in @("mark_blocked", "blocked")) { "blocked" } elseif ($Resolution -eq "ready") { "ready" } else { "todo" }
$now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
$clearedTasks = [Collections.Generic.List[string]]::new()
$protectedSet = [Collections.Generic.HashSet[string]]::new([string[]]@($check.ActiveLongRunningIds), [StringComparer]::OrdinalIgnoreCase)
if ($check.StaleTaskIds.Count -gt 0) {
$tasks = @(Get-SenTasks -Workspace $Workspace)
$staleSet = [Collections.Generic.HashSet[string]]::new([string[]]@($check.StaleTaskIds), [StringComparer]::OrdinalIgnoreCase)
foreach ($t in $tasks) {
if ($t -and $staleSet.Contains([string]$t.id) -and (-not $protectedSet.Contains([string]$t.id))) {
$t.status = $newStatus; $t.updatedAt = $now
$noteMsg = "Cleared hung task (> ${StaleMinutes}m) -> $newStatus"
if ($t.evidence) { $t.evidence.notes = $noteMsg }
$t | Add-Member -NotePropertyName "notes" -NotePropertyValue $noteMsg -Force
$curRev = if ($t.PSObject.Properties['_rev']) { [int]$t._rev } else { 1 }
$t | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
$clearedTasks.Add([string]$t.id)
}
}
[void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
}
$clearedSubs = [Collections.Generic.List[string]]::new(); $closedIdle = [Collections.Generic.List[string]]::new()
$subFile = Join-Path $Workspace ".agents/office/subagents.json"
if (($check.StaleSubagents.Count -gt 0 -or $check.IdleSubagents.Count -gt 0) -and (Test-Path -LiteralPath $subFile)) {
$subObj = Read-SenSafeJson -Path $subFile
$isWrapped = ($null -ne $subObj -and [bool]$subObj.PSObject.Properties['subagents'])
$subList = if ($null -eq $subObj) { @() } elseif ($isWrapped) { @($subObj.subagents) } else { @($subObj) }
$subSet = [Collections.Generic.HashSet[string]]::new([string[]]@($check.StaleSubagents), [StringComparer]::OrdinalIgnoreCase)
$idleSet = [Collections.Generic.HashSet[string]]::new([string[]]@($check.IdleSubagents), [StringComparer]::OrdinalIgnoreCase)
foreach ($s in $subList) {
$sid = if ($s.PSObject.Properties['id'] -and $s.id) { [string]$s.id } elseif ($s.PSObject.Properties['conversationId']) { [string]$s.conversationId } else { "" }
if ($sid -and $subSet.Contains($sid)) {
$s | Add-Member -NotePropertyName "status" -NotePropertyValue "terminated_hung" -Force
$s | Add-Member -NotePropertyName "state" -NotePropertyValue "terminated_hung" -Force
$s | Add-Member -NotePropertyName "updatedAt" -NotePropertyValue $now -Force
$clearedSubs.Add($sid)
}
elseif ($sid -and $idleSet.Contains($sid)) {
$s | Add-Member -NotePropertyName "status" -NotePropertyValue "closed_idle" -Force
$s | Add-Member -NotePropertyName "state" -NotePropertyValue "closed_idle" -Force
$s | Add-Member -NotePropertyName "updatedAt" -NotePropertyValue $now -Force
$closedIdle.Add($sid)
}
}
$outPayload = if ($isWrapped) { $subObj.subagents = $subList; $subObj } else { $subList }
Write-SenAtomicJson -Path $subFile -InputObject $outPayload -Depth 6
}
return [pscustomobject][ordered]@{
ClearedCount = ($clearedTasks.Count + $clearedSubs.Count + $killedPids.Count); ClearedTaskIds = @($clearedTasks.ToArray())
ClearedSubagents = @($clearedSubs.ToArray()); ClosedIdleSubagents = @($closedIdle.ToArray()); KilledProcessIds = @($killedPids.ToArray())
ProtectedLongRunningIds = @($check.ActiveLongRunningIds); Resolution = $Resolution; NewStatus = $newStatus
}
}
function Test-SenDeliveryGate {
[CmdletBinding()]
param(
[Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
[string]$ProjectPath = "", [string]$SessionStartedAt = "", [int]$StaleMinutes = 15, [int]$Tier = 0, [string[]]$ModifiedFiles = @(),
[switch]$RequireActiveSessionTask, [switch]$CheckCodeHealth, [switch]$CheckVnLaw, [switch]$SkipCodeHealth, [switch]$SkipVnLaw, [switch]$EnforcePhysicalDiff, [switch]$SkipPhysicalDiff
)
$targetDir = if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath } else { $Workspace }
if (Get-Command Sync-SenPlanToTasks -EA SilentlyContinue) { [void](Sync-SenPlanToTasks -Workspace $Workspace) }
$hungObj = Test-SenHungTasks -Workspace $Workspace -StaleMinutes $StaleMinutes
$tasks = @(Get-SenTasks -Workspace $Workspace)
$active = @($tasks | Where-Object { [string]$_.status -ne "backlog" -and (-not ($_.PSObject.Properties['isTelemetryOnly'] -and [bool]$_.isTelemetryOnly)) })
$incomplete = [Collections.Generic.List[string]]::new(); $rems = [Collections.Generic.List[string]]::new(); $doneCount = 0
$placeholderRe = '^(?i)(subagent-verified|verified-in-session|session-verified|hook-telemetry|subagent-report|subagent-closed|(echo|write-host|write-output|true|rem|::)\b.*|.*fake-pass.*)$'
foreach ($t in $active) {
$evCmd = if ($null -ne $t.evidence) { [string]$t.evidence.command } else { "" }
if ([string]$t.status -eq "done" -and (-not [string]::IsNullOrWhiteSpace($evCmd)) -and ($evCmd -notmatch $placeholderRe) -and ([int]$t.evidence.exitCode -eq 0)) { $doneCount++ } else { $incomplete.Add([string]$t.id) }
}
$reasons = [Collections.Generic.List[string]]::new()
$allowed = ($active.Count -gt 0) -and ($incomplete.Count -eq 0) -and $hungObj.Healthy
if (-not $hungObj.Healthy) { $reasons.Add("Hung tasks or stale subagents ($((@($hungObj.StaleTaskIds) + @($hungObj.StaleSubagents) + @($hungObj.HungProcessIds)) -join ', '))"); $rems.Add("Clear-SenHungTasks -Workspace '$Workspace'") }
if ($active.Count -eq 0) { $reasons.Add("No active tasks registered in tasks.json"); $rems.Add("New-SenTask -Workspace '$Workspace' -Title 'Task'") }
elseif ($incomplete.Count -gt 0) { $reasons.Add("Incomplete or unverified tasks ($($incomplete -join ', '))"); $rems.Add("Complete-SenTaskReview -Workspace '$Workspace' -Id '$($incomplete[0])' -Passed `$true -Reviewer 'qa' -EvidenceCommand 'tests/run.ps1' -ExitCode 0") }
$ofDir = Join-Path $Workspace ".agents/office"; $auditFile = Join-Path $ofDir "process-audit.json"
$auditObj = if (Test-Path -LiteralPath $auditFile) { Read-SenSafeJson -Path $auditFile } else { $null }
$hasTier3 = ($Tier -ge 3) -or (@($active | Where-Object { $_.PSObject.Properties['tier'] -and [int]$_.tier -ge 3 }).Count -gt 0)
if ($hasTier3 -and $null -eq $auditObj -and (-not (Test-Path -LiteralPath (Join-Path $ofDir "requirements.json"))) -and (-not (Test-Path -LiteralPath (Join-Path $ofDir "claims.json")))) {
$allowed = $false; $reasons.Add("Tier 3 governance artifacts missing (process-audit.json / requirements.json / claims.json)"); $rems.Add("Initialize-SenProcessAudit -Workspace '$Workspace' -Tier 3")
}
$sessStart = if ($SessionStartedAt) { $SessionStartedAt } elseif ($auditObj -and $auditObj.PSObject.Properties['startedAt']) { [string]$auditObj.startedAt } else { "" }
if ($active.Count -gt 0 -and ($sessStart -or $RequireActiveSessionTask.IsPresent)) {
$minTs = if ($sessStart) { $sessStart } else { [DateTime]::UtcNow.AddHours(-4).ToString("yyyy-MM-ddTHH:mm:ssZ") }
$sessionDone = @($active | Where-Object { [string]$_.status -eq "done" -and ([string]$_.updatedAt -ge $minTs -or ($_.evidence -and ([string]$_.evidence.verifiedAt -ge $minTs -or [string]$_.evidence.at -ge $minTs))) })
if ($sessionDone.Count -eq 0) { $allowed = $false; $reasons.Add("No tasks verified in current audit session since $minTs"); $rems.Add("Initialize-SenProcessAudit -Workspace '$Workspace'") }
}
$codeHealthObj = if ((-not $SkipCodeHealth.IsPresent) -and (Get-Command Measure-SenCodeHealth -EA SilentlyContinue)) { Measure-SenCodeHealth -Path $targetDir } else { $null }
if ($null -ne $codeHealthObj -and (-not $codeHealthObj.Healthy)) { $allowed = $false; $reasons.Add("Clean Code check failed (Score=$($codeHealthObj.Score))"); $rems.Add("Measure-SenCodeHealth -Path '$targetDir'") }
$vnLawObj = if ((-not $SkipVnLaw.IsPresent) -and (Get-Command Invoke-SenVnLawScan -EA SilentlyContinue)) { Invoke-SenVnLawScan -Path $targetDir } else { $null }
if ($null -ne $vnLawObj -and ((-not $vnLawObj.CompliantCodeLevel) -or ($vnLawObj.Verdict -notin @("PASS", "NOT_APPLICABLE")))) {
$allowed = $false; $codes = @($vnLawObj.CodeRedFlags | ForEach-Object { $_.Code }) -join ', '; $reasons.Add("Vietnam Law gate blocked (Verdict=$($vnLawObj.Verdict); RedFlags=$codes)"); $rems.Add("Invoke-SenVnLawScan -Path '$targetDir'")
}
if ((Test-Path -LiteralPath (Join-Path $ofDir "state-seal.json")) -and (Get-Command Sync-SenOfficeState -EA SilentlyContinue)) {
$sealRes = Sync-SenOfficeState -Workspace $Workspace -VerifySeal
if ($sealRes.Tampered) { $allowed = $false; $reasons.Add("State seal tampered ($($sealRes.TamperedFiles -join ', '))"); $rems.Add($sealRes.RemediationCommand) }
}
$complianceObj = if ($null -ne $auditObj -and (Get-Command Test-SenProjectCompliance -EA SilentlyContinue)) { Test-SenProjectCompliance -Workspace $Workspace -ProjectPath $targetDir } else { $null }
if ($null -ne $complianceObj -and (-not $complianceObj.Compliant)) { $allowed = $false; $reasons.Add("Process Compliance missing steps ($($complianceObj.MissingSteps -join ', '))"); $rems.Add("Test-SenProjectCompliance -Workspace '$Workspace'") }
$rtmObj = if ((Test-Path -LiteralPath (Join-Path $ofDir "requirements.json")) -and (Get-Command Get-SenRequirementTraceability -EA SilentlyContinue)) { Get-SenRequirementTraceability -Workspace $Workspace } else { $null }
if ($null -ne $rtmObj -and (-not $rtmObj.Accepted)) { $allowed = $false; $reasons.Add("Requirement Traceability NOT_ACCEPTED (Unverified=$($rtmObj.UnverifiedRequirements -join ', '))"); $rems.Add("Get-SenRequirementTraceability -Workspace '$Workspace'") }
if ((Test-Path -LiteralPath (Join-Path $ofDir "quality-baseline.json")) -and (Get-Command Test-SenAntiMetricGaming -EA SilentlyContinue)) {
$amgObj = Test-SenAntiMetricGaming -Workspace $Workspace
if (-not $amgObj.Passed) { $allowed = $false; $reasons.Add("Anti-Metric Gaming violation ($($amgObj.Violations -join '; '))"); $rems.Add("Lock-SenQualityBaseline -Workspace '$Workspace'") }
}
if (Test-Path -LiteralPath (Join-Path $ofDir "bounded-loops.json")) {
$escClaims = @(Read-SenSafeJson -Path (Join-Path $ofDir "bounded-loops.json") | Where-Object { $_ -and [string]$_.state -in @("ESCALATED", "REJECTED") } | ForEach-Object { [string]$_.claimId })
if ($escClaims.Count -gt 0) { $allowed = $false; $reasons.Add("Quarantined ESCALATED claims awaiting pre-push review ($($escClaims -join ', '))"); $rems.Add("Invoke-SenEscalationQuarantine -Workspace '$Workspace' -ClaimId '$($escClaims[0])'") }
}
$clPath = Join-Path $ofDir "claims.json"
if (Test-Path -LiteralPath $clPath) {
$clRaw = Read-SenSafeJson -Path $clPath; $clArr = if ($null -eq $clRaw) { @() } elseif ($clRaw.PSObject.Properties['claims']) { @($clRaw.claims) } else { @($clRaw) }
$badCl = @($clArr | Where-Object { $_ -and (([string]$_.status -in @("REJECTED", "INCONCLUSIVE", "PROPOSED")) -or ([string]$_.decision -in @("REJECTED", "INCONCLUSIVE", "PROPOSED"))) } | ForEach-Object { if ($_.claimId) { [string]$_.claimId } else { [string]$_.id } })
if ($badCl.Count -gt 0) { $allowed = $false; $reasons.Add("Unresolved or rejected adversarial claims ($($badCl -join ', '))"); $rems.Add("Invoke-SenAdversarialCheck -Workspace '$Workspace'") }
}
if ((-not $SkipPhysicalDiff.IsPresent) -and ((-not $PSBoundParameters.ContainsKey('EnforcePhysicalDiff')) -or $EnforcePhysicalDiff.IsPresent) -and (Get-Command Test-SenEvidenceValidity -EA SilentlyContinue)) {
$evVal = Test-SenEvidenceValidity -Workspace $Workspace
if (-not $evVal.AllValid) { $allowed = $false; $reasons.Add("Physical diff / stale evidence ($($evVal.StaleEvidenceIds -join ', '))"); $rems.Add("Register-SenEvidence -Workspace '$Workspace' -Command 'tests/run.ps1' -ExitCode 0") }
}
$reason = if ($allowed) { "All $($active.Count) active task(s) verified and done." } else { "Delivery blocked: " + ($reasons -join "; ") + "." }
return [pscustomobject]@{
Allowed = $allowed; Passed = $allowed; TotalActive = $active.Count; DoneCount = $doneCount; IncompleteIds = @($incomplete.ToArray())
HungTasks = $hungObj; CodeHealth = $codeHealthObj; VnLawScan = $vnLawObj; ProcessCompliance = $complianceObj; RequirementTraceability = $rtmObj
Reason = $reason; Issues = @($reasons.ToArray()); RemediationCommands = @($rems.ToArray())
}
}
function Get-SenRecoveryState {
[CmdletBinding()] param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
$tasks = @(Get-SenTasks -Workspace $Workspace)
$inProgress = @($tasks | Where-Object { [string]$_.status -eq "in_progress" } | ForEach-Object { [string]$_.id })
$reviewing = @($tasks | Where-Object { [string]$_.status -eq "reviewing" } | ForEach-Object { [string]$_.id })
$ready = @($tasks | Where-Object { [string]$_.status -eq "ready" } | ForEach-Object { [string]$_.id })
$pending = @($tasks | Where-Object { [string]$_.status -eq "pending" } | ForEach-Object { [string]$_.id })
$done = @($tasks | Where-Object { [string]$_.status -eq "done" } | ForEach-Object { [string]$_.id })
$backlog = @($tasks | Where-Object { [string]$_.status -eq "backlog" } | ForEach-Object { [string]$_.id })
$failed = @($tasks | Where-Object { [string]$_.status -eq "failed" } | ForEach-Object { [string]$_.id })
return [pscustomobject][ordered]@{
needsRecovery = [bool](($inProgress.Count + $reviewing.Count + $failed.Count) -gt 0); totalTasks = $tasks.Count
doneIds = $done; inProgressIds = $inProgress; reviewingIds = $reviewing; readyIds = $ready; pendingIds = $pending; failedIds = $failed; backlogIds = $backlog
}
}
function Get-SenQualityMetrics {
[CmdletBinding()] param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
$tasks = @(Get-SenTasks -Workspace $Workspace)
$active = @($tasks | Where-Object { [string]$_.status -ne "backlog" }); $backlog = @($tasks | Where-Object { [string]$_.status -eq "backlog" })
$done = @($active | Where-Object { [string]$_.status -eq "done" }); $inProg = @($active | Where-Object { [string]$_.status -in @("in_progress", "reviewing") })
$ready = @($active | Where-Object { [string]$_.status -in @("ready", "pending") })
$totalActive = $active.Count; $doneCount = $done.Count
$firstPassCount = @($done | Where-Object { [int]$_.reworkCount -eq 0 }).Count; $reworkedCount = @($active | Where-Object { [int]$_.reworkCount -gt 0 }).Count
$verifiedPassCount = @($done | Where-Object { $null -ne $_.evidence -and [int]$_.evidence.exitCode -eq 0 }).Count
$successPct = if ($totalActive -gt 0) { [int][Math]::Round(($doneCount * 100.0) / $totalActive) } else { 100 }
$firstPassPct = if ($doneCount -gt 0) { [int][Math]::Round(($firstPassCount * 100.0) / $doneCount) } else { 100 }
$reworkPct = if ($totalActive -gt 0) { [int][Math]::Round(($reworkedCount * 100.0) / $totalActive) } else { 0 }
$testPassPct = if ($doneCount -gt 0) { [int][Math]::Round(($verifiedPassCount * 100.0) / $doneCount) } else { 100 }
$reqCovPct = 100
if ((Test-Path -LiteralPath (Join-Path $Workspace ".agents/office/requirements.json")) -and (Get-Command Get-SenRequirementTraceability -EA SilentlyContinue)) {
$rtm = Get-SenRequirementTraceability -Workspace $Workspace
if ($rtm.TotalRequirements -gt 0) { $reqCovPct = [int][Math]::Round(($rtm.Verified * 100.0) / $rtm.TotalRequirements) }
}
return [pscustomobject][ordered]@{
totalTasks = $tasks.Count; activeTasks = $totalActive; doneTasks = $doneCount; inProgressTasks = $inProg.Count
readyTasks = $ready.Count; backlogTasks = $backlog.Count; taskSuccessRatePct = $successPct
firstPassRatePct = $firstPassPct; reworkRatePct = $reworkPct; testPassRatePct = $testPassPct; requirementCoveragePct = $reqCovPct
}
}
function Add-SenBacklogItem {
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Workspace, [string]$Id = ("BL-" + [Guid]::NewGuid().ToString("N").Substring(0, 6)), [Parameter(Mandatory)][string]$Title, [string]$Priority = "P1", [string]$Details = "", [string]$Module = "Backlog")
$task = New-SenTask -Workspace $Workspace -Id $Id -Title $Title -Tier 2 -RiskLevel "medium" -Module $Module -Assignee "pm" -Status "backlog"
$docsDir = Join-Path $Workspace "docs"
if (-not (Test-Path -LiteralPath $docsDir)) { [IO.Directory]::CreateDirectory($docsDir) | Out-Null }
$todoPath = Join-Path $docsDir "TODO.md"
$existingText = if (Test-Path -LiteralPath $todoPath) { [IO.File]::ReadAllText((Resolve-Path -LiteralPath $todoPath).Path, [Text.Encoding]::UTF8) } else { "# Project Backlog (TODO)`n`n" }
if ($existingText -notmatch "(?<!\w)$([regex]::Escape($Id))(?!\w)") {
$entryLine = "- [ ] **${Id} (${Priority}): ${Title}**" + $(if (-not [string]::IsNullOrWhiteSpace($Details)) { "`n  - " + $Details.Trim() } else { "" })
[IO.File]::WriteAllText($todoPath, ($existingText.TrimEnd() + "`n`n" + $entryLine + "`n"), [Text.UTF8Encoding]::new($false))
}
return [pscustomobject]@{ Id = $Id; Title = $Title; Priority = $Priority; TodoPath = $todoPath; Task = $task }
}
function New-SenRestorePoint {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string[]]$Files = @(), [string]$Label = "pre-edit")
$resolvedWs = (Resolve-Path -LiteralPath $Workspace).Path.TrimEnd('\', '/')
$restoreRoot = Join-Path $resolvedWs ".agents/.sen-restore"
$ts = [DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
$id = "rp-$ts-" + ([Guid]::NewGuid().ToString("N").Substring(0, 6))
$rpDir = Join-Path $restoreRoot $id; $filesDir = Join-Path $rpDir "files"
[IO.Directory]::CreateDirectory($filesDir) | Out-Null
$skipHeavyRe = '(?i)(^|[\\/])(node_modules|\.git|\.agents|Code|Antigravity IDE|dist|build)([\\/]|$)'
$entries = [Collections.Generic.List[object]]::new(); $idx = 0
foreach ($f in $Files) {
if ([string]::IsNullOrWhiteSpace($f) -or ($f -match $skipHeavyRe)) { continue }
$fullPath = if ([IO.Path]::IsPathRooted($f)) { [IO.Path]::GetFullPath($f) } else { [IO.Path]::GetFullPath((Join-Path $resolvedWs $f)) }
$relPath = if ($fullPath.StartsWith($resolvedWs, [StringComparison]::OrdinalIgnoreCase)) { $fullPath.Substring($resolvedWs.Length).TrimStart('\', '/') } else { [IO.Path]::GetFileName($fullPath) }
if ($relPath -match $skipHeavyRe) { continue }
$existed = Test-Path -LiteralPath $fullPath -PathType Leaf; $storedName = "f_$idx.bak"
if ($existed) { Copy-Item -LiteralPath $fullPath -Destination (Join-Path $filesDir $storedName) -Force }
$entries.Add([ordered]@{ relPath = $relPath; fullPath = $fullPath; existed = [bool]$existed; storedName = $storedName }); $idx++
}
$manifest = [ordered]@{ id = $id; label = $Label; createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); entries = @($entries.ToArray()) }
Write-SenAtomicJson -Path (Join-Path $rpDir "manifest.json") -InputObject $manifest -Depth 6
if (Get-Command Write-SenOfficeEvent -EA SilentlyContinue) { [void](Write-SenOfficeEvent -Workspace $resolvedWs -From "pm" -To "sys" -Lane "Safety" -EcoText "RestorePoint: $id" -FullText "Created restore point $id ($Label)") }
return [pscustomobject]@{ Id = $id; Label = $Label; Directory = $rpDir; FileCount = $entries.Count }
}
function Restore-SenRestorePoint {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$Id = "")
$resolvedWs = (Resolve-Path -LiteralPath $Workspace).Path.TrimEnd('\', '/')
$restoreRoot = Join-Path $resolvedWs ".agents/.sen-restore"
if (-not (Test-Path -LiteralPath $restoreRoot)) { return [pscustomobject]@{ Restored = $false; Id = $null; Error = "No restore points found" } }
$targetDir = if (-not [string]::IsNullOrWhiteSpace($Id)) {
$cand = Join-Path $restoreRoot $Id
if (Test-Path -LiteralPath $cand) { Get-Item -LiteralPath $cand } else { $null }
}
else { Get-ChildItem -LiteralPath $restoreRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1 }
if ($null -eq $targetDir) { return [pscustomobject]@{ Restored = $false; Id = $Id; Error = "Restore point not found" } }
$manifest = Read-SenSafeJson -Path (Join-Path $targetDir.FullName "manifest.json")
if ($null -eq $manifest) { return [pscustomobject]@{ Restored = $false; Id = $targetDir.Name; Error = "Manifest missing" } }
$filesDir = Join-Path $targetDir.FullName "files"; $restoredCount = 0
foreach ($e in @($manifest.entries)) {
$destPath = Join-Path $resolvedWs ([string]$e.relPath)
if ([bool]$e.existed) {
$srcBak = Join-Path $filesDir ([string]$e.storedName)
if (Test-Path -LiteralPath $srcBak) {
$parent = Split-Path -Parent $destPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
Copy-Item -LiteralPath $srcBak -Destination $destPath -Force; $restoredCount++
}
}
elseif (Test-Path -LiteralPath $destPath) { Remove-Item -LiteralPath $destPath -Force -EA SilentlyContinue; $restoredCount++ }
}
return [pscustomobject]@{ Restored = $true; Id = [string]$manifest.id; RestoredCount = $restoredCount; Error = $null }
}
$senGovPath = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Governance.psm1"
if (Test-Path -LiteralPath $senGovPath) {
  Import-Module -Name $senGovPath -Global -Force
}
Export-ModuleMember -Function Save-SenTasks, Get-SenTasks, Clear-SenTasks, New-SenTask, Get-SenReadyTasks, Start-SenTask, Unlock-SenTask, Submit-SenTaskForReview, Complete-SenTaskReview, Test-SenHungTasks, Clear-SenHungTasks, Test-SenDeliveryGate, Get-SenRecoveryState, Get-SenQualityMetrics, Add-SenBacklogItem, New-SenRestorePoint, Restore-SenRestorePoint
