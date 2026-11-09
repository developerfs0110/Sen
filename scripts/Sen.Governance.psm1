# scripts/Sen.Governance.psm1 - Sen v0.5.0 Governance & State Seal Engine
$ErrorActionPreference = "Stop"
function Resolve-SenWorkspaceRoot {
[CmdletBinding()] param([string]$StartPath = $PWD.Path)
if ([string]::IsNullOrWhiteSpace($StartPath)) { return $PWD.Path }
$cur = try { [IO.Path]::GetFullPath($StartPath).TrimEnd('\', '/') } catch { <# Fallback #> $StartPath.TrimEnd('\', '/') }
if (Test-Path -LiteralPath $cur -PathType Leaf) { $cur = Split-Path -Parent $cur }
for ($d = 0; $d -lt 12; $d++) {
if (-not $cur) { break }
if ((Test-Path -LiteralPath (Join-Path $cur ".agents")) -or (Test-Path -LiteralPath (Join-Path $cur "plugin.json")) -or (Test-Path -LiteralPath (Join-Path $cur ".agents-plugin/plugin.json"))) { return $cur }
$p = Split-Path -Parent $cur; if (-not $p -or $p -eq $cur) { break }; $cur = $p
}
return (try { [IO.Path]::GetFullPath($StartPath).TrimEnd('\', '/') } catch { <# Fallback #> $StartPath })
}
function Test-SenSymlinkEscape {
param([string]$FullTarget, [string[]]$ResolvedWorkspaces)
$probe = $FullTarget
for ($i = 0; $i -lt 10; $i++) {
if (-not $probe) { break }
$it = if (Test-Path -LiteralPath $probe) { Get-Item -LiteralPath $probe -Force -EA SilentlyContinue } else { $null }
if (($null -ne $it) -and ([int]($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
$lt = if ($it.PSObject.Properties['Target'] -and $it.Target) { [string](@($it.Target)[0]) } else { "" }
if (-not $lt) { return $true }
$abs = if ([IO.Path]::IsPathRooted($lt)) { [IO.Path]::GetFullPath($lt) } else { [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $probe) $lt)) }
if (@($ResolvedWorkspaces | Where-Object { $abs.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) { return $true }
}
$p = Split-Path -Parent $probe; if (-not $p -or $p -eq $probe) { break }; $probe = $p
}
return $false
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
function Format-SenReleaseBullets {
param([string[]]$Items, [string]$EmptyText)
$valid = @($Items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($valid.Count -eq 0) { return "- $EmptyText" }
return (($valid | ForEach-Object { "- " + $_.Trim() }) -join "`n")
}
function Update-SenReleaseNotesIndex {
param([string]$ReleasesDir)
$viFiles = @(Get-ChildItem -LiteralPath $ReleasesDir -Filter "v*.vi.md" -File -EA SilentlyContinue | Sort-Object Name -Descending)
$enFiles = @(Get-ChildItem -LiteralPath $ReleasesDir -Filter "v*.en.md" -File -EA SilentlyContinue | Sort-Object Name -Descending)
$viHdr = [regex]::Unescape('# T\u1ed5ng H\u1ee3p Release Notes (Ti\u1ebfng Vi\u1ec7t) \u2014 Sen (`sen-method`)\n\n| Phi\u00ean b\u1ea3n | T\u00e0i li\u1ec7u chi ti\u1ebft | Tr\u1ea1ng th\u00e1i |\n|---|---|---|')
$viRows = foreach ($vf in $viFiles) { $vTag = $vf.BaseName -replace '\.vi$', ''; "| **$vTag** | [$vTag ($($vf.Name))]($($vf.Name)) | Released / Verified |" }
$enHdr = "# Master Release Notes Index (English) - Sen (``sen-method``)`n`n| Version | Detailed Release Note | Status |`n|---|---|---|"
$enRows = foreach ($ef in $enFiles) { $vTag = $ef.BaseName -replace '\.en$', ''; "| **$vTag** | [$vTag ($($ef.Name))]($($ef.Name)) | Released / Verified |" }
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $ReleasesDir "RELEASE-NOTES.vi.md"), ($viHdr + "`n" + ($viRows -join "`n") + "`n"), $utf8)
[IO.File]::WriteAllText((Join-Path $ReleasesDir "RELEASE-NOTES.en.md"), ($enHdr + "`n" + ($enRows -join "`n") + "`n"), $utf8)
}
function New-SenReleaseNote {
[CmdletBinding()]
param(
[Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
[Parameter(Mandatory)][string]$Version, [string]$Date = "",
[string[]]$Fixed = @(), [string[]]$Removed = @(), [string[]]$Improved = @(), [string[]]$Deferred = @(),
[string]$SummaryVi = "", [string]$SummaryEn = ""
)
$cleanVer = ($Version.Trim() -replace '^[vV]', ''); $useDate = if ($Date) { $Date } else { [DateTime]::UtcNow.ToString("yyyy-MM-dd") }
$relDir = Join-Path $Workspace "docs/releases"; if (-not (Test-Path -LiteralPath $relDir)) { [IO.Directory]::CreateDirectory($relDir) | Out-Null }
$u = { param($s) [regex]::Unescape($s) }
$sumVi = if ($SummaryVi) { $SummaryVi } else { & $u "B\u1ea3n ph\u00e1t h\u00e0nh Sen ``v$cleanVer`` ($useDate)." }
$sumEn = if ($SummaryEn) { $SummaryEn } else { "Sen release ``v$cleanVer`` ($useDate)." }
$viBody = @(
(& $u "# Release Notes ``v$cleanVer`` (Ti\u1ebfng Vi\u1ec7t) \u2014 Sen (``sen-method``)"), "", (& $u "- **Phi\u00ean b\u1ea3n:** ``v$cleanVer``"), (& $u "- **Ng\u00e0y ph\u00e1t h\u00e0nh:** $useDate"),
(& $u "- **B\u1ea3n ti\u1ebfng Anh:** [v$cleanVer.en.md](v$cleanVer.en.md) | **M\u1ee5c l\u1ee5c:** [RELEASE-NOTES.vi.md](RELEASE-NOTES.vi.md)"), "",
(& $u "## 1. T\u00f3m t\u1eaft (Summary)"), $sumVi, "", (& $u "## 2. \u0110\u00e3 s\u1eeda (Fixed)"), (Format-SenReleaseBullets -Items $Fixed -EmptyText (& $u "Kh\u00f4ng c\u00f3 l\u1ed7i ph\u00e1t sinh.")), "",
(& $u "## 3. \u0110\u00e3 x\u00f3a / Lo\u1ea1i b\u1ecf (Removed)"), (Format-SenReleaseBullets -Items $Removed -EmptyText (& $u "Kh\u00f4ng c\u00f3 th\u00e0nh ph\u1ea7n b\u1ecb lo\u1ea1i b\u1ecf.")), "",
(& $u "## 4. C\u1ea3i ti\u1ebfn & T\u00ednh n\u0103ng m\u1edbi (Improved & Added)"), (Format-SenReleaseBullets -Items $Improved -EmptyText (& $u "C\u1eadp nh\u1eadt \u0111\u1ecbnh k\u1ef3.")), "",
(& $u "## 5. Danh s\u00e1ch Ch\u1edd X\u00e1c Nh\u1eadn / B\u1ea3o L\u01b0u (Deferred & Pending Review)"), (Format-SenReleaseBullets -Items $Deferred -EmptyText (& $u "Kh\u00f4ng c\u00f3 h\u1ea1ng m\u1ee5c ch\u1edd duy\u1ec7t."))
) -join "`n"
$enBody = @(
"# Release Notes ``v$cleanVer`` (English) - Sen (``sen-method``)", "", "- **Version:** ``v$cleanVer``", "- **Release Date:** $useDate",
"- **Vietnamese Edition:** [v$cleanVer.vi.md](v$cleanVer.vi.md) | **Master Index:** [RELEASE-NOTES.en.md](RELEASE-NOTES.en.md)", "",
"## 1. Summary", $sumEn, "", "## 2. Fixed", (Format-SenReleaseBullets -Items $Fixed -EmptyText "No bug fixes in this release."), "",
"## 3. Removed", (Format-SenReleaseBullets -Items $Removed -EmptyText "No features or files removed in this release."), "",
"## 4. Improved & Added", (Format-SenReleaseBullets -Items $Improved -EmptyText "Routine maintenance updates."), "",
"## 5. Deferred & Pending Review", (Format-SenReleaseBullets -Items $Deferred -EmptyText "No deferred items pending review.")
) -join "`n"
$viPath = Join-Path $relDir "v$cleanVer.vi.md"; $enPath = Join-Path $relDir "v$cleanVer.en.md"; $utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($viPath, $viBody + "`n", $utf8); [IO.File]::WriteAllText($enPath, $enBody + "`n", $utf8)
Update-SenReleaseNotesIndex -ReleasesDir $relDir
return [pscustomobject]@{ Version = $cleanVer; ViPath = $viPath; EnPath = $enPath; IndexViPath = (Join-Path $relDir "RELEASE-NOTES.vi.md"); IndexEnPath = (Join-Path $relDir "RELEASE-NOTES.en.md") }
}
function Test-SenReleaseNoteGate {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$Version = "")
$cleanVer = ($Version.Trim() -replace '^[vV]', '')
if (-not $cleanVer) {
$pJson = Read-SenSafeJson -Path (Join-Path $Workspace "plugin.json")
if ($null -eq $pJson) { $pJson = Read-SenSafeJson -Path (Join-Path $Workspace ".agents-plugin/plugin.json") }
$cleanVer = if ($null -ne $pJson -and $pJson.version) { ([string]$pJson.version).Trim() } else { "0.5.0" }
}
$relDir = Join-Path $Workspace "docs/releases"; $viPath = Join-Path $relDir "v$cleanVer.vi.md"; $enPath = Join-Path $relDir "v$cleanVer.en.md"
$missing = [Collections.Generic.List[string]]::new()
foreach ($pair in @(
@{ name = "v$cleanVer.vi.md"; path = $viPath; s = $true }, @{ name = "v$cleanVer.en.md"; path = $enPath; s = $true },
@{ name = "RELEASE-NOTES.vi.md"; path = (Join-Path $relDir "RELEASE-NOTES.vi.md"); s = $false }, @{ name = "RELEASE-NOTES.en.md"; path = (Join-Path $relDir "RELEASE-NOTES.en.md"); s = $false }
)) {
if (-not (Test-Path -LiteralPath $pair.path)) { $missing.Add("MissingFile:$($pair.name)"); continue }
$txt = [IO.File]::ReadAllText($pair.path, [Text.Encoding]::UTF8)
if ($pair.s) { foreach ($sec in @("Fixed", "Removed", "Improved")) { if ($txt -notmatch "(?i)\b$sec\b") { $missing.Add("MissingSection:$($pair.name):$sec") } } }
elseif ($txt -notmatch [regex]::Escape("v$cleanVer")) { $missing.Add("MissingIndexEntry:$($pair.name):v$cleanVer") }
}
return [pscustomobject]@{ Passed = ($missing.Count -eq 0); Version = $cleanVer; ViPath = $viPath; EnPath = $enPath; Missing = @($missing.ToArray()) }
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
$reqPath = Join-Path $Workspace ".agents/office/requirements.json"; $loaded = Read-SenSafeJson -Path $reqPath
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
if (-not $PSBoundParameters.ContainsKey('Status') -and ($Title -match '(?i)\b(TODO|TBD)\b|\?\?\?')) { $Status = "NEEDS_CLARIFICATION" }
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
}
function Register-SenEvidence {
[CmdletBinding()]
param(
[Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
[string]$EvidenceId = "", [string]$RequirementId = "", [string]$TaskId = "",
[ValidateSet("unit", "integration", "e2e", "security", "performance", "build", "lint")][string]$Type = "unit",
[ValidateSet("PASS", "FAIL", "STALE")][string]$Status = "PASS",
[string]$Source = "TestRunner", [string]$Command = "tests/run.ps1", [int]$ExitCode = 0,
[string[]]$CodePaths = @(), [string]$SubjectPath = "", [int]$TTLMinutes = 1440
)
if ([string]::IsNullOrWhiteSpace($EvidenceId)) { $EvidenceId = "EV-" + [DateTime]::UtcNow.ToString("HHmmss") + "-" + ([Guid]::NewGuid().ToString("N").Substring(0, 4)) }
$evPath = Join-Path $Workspace ".agents/office/evidence.json"; $loaded = Read-SenSafeJson -Path $evPath
$existing = if ($null -eq $loaded) { @() } elseif ($loaded.PSObject.Properties.Name -contains "evidence") { @($loaded.evidence) } else { @($loaded) }
$list = [Collections.Generic.List[object]]::new()
foreach ($e in $existing) { if ($e -and [string]$e.evidence_id -ne $EvidenceId) { $list.Add($e) } }
$cleanPaths = [Collections.Generic.List[string]]::new()
foreach ($cp in @($CodePaths)) { if (-not [string]::IsNullOrWhiteSpace($cp)) { $cleanPaths.Add($cp) } }
if (-not [string]::IsNullOrWhiteSpace($SubjectPath) -and (-not $cleanPaths.Contains($SubjectPath))) { $cleanPaths.Insert(0, $SubjectPath) }
$subjRel = if (-not [string]::IsNullOrWhiteSpace($SubjectPath)) { $SubjectPath } elseif ($cleanPaths.Count -gt 0) { $cleanPaths[0] } else { "" }
$subjFull = if (-not $subjRel) { "" } elseif ([IO.Path]::IsPathRooted($subjRel)) { $subjRel } else { Join-Path $Workspace $subjRel }
$subjHash = if ($subjFull -and (Test-Path -LiteralPath $subjFull -PathType Leaf)) { (Get-FileHash -LiteralPath $subjFull -Algorithm SHA256).Hash.ToLowerInvariant() } else { "" }
$now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); $expIso = (Get-Date).ToUniversalTime().AddMinutes($TTLMinutes).ToString("o")
$verified = ($Status -eq "PASS" -and $ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($Command))
$entry = [pscustomobject]@{
evidence_id = $EvidenceId; requirement_id = $RequirementId; task_id = $TaskId; type = $Type
status = if ($verified) { "PASS" } elseif ($Status -eq "STALE") { "STALE" } else { "FAIL" }
source = $Source; command = $Command; exitCode = $ExitCode; codePaths = @($cleanPaths.ToArray())
subjectPath = $subjRel; subjectHash = $subjHash; ttlMinutes = $TTLMinutes; expiresAt = $expIso; timestamp = $now; verified = [bool]$verified
}
$list.Add($entry)
Write-SenAtomicJson -Path $evPath -InputObject ([ordered]@{ updatedAt = $now; evidence = @($list.ToArray()) }) -Depth 8
return $entry
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
[Parameter(Mandatory)][ValidateSet("backlog", "todo", "pending", "ready", "in_progress", "reviewing", "verified", "done", "blocked", "failed", "cancelled", "retrying", "superseded", "stale")][string]$ToStatus,
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
$targetTier = $curTier; $reason = $null
$critRe = '(?i)(auth|login|oauth|jwt|payment|billing|stripe|vnpay|momo|schema|migration|database|secret|guard\.ps1)'
foreach ($mf in $ModifiedFiles) {
if ($mf -match $critRe) { $targetTier = 3; $reason = "Modified critical security/data/auth path: $mf"; break }
}
if ($targetTier -lt 2 -and $ModifiedFiles.Count -ge 3) { $targetTier = 2; $reason = "Modified file count ($($ModifiedFiles.Count)) reached Tier 2 threshold (>= 3 files)" }
$escalated = ($targetTier -gt $curTier)
if ($escalated -and $null -ne $audit) {
$audit | Add-Member -NotePropertyName "escalatedFrom" -NotePropertyValue $curTier -Force
$audit.tier = $targetTier; $audit.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
Write-SenAtomicJson -Path $auditPath -InputObject $audit -Depth 8
}
return [pscustomobject]@{ Escalated = $escalated; PreviousTier = $curTier; NewTier = $targetTier; Reason = $reason }
}
function Test-SenSuiteIntegrity {
[CmdletBinding()]
param([string]$TestsPath = "", [int]$MinFiles = 1, [int]$MinAssertions = 1)
$tDir = if (-not [string]::IsNullOrWhiteSpace($TestsPath)) { $TestsPath } else { Join-Path $PSScriptRoot "../tests" }
if (-not (Test-Path -LiteralPath $tDir)) {
return [pscustomobject]@{ Passed = $false; FileCount = 0; AssertionCount = 0; MinAssertions = $MinAssertions; Reason = "Tests directory not found: $tDir" }
}
$files = @(Get-ChildItem -LiteralPath $tDir -Filter "*.Tests.ps1" -File -EA SilentlyContinue)
$assertCount = 0; $emptyFiles = [Collections.Generic.List[string]]::new()
foreach ($f in $files) {
$txt = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
$cnt = [regex]::Matches($txt, '\bAssert-[A-Za-z]+\b').Count
if ($cnt -eq 0) { $emptyFiles.Add($f.Name) }
$assertCount += $cnt
}
$passed = ($files.Count -ge $MinFiles) -and ($assertCount -ge $MinAssertions) -and ($emptyFiles.Count -eq 0)
$reason = if ($passed) { "Suite integrity verified ($($files.Count) files, $assertCount assertions)." } else { "Suite integrity failed: files=$($files.Count)/$MinFiles, assertions=$assertCount/$MinAssertions, empty=$($emptyFiles -join ',')" }
return [pscustomobject]@{ Passed = $passed; FileCount = $files.Count; AssertionCount = $assertCount; MinAssertions = $MinAssertions; Reason = $reason }
}
function Measure-SenTokenEstimate {
[CmdletBinding()]
param([AllowEmptyString()][string]$Text = "", [string]$Path = "", [int]$TokenBudget = 1500)
$content = if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) { [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) } else { $Text }
if ([string]::IsNullOrEmpty($content)) { return [pscustomobject]@{ EstimatedTokens = 0; ByteCount = 0; CharCount = 0; NonAsciiCount = 0; TokenBudget = $TokenBudget; WithinBudget = $true } }
$bytes = [Text.Encoding]::UTF8.GetByteCount($content); $chars = $content.Length
$nonAscii = [regex]::Matches($content, '[^\x00-\x7F]').Count; $punct = [regex]::Matches($content, '[\{\}\[\]\(\);:,<>=\+\-\*/\|\\]').Count
$est = [int][Math]::Ceiling(($chars / 3.8) + ($nonAscii * 0.45) + ($punct * 0.15))
return [pscustomobject]@{ EstimatedTokens = $est; ByteCount = $bytes; CharCount = $chars; NonAsciiCount = $nonAscii; TokenBudget = $TokenBudget; WithinBudget = ($est -le $TokenBudget) }
}
function Set-SenEdition {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [Parameter(Mandatory)][ValidateSet("core", "full")][string]$Edition)
$mode = if ($Edition -eq "core") { "off" } else { "eco" }
$cfg = Set-SenOfficeConfig -Workspace $Workspace -Mode $mode
$cfg["edition"] = $Edition; $cfg["telemetryEnabled"] = ($Edition -eq "full"); $cfg["creativePacksEnabled"] = ($Edition -eq "full")
Write-SenAtomicJson -Path (Join-Path $Workspace ".agents/office/config.json") -InputObject $cfg -Depth 5
return [pscustomobject]$cfg
}
function Get-SenDeferredItems {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
$defPath = Join-Path $Workspace ".agents/office/deferred-items.json"; $loaded = Read-SenSafeJson -Path $defPath
if ($null -ne $loaded -and $loaded.PSObject.Properties['items']) { return @($loaded.items) }
$defaultItems = @(
[ordered]@{ id = "W-09"; source = "Grok"; title = "Tone down marketing/pitch style in README.md"; status = "pending_user_confirmation"; mitigation = "Kept accessible prose style pending user confirmation" },
[ordered]@{ id = "W-26 / IMP-19"; source = "Claude"; title = "Hide or replace public contact & bank donate info in README.md"; status = "pending_user_confirmation"; mitigation = "Never delete author contact/donation info without owner confirmation" },
[ordered]@{ id = "IMP-13 / IMP-05"; source = "Grok"; title = "Rewrite core PowerShell runtime into Node.js/TypeScript or Python"; status = "disagreed_rejected"; mitigation = "Rejected to preserve zero-dependency core; solved via POSIX .sh scripts" },
[ordered]@{ id = "IMP-10 / IMP-29"; source = "Grok/Claude"; title = "Split Sen.Legal.psm1 and sen-office into separate Git repos"; status = "disagreed_rejected"; mitigation = "Rejected repo fragmentation; solved via Set-SenEdition -Edition core|full" }
)
Write-SenAtomicJson -Path $defPath -InputObject ([ordered]@{ version = "0.5.0"; updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); items = $defaultItems }) -Depth 6
return @($defaultItems | ForEach-Object { [pscustomobject]$_ })
}
function Uninstall-SenSelf {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [switch]$RemovePluginDir, [switch]$DryRun)
$leaf = Split-Path -Path $Workspace -Leaf; $taskName = "Sen update check ($leaf)"; $schedRemoved = $false
if (-not $DryRun.IsPresent) {
try { if (Get-Command Unregister-ScheduledTask -EA SilentlyContinue) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -EA SilentlyContinue; $schedRemoved = $true } } catch { <# Ignore #> }
}
$hRemoved = if (-not $DryRun.IsPresent -and (Get-Command Uninstall-SenHarness -EA SilentlyContinue)) { @((Uninstall-SenHarness -Workspace $Workspace -Harness @("all")).Uninstalled) } else { @() }
$pluginDir = Join-Path $Workspace ".agents/plugins/sen-method"
if ($RemovePluginDir.IsPresent -and (-not $DryRun.IsPresent) -and (Test-Path -LiteralPath $pluginDir)) { Remove-Item -LiteralPath $pluginDir -Recurse -Force -EA SilentlyContinue }
return [pscustomobject]@{ Uninstalled = $true; Workspace = $Workspace; ScheduledTaskName = $taskName; ScheduledTaskRemoved = $schedRemoved; HarnessesRemoved = $hRemoved; DryRun = [bool]$DryRun.IsPresent }
}
function Add-SenExecutionLesson {
[CmdletBinding()]
param(
[Parameter(Mandatory)][string]$Workspace, [Parameter(Mandatory)][string]$Category,
[Parameter(Mandatory)][string]$Problem, [Parameter(Mandatory)][string]$Solution,
[string]$RootCause = "", [bool]$VerifiedByUser = $true, [string]$Stack = "general", [double]$Confidence = 1.0,
[ValidateSet("active", "deprecated", "archived")][string]$Status = "active", [string]$ExpiresAt = ""
)
$lessonsPath = Join-Path $Workspace ".agents/office/lessons.json"
$existing = [Collections.Generic.List[object]]::new(); $raw = Read-SenSafeJson -Path $lessonsPath
if ($null -ne $raw) { foreach ($item in $raw) { if ($item) { $existing.Add($item) } } }
$entry = [pscustomobject]@{
id = "LES-" + ([DateTime]::UtcNow.ToString("yyyyMMddHHmmss")) + "-" + ([Guid]::NewGuid().ToString("N").Substring(0, 4))
category = $Category; stack = $Stack; problem = $Problem; rootCause = $RootCause; solution = $Solution
confidence = $Confidence; status = $Status; verifiedByUser = $VerifiedByUser
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
return [pscustomobject]@{
userMemory = [ordered]@{ present = (Test-Path -LiteralPath (Join-Path $Workspace ".agents/profile.md")); path = ".agents/profile.md" }
projectMemory = [ordered]@{ hasAgentsMd = (Test-Path -LiteralPath (Join-Path $Workspace "AGENTS.md")); hasContextMd = (Test-Path -LiteralPath (Join-Path $Workspace "docs/CONTEXT.md")); hasTodoMd = (Test-Path -LiteralPath (Join-Path $Workspace "docs/TODO.md")) }
executionMemory = [ordered]@{ lessonCount = $lessons.Count; lessons = $lessons }
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
$savedSeal = if ($VerifySeal.IsPresent -and (Test-Path -LiteralPath $sealPath)) { Read-SenSafeJson -Path $sealPath } else { $null }
$fileHashes = [ordered]@{}
foreach ($jf in @(Get-ChildItem -LiteralPath $offDir -Filter "*.json" -File -EA SilentlyContinue | Where-Object { $_.Name -ne "state-seal.json" } | Sort-Object Name)) {
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
}
function Initialize-SenIntake {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [Parameter(Mandatory)][string]$Request, [int]$FileCount = 1, [string[]]$Files = @(), [string]$UserName = "")
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
$risk = if (Get-Command Get-SenTaskRiskScore -EA SilentlyContinue) { Get-SenTaskRiskScore -Request $Request -FileCount ([Math]::Max($FileCount, $Files.Count)) } else { [pscustomobject]@{ Tier = 1; LabelVi = "[Cap 1 - Thuc thi ngay]"; LabelEn = "[Tier 1 - Doing it now]" } }
$t = [int]$risk.Tier; $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
if ($t -ge 2 -and (Get-Command Initialize-SenProcessAudit -EA SilentlyContinue)) { [void](Initialize-SenProcessAudit -Workspace $Workspace -Tier $t -PreserveLatched) }
$obj = [pscustomobject]@{
userName = $uName; request = $Request; tier = $t; tierLabelVi = [string]$risk.LabelVi; tierLabelEn = [string]$risk.LabelEn
requiresDialecticalProof = ($t -ge 2); requiresResourceCostTable = ($t -ge 2); requiresRestorePoint = ($t -ge 2)
requiresSubagentInTurn1 = ($t -ge 2); requiresMermaidDiagrams = ($t -eq 3); createdAt = $now
}
Write-SenAtomicJson -Path (Join-Path $Workspace ".agents/office/current-intake.json") -InputObject $obj -Depth 6
return $obj
}
function Test-SenIntakeCompleteness {
[CmdletBinding()]
param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$DraftResponse = "")
$inObj = Read-SenSafeJson -Path (Join-Path $Workspace ".agents/office/current-intake.json")
$tier = if ($null -ne $inObj -and $inObj.PSObject.Properties['tier']) { [int]$inObj.tier } else { 1 }
$uName = if ($null -ne $inObj -and $inObj.PSObject.Properties['userName']) { [string]$inObj.userName } else { "" }
$miss = [Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($DraftResponse)) {
if ($DraftResponse -notmatch '(?i)\[(Tier|C.p)\s*[123]\b') { $miss.Add("MissingTierLabel") }
if ($uName -and $uName -ne "User" -and $DraftResponse.IndexOf($uName, [StringComparison]::OrdinalIgnoreCase) -lt 0) { $miss.Add("MissingUserNameAck:$uName") }
if ($tier -ge 2 -and $DraftResponse -notmatch '(?i)(Resource Cost|T.i nguy.n ti.u t.n|Best-of-the-Best)') { $miss.Add("MissingDialecticalCostTable") }
}
if ($tier -ge 2) {
$rpDir = Join-Path $Workspace ".agents/.sen-restore"
$hasRp = (Test-Path -LiteralPath $rpDir) -and (@(Get-ChildItem -LiteralPath $rpDir -Directory -EA SilentlyContinue).Count -gt 0)
if (-not $hasRp) { $miss.Add("MissingRestorePoint") }
}
return [pscustomobject]@{ Passed = ($miss.Count -eq 0); Tier = $tier; UserName = $uName; MissingElements = @($miss.ToArray()); ReminderText = "[SEN WATCHDOG] Verify Tier $tier requirements: $($miss -join ', ')" }
}
Export-ModuleMember -Function Resolve-SenWorkspaceRoot, Test-SenSafeWorkspacePath, New-SenReleaseNote, Test-SenReleaseNoteGate, Register-SenRequirement, Register-SenEvidence, Test-SenEvidenceValidity, Get-SenRequirementTraceability, Invoke-SenTaskTransition, Invoke-SenChangeImpactAnalysis, Invoke-SenCheckpointResume, Test-SenMidTaskEscalation, Test-SenSuiteIntegrity, Measure-SenTokenEstimate, Set-SenEdition, Get-SenDeferredItems, Uninstall-SenSelf, Add-SenExecutionLesson, Get-SenExecutionLessons, Get-SenMemorySnapshot, Sync-SenOfficeState, Initialize-SenIntake, Test-SenIntakeCompleteness
