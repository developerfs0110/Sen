# scripts/Sen.psm1
# Pure ASCII PowerShell module for Sen workspace, drive, tool catalog, and package helpers.
# Runtime, Office, Risk, Task DAG, Backlog, Restore Point, and Memory functions live in Sen.Runtime.psm1.

$senRuntimeModulePath = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Runtime.psm1"
if (Test-Path -LiteralPath $senRuntimeModulePath) {
    Import-Module -Name $senRuntimeModulePath -Global -Force
}

function Get-SenSelfPayloadNames {
    return @("plugin.json", "hooks.json", "rules", "skills", "templates", "scripts", "office", "AGENTS.md", "INSTALL.md", "LICENSE", "CHANGELOG.md")
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
                        $r = $d.RootDirectory.FullName
                        $freeBytes = $d.AvailableFreeSpace
                        $freeGB = [double]($freeBytes / 1GB)
                        $writable = Test-SenDriveWritable -Root $r
                        $items.Add([pscustomobject]@{
                            Root = $r
                            FreeGB = $freeGB
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
                Root = $root
                FreeGB = [double][Math]::Round($freeGB, 2)
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
        $mgrCmd  = if ($mgr -is [string]) { $mgr } elseif ($mgr.PSObject.Properties['name']) { [string]$mgr.command } else { $null }
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

    return ,@($planItems.ToArray())
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

Export-ModuleMember -Function Get-SenSelfPayloadNames, Get-SenDriveCandidates, New-SenWorkspace, New-SenFileFromTemplate, Get-SenToolCatalog, Get-SenToolStatus, Get-SenInstallPlan, Install-SenCreativePack
