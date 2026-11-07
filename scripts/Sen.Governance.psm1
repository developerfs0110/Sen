# scripts/Sen.Governance.psm1
# Pure ASCII PowerShell module for Sen v0.5.0 Governance: Bilingual Release Notes,
# Requirement Traceability Matrix (RTM), Evidence Validity, Formal Task State Machine,
# Change Impact Analysis, Checkpoint Resume, Mid-Task Escalation, Suite Integrity,
# Safe Workspace Path Guard, Token Estimation, Edition Mode, Deferred Items & Uninstall.

$ErrorActionPreference = "Stop"

function Resolve-SenWorkspaceRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$StartPath = $PWD.Path
    )
    if ([string]::IsNullOrWhiteSpace($StartPath)) { return $PWD.Path }
    $cur = try { [System.IO.Path]::GetFullPath($StartPath).TrimEnd('\', '/') } catch { <# Fallback raw path #> $StartPath.TrimEnd('\', '/') }
    if (Test-Path -LiteralPath $cur -PathType Leaf) {
        $cur = Split-Path -Parent $cur
    }
    for ($depth = 0; $depth -lt 12; $depth++) {
        if ([string]::IsNullOrWhiteSpace($cur)) { break }
        $hasAgents = Test-Path -LiteralPath (Join-Path $cur ".agents")
        $hasPlugin = (Test-Path -LiteralPath (Join-Path $cur "plugin.json")) -or (Test-Path -LiteralPath (Join-Path $cur ".agents-plugin/plugin.json"))
        if ($hasAgents -or $hasPlugin) { return $cur }
        $parent = Split-Path -Parent $cur
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cur) { break }
        $cur = $parent
    }
    return (try { [System.IO.Path]::GetFullPath($StartPath).TrimEnd('\', '/') } catch { <# Return raw StartPath #> $StartPath })
}

function Test-SenSymlinkEscape {
    param([string]$FullTarget, [string[]]$ResolvedWorkspaces)
    $probe = $FullTarget
    for ($i = 0; $i -lt 10; $i++) {
        if ([string]::IsNullOrWhiteSpace($probe)) { break }
        $item = if (Test-Path -LiteralPath $probe) { Get-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue } else { $null }
        $isReparse = ($null -ne $item) -and ([int]($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        if ($isReparse) {
            $linkTarget = if ($item.PSObject.Properties['Target'] -and $item.Target) { [string](@($item.Target)[0]) } else { "" }
            if ([string]::IsNullOrWhiteSpace($linkTarget)) { return $true }
            $absLink = if ([System.IO.Path]::IsPathRooted($linkTarget)) { [System.IO.Path]::GetFullPath($linkTarget) } else { [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $probe) $linkTarget)) }
            $inWs = @($ResolvedWorkspaces | Where-Object { $absLink.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            if (-not $inWs) { return $true }
        }
        $parent = Split-Path -Parent $probe
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $probe) { break }
        $probe = $parent
    }
    return $false
}

function Test-SenSafeWorkspacePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [Parameter(Mandatory = $false)]
        [string[]]$WorkspaceList = @(),
        [Parameter(Mandatory = $false)]
        [string]$ToolName = "write_file"
    )
    $normRaw = $TargetPath.Replace('\', '/').Trim()
    $sensRe = '(?i)(^|/)(\.ssh|\.aws|\.gnupg|\.kube)(/|$)|(^|/)(id_rsa|id_ed25519|\.npmrc|\.pypirc|\.netrc)$'
    if ($normRaw -match $sensRe) {
        return [pscustomobject][ordered]@{ Allowed = $false; Reason = "Sensitive host credential path blocked: $TargetPath"; NormalizedPath = $normRaw; IsSymlinkEscape = $false }
    }
    $fullTarget = try { [System.IO.Path]::GetFullPath($TargetPath).TrimEnd('\', '/') } catch { <# Fallback normalized #> $normRaw }
    if ($fullTarget.Replace('\', '/') -match $sensRe) {
        return [pscustomobject][ordered]@{ Allowed = $false; Reason = "Sensitive host credential path blocked: $fullTarget"; NormalizedPath = $fullTarget; IsSymlinkEscape = $false }
    }
    $resolvedWs = [System.Collections.Generic.List[string]]::new()
    foreach ($w in $WorkspaceList) {
        if (-not [string]::IsNullOrWhiteSpace($w)) {
            $rw = Resolve-SenWorkspaceRoot -StartPath $w
            if (-not $resolvedWs.Contains($rw)) { $resolvedWs.Add($rw) }
        }
    }
    if ($resolvedWs.Count -gt 0 -and (Test-SenSymlinkEscape -FullTarget $fullTarget -ResolvedWorkspaces $resolvedWs.ToArray())) {
        return [pscustomobject][ordered]@{ Allowed = $false; Reason = "Symlink or junction escape outside workspace blocked: $fullTarget"; NormalizedPath = $fullTarget; IsSymlinkEscape = $true }
    }
    if ($ToolName -in @("write_file", "edit_file") -and $resolvedWs.Count -gt 0) {
        $inside = $false
        foreach ($rw in $resolvedWs) {
            if ($fullTarget.Equals($rw, [System.StringComparison]::OrdinalIgnoreCase) -or
                $fullTarget.StartsWith($rw + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
                $fullTarget.StartsWith($rw + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
                $inside = $true; break
            }
        }
        if (-not $inside -and $env:USERPROFILE) {
            $gemDir = [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE ".gemini")).TrimEnd('\', '/')
            if ($fullTarget.StartsWith($gemDir + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) { $inside = $true }
        }
        if (-not $inside) {
            return [pscustomobject][ordered]@{ Allowed = $false; Reason = "File write outside active workspace blocked: $fullTarget"; NormalizedPath = $fullTarget; IsSymlinkEscape = $false }
        }
    }
    return [pscustomobject][ordered]@{ Allowed = $true; Reason = $null; NormalizedPath = $fullTarget; IsSymlinkEscape = $false }
}

function Format-SenReleaseBullets {
    param([string[]]$Items, [string]$EmptyText)
    $valid = @($Items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($valid.Count -eq 0) { return "- $EmptyText" }
    return (($valid | ForEach-Object { "- " + $_.Trim() }) -join "`n")
}

function Update-SenReleaseNotesIndex {
    param([string]$ReleasesDir)
    $viFiles = @(Get-ChildItem -LiteralPath $ReleasesDir -Filter "v*.vi.md" -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    $enFiles = @(Get-ChildItem -LiteralPath $ReleasesDir -Filter "v*.en.md" -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    $viHdr = [regex]::Unescape('# T\u1ed5ng H\u1ee3p Release Notes (Ti\u1ebfng Vi\u1ec7t) \u2014 Sen (`sen-method`)\n\nDanh s\u00e1ch to\u00e0n b\u1ed9 c\u00e1c phi\u00ean b\u1ea3n ph\u00e1t h\u00e0nh (Fixed / Removed / Improved / Deferred):\n\n| Phi\u00ean b\u1ea3n | T\u00e0i li\u1ec7u chi ti\u1ebft | Tr\u1ea1ng th\u00e1i |\n|---|---|---|')
    $viRows = foreach ($vf in $viFiles) {
        $vTag = $vf.BaseName -replace '\.vi$', ''
        "| **$vTag** | [$vTag ($($vf.Name))]($($vf.Name)) | Released / Verified |"
    }
    $enHdr = "# Master Release Notes Index (English) - Sen (``sen-method``)`n`nComplete history of all releases (Fixed / Removed / Improved / Deferred):`n`n| Version | Detailed Release Note | Status |`n|---|---|---|"
    $enRows = foreach ($ef in $enFiles) {
        $vTag = $ef.BaseName -replace '\.en$', ''
        "| **$vTag** | [$vTag ($($ef.Name))]($($ef.Name)) | Released / Verified |"
    }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Join-Path $ReleasesDir "RELEASE-NOTES.vi.md"), ($viHdr + "`n" + ($viRows -join "`n") + "`n"), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $ReleasesDir "RELEASE-NOTES.en.md"), ($enHdr + "`n" + ($enRows -join "`n") + "`n"), $utf8)
}

function New-SenReleaseNote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
        [Parameter(Mandatory = $true)][string]$Version,
        [string]$Date = "",
        [string[]]$Fixed = @(),
        [string[]]$Removed = @(),
        [string[]]$Improved = @(),
        [string[]]$Deferred = @(),
        [string]$SummaryVi = "",
        [string]$SummaryEn = ""
    )
    $cleanVer = ($Version.Trim() -replace '^[vV]', '')
    $useDate = if (-not [string]::IsNullOrWhiteSpace($Date)) { $Date } else { [DateTime]::UtcNow.ToString("yyyy-MM-dd") }
    $relDir = Join-Path -Path $Workspace -ChildPath "docs/releases"
    if (-not (Test-Path -LiteralPath $relDir)) { [System.IO.Directory]::CreateDirectory($relDir) | Out-Null }

    $sumVi = if (-not [string]::IsNullOrWhiteSpace($SummaryVi)) { $SummaryVi } else { [regex]::Unescape("B\u1ea3n ph\u00e1t h\u00e0nh Sen ``v$cleanVer`` ($useDate).") }
    $sumEn = if (-not [string]::IsNullOrWhiteSpace($SummaryEn)) { $SummaryEn } else { "Sen release ``v$cleanVer`` ($useDate)." }

    $viBody = @(
        ([regex]::Unescape("# Release Notes ``v$cleanVer`` (Ti\u1ebfng Vi\u1ec7t) \u2014 Sen (``sen-method``)")),
        "",
        ([regex]::Unescape("- **Phi\u00ean b\u1ea3n:** ``v$cleanVer``")),
        ([regex]::Unescape("- **Ng\u00e0y ph\u00e1t h\u00e0nh:** $useDate")),
        ([regex]::Unescape("- **B\u1ea3n ti\u1ebfng Anh:** [v$cleanVer.en.md](v$cleanVer.en.md) | **M\u1ee5c l\u1ee5c:** [RELEASE-NOTES.vi.md](RELEASE-NOTES.vi.md)")),
        "",
        ([regex]::Unescape("## 1. T\u00f3m t\u1eaft (Summary)")),
        $sumVi,
        "",
        ([regex]::Unescape("## 2. \u0110\u00e3 s\u1eeda (Fixed)")),
        (Format-SenReleaseBullets -Items $Fixed -EmptyText ([regex]::Unescape("Kh\u00f4ng c\u00f3 l\u1ed7i ph\u00e1t sinh."))) ,
        "",
        ([regex]::Unescape("## 3. \u0110\u00e3 x\u00f3a / Lo\u1ea1i b\u1ecf (Removed)")),
        (Format-SenReleaseBullets -Items $Removed -EmptyText ([regex]::Unescape("Kh\u00f4ng c\u00f3 th\u00e0nh ph\u1ea7n b\u1ecb lo\u1ea1i b\u1ecf."))) ,
        "",
        ([regex]::Unescape("## 4. C\u1ea3i ti\u1ebfn & T\u00ednh n\u0103ng m\u1edbi (Improved & Added)")),
        (Format-SenReleaseBullets -Items $Improved -EmptyText ([regex]::Unescape("C\u1eadp nh\u1eadt \u0111\u1ecbnh k\u1ef3."))) ,
        "",
        ([regex]::Unescape("## 5. Danh s\u00e1ch Ch\u1edd X\u00e1c Nh\u1eadn / B\u1ea3o L\u01b0u (Deferred & Pending Review)")),
        (Format-SenReleaseBullets -Items $Deferred -EmptyText ([regex]::Unescape("Kh\u00f4ng c\u00f3 h\u1ea1ng m\u1ee5c ch\u1edd duy\u1ec7t.")))
    ) -join "`n"

    $enBody = @(
        "# Release Notes ``v$cleanVer`` (English) - Sen (``sen-method``)",
        "",
        "- **Version:** ``v$cleanVer``",
        "- **Release Date:** $useDate",
        "- **Vietnamese Edition:** [v$cleanVer.vi.md](v$cleanVer.vi.md) | **Master Index:** [RELEASE-NOTES.en.md](RELEASE-NOTES.en.md)",
        "",
        "## 1. Summary",
        $sumEn,
        "",
        "## 2. Fixed",
        (Format-SenReleaseBullets -Items $Fixed -EmptyText "No bug fixes in this release."),
        "",
        "## 3. Removed",
        (Format-SenReleaseBullets -Items $Removed -EmptyText "No features or files removed in this release."),
        "",
        "## 4. Improved & Added",
        (Format-SenReleaseBullets -Items $Improved -EmptyText "Routine maintenance updates."),
        "",
        "## 5. Deferred & Pending Review",
        (Format-SenReleaseBullets -Items $Deferred -EmptyText "No deferred items pending review.")
    ) -join "`n"

    $viPath = Join-Path $relDir "v$cleanVer.vi.md"
    $enPath = Join-Path $relDir "v$cleanVer.en.md"
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($viPath, $viBody + "`n", $utf8)
    [System.IO.File]::WriteAllText($enPath, $enBody + "`n", $utf8)
    Update-SenReleaseNotesIndex -ReleasesDir $relDir

    return [pscustomobject][ordered]@{
        Version     = $cleanVer
        ViPath      = $viPath
        EnPath      = $enPath
        IndexViPath = (Join-Path $relDir "RELEASE-NOTES.vi.md")
        IndexEnPath = (Join-Path $relDir "RELEASE-NOTES.en.md")
    }
}

function Test-SenReleaseNoteGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
        [string]$Version = ""
    )
    $cleanVer = ($Version.Trim() -replace '^[vV]', '')
    if ([string]::IsNullOrWhiteSpace($cleanVer)) {
        $pJson = Read-SenSafeJson -Path (Join-Path $Workspace "plugin.json")
        if ($null -eq $pJson) { $pJson = Read-SenSafeJson -Path (Join-Path $Workspace ".agents-plugin/plugin.json") }
        if ($null -ne $pJson -and $pJson.version) { $cleanVer = ([string]$pJson.version).Trim() } else { $cleanVer = "0.5.0" }
    }
    $relDir = Join-Path $Workspace "docs/releases"
    $viPath = Join-Path $relDir "v$cleanVer.vi.md"
    $enPath = Join-Path $relDir "v$cleanVer.en.md"
    $idxVi  = Join-Path $relDir "RELEASE-NOTES.vi.md"
    $idxEn  = Join-Path $relDir "RELEASE-NOTES.en.md"
    $missing = [System.Collections.Generic.List[string]]::new()

    foreach ($pair in @(
        @{ name = "v$cleanVer.vi.md"; path = $viPath; checkSections = $true },
        @{ name = "v$cleanVer.en.md"; path = $enPath; checkSections = $true },
        @{ name = "RELEASE-NOTES.vi.md"; path = $idxVi; checkSections = $false },
        @{ name = "RELEASE-NOTES.en.md"; path = $idxEn; checkSections = $false }
    )) {
        if (-not (Test-Path -LiteralPath $pair.path)) {
            $missing.Add("MissingFile:$($pair.name)")
            continue
        }
        $txt = [System.IO.File]::ReadAllText($pair.path, [System.Text.Encoding]::UTF8)
        if ($pair.checkSections) {
            foreach ($sec in @("Fixed", "Removed", "Improved")) {
                if ($txt -notmatch "(?i)\b$sec\b") { $missing.Add("MissingSection:$($pair.name):$sec") }
            }
        }
        elseif ($txt -notmatch [regex]::Escape("v$cleanVer")) {
            $missing.Add("MissingIndexEntry:$($pair.name):v$cleanVer")
        }
    }
    return [pscustomobject][ordered]@{
        Passed  = ($missing.Count -eq 0)
        Version = $cleanVer
        ViPath  = $viPath
        EnPath  = $enPath
        Missing = @($missing.ToArray())
    }
}

function Register-SenRequirement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Title,
        [ValidateSet("Functional", "NonFunctional", "Security", "Legal")][string]$Category = "Functional",
        [ValidateSet("Confirmed", "Inferred")][string]$Source = "Confirmed",
        [ValidateSet("Identified", "Planned", "Implemented", "Tested", "Verified", "NEEDS_CLARIFICATION", "SUPERSEDED")][string]$Status = "Planned",
        [string[]]$DependsOn = @(),
        [string[]]$ConflictWith = @(),
        [string[]]$DesignIds = @(),
        [string[]]$TaskIds = @(),
        [string[]]$CodePaths = @(),
        [string[]]$TestIds = @(),
        [string[]]$EvidenceIds = @()
    )
    $reqPath = Join-Path $Workspace ".agents/office/requirements.json"
    $loaded = Read-SenSafeJson -Path $reqPath
    $list = [System.Collections.Generic.List[object]]::new()
    $existingArr = if ($null -eq $loaded) { @() } elseif ($loaded.PSObject.Properties.Name -contains "requirements") { @($loaded.requirements) } else { @($loaded) }
    $normTitle = $Title.Trim().ToLowerInvariant()
    $dedup = $false; $ver = 1; $targetId = $Id

    foreach ($item in $existingArr) {
        if (-not $item) { continue }
        if ([string]$item.id -eq $Id) {
            $ver = if ($item.PSObject.Properties['version']) { [int]$item.version + 1 } else { 2 }
            continue
        }
        if (([string]$item.title).Trim().ToLowerInvariant() -eq $normTitle) {
            $dedup = $true; $targetId = [string]$item.id
            $ver = if ($item.PSObject.Properties['version']) { [int]$item.version + 1 } else { 2 }
            continue
        }
        $list.Add($item)
    }
    $effStatus = if ($Source -eq "Inferred" -and $Status -eq "Identified") { "NEEDS_CLARIFICATION" } else { $Status }
    $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $reqObj = [pscustomobject][ordered]@{
        id           = $targetId
        title        = $Title.Trim()
        category     = $Category
        source       = $Source
        status       = $effStatus
        dependsOn    = @($DependsOn | Where-Object { $_ })
        conflictWith = @($ConflictWith | Where-Object { $_ })
        designIds    = @($DesignIds | Where-Object { $_ })
        taskIds      = @($TaskIds | Where-Object { $_ })
        codePaths    = @($CodePaths | Where-Object { $_ })
        testIds      = @($TestIds | Where-Object { $_ })
        evidenceIds  = @($EvidenceIds | Where-Object { $_ })
        version      = $ver
        updatedAt    = $now
    }
    $list.Add($reqObj)
    Write-SenAtomicJson -Path $reqPath -InputObject ([ordered]@{ updatedAt = $now; requirements = @($list.ToArray()) }) -Depth 8
    return [pscustomobject][ordered]@{ Requirement = $reqObj; Deduplicated = $dedup; HasConflict = ($reqObj.conflictWith.Count -gt 0) }
}

function Register-SenEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
        [string]$EvidenceId = "",
        [string]$RequirementId = "",
        [string]$TaskId = "",
        [ValidateSet("unit", "integration", "e2e", "security", "performance", "build", "lint")][string]$Type = "unit",
        [ValidateSet("PASS", "FAIL", "STALE")][string]$Status = "PASS",
        [string]$Source = "TestRunner",
        [string]$Command = "tests/run.ps1",
        [int]$ExitCode = 0,
        [string[]]$CodePaths = @()
    )
    if ([string]::IsNullOrWhiteSpace($EvidenceId)) { $EvidenceId = "EV-" + [DateTime]::UtcNow.ToString("HHmmss") + "-" + ([Guid]::NewGuid().ToString("N").Substring(0, 4)) }
    $evPath = Join-Path $Workspace ".agents/office/evidence.json"
    $loaded = Read-SenSafeJson -Path $evPath
    $existing = if ($null -eq $loaded) { @() } elseif ($loaded.PSObject.Properties.Name -contains "evidence") { @($loaded.evidence) } else { @($loaded) }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $existing) {
        if ($e -and [string]$e.evidence_id -ne $EvidenceId) { $list.Add($e) }
    }
    $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $verified = ($Status -eq "PASS" -and $ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($Command))
    $entry = [pscustomobject][ordered]@{
        evidence_id    = $EvidenceId
        requirement_id = $RequirementId
        task_id        = $TaskId
        type           = $Type
        status         = if ($verified) { "PASS" } elseif ($Status -eq "STALE") { "STALE" } else { "FAIL" }
        source         = $Source
        command        = $Command
        exitCode       = $ExitCode
        codePaths      = @($CodePaths | Where-Object { $_ })
        timestamp      = $now
        verified       = [bool]$verified
    }
    $list.Add($entry)
    Write-SenAtomicJson -Path $evPath -InputObject ([ordered]@{ updatedAt = $now; evidence = @($list.ToArray()) }) -Depth 8
    return $entry
}

function Test-SenEvidenceValidity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
        [string[]]$InvalidatedTaskIds = @(),
        [string[]]$ModifiedFiles = @()
    )
    $evPath = Join-Path $Workspace ".agents/office/evidence.json"
    $loaded = Read-SenSafeJson -Path $evPath
    if ($null -eq $loaded) { return [pscustomobject][ordered]@{ TotalEvidence = 0; ValidCount = 0; StaleCount = 0; AllValid = $true; StaleEvidenceIds = @() } }
    $list = if ($loaded.PSObject.Properties.Name -contains "evidence") { @($loaded.evidence) } else { @($loaded) }
    $staleIds = [System.Collections.Generic.List[string]]::new()
    $validCount = 0; $changed = $false
    $invSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($InvalidatedTaskIds | Where-Object { $_ }), [System.StringComparer]::OrdinalIgnoreCase)

    foreach ($ev in $list) {
        if (-not $ev) { continue }
        $isStale = ([string]$ev.status -eq "STALE")
        if (-not $isStale -and $ev.task_id -and $invSet.Contains([string]$ev.task_id)) { $isStale = $true }
        if (-not $isStale -and $ModifiedFiles.Count -gt 0 -and (Test-SenPathOverlap -PathsA @($ev.codePaths) -PathsB $ModifiedFiles)) { $isStale = $true }
        $evDt = [DateTime]::MinValue
        $hasValidDt = (-not $isStale) -and $ev.timestamp -and ([DateTime]::TryParse([string]$ev.timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$evDt))
        if ($hasValidDt -and @($ev.codePaths).Count -gt 0) {
            $newerFiles = @($ev.codePaths | Where-Object { $f = Join-Path $Workspace ([string]$_); (Test-Path -LiteralPath $f -PathType Leaf) -and (Get-Item -LiteralPath $f).LastWriteTimeUtc -gt $evDt.AddSeconds(1) })
            if ($newerFiles.Count -gt 0) { $isStale = $true }
        }
        if ($isStale) {
            if ([string]$ev.status -ne "STALE" -or [bool]$ev.verified) { $ev.status = "STALE"; $ev.verified = $false; $changed = $true }
            $staleIds.Add([string]$ev.evidence_id)
        }
        elseif ([bool]$ev.verified -and [string]$ev.status -eq "PASS") { $validCount++ }
    }
    if ($changed) { Write-SenAtomicJson -Path $evPath -InputObject ([ordered]@{ updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); evidence = $list }) -Depth 8 }
    return [pscustomobject][ordered]@{ TotalEvidence = $list.Count; ValidCount = $validCount; StaleCount = $staleIds.Count; AllValid = ($staleIds.Count -eq 0); StaleEvidenceIds = @($staleIds.ToArray()) }
}

function Get-SenRequirementTraceability {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
    [void](Test-SenEvidenceValidity -Workspace $Workspace)
    $reqObj = Read-SenSafeJson -Path (Join-Path $Workspace ".agents/office/requirements.json")
    $reqs = if ($null -eq $reqObj) { @() } elseif ($reqObj.PSObject.Properties.Name -contains "requirements") { @($reqObj.requirements | Where-Object { $_ -and [string]$_.status -ne "SUPERSEDED" }) } else { @($reqObj) }
    $evObj = Read-SenSafeJson -Path (Join-Path $Workspace ".agents/office/evidence.json")
    $evList = if ($null -eq $evObj) { @() } elseif ($evObj.PSObject.Properties.Name -contains "evidence") { @($evObj.evidence) } else { @($evObj) }
    $tasks = @(Get-SenTasks -Workspace $Workspace)

    $missImpl = [System.Collections.Generic.List[string]]::new(); $missTest = [System.Collections.Generic.List[string]]::new()
    $unver = [System.Collections.Generic.List[string]]::new(); $clarif = [System.Collections.Generic.List[string]]::new(); $confl = [System.Collections.Generic.List[string]]::new()
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
    return [pscustomobject][ordered]@{
        TotalRequirements = $reqs.Count; Identified = $reqs.Count; Planned = $reqs.Count; Implemented = $implCnt; Tested = $testCnt; Verified = $verCnt
        MissingImplementation = @($missImpl.ToArray()); MissingTestCoverage = @($missTest.ToArray()); UnverifiedRequirements = @($unver.ToArray())
        NeedsClarification = @($clarif.ToArray()); Conflicts = @($confl.ToArray()); FinalStatus = $finalSt; Accepted = $accepted; ReportText = $rep
    }
}

function Invoke-SenTaskTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][ValidateSet("backlog", "todo", "pending", "ready", "in_progress", "reviewing", "verified", "done", "blocked", "failed", "cancelled", "retrying", "superseded", "stale")][string]$ToStatus,
        [string]$Actor = "pm",
        [string]$Reason = "",
        [int]$LockMinutes = 30
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
    if ($null -eq $target) { return [pscustomobject][ordered]@{ Transitioned = $false; FromStatus = $null; ToStatus = $ToStatus; Task = $null; Reason = "Task '$Id' not found" } }
    $from = [string]$target.status
    $invalidDirectDone = ($from -in @("backlog", "todo", "pending", "ready", "stale", "failed")) -and ($ToStatus -in @("done", "verified"))
    if ($invalidDirectDone) {
        return [pscustomobject][ordered]@{ Transitioned = $false; FromStatus = $from; ToStatus = $ToStatus; Task = $target; Reason = "Invalid transition '$from -> $ToStatus': task must pass through in_progress/reviewing first." }
    }
    $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $hist = [System.Collections.Generic.List[object]]::new()
    if ($target.PSObject.Properties['history'] -and $target.history) { foreach ($h in @($target.history)) { $hist.Add($h) } }
    $hist.Add([ordered]@{ from = $from; to = $ToStatus; actor = $Actor; timestamp = $now; reason = $Reason })
    $target.status = $ToStatus; $target.updatedAt = $now
    $target | Add-Member -NotePropertyName "history" -NotePropertyValue @($hist.ToArray()) -Force
    $expIso = if ($ToStatus -eq "in_progress") { [DateTime]::UtcNow.AddMinutes($LockMinutes).ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }
    $target | Add-Member -NotePropertyName "lockExpiresAt" -NotePropertyValue $expIso -Force
    $curRev = if ($target.PSObject.Properties.Name -contains "_rev") { [int]$target._rev } else { 1 }
    $target | Add-Member -NotePropertyName "_rev" -NotePropertyValue ($curRev + 1) -Force
    [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
    return [pscustomobject][ordered]@{ Transitioned = $true; FromStatus = $from; ToStatus = $ToStatus; Task = $target; Reason = $null }
}

function Invoke-SenChangeImpactAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
        [string]$RequirementId = "",
        [string]$TaskId = "",
        [string]$Reason = "Upstream requirement or task changed"
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $reqPath = Join-Path $Workspace ".agents/office/requirements.json"
    $reqObj = Read-SenSafeJson -Path $reqPath
    $reqs = if ($null -eq $reqObj) { @() } elseif ($reqObj.PSObject.Properties.Name -contains "requirements") { @($reqObj.requirements) } else { @($reqObj) }
    $seedTasks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($TaskId) { [void]$seedTasks.Add($TaskId) }
    $impReqs = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $reqs) {
        if (-not $r) { continue }
        if ($RequirementId -and ([string]$r.id -eq $RequirementId -or @($r.dependsOn) -contains $RequirementId)) {
            $impReqs.Add([string]$r.id); $r.status = "Planned"
            foreach ($tid in @($r.taskIds)) { if ($tid) { [void]$seedTasks.Add([string]$tid) } }
        }
    }
    $added = $true
    while ($added) {
        $added = $false
        foreach ($t in $tasks) {
            if (-not $t -or $seedTasks.Contains([string]$t.id)) { continue }
            foreach ($d in @($t.dependsOn)) {
                if ($seedTasks.Contains([string]$d)) { [void]$seedTasks.Add([string]$t.id); $added = $true; break }
            }
        }
    }
    $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $impFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $tasks) {
        if ($t -and $seedTasks.Contains([string]$t.id)) {
            foreach ($ap in @($t.allowedPaths)) { if ($ap -and -not $impFiles.Contains([string]$ap)) { $impFiles.Add([string]$ap) } }
            if ([string]$t.status -in @("done", "verified", "reviewing")) {
                $t.status = "stale"; $t.updatedAt = $now
                $t | Add-Member -NotePropertyName "needsReverification" -NotePropertyValue $true -Force
            }
        }
    }
    [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks -Internal)
    if ($reqs.Count -gt 0) { Write-SenAtomicJson -Path $reqPath -InputObject ([ordered]@{ updatedAt = $now; requirements = $reqs }) -Depth 8 }
    $evRes = Test-SenEvidenceValidity -Workspace $Workspace -InvalidatedTaskIds @($seedTasks)
    $chgId = "CR-" + [DateTime]::UtcNow.ToString("HHmmss")
    Write-SenAtomicJson -Path (Join-Path $Workspace ".agents/office/change-log.json") -InputObject ([ordered]@{ changeId = $chgId; requirementId = $RequirementId; taskId = $TaskId; reason = $Reason; impactedTasks = @($seedTasks); updatedAt = $now }) -Depth 6
    return [pscustomobject][ordered]@{ ChangedId = if ($RequirementId) { $RequirementId } else { $TaskId }; ChangeRequestId = $chgId; ImpactedTasks = @($seedTasks); ImpactedRequirements = @($impReqs.ToArray()); InvalidatedEvidence = $evRes.StaleEvidenceIds; ImpactedFiles = @($impFiles.ToArray()) }
}

function Invoke-SenCheckpointResume {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
        [string[]]$SimulatedDirtyFiles = @()
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $expired = [System.Collections.Generic.List[string]]::new()
    $nowUtc = [DateTime]::UtcNow
    foreach ($t in $tasks) {
        if ($t -and [string]$t.status -eq "in_progress" -and $t.PSObject.Properties['lockExpiresAt'] -and $t.lockExpiresAt) {
            $expDt = [DateTime]::MinValue
            if ([DateTime]::TryParse([string]$t.lockExpiresAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$expDt) -and $expDt -lt $nowUtc) {
                $expired.Add([string]$t.id)
                [void](Unlock-SenTask -Workspace $Workspace -Id ([string]$t.id))
            }
        }
    }
    $dirty = [System.Collections.Generic.List[string]]::new()
    foreach ($sf in $SimulatedDirtyFiles) { if (-not [string]::IsNullOrWhiteSpace($sf)) { $dirty.Add($sf) } }
    if ($dirty.Count -eq 0 -and (Test-Path -LiteralPath (Join-Path $Workspace ".git"))) {
        try {
            $gitLines = @(& git -C $Workspace status --porcelain 2>$null)
            foreach ($gl in $gitLines) {
                if ($gl -and $gl.Length -gt 3) { $dirty.Add($gl.Substring(3).Trim()) }
            }
        }
        catch { <# Ignore git status error in non-git temp workspace #> }
    }
    $evCheck = Test-SenEvidenceValidity -Workspace $Workspace -ModifiedFiles @($dirty.ToArray())
    $rec = Get-SenRecoveryState -Workspace $Workspace
    return [pscustomobject][ordered]@{
        CompletedTasks      = @($rec.doneIds)
        ActiveTasks         = @($rec.inProgressIds)
        ReadyTasks          = @($rec.readyIds)
        ExpiredLocks        = @($expired.ToArray())
        UncommittedFiles    = @($dirty.ToArray())
        StaleEvidence       = @($evCheck.StaleEvidenceIds)
        SafeToResume        = $true
        PreventDuplicateIds = @($rec.doneIds)
    }
}

function Test-SenMidTaskEscalation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
        [string[]]$ModifiedFiles = @()
    )
    $auditPath = Join-Path $Workspace ".agents/office/process-audit.json"
    $audit = Read-SenSafeJson -Path $auditPath
    $curTier = if ($null -ne $audit -and $audit.PSObject.Properties['tier']) { [int]$audit.tier } else { 1 }
    $targetTier = $curTier; $reason = $null
    $critRe = '(?i)(auth|login|oauth|jwt|payment|billing|stripe|vnpay|momo|schema|migration|database|secret|guard\.ps1)'
    foreach ($mf in $ModifiedFiles) {
        if ($mf -match $critRe) { $targetTier = 3; $reason = "Modified critical security/data/auth path: $mf"; break }
    }
    if ($targetTier -lt 2 -and $ModifiedFiles.Count -ge 3) {
        $targetTier = 2; $reason = "Modified file count ($($ModifiedFiles.Count)) reached Tier 2 threshold (>= 3 files)"
    }
    $escalated = ($targetTier -gt $curTier)
    if ($escalated -and $null -ne $audit) {
        $audit | Add-Member -NotePropertyName "escalatedFrom" -NotePropertyValue $curTier -Force
        $audit.tier = $targetTier
        $audit.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        Write-SenAtomicJson -Path $auditPath -InputObject $audit -Depth 8
    }
    return [pscustomobject][ordered]@{ Escalated = $escalated; PreviousTier = $curTier; NewTier = $targetTier; Reason = $reason }
}

function Test-SenSuiteIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$TestsPath = "",
        [int]$MinFiles = 1,
        [int]$MinAssertions = 1
    )
    $tDir = if (-not [string]::IsNullOrWhiteSpace($TestsPath)) { $TestsPath } else { Join-Path $PSScriptRoot "../tests" }
    if (-not (Test-Path -LiteralPath $tDir)) {
        return [pscustomobject][ordered]@{ Passed = $false; FileCount = 0; AssertionCount = 0; MinAssertions = $MinAssertions; Reason = "Tests directory not found: $tDir" }
    }
    $files = @(Get-ChildItem -LiteralPath $tDir -Filter "*.Tests.ps1" -File -ErrorAction SilentlyContinue)
    $assertCount = 0; $emptyFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $files) {
        $txt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
        $cnt = [regex]::Matches($txt, '\bAssert-[A-Za-z]+\b').Count
        if ($cnt -eq 0) { $emptyFiles.Add($f.Name) }
        $assertCount += $cnt
    }
    $passed = ($files.Count -ge $MinFiles) -and ($assertCount -ge $MinAssertions) -and ($emptyFiles.Count -eq 0)
    $reason = if ($passed) { "Suite integrity verified ($($files.Count) files, $assertCount assertions)." } else { "Suite integrity failed: files=$($files.Count)/$MinFiles, assertions=$assertCount/$MinAssertions, empty=$($emptyFiles -join ',')" }
    return [pscustomobject][ordered]@{ Passed = $passed; FileCount = $files.Count; AssertionCount = $assertCount; MinAssertions = $MinAssertions; Reason = $reason }
}

function Measure-SenTokenEstimate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$Text = "",
        [string]$Path = "",
        [int]$TokenBudget = 1500
    )
    $content = if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) { [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) } else { $Text }
    if ([string]::IsNullOrEmpty($content)) {
        return [pscustomobject][ordered]@{ EstimatedTokens = 0; ByteCount = 0; CharCount = 0; NonAsciiCount = 0; TokenBudget = $TokenBudget; WithinBudget = $true }
    }
    $bytes = [System.Text.Encoding]::UTF8.GetByteCount($content)
    $chars = $content.Length
    $nonAscii = [regex]::Matches($content, '[^\x00-\x7F]').Count
    $punct = [regex]::Matches($content, '[\{\}\[\]\(\);:,<>=\+\-\*/\|\\]').Count
    $est = [int][Math]::Ceiling(($chars / 3.8) + ($nonAscii * 0.45) + ($punct * 0.15))
    return [pscustomobject][ordered]@{
        EstimatedTokens = $est; ByteCount = $bytes; CharCount = $chars; NonAsciiCount = $nonAscii
        TokenBudget = $TokenBudget; WithinBudget = ($est -le $TokenBudget)
    }
}

function Set-SenEdition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
        [Parameter(Mandatory = $true)][ValidateSet("core", "full")][string]$Edition
    )
    $mode = if ($Edition -eq "core") { "off" } else { "eco" }
    $cfg = Set-SenOfficeConfig -Workspace $Workspace -Mode $mode
    $cfg["edition"] = $Edition
    $cfg["telemetryEnabled"] = ($Edition -eq "full")
    $cfg["creativePacksEnabled"] = ($Edition -eq "full")
    Write-SenAtomicJson -Path (Join-Path $Workspace ".agents/office/config.json") -InputObject $cfg -Depth 5
    return [pscustomobject]$cfg
}

function Get-SenDeferredItems {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
    $defPath = Join-Path $Workspace ".agents/office/deferred-items.json"
    $loaded = Read-SenSafeJson -Path $defPath
    if ($null -ne $loaded -and $loaded.PSObject.Properties['items']) { return @($loaded.items) }
    $defaultItems = @(
        [ordered]@{ id = "W-09"; source = "Grok"; title = "Tone down marketing/pitch style in README.md and shorten overview prose"; status = "pending_user_confirmation"; mitigation = "Kept current inspiring/accessible prose style intact pending user confirmation" },
        [ordered]@{ id = "W-26 / IMP-19"; source = "Claude"; title = "Hide or replace public personal contact & bank donate info (Phone, Email, Bank Account) in README.md and docs/huong-dan.md"; status = "pending_user_confirmation"; mitigation = "Never delete author contact/donation info without explicit owner confirmation" },
        [ordered]@{ id = "IMP-13 / IMP-05"; source = "Grok"; title = "Rewrite core PowerShell runtime into Node.js/TypeScript or Python runtime"; status = "disagreed_rejected"; mitigation = "Rejected to preserve zero-dependency core (no node_modules required for core); solved cross-platform via POSIX .sh scripts and hook dispatcher" },
        [ordered]@{ id = "IMP-10 / IMP-29"; source = "Grok/Claude"; title = "Split Sen.Legal.psm1 and sen-office into separate external Git repositories"; status = "disagreed_rejected"; mitigation = "Rejected repo fragmentation; solved via single-repo Set-SenEdition -Edition core|full switch" }
    )
    Write-SenAtomicJson -Path $defPath -InputObject ([ordered]@{ version = "0.5.0"; updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); items = $defaultItems }) -Depth 6
    return @($defaultItems | ForEach-Object { [pscustomobject]$_ })
}

function Uninstall-SenSelf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path,
        [switch]$RemovePluginDir,
        [switch]$DryRun
    )
    $leaf = Split-Path -Path $Workspace -Leaf
    $taskName = "Sen update check ($leaf)"
    $schedRemoved = $false
    if (-not $DryRun.IsPresent) {
        try {
            if (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                $schedRemoved = $true
            }
        }
        catch { <# Ignore if scheduled task does not exist #> }
    }
    $hRemoved = @()
    if (-not $DryRun.IsPresent -and (Get-Command Uninstall-SenHarness -ErrorAction SilentlyContinue)) {
        $unH = Uninstall-SenHarness -Workspace $Workspace -Harness @("all")
        $hRemoved = @($unH.Uninstalled)
    }
    $pluginDir = Join-Path $Workspace ".agents/plugins/sen-method"
    if ($RemovePluginDir.IsPresent -and (-not $DryRun.IsPresent) -and (Test-Path -LiteralPath $pluginDir)) {
        Remove-Item -LiteralPath $pluginDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    return [pscustomobject][ordered]@{
        Uninstalled          = $true
        Workspace            = $Workspace
        ScheduledTaskName    = $taskName
        ScheduledTaskRemoved = $schedRemoved
        HarnessesRemoved     = $hRemoved
        DryRun               = [bool]$DryRun.IsPresent
    }
}

Export-ModuleMember -Function Resolve-SenWorkspaceRoot, Test-SenSafeWorkspacePath, New-SenReleaseNote, Test-SenReleaseNoteGate, Register-SenRequirement, Register-SenEvidence, Test-SenEvidenceValidity, Get-SenRequirementTraceability, Invoke-SenTaskTransition, Invoke-SenChangeImpactAnalysis, Invoke-SenCheckpointResume, Test-SenMidTaskEscalation, Test-SenSuiteIntegrity, Measure-SenTokenEstimate, Set-SenEdition, Get-SenDeferredItems, Uninstall-SenSelf
