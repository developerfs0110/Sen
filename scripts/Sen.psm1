# scripts/Sen.psm1
# Pure ASCII PowerShell module for Sen workspace, drive, tool catalog, and package helpers.
# Runtime, Office, Risk, Task DAG, Backlog, Restore Point, and Memory functions live in Sen.Runtime.psm1.

$senRuntimeModulePath = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Runtime.psm1"
if (Test-Path -LiteralPath $senRuntimeModulePath) {
    Import-Module -Name $senRuntimeModulePath -Global -Force
}

function Get-SenSelfPayloadNames {
    return @("plugin.json", "hooks.json", "rules", "skills", "templates", "scripts", "office", "INSTALL.md", "LICENSE", "CHANGELOG.md")
}

function Test-SenDriveWritable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )
    if ([string]::IsNullOrEmpty($Root)) { return $false }
    $cleanRoot = $Root
    if ($cleanRoot -match '^[a-zA-Z]:$') {
        $cleanRoot = $cleanRoot + "\"
    }
    $testFile = Join-Path -Path $cleanRoot -ChildPath ".sen-write-test"
    try {
        [System.IO.File]::WriteAllText($testFile, "sen-probe")
        if (Test-Path -LiteralPath $testFile) {
            Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
        }
        return $true
    }
    catch {
        return $false
    }
}

function Get-SenDriveCandidates {
    [CmdletBinding()]
    param(
        [Parameter(DontShow = $true)]
        [scriptblock]$DriveSource = $null
    )

    if ($null -eq $DriveSource) {
        $DriveSource = {
            $items = [System.Collections.Generic.List[object]]::new()
            try {
                $drives = [System.IO.DriveInfo]::GetDrives()
                foreach ($d in $drives) {
                    try {
                        if (-not $d.IsReady) { continue }
                        if ($null -ne $d.PSObject.Properties['DriveType'] -and $null -ne $d.DriveType -and ([string]$d.DriveType -ne 'Fixed')) { continue }
                        $r = $d.RootDirectory.FullName
                        $freeBytes = $d.AvailableFreeSpace
                        $freeGB = [double]($freeBytes / 1GB)
                        $writable = Test-SenDriveWritable -Root $r
                        $items.Add([pscustomobject]@{
                                Root     = $r
                                FreeGB   = $freeGB
                                Writable = $writable
                            })
                    }
                    catch { <# Ignore inaccessible drive entry #> }
                }
            }
            catch { <# Ignore drive enumeration failure #> }
            return $items
        }
    }

    $raw = & $DriveSource
    $candidates = [System.Collections.Generic.List[object]]::new()

    foreach ($item in $raw) {
        if ($null -eq $item) { continue }
        if ($null -ne $item.PSObject.Properties['DriveType'] -and $null -ne $item.DriveType -and ([string]$item.DriveType -ne 'Fixed')) { continue }

        $root = $null
        if ($item.PSObject.Properties['Root']) {
            $root = [string]$item.Root
        }
        elseif ($item.PSObject.Properties['RootDirectory']) {
            $root = [string]$item.RootDirectory.FullName
        }
        elseif ($item.PSObject.Properties['Name']) {
            $root = [string]$item.Name
        }
        else {
            $root = [string]$item
        }

        $freeGB = 0.0
        if ($item.PSObject.Properties['FreeGB'] -and $null -ne $item.FreeGB) {
            $freeGB = [double]$item.FreeGB
        }
        elseif ($item.PSObject.Properties['AvailableFreeSpace'] -and $null -ne $item.AvailableFreeSpace) {
            $freeGB = [double]($item.AvailableFreeSpace / 1GB)
        }
        elseif ($item.PSObject.Properties['TotalFreeSpace'] -and $null -ne $item.TotalFreeSpace) {
            $freeGB = [double]($item.TotalFreeSpace / 1GB)
        }

        $writable = $false
        if ($item.PSObject.Properties['Writable'] -and $null -ne $item.Writable) {
            $writable = [bool]$item.Writable
        }
        else {
            $writable = Test-SenDriveWritable -Root $root
        }

        if ($writable -and $freeGB -gt 1.0) {
            $candidates.Add([pscustomobject]@{
                    Root     = $root
                    FreeGB   = [double][Math]::Round($freeGB, 2)
                    Writable = [bool]$writable
                })
        }
    }

    $sorted = $candidates | Sort-Object -Property FreeGB -Descending
    return @($sorted)
}

function New-SenWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$TemplateRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        [System.IO.Directory]::CreateDirectory($Path) | Out-Null
    }

    $wsSource = $null
    if (Test-Path -LiteralPath (Join-Path $TemplateRoot "workspace")) {
        $wsSource = (Resolve-Path -LiteralPath (Join-Path $TemplateRoot "workspace")).Path
    }
    elseif (Test-Path -LiteralPath $TemplateRoot) {
        $wsSource = (Resolve-Path -LiteralPath $TemplateRoot).Path
    }

    $standardRelDirs = @(
        ".agents/rules",
        ".agents/plugins",
        ".agents/skills",
        "Code",
        "Templates",
        "docs"
    )

    $relDirs = [System.Collections.Generic.List[string]]::new()
    foreach ($d in $standardRelDirs) {
        $relDirs.Add($d)
    }

    if ($wsSource -and (Test-Path -LiteralPath $wsSource)) {
        $files = Get-ChildItem -LiteralPath $wsSource -File -Recurse
        foreach ($f in $files) {
            $parentDir = $f.DirectoryName
            $rel = $parentDir.Substring($wsSource.Length).TrimStart("\/")
            $normalizedRel = $rel -replace '\\', '/'
            if ($normalizedRel -and -not $relDirs.Contains($normalizedRel)) {
                $relDirs.Add($normalizedRel)
            }
        }
    }

    $created = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()

    foreach ($rel in $relDirs) {
        $targetSubDir = Join-Path -Path $Path -ChildPath ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $targetSubDir) {
            $skipped.Add($rel)
        }
        else {
            [System.IO.Directory]::CreateDirectory($targetSubDir) | Out-Null
            $created.Add($rel)
        }

        if (-not $wsSource) { continue }
        $srcDir = Join-Path -Path $wsSource -ChildPath ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $srcDir)) { continue }
        foreach ($sf in (Get-ChildItem -LiteralPath $srcDir -File)) {
            $targetFile = Join-Path -Path $targetSubDir -ChildPath $sf.Name
            if (-not (Test-Path -LiteralPath $targetFile)) {
                Copy-Item -LiteralPath $sf.FullName -Destination $targetFile -Force
            }
        }
    }

    return [pscustomobject]@{
        Created = [string[]]$created.ToArray()
        Skipped = [string[]]$skipped.ToArray()
    }
}

function New-SenFileFromTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template,
        [Parameter(Mandatory = $true)]
        [string]$Destination,
        [Parameter(Mandatory = $false)]
        [hashtable]$Values = @{}
    )

    if (Test-Path -LiteralPath $Destination) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $Template)) {
        throw "Template not found: $Template"
    }

    $templateResolved = (Resolve-Path -LiteralPath $Template).Path
    $content = [System.IO.File]::ReadAllText($templateResolved, [System.Text.Encoding]::UTF8)

    if ($null -ne $Values) {
        foreach ($key in $Values.Keys) {
            $placeholder = "{{" + $key + "}}"
            $val = if ($null -eq $Values[$key]) { "" } else { [string]$Values[$key] }
            $content = $content.Replace($placeholder, $val)
        }
    }

    $destDir = [System.IO.Path]::GetDirectoryName($Destination)
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        [System.IO.Directory]::CreateDirectory($destDir) | Out-Null
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Destination, $content, $utf8NoBom)

    return $true
}

function Get-SenCleanVersion {
    param([string]$Raw)
    if ([string]::IsNullOrEmpty($Raw)) { return $null }
    if ($Raw -match '(?i)\b[vn]?(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)\b') {
        return $matches[1]
    }
    return $null
}

function ConvertTo-SenNormalizedVersion {
    param([string]$VersionString)
    if ([string]::IsNullOrEmpty($VersionString)) { return $null }
    $clean = Get-SenCleanVersion -Raw $VersionString
    if ([string]::IsNullOrEmpty($clean)) { return $null }
    $parts = $clean.Split('.')
    if ($parts.Count -eq 1) {
        return [version]("$($parts[0]).0.0")
    }
    elseif ($parts.Count -eq 2) {
        return [version]("$($parts[0]).$($parts[1]).0")
    }
    else {
        $take = [Math]::Min($parts.Count, 4)
        return [version](($parts[0..($take - 1)]) -join '.')
    }
}

function Test-SenVersionMeetsMin {
    param(
        [string]$DetectedVersion,
        [string]$MinVersion
    )
    if ([string]::IsNullOrEmpty($MinVersion)) { return $true }
    if ([string]::IsNullOrEmpty($DetectedVersion)) { return $false }
    $vDetected = ConvertTo-SenNormalizedVersion -VersionString $DetectedVersion
    $vMin = ConvertTo-SenNormalizedVersion -VersionString $MinVersion
    if ($null -eq $vDetected -or $null -eq $vMin) { return $false }
    return ($vDetected -ge $vMin)
}

function Invoke-SenRunner {
    param(
        [scriptblock]$Runner,
        [string]$CommandLine
    )
    if ($null -eq $Runner) {
        try {
            $cleanCmd = ($CommandLine -replace '\s*2>&1\s*$', '').Trim()
            if ($cleanCmd.StartsWith('&')) { $cleanCmd = $cleanCmd.Substring(1).Trim() }
            $parts = [System.Collections.Generic.List[string]]::new()
            foreach ($m in [regex]::Matches($cleanCmd, '"([^"]+)"|''([^'']+)''|(\S+)')) {
                $val = if ($m.Groups[1].Success) { $m.Groups[1].Value } elseif ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[3].Value }
                if (-not [string]::IsNullOrWhiteSpace($val)) { $parts.Add($val) }
            }
            if ($parts.Count -eq 0) { return $null }
            $exe = [string]$parts[0]
            [string[]]$cmdArgs = @(if ($parts.Count -gt 1) { $parts[1..($parts.Count - 1)] })
            $out = & $exe @cmdArgs 2>$null
            if ($null -eq $out) { return $null }
            if ($out -is [System.Collections.IEnumerable] -and $out -isnot [string]) {
                $joined = ($out -join "`n").Trim()
                if ($joined) { return $joined } else { return $null }
            }
            $str = [string]$out
            if (-not [string]::IsNullOrWhiteSpace($str)) { return $str.Trim() }
            return $null
        }
        catch {
            return $null
        }
    }
    else {
        try {
            $out = & $Runner $CommandLine
            if ($null -eq $out) { return $null }
            if ($out -is [System.Collections.IEnumerable] -and $out -isnot [string]) {
                $joined = ($out -join "`n").Trim()
                if ($joined) { return $joined } else { return $null }
            }
            $str = [string]$out
            if (-not [string]::IsNullOrWhiteSpace($str)) { return $str.Trim() }
            return $null
        }
        catch {
            return $null
        }
    }
}

function Get-SenToolCatalog {
    param([string]$CatalogPath)
    $resolvedPath = $CatalogPath
    if ([string]::IsNullOrEmpty($resolvedPath)) {
        $resolvedPath = Join-Path -Path $PSScriptRoot -ChildPath "tools.json"
    }
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        throw "Tools catalog not found: $resolvedPath"
    }
    $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $resolvedPath).Path, [System.Text.Encoding]::UTF8)
    $cleaned = [regex]::Replace($raw, '(?m)^\s*//.*$', '')
    return @(ConvertFrom-Json -InputObject $cleaned)
}

function New-SenToolStatusResult {
    param([string]$Id, [string]$Version, [string]$MinVersion, [string]$Source)
    if ([string]::IsNullOrEmpty($Version)) {
        return [pscustomobject]@{ Id = $Id; Status = 'missing'; Version = $null; Source = $null }
    }
    $isOk = Test-SenVersionMeetsMin -DetectedVersion $Version -MinVersion $MinVersion
    return [pscustomobject]@{
        Id      = $Id
        Status  = if ($isOk) { 'ok' } else { 'outdated' }
        Version = $Version
        Source  = $Source
    }
}

function Select-SenManagerActiveVersion {
    param([string]$ManagerOutput)
    if ([string]::IsNullOrEmpty($ManagerOutput)) { return $null }
    foreach ($line in ($ManagerOutput -split "[\r\n]+")) {
        if ($line -match '^\s*(?:\*|->)\s*v?(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)') {
            return $matches[1]
        }
    }
    $matchesList = [regex]::Matches($ManagerOutput, '(?i)\bv?(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)\b')
    $bestNorm = $null
    $bestRaw = $null
    foreach ($m in $matchesList) {
        $cand = $m.Groups[1].Value
        $norm = ConvertTo-SenNormalizedVersion -VersionString $cand
        if ($null -ne $norm -and ($null -eq $bestNorm -or $norm -gt $bestNorm)) {
            $bestNorm = $norm
            $bestRaw = $cand
        }
    }
    return $bestRaw
}

function Find-SenToolViaExtraPaths {
    param($Tool, [scriptblock]$Runner, [scriptblock]$PathChecker)
    if (-not $Tool.extraPaths) { return $null }
    $vArgs = "--version"
    if (-not [string]::IsNullOrEmpty($Tool.versionCommand)) {
        $tokens = $Tool.versionCommand -split '\s+', 2
        if ($tokens.Count -ge 2) { $vArgs = $tokens[1] }
    }
    foreach ($rawPath in $Tool.extraPaths) {
        if ([string]::IsNullOrEmpty($rawPath)) { continue }
        $expanded = [System.Environment]::ExpandEnvironmentVariables($rawPath)
        if (-not (& $PathChecker $expanded)) { continue }
        $extraOutput = Invoke-SenRunner -Runner $Runner -CommandLine ("& `"$expanded`" $vArgs")
        $ver = Get-SenCleanVersion -Raw $extraOutput
        if (-not [string]::IsNullOrEmpty($ver)) { return $ver }
    }
    return $null
}

function Find-SenToolViaManagers {
    param($Tool, [scriptblock]$Runner)
    if (-not $Tool.managers) { return $null }
    foreach ($mgr in $Tool.managers) {
        $mgrName = if ($mgr -is [string]) { ($mgr -split '\s+')[0] } elseif ($mgr.PSObject.Properties['name']) { [string]$mgr.name } else { $null }
        $mgrCmd = if ($mgr -is [string]) { $mgr } elseif ($mgr.PSObject.Properties['name']) { [string]$mgr.command } else { $null }
        if ([string]::IsNullOrEmpty($mgrCmd)) { continue }
        $mgrOutput = Invoke-SenRunner -Runner $Runner -CommandLine $mgrCmd
        $activeVer = Select-SenManagerActiveVersion -ManagerOutput $mgrOutput
        if (-not [string]::IsNullOrEmpty($activeVer)) {
            return @{ Version = $activeVer; Source = $mgrName }
        }
    }
    return $null
}

function Get-SenToolStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $false)]
        [string]$Catalog = "",
        [Parameter(Mandatory = $false)]
        [scriptblock]$Runner = $null,
        [Parameter(Mandatory = $false)]
        [scriptblock]$PathChecker = $null
    )
    if ($null -eq $PathChecker) {
        $PathChecker = { param([string]$P) return (Test-Path -LiteralPath $P) }
    }
    $catalogTools = Get-SenToolCatalog -CatalogPath $Catalog
    $tool = $catalogTools | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if ($null -eq $tool) {
        return (New-SenToolStatusResult -Id $Id -Version $null -MinVersion $null -Source $null)
    }

    if (-not [string]::IsNullOrEmpty($tool.versionCommand)) {
        $rawVerOut = Invoke-SenRunner -Runner $Runner -CommandLine $tool.versionCommand
        if ([string]::IsNullOrEmpty($rawVerOut) -and $tool.id -eq "imagemagick") {
            $rawVerOut = Invoke-SenRunner -Runner $Runner -CommandLine "magick --version"
            if ([string]::IsNullOrEmpty($rawVerOut)) { $rawVerOut = Invoke-SenRunner -Runner $Runner -CommandLine "convert -version" }
        }
        elseif ([string]::IsNullOrEmpty($rawVerOut) -and $tool.id -eq "ffmpeg") {
            $rawVerOut = Invoke-SenRunner -Runner $Runner -CommandLine "ffmpeg --version"
        }
        $ver = Get-SenCleanVersion -Raw $rawVerOut
        if (-not [string]::IsNullOrEmpty($ver)) {
            return (New-SenToolStatusResult -Id $tool.id -Version $ver -MinVersion $tool.minVersion -Source 'PATH')
        }
    }

    $extraVer = Find-SenToolViaExtraPaths -Tool $tool -Runner $Runner -PathChecker $PathChecker
    if (-not [string]::IsNullOrEmpty($extraVer)) {
        return (New-SenToolStatusResult -Id $tool.id -Version $extraVer -MinVersion $tool.minVersion -Source 'extraPath')
    }

    $mgrHit = Find-SenToolViaManagers -Tool $tool -Runner $Runner
    if ($null -ne $mgrHit) {
        return (New-SenToolStatusResult -Id $tool.id -Version $mgrHit.Version -MinVersion $tool.minVersion -Source $mgrHit.Source)
    }

    return (New-SenToolStatusResult -Id $tool.id -Version $null -MinVersion $tool.minVersion -Source $null)
}

function Get-SenInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids,
        [Parameter(Mandatory = $false)]
        [string[]]$Required = @(),
        [Parameter(Mandatory = $false)]
        [string]$Catalog = "",
        [Parameter(Mandatory = $false)]
        [string]$Platform = "",
        [Parameter(Mandatory = $false)]
        [scriptblock]$Runner = $null,
        [Parameter(Mandatory = $false)]
        [scriptblock]$PathChecker = $null
    )

    $isWin = $false
    if (-not [string]::IsNullOrEmpty($Platform)) {
        if ($Platform -match '(?i)^(win|windows|windows_nt|win32)$') {
            $isWin = $true
        }
        elseif ($Platform -match '(?i)^(mac|macos|darwin|osx)$') {
            $isWin = $false
        }
        else {
            $isWin = ($Platform -like "*win*")
        }
    }
    else {
        if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
            $isWin = [bool]$IsWindows
        }
        else {
            $isWin = ($env:OS -eq 'Windows_NT')
        }
    }

    $catalogTools = Get-SenToolCatalog -CatalogPath $Catalog
    $planItems = [System.Collections.Generic.List[object]]::new()

    foreach ($toolId in $Ids) {
        if ([string]::IsNullOrEmpty($toolId)) { continue }
        $tool = $catalogTools | Where-Object { $_.id -eq $toolId } | Select-Object -First 1
        if ($null -eq $tool) { continue }

        $statusObj = Get-SenToolStatus -Id $toolId -Catalog $Catalog -Runner $Runner -PathChecker $PathChecker
        if ($statusObj.Status -eq 'missing' -or $statusObj.Status -eq 'outdated') {
            $isRequired = ($null -ne $Required -and $Required -contains $toolId)
            $cmd = $null

            if ($isWin) {
                if (-not [string]::IsNullOrEmpty($tool.winget)) {
                    $cmd = "winget install --id $($tool.winget) -e --source winget"
                }
            }
            else {
                if (-not [string]::IsNullOrEmpty($tool.brew)) {
                    $cmd = "brew install $($tool.brew)"
                }
            }

            $manualUrl = $null
            if ($tool.PSObject.Properties['manualUrl'] -and -not [string]::IsNullOrEmpty($tool.manualUrl)) {
                $manualUrl = [string]$tool.manualUrl
            }

            $planItems.Add([pscustomobject]@{
                    Id             = $tool.id
                    DisplayName    = $tool.displayName
                    Version        = $tool.minVersion
                    ApproxSizeMB   = $tool.approxSizeMB
                    Required       = [bool]$isRequired
                    Command        = $cmd
                    Status         = $statusObj.Status
                    CurrentVersion = $statusObj.Version
                    ManualUrl      = $manualUrl
                })
        }
    }

    return , @($planItems.ToArray())
}


$senPackagesModulePath = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Packages.psm1"
if (Test-Path -LiteralPath $senPackagesModulePath) {
    Import-Module -Name $senPackagesModulePath -Global -Force
}

$senHarnessModulePath = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Harness.psm1"
if (Test-Path -LiteralPath $senHarnessModulePath) {
    Import-Module -Name $senHarnessModulePath -Global -Force
}

$senGovernanceModulePath = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Governance.psm1"
if (Test-Path -LiteralPath $senGovernanceModulePath) {
    Import-Module -Name $senGovernanceModulePath -Global -Force
}

$senAdversarialModulePath = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Adversarial.psm1"
if (Test-Path -LiteralPath $senAdversarialModulePath) {
    Import-Module -Name $senAdversarialModulePath -Global -Force
}

$senBoundedLoopModulePath = Join-Path -Path $PSScriptRoot -ChildPath "Sen.BoundedLoop.psm1"
if (Test-Path -LiteralPath $senBoundedLoopModulePath) {
    Import-Module -Name $senBoundedLoopModulePath -Global -Force
}

function Format-SenReleaseBullets {
    param([string[]]$Items, [string]$EmptyText)
    $valid = @($Items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($valid.Count -eq 0) { return "- $EmptyText" }
    return (($valid | ForEach-Object { "- " + $_.Trim() }) -join "`n")
}

function Update-SenReleaseNotesIndex {
    param([string]$ReleasesDir)
    $viF = @(Get-ChildItem -LiteralPath $ReleasesDir -Filter "v*.vi.md" -File -EA SilentlyContinue | Sort-Object Name -Descending)
    $enF = @(Get-ChildItem -LiteralPath $ReleasesDir -Filter "v*.en.md" -File -EA SilentlyContinue | Sort-Object Name -Descending)
    $viH = [regex]::Unescape('# T\u1ed5ng H\u1ee3p Release Notes (Ti\u1ebfng Vi\u1ec7t) \u2014 Sen (`sen-method`)\n\n| Phi\u00ean b\u1ea3n | T\u00e0i li\u1ec7u | Tr\u1ea1ng th\u00e1i |\n|---|---|---|')
    $viR = foreach ($f in $viF) { $t = $f.BaseName -replace '\.vi$', ''; "| **$t** | [$t ($($f.Name))]($($f.Name)) | Released / Verified |" }
    $enH = "# Master Release Notes Index (English) - Sen (``sen-method``)`n`n| Version | Release Note | Status |`n|---|---|---|"
    $enR = foreach ($f in $enF) { $t = $f.BaseName -replace '\.en$', ''; "| **$t** | [$t ($($f.Name))]($($f.Name)) | Released / Verified |" }
    $u8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $ReleasesDir "RELEASE-NOTES.vi.md"), ($viH + "`n" + ($viR -join "`n") + "`n"), $u8)
    [IO.File]::WriteAllText((Join-Path $ReleasesDir "RELEASE-NOTES.en.md"), ($enH + "`n" + ($enR -join "`n") + "`n"), $u8)
}

function New-SenReleaseNote {
    [CmdletBinding()]
    param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [Parameter(Mandatory)][string]$Version, [string]$Date = "", [string[]]$Fixed = @(), [string[]]$Removed = @(), [string[]]$Improved = @(), [string[]]$Deferred = @(), [string]$SummaryVi = "", [string]$SummaryEn = "")
    $v = ($Version.Trim() -replace '^[vV]', ''); $dt = if ($Date) { $Date } else { [DateTime]::UtcNow.ToString("yyyy-MM-dd") }
    $relDir = Join-Path $Workspace "docs/releases"; if (-not (Test-Path -LiteralPath $relDir)) { [IO.Directory]::CreateDirectory($relDir) | Out-Null }
    $u = { param($s) [regex]::Unescape($s) }
    $sVi = if ($SummaryVi) { $SummaryVi } else { & $u "B\u1ea3n ph\u00e1t h\u00e0nh Sen ``v$v`` ($dt)." }
    $sEn = if ($SummaryEn) { $SummaryEn } else { "Sen release ``v$v`` ($dt)." }
    $viBody = @((& $u "# Release Notes ``v$v`` (Ti\u1ebfng Vi\u1ec7t) \u2014 Sen (``sen-method``)"), "", (& $u "- **Phi\u00ean b\u1ea3n:** ``v$v`` (`$dt`) | [v$v.en.md](v$v.en.md) | [RELEASE-NOTES.vi.md](RELEASE-NOTES.vi.md)"), "", (& $u "## 1. T\u00f3m t\u1eaft (Summary)"), $sVi, "", (& $u "## 2. \u0110\u00e3 s\u1eeda (Fixed)"), (Format-SenReleaseBullets $Fixed "None"), "", (& $u "## 3. \u0110\u00e3 x\u00f3a (Removed)"), (Format-SenReleaseBullets $Removed "None"), "", (& $u "## 4. C\u1ea3i ti\u1ebfn (Improved & Added)"), (Format-SenReleaseBullets $Improved "Updated"), "", (& $u "## 5. B\u1ea3o L\u01b0u (Deferred)"), (Format-SenReleaseBullets $Deferred "None")) -join "`n"
    $enBody = @("# Release Notes ``v$v`` (English) - Sen (``sen-method``)", "", "- **Version:** ``v$v`` ($dt) | [v$v.vi.md](v$v.vi.md) | [RELEASE-NOTES.en.md](RELEASE-NOTES.en.md)", "", "## 1. Summary", $sEn, "", "## 2. Fixed", (Format-SenReleaseBullets $Fixed "None"), "", "## 3. Removed", (Format-SenReleaseBullets $Removed "None"), "", "## 4. Improved & Added", (Format-SenReleaseBullets $Improved "Updated"), "", "## 5. Deferred & Pending Review", (Format-SenReleaseBullets $Deferred "None")) -join "`n"
    $viP = Join-Path $relDir "v$v.vi.md"; $enP = Join-Path $relDir "v$v.en.md"; $u8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($viP, $viBody + "`n", $u8); [IO.File]::WriteAllText($enP, $enBody + "`n", $u8); Update-SenReleaseNotesIndex -ReleasesDir $relDir
    return [pscustomobject]@{ Version = $v; ViPath = $viP; EnPath = $enP; IndexViPath = (Join-Path $relDir "RELEASE-NOTES.vi.md"); IndexEnPath = (Join-Path $relDir "RELEASE-NOTES.en.md") }
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

function Get-SenProjectTechStack {
    [CmdletBinding()]
    param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$Request = "")
    $fe = [Collections.Generic.List[string]]::new(); $be = [Collections.Generic.List[string]]::new()
    $db = [Collections.Generic.List[string]]::new(); $inf = [Collections.Generic.List[string]]::new(); $tst = [Collections.Generic.List[string]]::new()
    $mans = [Collections.Generic.List[string]]::new()
    foreach ($m in @("package.json", "tsconfig.json", "pyproject.toml", "requirements.txt", "pubspec.yaml", "go.mod", "Cargo.toml", "plugin.json", "office/index.html", "Dockerfile")) {
        if (Test-Path -LiteralPath (Join-Path $Workspace $m)) { $mans.Add($m) }
    }
    if ($mans.Contains("package.json")) {
        $pkgTxt = [IO.File]::ReadAllText((Join-Path $Workspace "package.json"), [Text.Encoding]::UTF8)
        if ($pkgTxt -match '"next"') { $fe.Add("Next.js") }; if ($pkgTxt -match '"react"') { $fe.Add("React") }
        if ($pkgTxt -match '"vue"') { $fe.Add("Vue") }; if ($pkgTxt -match '"vite"') { $fe.Add("Vite") }
        if ($pkgTxt -match '"(@nestjs|express|fastify)"') { $be.Add("Node.js") }
        if ($pkgTxt -match '"(@prisma/client|prisma|pg|mysql2|mongoose)"') { $db.Add("Prisma/SQL/NoSQL ORM") }
        if ($pkgTxt -match '"(vitest|jest|playwright)"') { $tst.Add("Vitest/Jest/Playwright") }
    }
    if ($mans.Contains("pubspec.yaml")) { $fe.Add("Flutter (Dart)"); $tst.Add("flutter_test") }
    if ($mans.Contains("pyproject.toml") -or $mans.Contains("requirements.txt")) { $be.Add("Python (FastAPI/Django)"); $tst.Add("Pytest") }
    if ($mans.Contains("go.mod")) { $be.Add("Go"); $tst.Add("go test") }
    if ($mans.Contains("plugin.json") -or (Test-Path -LiteralPath (Join-Path $Workspace "scripts/Sen.psm1"))) {
        $be.Add("PowerShell 5.1/7+ & POSIX sh"); $db.Add("Atomic JSON/JSONL State Engine"); $tst.Add("Sen AST/Unit Test Runner")
    }
    if ($mans.Contains("office/index.html")) { $fe.Add("HTML5/SVG 3D Isometric UI") }
    if (Test-Path -LiteralPath (Join-Path $Workspace ".github/workflows")) { $inf.Add("GitHub Actions CI/CD") }
    if ($mans.Contains("Dockerfile")) { $inf.Add("Docker Container") }
    $green = ($mans.Count -eq 0)
    $rec = @(
        [pscustomobject][ordered]@{ Option = "Web/Mobile Modern Stack"; Stack = "Next.js/Vite + FastAPI/Node.js + PostgreSQL"; ResourceCost = "Low-Medium (~150MB RAM dev, fast HMR)" },
        [pscustomobject][ordered]@{ Option = "Lightweight Local/CLI Stack"; Stack = "Static HTML5/JS + PowerShell/Python + SQLite/JSON"; ResourceCost = "Minimal (<50MB RAM, zero external DB)" }
    )
    $layers = [pscustomobject][ordered]@{
        Frontend       = $(if ($fe.Count -gt 0) { @($fe.ToArray()) } else { @("TBD (Recommend React/Vite or Flutter)") })
        Backend        = $(if ($be.Count -gt 0) { @($be.ToArray()) } else { @("TBD (Recommend FastAPI or Node.js)") })
        Database       = $(if ($db.Count -gt 0) { @($db.ToArray()) } else { @("TBD (Recommend PostgreSQL or SQLite)") })
        Infrastructure = $(if ($inf.Count -gt 0) { @($inf.ToArray()) } else { @("Localhost + GitHub Actions CI") })
        Testing        = $(if ($tst.Count -gt 0) { @($tst.ToArray()) } else { @("Unit + Integration + Smoke E2E") })
    }
    return [pscustomobject][ordered]@{
        Workspace = $Workspace; IsGreenfield = $green; DetectedManifests = @($mans.ToArray())
        Layers = $layers; RecommendedOptions = $rec
        Summary = $(if ($green) { "Greenfield project: select a 5-layer Tech Stack before coding." } else { "Detected stack: FE=($($layers.Frontend -join ', ')), BE=($($layers.Backend -join ', ')), Test=($($layers.Testing -join ', '))." })
    }
}

function Get-SenGitWorkingTreeProbe {
    param([string]$Workspace)
    $dirty = [Collections.Generic.List[string]]::new(); $synced = $true
    if (-not (Test-Path -LiteralPath (Join-Path $Workspace ".git"))) { return [pscustomobject]@{ DirtyFiles = @(); PushSynced = $true } }
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try {
        foreach ($ln in @(git -C $Workspace status --porcelain 2>$null)) {
            if ($ln -match '^\s*[MADRCU\?]{1,2}\s+(.+)$') { $dirty.Add($matches[1].Trim('"').Trim()) }
        }
        $hSha = ([string](git -C $Workspace rev-parse HEAD 2>$null)).Trim()
        $uSha = ([string](git -C $Workspace rev-parse '@{u}' 2>$null)).Trim()
        if ($hSha -and $uSha -and ($uSha -notmatch 'fatal') -and ($hSha -ne $uSha)) { $synced = $false }
    }
    catch { <# Ignore git probe error #> } finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ DirtyFiles = @($dirty.ToArray()); PushSynced = $synced }
}

function Test-SenTargetCollision {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Alias("WorkspacePath", "Path")][string]$Workspace, [string[]]$TargetPaths = @(), [string]$SessionId = "", [int]$QuietWindowSeconds = 90)
    $tasks = if (Get-Command Get-SenTasks -EA SilentlyContinue) { @(Get-SenTasks -Workspace $Workspace) } else { @() }
    $confTasks = [Collections.Generic.List[string]]::new(); $confFiles = [Collections.Generic.List[string]]::new()
    foreach ($t in $tasks) {
        $isActive = ($null -ne $t) -and ([string]$t.status -in @("in_progress", "reviewing")) -and (-not ($t.PSObject.Properties['isTelemetryOnly'] -and [bool]$t.isTelemetryOnly))
        $otherSess = (-not $SessionId) -or (-not $t.PSObject.Properties['sessionId']) -or ([string]$t.sessionId -ne $SessionId)
        if ($isActive -and $otherSess -and ($TargetPaths.Count -eq 0 -or (Test-SenPathOverlap -PathsA $TargetPaths -PathsB @($t.allowedPaths)))) {
            $confTasks.Add([string]$t.id)
            foreach ($ap in @($t.allowedPaths | Where-Object { $_ })) { if (-not $confFiles.Contains([string]$ap)) { $confFiles.Add([string]$ap) } }
        }
    }
    $gitProbe = Get-SenGitWorkingTreeProbe -Workspace $Workspace
    $treeClean = ($gitProbe.DirtyFiles.Count -eq 0); $pushSynced = [bool]$gitProbe.PushSynced
    foreach ($df in $gitProbe.DirtyFiles) {
        if (($TargetPaths.Count -eq 0 -or (Test-SenPathOverlap -PathsA $TargetPaths -PathsB @($df))) -and (-not $confFiles.Contains($df))) { $confFiles.Add($df) }
    }
    $latestModUtc = [DateTime]::MinValue
    foreach ($f in @(Get-ChildItem -LiteralPath $Workspace -File -EA SilentlyContinue)) { if ($f.LastWriteTimeUtc -gt $latestModUtc) { $latestModUtc = $f.LastWriteTimeUtc } }
    $quietAge = if ($latestModUtc -gt [DateTime]::MinValue) { [int][Math]::Max(0, ([DateTime]::UtcNow - $latestModUtc).TotalSeconds) } else { 9999 }
    $quietOk = ($QuietWindowSeconds -le 0) -or ($quietAge -ge $QuietWindowSeconds) -or ($treeClean -and $confTasks.Count -eq 0)
    $hasCol = ($confTasks.Count -gt 0) -or ($confFiles.Count -gt 0 -and (-not $treeClean -or -not $quietOk)) -or (-not $pushSynced -and $quietAge -lt 180)
    $prevDone = ($treeClean -and $pushSynced -and $quietOk -and $confTasks.Count -eq 0)
    return [pscustomobject][ordered]@{
        Workspace = $Workspace; HasCollision = [bool]$hasCol; PreviousSessionComplete = [bool]$prevDone
        Signals = [pscustomobject][ordered]@{ WorkingTreeClean = $treeClean; PushSynced = $pushSynced; QuietWindowPassed = $quietOk; ActiveTaskLockFree = ($confTasks.Count -eq 0) }
        ConflictingTaskIds = @($confTasks.ToArray()); ConflictingFiles = @($confFiles.ToArray()); QuietAgeSeconds = $quietAge
        Recommendation = $(if ($hasCol) { "Collision detected: enqueue task via Register-SenTaskQueue and wait for 4-Signal completion." } else { "Target files clear for execution." })
    }
}

function Register-SenTaskQueue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Alias("WorkspacePath", "Path")][string]$Workspace, [ValidateSet("enqueue", "list", "pop", "complete", "clear")][string]$Action = "list", [string]$QueueId = "", [string]$Title = "", [string[]]$TargetPaths = @(), [string]$SessionId = "", [int]$Tier = 2)
    $qPath = Join-Path $Workspace ".agents/office/task-queue.state"
    return (Invoke-SenWithFileMutex -FilePath $qPath -Action {
            $raw = Read-SenSafeJson -Path $qPath
            $list = [Collections.Generic.List[object]]::new()
            if ($null -ne $raw) { foreach ($it in @($raw | Where-Object { $_ -and $_.queueId })) { $list.Add($it) } }
            $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            $col = Test-SenTargetCollision -Workspace $Workspace -TargetPaths $TargetPaths -SessionId $SessionId
            if ($Action -eq "clear") { $list.Clear(); Write-SenAtomicJson -Path $qPath -InputObject @() -Depth 5; return [pscustomobject]@{ Action = "clear"; Count = 0; Items = @() } }
            if ($Action -eq "enqueue") {
                $qid = if ($QueueId) { $QueueId } else { "Q-" + ([DateTime]::UtcNow.ToString("HHmmss")) + "-" + ([Guid]::NewGuid().ToString("N").Substring(0, 4)) }
                $activeQueue = @($list | Where-Object { [string]$_.status -in @("queued", "running", "ready_to_run") })
                $st = if ($col.HasCollision -or $activeQueue.Count -gt 0) { "queued" } else { "ready_to_run" }
                $list.Add([pscustomobject][ordered]@{ queueId = $qid; title = $(if ($Title) { $Title } else { $qid }); tier = $Tier; sessionId = $SessionId; targetPaths = @($TargetPaths); status = $st; position = ($activeQueue.Count + 1); conflictingFiles = $col.ConflictingFiles; createdAt = $now; updatedAt = $now })
            }
            elseif ($Action -eq "complete" -and $QueueId) {
                foreach ($it in @($list | Where-Object { [string]$_.queueId -eq $QueueId })) { $it.status = "done"; $it.updatedAt = $now }
            }
            $runningCnt = @($list | Where-Object { [string]$_.status -eq "running" }).Count
            $firstWait = if ($runningCnt -eq 0 -and (-not $col.HasCollision)) { $list | Where-Object { [string]$_.status -eq "queued" } | Select-Object -First 1 } else { $null }
            if ($null -ne $firstWait) { $firstWait.status = "ready_to_run"; $firstWait.updatedAt = $now }
            $cand = if ($Action -eq "pop") { $list | Where-Object { [string]$_.status -eq "ready_to_run" -or ([string]$_.status -eq "queued" -and (-not $col.HasCollision)) } | Select-Object -First 1 } else { $null }
            if ($null -ne $cand) { $cand.status = "running"; $cand.updatedAt = $now }
            Write-SenAtomicJson -Path $qPath -InputObject @($list.ToArray()) -Depth 6
            $pending = @($list | Where-Object { [string]$_.status -in @("queued", "ready_to_run", "running") })
            return [pscustomobject][ordered]@{ Action = $Action; PendingCount = $pending.Count; Collision = $col; PoppedItem = $cand; Items = @($list.ToArray()) }
        })
}

Export-ModuleMember -Function Get-SenSelfPayloadNames, Get-SenDriveCandidates, New-SenWorkspace, New-SenFileFromTemplate, Get-SenToolCatalog, Get-SenToolStatus, Get-SenInstallPlan, Install-SenCreativePack, New-SenReleaseNote, Test-SenReleaseNoteGate, Get-SenProjectTechStack, Test-SenTargetCollision, Register-SenTaskQueue
