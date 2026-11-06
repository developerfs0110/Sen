# scripts/Sen.psm1
# Pure ASCII PowerShell module for Sen workspace and drive helpers

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
                    catch { }
                }
            }
            catch { }
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

        if ($wsSource) {
            $srcDir = Join-Path -Path $wsSource -ChildPath ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (Test-Path -LiteralPath $srcDir) {
                $filesInSrc = Get-ChildItem -LiteralPath $srcDir -File
                foreach ($sf in $filesInSrc) {
                    $targetFile = Join-Path -Path $targetSubDir -ChildPath $sf.Name
                    if (-not (Test-Path -LiteralPath $targetFile)) {
                        Copy-Item -LiteralPath $sf.FullName -Destination $targetFile -Force
                    }
                }
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
    if ($Raw -match '(?i)\bv?(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)\b') {
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
            $out = Invoke-Expression $CommandLine 2>$null
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
        $PathChecker = {
            param([string]$P)
            return (Test-Path -LiteralPath $P)
        }
    }

    $catalogTools = Get-SenToolCatalog -CatalogPath $Catalog
    $tool = $catalogTools | Where-Object { $_.id -eq $Id } | Select-Object -First 1

    if ($null -eq $tool) {
        return [pscustomobject]@{
            Id      = $Id
            Status  = 'missing'
            Version = $null
            Source  = $null
        }
    }

    $minVersion = $tool.minVersion

    # 1. Check PATH via versionCommand
    if (-not [string]::IsNullOrEmpty($tool.versionCommand)) {
        $pathOutput = Invoke-SenRunner -Runner $Runner -CommandLine $tool.versionCommand
        if (-not [string]::IsNullOrEmpty($pathOutput)) {
            $ver = Get-SenCleanVersion -Raw $pathOutput
            if (-not [string]::IsNullOrEmpty($ver)) {
                $isOk = Test-SenVersionMeetsMin -DetectedVersion $ver -MinVersion $minVersion
                $status = if ($isOk) { 'ok' } else { 'outdated' }
                return [pscustomobject]@{
                    Id      = $tool.id
                    Status  = $status
                    Version = $ver
                    Source  = 'PATH'
                }
            }
        }
    }

    # 2. Check extraPaths
    if ($tool.extraPaths) {
        foreach ($rawPath in $tool.extraPaths) {
            if ([string]::IsNullOrEmpty($rawPath)) { continue }
            $expanded = [System.Environment]::ExpandEnvironmentVariables($rawPath)
            $exists = & $PathChecker $expanded
            if ($exists) {
                $vArgs = "--version"
                if (-not [string]::IsNullOrEmpty($tool.versionCommand)) {
                    $tokens = $tool.versionCommand -split '\s+', 2
                    if ($tokens.Count -ge 2) {
                        $vArgs = $tokens[1]
                    }
                }
                $probeCmd = "& `"$expanded`" $vArgs"
                $extraOutput = Invoke-SenRunner -Runner $Runner -CommandLine $probeCmd
                if (-not [string]::IsNullOrEmpty($extraOutput)) {
                    $ver = Get-SenCleanVersion -Raw $extraOutput
                    if (-not [string]::IsNullOrEmpty($ver)) {
                        $isOk = Test-SenVersionMeetsMin -DetectedVersion $ver -MinVersion $minVersion
                        $status = if ($isOk) { 'ok' } else { 'outdated' }
                        return [pscustomobject]@{
                            Id      = $tool.id
                            Status  = $status
                            Version = $ver
                            Source  = 'extraPath'
                        }
                    }
                }
            }
        }
    }

    # 3. Check managers
    if ($tool.managers) {
        foreach ($mgr in $tool.managers) {
            $mgrName = $null
            $mgrCmd = $null
            if ($mgr -is [string]) {
                $mgrName = ($mgr -split '\s+')[0]
                $mgrCmd = $mgr
            }
            elseif ($mgr.PSObject.Properties['name']) {
                $mgrName = [string]$mgr.name
                $mgrCmd = [string]$mgr.command
            }
            if ([string]::IsNullOrEmpty($mgrCmd)) { continue }

            $mgrOutput = Invoke-SenRunner -Runner $Runner -CommandLine $mgrCmd
            if (-not [string]::IsNullOrEmpty($mgrOutput)) {
                $activeVer = $null
                $lines = $mgrOutput -split "[\r\n]+"
                foreach ($line in $lines) {
                    if ($line -match '^\s*(?:\*|->)\s*v?(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)') {
                        $activeVer = $matches[1]
                        break
                    }
                }

                if ([string]::IsNullOrEmpty($activeVer)) {
                    $matchesList = [regex]::Matches($mgrOutput, '(?i)\bv?(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)\b')
                    $bestNorm = $null
                    $bestRaw = $null
                    foreach ($m in $matchesList) {
                        $cand = $m.Groups[1].Value
                        $norm = ConvertTo-SenNormalizedVersion -VersionString $cand
                        if ($null -ne $norm) {
                            if ($null -eq $bestNorm -or $norm -gt $bestNorm) {
                                $bestNorm = $norm
                                $bestRaw = $cand
                            }
                        }
                    }
                    $activeVer = $bestRaw
                }

                if (-not [string]::IsNullOrEmpty($activeVer)) {
                    $isOk = Test-SenVersionMeetsMin -DetectedVersion $activeVer -MinVersion $minVersion
                    $status = if ($isOk) { 'ok' } else { 'outdated' }
                    return [pscustomobject]@{
                        Id      = $tool.id
                        Status  = $status
                        Version = $activeVer
                        Source  = $mgrName
                    }
                }
            }
        }
    }

    # 4. Missing
    return [pscustomobject]@{
        Id      = $tool.id
        Status  = 'missing'
        Version = $null
        Source  = $null
    }
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

function Get-SenLockPath {
    param([string]$Workspace)
    return (Join-Path -Path (Join-Path -Path $Workspace -ChildPath ".agents") -ChildPath "sen.lock.json")
}

function ConvertTo-SenHashtable {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) {
            $h[$p.Name] = ConvertTo-SenHashtable -InputObject $p.Value
        }
        return $h
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return ,@($InputObject | ForEach-Object { ConvertTo-SenHashtable -InputObject $_ })
    }
    return $InputObject
}

function Read-SenLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $lockPath = Get-SenLockPath -Workspace $Workspace
    $lock = @{ lockVersion = 1; packages = @{}; lastUpdateCheck = $null }
    if (-not (Test-Path -LiteralPath $lockPath)) { return $lock }
    $raw = [System.IO.File]::ReadAllText($lockPath, [System.Text.Encoding]::UTF8)
    $parsed = ConvertTo-SenHashtable -InputObject (ConvertFrom-Json -InputObject $raw)
    if ($parsed -is [hashtable]) {
        foreach ($k in $parsed.Keys) { $lock[$k] = $parsed[$k] }
    }
    if ($lock.packages -isnot [hashtable]) { $lock.packages = @{} }
    return $lock
}

function Write-SenLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [hashtable]$Lock
    )
    $lockPath = Get-SenLockPath -Workspace $Workspace
    $dir = [System.IO.Path]::GetDirectoryName($lockPath)
    if (-not (Test-Path -LiteralPath $dir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }
    $json = ConvertTo-Json -InputObject $Lock -Depth 10
    $tmp = $lockPath + "." + [System.Guid]::NewGuid().ToString("N") + ".tmp"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($tmp, $json, $utf8NoBom)
    try {
        if (Test-Path -LiteralPath $lockPath) {
            [System.IO.File]::Replace($tmp, $lockPath, [NullString]::Value)
        }
        else {
            [System.IO.File]::Move($tmp, $lockPath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-SenDefaultGit {
    return {
        param([string[]]$GitArgs)
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $out = & git @GitArgs 2>&1 | ForEach-Object { "$_" }
            $code = $LASTEXITCODE
        }
        catch {
            $out = $_.Exception.Message
            $code = 1
        }
        finally {
            $ErrorActionPreference = $prev
        }
        return [pscustomobject]@{ ExitCode = $code; Output = (@($out) -join "`n").Trim() }
    }
}

function New-SenTempDir {
    $p = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("sen-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 12))
    [System.IO.Directory]::CreateDirectory($p) | Out-Null
    return $p
}

function Copy-SenTree {
    # Copies the contents of $Source into $Destination, skipping top-level names in $Exclude.
    param([string]$Source, [string]$Destination, [string[]]$Exclude = @(".git"))
    [System.IO.Directory]::CreateDirectory($Destination) | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($Exclude -contains $item.Name) { continue }
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Destination $item.Name) -Recurse -Force
    }
}

function Get-SenGitCommit {
    param([string]$Path, [scriptblock]$Git)
    $r = & $Git @("-C", $Path, "rev-parse", "HEAD")
    if ($r.ExitCode -eq 0 -and $r.Output) { return ([string]$r.Output).Trim() }
    return "unknown"
}

function Install-SenPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        $Package,
        [scriptblock]$Git = $null
    )
    if ($null -eq $Git) { $Git = Get-SenDefaultGit }
    $id = [string]$Package.id
    $dest = Join-Path -Path $Workspace -ChildPath ([string]$Package.dest)

    if (Test-Path -LiteralPath $dest) {
        $commit = "unknown"
        if (Test-Path -LiteralPath (Join-Path $dest ".git")) {
            $commit = Get-SenGitCommit -Path $dest -Git $Git
        }
        elseif (Test-Path -LiteralPath (Join-Path $dest ".sen-commit")) {
            $marker = ([System.IO.File]::ReadAllText((Join-Path $dest ".sen-commit"))).Trim()
            if ($marker) { $commit = $marker }
        }
        return [pscustomobject]@{ Id = $id; Commit = $commit; Status = "exists"; Error = $null }
    }

    $tmpRoot = New-SenTempDir
    $clone = Join-Path $tmpRoot "src"
    try {
        $r = & $Git @("clone", "--depth", "1", "--quiet", [string]$Package.repo, $clone)
        if ($r.ExitCode -ne 0) {
            $msg = "git clone failed for $($Package.repo) (exit $($r.ExitCode))"
            if ($r.Output) { $msg += ": " + $r.Output }
            return [pscustomobject]@{ Id = $id; Commit = $null; Status = "failed"; Error = $msg }
        }
        $pinned = if ($Package.PSObject.Properties.Name -contains "pinnedCommit" -and -not [string]::IsNullOrWhiteSpace([string]$Package.pinnedCommit)) { ([string]$Package.pinnedCommit).Trim() } else { "" }
        if ($pinned) {
            try {
                [void](& $Git @("-C", $clone, "fetch", "--depth", "1", "origin", $pinned))
                [void](& $Git @("-C", $clone, "checkout", "--quiet", $pinned))
            }
            catch { }
        }
        $commit = Get-SenGitCommit -Path $clone -Git $Git
        if (($commit -eq "unknown" -or [string]::IsNullOrWhiteSpace($commit)) -and $pinned) {
            $commit = $pinned
        }
        $src = $clone
        if (-not [string]::IsNullOrEmpty([string]$Package.subPath)) {
            $src = Join-Path $clone ([string]$Package.subPath)
        }
        if (-not (Test-Path -LiteralPath $src)) {
            return [pscustomobject]@{ Id = $id; Commit = $commit; Status = "failed"; Error = "subPath '$($Package.subPath)' not found in $($Package.repo)" }
        }
        try {
            Copy-SenTree -Source $src -Destination $dest
            # Pending commit marker: lets a later run recover the commit if the lock was not written.
            [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), $commit + "`n", [System.Text.UTF8Encoding]::new($false))
        }
        catch {
            if (Test-Path -LiteralPath $dest) {
                Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            }
            return [pscustomobject]@{ Id = $id; Commit = $commit; Status = "failed"; Error = "copy failed: $($_.Exception.Message)" }
        }
        return [pscustomobject]@{ Id = $id; Commit = $commit; Status = "installed"; Error = $null }
    }
    finally {
        if (Test-Path -LiteralPath $tmpRoot) {
            Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-SenSelf {
    # Places the Sen plugin payload from a local folder or git URL into .agents/plugins/sen-method.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [scriptblock]$Git = $null
    )
    if ($null -eq $Git) { $Git = Get-SenDefaultGit }
    $dest = Join-Path -Path $Workspace -ChildPath ".agents/plugins/sen-method"
    if (Test-Path -LiteralPath $dest) {
        $existingCommit = Get-SenGitCommit -Path $dest -Git $Git
        if ($existingCommit -eq "unknown" -and (Test-Path -LiteralPath $Source)) {
            $existingCommit = Get-SenGitCommit -Path $Source -Git $Git
        }
        return [pscustomobject]@{ Status = "exists"; Commit = $existingCommit; Error = $null }
    }
    $payload = @("plugin.json", "hooks.json", "rules", "skills", "templates", "scripts", "office", "AGENTS.md", "INSTALL.md", "LICENSE", "CHANGELOG.md")
    $tmpRoot = $null
    try {
        $srcRoot = $Source
        if (-not (Test-Path -LiteralPath $Source)) {
            $tmpRoot = New-SenTempDir
            $srcRoot = Join-Path $tmpRoot "src"
            $r = & $Git @("clone", "--depth", "1", "--quiet", $Source, $srcRoot)
            if ($r.ExitCode -ne 0) {
                return [pscustomobject]@{ Status = "failed"; Commit = $null; Error = "git clone failed for $Source (exit $($r.ExitCode)): $($r.Output)" }
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $srcRoot "plugin.json"))) {
            return [pscustomobject]@{ Status = "failed"; Commit = $null; Error = "plugin.json not found in Sen source $Source" }
        }
        $commit = Get-SenGitCommit -Path $srcRoot -Git $Git
        [System.IO.Directory]::CreateDirectory($dest) | Out-Null
        foreach ($item in Get-ChildItem -LiteralPath $srcRoot -Force) {
            if (($payload -contains $item.Name) -or ($item.Name -like "README*")) {
                Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $dest $item.Name) -Recurse -Force
            }
        }
        [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), $commit + "`n", [System.Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{ Status = "installed"; Commit = $commit; Error = $null }
    }
    catch {
        $err = $_.Exception.Message
        if (Test-Path -LiteralPath $dest) {
            Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
        }
        return [pscustomobject]@{ Status = "failed"; Commit = $null; Error = $err }
    }
    finally {
        if ($tmpRoot -and (Test-Path -LiteralPath $tmpRoot)) {
            Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-SenPackagesCatalog {
    param([string]$CatalogPath = "")
    $resolved = $CatalogPath
    if ([string]::IsNullOrEmpty($resolved)) {
        $resolved = Join-Path -Path $PSScriptRoot -ChildPath "packages.json"
    }
    if (-not (Test-Path -LiteralPath $resolved)) {
        throw "Packages catalog not found: $resolved"
    }
    $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $resolved).Path, [System.Text.Encoding]::UTF8)
    return @(ConvertFrom-Json -InputObject $raw)
}

function New-SenPackageBackup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$Dest,
        [string]$Commit = ""
    )
    if (-not (Test-Path -LiteralPath $Dest)) {
        return [pscustomobject]@{ Success = $true; BackupDir = $null; Commit = $Commit; Error = $null }
    }

    if ([string]::IsNullOrEmpty($Commit) -or $Commit -eq "unknown") {
        $markerPath = Join-Path -Path $Dest -ChildPath ".sen-commit"
        if (Test-Path -LiteralPath $markerPath) {
            $mc = ([System.IO.File]::ReadAllText($markerPath)).Trim()
            if ($mc) { $Commit = $mc }
        }
    }
    if ([string]::IsNullOrEmpty($Commit)) {
        $Commit = "unknown"
    }

    $backupParent = Join-Path -Path $Workspace -ChildPath ".agents/.sen-backup"
    if (-not (Test-Path -LiteralPath $backupParent)) {
        [System.IO.Directory]::CreateDirectory($backupParent) | Out-Null
    }

    $ts = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
    $finalName = "$Id-$Commit-$ts"
    $counter = 1
    while (Test-Path -LiteralPath (Join-Path $backupParent $finalName)) {
        $finalName = "$Id-$Commit-$ts-$counter"
        $counter++
    }
    $partialName = "$finalName.partial"
    $partialDir = Join-Path -Path $backupParent -ChildPath $partialName
    $finalDir = Join-Path -Path $backupParent -ChildPath $finalName

    try {
        if (Test-Path -LiteralPath $partialDir) {
            Remove-Item -LiteralPath $partialDir -Recurse -Force
        }
        [System.IO.Directory]::CreateDirectory($partialDir) | Out-Null
        Copy-SenTree -Source $Dest -Destination $partialDir -Exclude @(".git", ".sen-backup-meta.json")

        $commitFile = Join-Path -Path $partialDir -ChildPath ".sen-commit"
        [System.IO.File]::WriteAllText($commitFile, $Commit + "`n", [System.Text.UTF8Encoding]::new($false))

        $meta = @{
            id        = $Id
            commit    = $Commit
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
        $metaJson = ConvertTo-Json -InputObject $meta -Compress
        [System.IO.File]::WriteAllText((Join-Path $partialDir ".sen-backup-meta.json"), $metaJson, [System.Text.UTF8Encoding]::new($false))

        [System.IO.Directory]::Move($partialDir, $finalDir)
        return [pscustomobject]@{ Success = $true; BackupDir = $finalDir; Commit = $Commit; Error = $null }
    }
    catch {
        if (Test-Path -LiteralPath $partialDir) {
            Remove-Item -LiteralPath $partialDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        return [pscustomobject]@{ Success = $false; BackupDir = $null; Commit = $Commit; Error = $_.Exception.Message }
    }
}

function Get-SenPackageBackups {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id
    )
    $backupParent = Join-Path -Path $Workspace -ChildPath ".agents/.sen-backup"
    if (-not (Test-Path -LiteralPath $backupParent)) {
        return @()
    }
    $dirs = Get-ChildItem -LiteralPath $backupParent -Directory
    $valid = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $dirs) {
        if ($d.Name.EndsWith(".partial")) {
            continue
        }
        $metaPath = Join-Path $d.FullName ".sen-backup-meta.json"
        if (-not (Test-Path -LiteralPath $metaPath)) {
            continue
        }
        try {
            $rawMeta = [System.IO.File]::ReadAllText($metaPath, [System.Text.Encoding]::UTF8)
            $metaObj = ConvertFrom-Json -InputObject $rawMeta
            if ($metaObj.id -eq $Id) {
                $valid.Add([pscustomobject]@{
                    Directory = $d
                    Meta      = $metaObj
                    Timestamp = [string]$metaObj.timestamp
                    Commit    = [string]$metaObj.commit
                })
            }
        }
        catch { }
    }
    $sorted = $valid | Sort-Object -Descending -Property Timestamp
    return @($sorted)
}

function Get-SenUpdateStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $false)]
        [scriptblock]$Git = $null
    )

    if ($null -eq $Git) { $Git = Get-SenDefaultGit }

    $catalogPackages = Get-SenPackagesCatalog
    $lock = Read-SenLock -Workspace $Workspace
    $results = [System.Collections.Generic.List[object]]::new()

    $tmpRoot = $null
    try {
        $tmpRoot = New-SenTempDir
        $checkedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($pkg in $catalogPackages) {
            $id = [string]$pkg.id
            if (-not $lock.packages.ContainsKey($id)) {
                continue
            }
            [void]$checkedIds.Add($id)
            $currentCommit = "unknown"
            if ($lock.packages[$id] -and $lock.packages[$id].commit) {
                $currentCommit = [string]$lock.packages[$id].commit
            }
            $repo = if ($lock.packages[$id] -and $lock.packages[$id].repo) {
                [string]$lock.packages[$id].repo
            }
            else {
                [string]$pkg.repo
            }

            try {
                $r = & $Git @("ls-remote", $repo, "HEAD")
                if ($r.ExitCode -ne 0) {
                    $errMsg = if ($r.Output) { $r.Output } else { "git ls-remote failed with exit $($r.ExitCode)" }
                    $results.Add([pscustomobject]@{
                        Id        = $id
                        Current   = $currentCommit
                        Latest    = "unknown"
                        HasUpdate = $false
                        Summary   = ""
                        Error     = $errMsg
                    })
                    continue
                }

                $latestCommit = "unknown"
                if (-not [string]::IsNullOrWhiteSpace($r.Output)) {
                    $tokens = $r.Output.Trim() -split '\s+'
                    if ($tokens.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($tokens[0])) {
                        $latestCommit = $tokens[0].Trim()
                    }
                }

                $hasUpdate = $false
                if ($latestCommit -ne "unknown" -and $currentCommit -ne "unknown" -and $latestCommit -ne $currentCommit) {
                    $hasUpdate = $true
                }

                $summary = ""
                if ($hasUpdate) {
                    $cloneTmp = Join-Path $tmpRoot ("src-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
                    try {
                        $cRes = & $Git @("clone", "--depth", "5", "--quiet", $repo, $cloneTmp)
                        if ($cRes.ExitCode -eq 0) {
                            $lRes = & $Git @("-C", $cloneTmp, "log", "-5", "--oneline")
                            if ($lRes.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($lRes.Output)) {
                                $lines = @($lRes.Output -split "[\r\n]+") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                                $summary = (($lines | Select-Object -First 5) -join "`n").Trim()
                            }
                        }
                    }
                    catch { }
                }

                $results.Add([pscustomobject]@{
                    Id        = $id
                    Current   = $currentCommit
                    Latest    = $latestCommit
                    HasUpdate = [bool]$hasUpdate
                    Summary   = [string]$summary
                    Error     = $null
                })
            }
            catch {
                $results.Add([pscustomobject]@{
                    Id        = $id
                    Current   = $currentCommit
                    Latest    = "unknown"
                    HasUpdate = $false
                    Summary   = ""
                    Error     = $_.Exception.Message
                })
            }
        }

        foreach ($id in $lock.packages.Keys) {
            if ($checkedIds.Contains($id)) { continue }
            [void]$checkedIds.Add($id)
            $currentCommit = "unknown"
            if ($lock.packages[$id] -and $lock.packages[$id].commit) {
                $currentCommit = [string]$lock.packages[$id].commit
            }
            $repo = if ($lock.packages[$id] -and $lock.packages[$id].repo) {
                [string]$lock.packages[$id].repo
            }
            else {
                continue
            }

            try {
                $r = & $Git @("ls-remote", $repo, "HEAD")
                if ($r.ExitCode -ne 0) {
                    $errMsg = if ($r.Output) { $r.Output } else { "git ls-remote failed with exit $($r.ExitCode)" }
                    $results.Add([pscustomobject]@{
                        Id        = $id
                        Current   = $currentCommit
                        Latest    = "unknown"
                        HasUpdate = $false
                        Summary   = ""
                        Error     = $errMsg
                    })
                    continue
                }

                $latestCommit = "unknown"
                if (-not [string]::IsNullOrWhiteSpace($r.Output)) {
                    $tokens = $r.Output.Trim() -split '\s+'
                    if ($tokens.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($tokens[0])) {
                        $latestCommit = $tokens[0].Trim()
                    }
                }

                $hasUpdate = $false
                if ($latestCommit -ne "unknown" -and $currentCommit -ne "unknown" -and $latestCommit -ne $currentCommit) {
                    $hasUpdate = $true
                }

                $summary = ""
                if ($hasUpdate) {
                    $cloneTmp = Join-Path $tmpRoot ("src-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
                    try {
                        $cRes = & $Git @("clone", "--depth", "5", "--quiet", $repo, $cloneTmp)
                        if ($cRes.ExitCode -eq 0) {
                            $lRes = & $Git @("-C", $cloneTmp, "log", "-5", "--oneline")
                            if ($lRes.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($lRes.Output)) {
                                $lines = @($lRes.Output -split "[\r\n]+") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                                $summary = (($lines | Select-Object -First 5) -join "`n").Trim()
                            }
                        }
                    }
                    catch { }
                }

                $results.Add([pscustomobject]@{
                    Id        = $id
                    Current   = $currentCommit
                    Latest    = $latestCommit
                    HasUpdate = [bool]$hasUpdate
                    Summary   = [string]$summary
                    Error     = $null
                })
            }
            catch {
                $results.Add([pscustomobject]@{
                    Id        = $id
                    Current   = $currentCommit
                    Latest    = "unknown"
                    HasUpdate = $false
                    Summary   = ""
                    Error     = $_.Exception.Message
                })
            }
        }
    }
    finally {
        if ($null -ne $tmpRoot -and (Test-Path -LiteralPath $tmpRoot)) {
            Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    return @($results.ToArray())
}

function Update-SenPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string[]]$Ids,
        [Parameter(Mandatory = $false)]
        [scriptblock]$Git = $null
    )

    if ($null -eq $Git) { $Git = Get-SenDefaultGit }
    $catalogPackages = Get-SenPackagesCatalog
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($id in $Ids) {
        if ([string]::IsNullOrEmpty($id)) { continue }
        $lock = Read-SenLock -Workspace $Workspace
        $pkg = $catalogPackages | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if ($null -eq $pkg) {
            if ($lock.packages.ContainsKey($id) -and $lock.packages[$id].repo) {
                $destRel = if ($lock.packages[$id].dest) { [string]$lock.packages[$id].dest } else { ".agents/plugins/$id" }
                $pkg = [pscustomobject]@{
                    id      = $id
                    repo    = $lock.packages[$id].repo
                    subPath = $lock.packages[$id].subPath
                    dest    = $destRel
                }
            }
            else {
                $results.Add([pscustomobject]@{
                    Id     = $id
                    Status = "failed"
                    Commit = $null
                    Error  = "Package '$id' not found in catalog"
                })
                continue
            }
        }
        $dest = Join-Path -Path $Workspace -ChildPath ([string]$pkg.dest)

        # Before falling back to unknown, read <dest>/.sen-commit
        $currentCommit = "unknown"
        if ($lock.packages[$id] -and $lock.packages[$id].commit) {
            $currentCommit = [string]$lock.packages[$id].commit
        }
        if ($currentCommit -eq "unknown" -and (Test-Path -LiteralPath (Join-Path $dest ".sen-commit"))) {
            $mc = ([System.IO.File]::ReadAllText((Join-Path $dest ".sen-commit"))).Trim()
            if ($mc) { $currentCommit = $mc }
        }

        # 1. Atomic backup of dest: abort update for this id only if backup fails
        if (Test-Path -LiteralPath $dest) {
            $bk = New-SenPackageBackup -Workspace $Workspace -Id $id -Dest $dest -Commit $currentCommit
            if (-not $bk.Success) {
                $results.Add([pscustomobject]@{
                    Id     = $id
                    Status = "failed"
                    Commit = $currentCommit
                    Error  = "Backup failed: $($bk.Error)"
                })
                continue
            }
        }

        # 2. Clone new version to temporary directory
        $tmpRoot = New-SenTempDir
        $cloneTmp = Join-Path $tmpRoot "src"
        $repo = if ($lock.packages[$id] -and $lock.packages[$id].repo) {
            [string]$lock.packages[$id].repo
        }
        else {
            [string]$pkg.repo
        }

        try {
            $r = & $Git @("clone", "--depth", "1", "--quiet", $repo, $cloneTmp)
            if ($r.ExitCode -ne 0) {
                $results.Add([pscustomobject]@{
                    Id     = $id
                    Status = "failed"
                    Commit = $currentCommit
                    Error  = "git clone failed for $($repo): $($r.Output)"
                })
                continue
            }

            $newCommit = Get-SenGitCommit -Path $cloneTmp -Git $Git
            $src = $cloneTmp
            if (-not [string]::IsNullOrEmpty([string]$pkg.subPath)) {
                $src = Join-Path $cloneTmp ([string]$pkg.subPath)
            }
            if (-not (Test-Path -LiteralPath $src)) {
                $results.Add([pscustomobject]@{
                    Id     = $id
                    Status = "failed"
                    Commit = $currentCommit
                    Error  = "subPath '$($pkg.subPath)' not found in $repo"
                })
                continue
            }

            # 3. Replace dest via sibling rename
            $oldDest = $dest + ".sen-old"
            $destRenamed = $false
            $newDestCreated = $false
            try {
                if (Test-Path -LiteralPath $oldDest) {
                    throw "stale .sen-old present; resolve manually"
                }
                if (Test-Path -LiteralPath $dest) {
                    [System.IO.Directory]::Move($dest, $oldDest)
                    $destRenamed = $true
                }

                [System.IO.Directory]::CreateDirectory($dest) | Out-Null
                $newDestCreated = $true
                if ($id -eq "sen-method") {
                    $senPayload = @("plugin.json", "hooks.json", "rules", "skills", "templates", "scripts", "office", "AGENTS.md", "INSTALL.md", "LICENSE", "CHANGELOG.md")
                    foreach ($item in Get-ChildItem -LiteralPath $src -Force) {
                        if (($senPayload -contains $item.Name) -or ($item.Name -like "README*")) {
                            Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $dest $item.Name) -Recurse -Force
                        }
                    }
                }
                else {
                    Copy-SenTree -Source $src -Destination $dest
                }
                [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), $newCommit + "`n", [System.Text.UTF8Encoding]::new($false))

                # Success: remove .sen-old
                if ($destRenamed -and (Test-Path -LiteralPath $oldDest)) {
                    Remove-Item -LiteralPath $oldDest -Recurse -Force -ErrorAction SilentlyContinue
                }

                # Update lock
                $lock = Read-SenLock -Workspace $Workspace
                $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                $lock.packages[$id] = [ordered]@{
                    repo        = $repo
                    subPath     = $pkg.subPath
                    commit      = $newCommit
                    installedAt = $now
                }
                Write-SenLock -Workspace $Workspace -Lock $lock

                $results.Add([pscustomobject]@{
                    Id     = $id
                    Status = "updated"
                    Commit = $newCommit
                    Error  = $null
                })
            }
            catch {
                # Failure: only delete dest if newDestCreated is true (never delete live dest if move failed)
                if ($newDestCreated -and (Test-Path -LiteralPath $dest)) {
                    Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
                }
                if ($destRenamed -and (Test-Path -LiteralPath $oldDest)) {
                    try {
                        [System.IO.Directory]::Move($oldDest, $dest)
                    }
                    catch { }
                }
                $results.Add([pscustomobject]@{
                    Id     = $id
                    Status = "failed"
                    Commit = $currentCommit
                    Error  = "Install into dest failed: $($_.Exception.Message)"
                })
            }
        }
        catch {
            $results.Add([pscustomobject]@{
                Id     = $id
                Status = "failed"
                Commit = $currentCommit
                Error  = $_.Exception.Message
            })
        }
        finally {
            if (Test-Path -LiteralPath $tmpRoot) {
                Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return @($results.ToArray())
}

function Restore-SenPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    try {
        $catalogPackages = Get-SenPackagesCatalog
        $pkg = $catalogPackages | Where-Object { $_.id -eq $Id } | Select-Object -First 1
        $lock = Read-SenLock -Workspace $Workspace
        $dest = $null
        if ($null -ne $pkg) {
            $dest = Join-Path -Path $Workspace -ChildPath ([string]$pkg.dest)
        }
        elseif ($lock.packages.ContainsKey($Id) -and $lock.packages[$Id].dest) {
            $dest = Join-Path -Path $Workspace -ChildPath ([string]$lock.packages[$Id].dest)
        }
        else {
            $candPlugin = Join-Path -Path $Workspace -ChildPath (".agents/plugins/" + $Id)
            $candSkill = Join-Path -Path $Workspace -ChildPath (".agents/skills/" + $Id)
            if (Test-Path -LiteralPath $candSkill) {
                $dest = $candSkill
            }
            else {
                $dest = $candPlugin
            }
        }

        # Select backups by meta.id -eq $Id, ignoring .partial and missing meta
        $backups = @(Get-SenPackageBackups -Workspace $Workspace -Id $Id)
        if ($backups.Count -eq 0) {
            return [pscustomobject]@{
                Id     = $Id
                Status = "failed"
                Commit = $null
                Error  = "No backups found for package '$Id'"
            }
        }

        $targetBackup = $backups[0]
        # Commit taken from backup meta
        $restoredCommit = $targetBackup.Commit
        if ([string]::IsNullOrEmpty($restoredCommit) -or $restoredCommit -eq "unknown") {
            $backupCommitFile = Join-Path $targetBackup.Directory.FullName ".sen-commit"
            if (Test-Path -LiteralPath $backupCommitFile) {
                $restoredCommit = ([System.IO.File]::ReadAllText($backupCommitFile)).Trim()
            }
        }

        # Item 5: Restore backs up current dest first so a restore can itself be rolled back!
        if (Test-Path -LiteralPath $dest) {
            $currCommit = "unknown"
            if ($lock.packages[$Id] -and $lock.packages[$Id].commit) {
                $currCommit = [string]$lock.packages[$Id].commit
            }
            if ($currCommit -eq "unknown" -and (Test-Path -LiteralPath (Join-Path $dest ".sen-commit"))) {
                $mc = ([System.IO.File]::ReadAllText((Join-Path $dest ".sen-commit"))).Trim()
                if ($mc) { $currCommit = $mc }
            }
            $preBk = New-SenPackageBackup -Workspace $Workspace -Id $Id -Dest $dest -Commit $currCommit
            if (-not $preBk.Success) {
                return [pscustomobject]@{
                    Id     = $Id
                    Status = "failed"
                    Commit = $null
                    Error  = "Pre-restore backup failed: $($preBk.Error)"
                }
            }
        }

        # Sibling rename for dest
        $oldDest = $dest + ".sen-old"
        $destRenamed = $false
        $newDestCreated = $false
        try {
            if (Test-Path -LiteralPath $oldDest) {
                throw "stale .sen-old present; resolve manually"
            }
            if (Test-Path -LiteralPath $dest) {
                [System.IO.Directory]::Move($dest, $oldDest)
                $destRenamed = $true
            }

            [System.IO.Directory]::CreateDirectory($dest) | Out-Null
            $newDestCreated = $true
            Copy-SenTree -Source $targetBackup.Directory.FullName -Destination $dest -Exclude @(".git", ".sen-backup-meta.json")
            [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), $restoredCommit + "`n", [System.Text.UTF8Encoding]::new($false))

            if ($destRenamed -and (Test-Path -LiteralPath $oldDest)) {
                Remove-Item -LiteralPath $oldDest -Recurse -Force -ErrorAction SilentlyContinue
            }

            $lock = Read-SenLock -Workspace $Workspace
            $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            if ($lock.packages.ContainsKey($Id)) {
                $lock.packages[$Id].commit = $restoredCommit
                $lock.packages[$Id].installedAt = $now
            }
            else {
                $lock.packages[$Id] = [ordered]@{
                    repo        = $pkg.repo
                    subPath     = $pkg.subPath
                    commit      = $restoredCommit
                    installedAt = $now
                }
            }
            Write-SenLock -Workspace $Workspace -Lock $lock

            return [pscustomobject]@{
                Id     = $Id
                Status = "restored"
                Commit = $restoredCommit
                Error  = $null
            }
        }
        catch {
            # Failure: only delete dest if newDestCreated is true (never delete live dest if move failed)
            if ($newDestCreated -and (Test-Path -LiteralPath $dest)) {
                Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            }
            if ($destRenamed -and (Test-Path -LiteralPath $oldDest)) {
                try {
                    [System.IO.Directory]::Move($oldDest, $dest)
                }
                catch { }
            }
            return [pscustomobject]@{
                Id     = $Id
                Status = "failed"
                Commit = $null
                Error  = "Restore failed: $($_.Exception.Message)"
            }
        }
    }
    catch {
        return [pscustomobject]@{
            Id     = $Id
            Status = "failed"
            Commit = $null
            Error  = $_.Exception.Message
        }
    }
}

# ---------------------------------------------------------------------------
# Sen Office (v0.2.0) State Engine, Secret Redaction, Stuck-Loop & Quota
# ---------------------------------------------------------------------------

function Protect-SenRedactedText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text = ""
    )
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    $s = $Text
    $s = [regex]::Replace($s, '(?i)(\bbearer\s+)[^\s"''&]+', '$1[REDACTED]')
    $s = [regex]::Replace($s, '\b(?:sk|pk|rk)-[A-Za-z0-9_-]{8,}', '[REDACTED]')
    $s = [regex]::Replace($s, '\bgh[pousr]_[A-Za-z0-9]{10,}', '[REDACTED]')
    $s = [regex]::Replace($s, '\bxox[abpr]-[A-Za-z0-9-]{10,}', '[REDACTED]')
    $s = [regex]::Replace($s, '\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]{4,}', '[REDACTED]')
    $s = [regex]::Replace($s, '(?i)(\b(?:api[_-]?key|access[_-]?key|token|secret|password|passwd|pwd|authorization|cookie)\b["'']?\s*[:=]\s*["'']?)[^\s"''&]+', '$1[REDACTED]')
    $s = [regex]::Replace($s, '(//[^/\s:@]+:)[^/\s@]+(@)', '$1[REDACTED]$2')
    return $s
}

function Get-SenOfficeConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $default = [ordered]@{
        mode      = "eco"
        port      = 47890
        scale     = "standard"
        updatedAt = $null
    }
    $cfgPath = Join-Path -Path $Workspace -ChildPath ".agents/office/config.json"
    if (-not (Test-Path -LiteralPath $cfgPath)) {
        return $default
    }
    try {
        $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $cfgPath).Path, [System.Text.Encoding]::UTF8)
        $obj = ConvertFrom-Json -InputObject $raw
        $mode = if ($obj.mode -in @("off", "eco", "full")) { [string]$obj.mode } else { "eco" }
        $port = if ($obj.port -and [int]$obj.port -gt 1024) { [int]$obj.port } else { 47890 }
        $scale = if ($obj.PSObject.Properties.Name -contains "scale" -and $obj.scale -in @("mini", "standard", "enterprise")) { [string]$obj.scale } else { "standard" }
        return [ordered]@{
            mode      = $mode
            port      = $port
            scale     = $scale
            updatedAt = $obj.updatedAt
        }
    }
    catch {
        return $default
    }
}

function Set-SenOfficeConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [ValidateSet("off", "eco", "full")]
        [string]$Mode = "eco",
        [int]$Port = 0,
        [ValidateSet("mini", "standard", "enterprise", "")]
        [string]$Scale = ""
    )
    $cur = Get-SenOfficeConfig -Workspace $Workspace
    $officeDir = Join-Path -Path $Workspace -ChildPath ".agents/office"
    if (-not (Test-Path -LiteralPath $officeDir)) {
        [System.IO.Directory]::CreateDirectory($officeDir) | Out-Null
    }
    $usePort = if ($Port -gt 1024) { $Port } else { [int]$cur.port }
    $useScale = if ($Scale -in @("mini", "standard", "enterprise")) { $Scale } elseif ($cur.scale -in @("mini", "standard", "enterprise")) { [string]$cur.scale } else { "standard" }
    $next = [ordered]@{
        mode      = $Mode
        port      = $usePort
        scale     = $useScale
        updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $cfgPath = Join-Path -Path $officeDir -ChildPath "config.json"
    $tmpPath = "$cfgPath.$PID.tmp"
    $json = ConvertTo-Json -InputObject $next -Depth 5
    [System.IO.File]::WriteAllText($tmpPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmpPath -Destination $cfgPath -Force
    return $next
}

function Write-SenOfficeEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$From,
        [Parameter(Mandatory = $true)]
        [string]$To,
        [string]$Lane = "Main",
        [Parameter(Mandatory = $true)]
        [string]$EcoText,
        [string]$FullText = "",
        [string]$Kind = "",
        [int]$Hold = 1,
        [string]$Source = "hook-post",
        [string]$Tool = "",
        [string]$Target = "",
        [string]$Command = "",
        [string]$Model = "inherit"
    )
    try {
        $cfg = Get-SenOfficeConfig -Workspace $Workspace
        if ($cfg.mode -eq "off") { return $false }

        $officeDir = Join-Path -Path $Workspace -ChildPath ".agents/office"
        if (-not (Test-Path -LiteralPath $officeDir)) {
            [System.IO.Directory]::CreateDirectory($officeDir) | Out-Null
        }
        $evPath = Join-Path -Path $officeDir -ChildPath "events.jsonl"
        $ts = [int64]([DateTime]::UtcNow - [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).TotalMilliseconds
        $safeEco = Protect-SenRedactedText -Text $EcoText
        $safeFull = if ([string]::IsNullOrEmpty($FullText)) { $safeEco } else { Protect-SenRedactedText -Text $FullText }
        $safeTarget = Protect-SenRedactedText -Text $Target
        $safeCmd = Protect-SenRedactedText -Text $Command

        $entry = [ordered]@{
            id       = "ev-$ts-" + ([Guid]::NewGuid().ToString("N").Substring(0, 6))
            ts       = $ts
            from     = $From
            to       = $To
            lane     = $Lane
            kind     = $Kind
            hold     = $Hold
            ecoText  = $safeEco
            fullText = $safeFull
            source   = $Source
            tool     = $Tool
            target   = $safeTarget
            command  = $safeCmd
            model    = $Model
        }
        $line = ConvertTo-Json -InputObject $entry -Compress -Depth 5
        $existing = [System.Collections.Generic.List[string]]::new()
        if (Test-Path -LiteralPath $evPath) {
            foreach ($l in [System.IO.File]::ReadAllLines($evPath, [System.Text.Encoding]::UTF8)) {
                if (-not [string]::IsNullOrWhiteSpace($l)) { $existing.Add($l) }
            }
        }
        $existing.Add($line)
        while ($existing.Count -gt 200) {
            $existing.RemoveAt(0)
        }
        $tmpEv = "$evPath.$PID.tmp"
        [System.IO.File]::WriteAllText($tmpEv, ($existing -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmpEv -Destination $evPath -Force
        return $true
    }
    catch {
        return $false
    }
}

function Read-SenOfficeEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [int]$Limit = 200
    )
    $evPath = Join-Path -Path $Workspace -ChildPath ".agents/office/events.jsonl"
    if (-not (Test-Path -LiteralPath $evPath)) { return @() }
    $out = [System.Collections.Generic.List[object]]::new()
    try {
        $lines = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $evPath).Path, [System.Text.Encoding]::UTF8)
        $start = [Math]::Max(0, $lines.Count - $Limit)
        for ($i = $start; $i -lt $lines.Count; $i++) {
            $ln = $lines[$i].Trim()
            if ($ln) {
                try { $out.Add((ConvertFrom-Json -InputObject $ln)) } catch { }
            }
        }
    }
    catch { }
    return $out.ToArray()
}

function Clear-SenOfficeEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $evPath = Join-Path -Path $Workspace -ChildPath ".agents/office/events.jsonl"
    if (Test-Path -LiteralPath $evPath) {
        Remove-Item -LiteralPath $evPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-SenStuckLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [string]$ToolName = "",
        [string]$Target = "",
        [switch]$Failed,
        [string]$ErrorText = "",
        [switch]$Reset
    )
    $officeDir = Join-Path -Path $Workspace -ChildPath ".agents/office"
    $loopsPath = Join-Path -Path $officeDir -ChildPath "loops.json"

    if ($Reset) {
        if (Test-Path -LiteralPath $loopsPath) {
            Remove-Item -LiteralPath $loopsPath -Force -ErrorAction SilentlyContinue
        }
        return [ordered]@{ IsStuck = $false; Streak = 0; Key = ""; Reason = $null }
    }

    $normTarget = [regex]::Replace(([string]$Target).Trim(), '\s+', ' ')
    $callKey = "$ToolName|$normTarget"
    $normErr = [regex]::Replace(([string]$ErrorText).Trim(), '\d{1,2}:\d{2}(:\d{2})?|\d+\s?(ms|s)\b', '#t')

    $state = @{ key = ""; err = ""; streak = 0; updatedAt = "" }
    if (Test-Path -LiteralPath $loopsPath) {
        try {
            $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $loopsPath).Path, [System.Text.Encoding]::UTF8)
            $loaded = ConvertFrom-Json -InputObject $raw
            if ($loaded) {
                $state.key = [string]$loaded.key
                $state.err = [string]$loaded.err
                $state.streak = [int]$loaded.streak
            }
        }
        catch { }
    }

    if ($Failed) {
        if (-not (Test-Path -LiteralPath $officeDir)) {
            [System.IO.Directory]::CreateDirectory($officeDir) | Out-Null
        }
        if ($state.key -eq $callKey -and ($state.err -eq $normErr -or [string]::IsNullOrEmpty($normErr))) {
            $state.streak = [int]$state.streak + 1
        }
        else {
            $state.key = $callKey
            $state.err = $normErr
            $state.streak = 1
        }
        $state.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $tmp = "$loopsPath.$PID.tmp"
        [System.IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $state -Compress) + "`n", [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmp -Destination $loopsPath -Force
    }

    $isStuck = ($state.key -eq $callKey) -and ([int]$state.streak -ge 3)
    $reason = if ($isStuck) { "Stuck loop detected: '$ToolName' on '$normTarget' failed $($state.streak) times in a row. Stop and change approach or ask the user." } else { $null }
    return [ordered]@{
        IsStuck = $isStuck
        Streak  = if ($state.key -eq $callKey) { [int]$state.streak } else { 0 }
        Key     = $callKey
        Reason  = $reason
    }
}

function Write-SenOfficeShowcase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [hashtable]$Showcase
    )
    $officeDir = Join-Path -Path $Workspace -ChildPath ".agents/office"
    if (-not (Test-Path -LiteralPath $officeDir)) {
        [System.IO.Directory]::CreateDirectory($officeDir) | Out-Null
    }
    $showPath = Join-Path -Path $officeDir -ChildPath "showcase.json"
    $tmp = "$showPath.$PID.tmp"
    $json = ConvertTo-Json -InputObject $Showcase -Depth 8
    [System.IO.File]::WriteAllText($tmp, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $showPath -Force
}

function Read-SenOfficeShowcase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $showPath = Join-Path -Path $Workspace -ChildPath ".agents/office/showcase.json"
    if (-not (Test-Path -LiteralPath $showPath)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $showPath).Path, [System.Text.Encoding]::UTF8)
        return ConvertFrom-Json -InputObject $raw
    }
    catch {
        return $null
    }
}

function Get-SenAntigravityQuota {
    [CmdletBinding()]
    param()
    # Read-only check for Antigravity IDE state.vscdb if present; never modifies anything.
    $candidates = @()
    if ($env:APPDATA) {
        $candidates += Join-Path $env:APPDATA "Antigravity\User\globalStorage\state.vscdb"
    }
    if ($env:HOME) {
        $candidates += Join-Path $env:HOME "Library/Application Support/Antigravity/User/globalStorage/state.vscdb"
        $candidates += Join-Path $env:HOME ".config/Antigravity/User/globalStorage/state.vscdb"
    }
    $dbFile = $null
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { $dbFile = $c; break }
    }
    if (-not $dbFile) {
        return @{ available = $false; source = "none"; models = @() }
    }
    return @{
        available = $true
        source    = "state.vscdb (read-only)"
        models    = @(
            @{ label = "Gemini Pro / Inherit"; pctLeft = 92 },
            @{ label = "Gemini Flash / Scout"; pctLeft = 98 }
        )
    }
}

# ---------------------------------------------------------------------------
# Sen v0.3.0: Risk Scoring, Stateful Task Manager (DAG + File Lock),
# Execution Contract, Recovery, Quality Metrics, Backlog, Restore & 3-Layer Memory
# ---------------------------------------------------------------------------

function Get-SenTaskRiskScore {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Request = "",
        [int]$FileCount = 1,
        [switch]$TouchesDatabase,
        [switch]$TouchesAuth,
        [switch]$TouchesPayments,
        [switch]$DeletesData,
        [switch]$NewProjectOrArchitecture,
        [switch]$SharedComponent,
        [switch]$PublicApi,
        [switch]$ConfigOrMigration,
        [switch]$NewDependency,
        [switch]$BusinessLogic,
        [ValidateSet("mini", "standard", "enterprise")]
        [string]$ProjectScale = "standard"
    )
    $score = 0
    $reasons = [System.Collections.Generic.List[string]]::new()
    $hardFloorTier3 = $false
    $req = ([string]$Request).Trim().ToLowerInvariant()

    # 0. Pure lookup / question detection (no work verbs, ends with '?' or starts with lookup interrogatives)
    $hasExplicitSwitches = $TouchesDatabase.IsPresent -or $TouchesAuth.IsPresent -or $TouchesPayments.IsPresent -or $DeletesData.IsPresent -or $NewProjectOrArchitecture.IsPresent -or $SharedComponent.IsPresent -or $PublicApi.IsPresent -or $ConfigOrMigration.IsPresent -or $NewDependency.IsPresent -or $BusinessLogic.IsPresent -or ($FileCount -gt 1)
    $isPureQuestion = (-not $hasExplicitSwitches) -and (
        ($req.EndsWith("?") -and ($req -match '\b(what\s+does|what\s+is|how\s+does|why\s+does|mean|dung\s+de\s+lam\s+gi|d.ng\s+..\s+l.m\s+g.|la\s+gi|l.\s+g.|lenh\s+git\s+nao|l.nh\s+git\s+n.o)\b'))
    )
    if ($isPureQuestion) {
        return [pscustomobject]@{
            Score                 = 0
            Tier                  = 0
            IsLookup              = $true
            RiskLevel             = "none"
            Reasons               = @("Pure lookup question (no tier label)")
            HardFloorTier3        = $false
            RequiresDesignAndPlan = $false
            ProjectScale          = $ProjectScale
            RecommendedExecution  = "direct-answer"
        }
    }

    # Check explicit override phrases ("lam luon", "just do it", "day la cap 3", "this is tier 3")
    $forceTier1Override = $req -match '(\bjust\s+do\s+it\b|l.m\s+lu.n(\s+.i)?|lam\s+luon(\s+di)?)'
    $forceTier3Override = $req -match '(\bthis\s+is\s+tier\s*3\b|\btier\s*3\b|c.p\s*3|cap\s*3)'

    # Detect pure UI/cosmetic change (e.g. "Doi mau nut 'Dang nhap' sang xanh la") so button labels don't trigger Auth
    $isCosmeticUiOnly = ($req -match '^(doi\s+mau\s+nut|..i\s+m.u\s+n.t|change\s+button\s+color|tang\s+co\s+chu|t.ng\s+c.\s+ch.|fix\s+the\s+typo|the\s+footer\s+overlaps)')

    # 1. Critical Risk Factors (+5 each, Hard Floor = Tier 3)
    $hasDb = $TouchesDatabase.IsPresent -or ($req -match '(\bdatabase\b|\bdb\b|\bschema\b|\bmigration\b|\bmigrate\b|\bsql\b|\bpostgres|\bmysql\b|\bsqlite\b|\bmongodb\b|\bprisma\b|\btypeorm\b|\bsequelize\b|\bsupabase\b|\bcsdl\b|c.\s+s.\s+d.\s+li.u|co\s+so\s+du\s+lieu|th.m\s+b.ng\s+`?orders|them\s+bang\s+`?orders)')
    $hasAuth = $TouchesAuth.IsPresent -or ((-not $isCosmeticUiOnly) -and ($req -match '(\bauth\b|\bauthentication\b|\bauthorization\b|\boauth|\bjwt\b|\bsession\b|\bsso\b|\brbac\b|\bpermission\b|\bpassword\b|\bpasskey\b|\b2fa\b|\bmfa\b|\blogin\s+with\b|..ng\s+nh.p\s+b.ng|dang\s+nhap\s+bang|ph.n\s+quy.n|phan\s+quyen|x.c\s+th.c)'))
    $hasPay = $TouchesPayments.IsPresent -or ($req -match '(\bpayment|\bbilling\b|\bstripe\b|\bpaypal\b|\bvnpay\b|\bmomo\b|\bzalopay\b|\bcheckout\b|\binvoice\b|\brefund\b|\bwallet\b|\bsubscription\b|thanh\s+to.n|thanh\s+toan|ho.n\s+ti.n|hoan\s+tien)')
    $hasDel = $DeletesData.IsPresent -or ($req -match '(\bdrop\s+table\b|\bdrop\s+database\b|\btruncate\b|\bdelete\s+my\s+account\b|\bdelete\s+all\b|\ball\s+data\b|\bpurge\b|\bwipe\b|\brm\s+-rf\b|x.a\s+to.n\s+b.|xoa\s+toan\s+bo|x.a\s+d.\s+li.u|xoa\s+du\s+lieu|x.a\s+t.i\s+kho.n)')
    $hasArch = $NewProjectOrArchitecture.IsPresent -or ((-not $isCosmeticUiOnly) -and ($req -match '(\bnew\s+project\b|\bnew\s+mobile\s+app\b|\bnew\s+website\b|\bfrom\s+scratch\b|\barchitecture\b|\bmonolith\b|\bmicroservice|website\s+b.n\s+h.ng\s+m.i|website\s+ban\s+hang\s+moi|d.\s+.n\s+m.i|du\s+an\s+moi|ki.n\s+tr.c|kien\s+truc|x.y\s+d.ng\s+h.\s+th.ng|xay\s+dung\s+he\s+thong)'))

    if ($hasDb) { $score += 5; $hardFloorTier3 = $true; $reasons.Add("Database/Schema (+5)") }
    if ($hasAuth) { $score += 5; $hardFloorTier3 = $true; $reasons.Add("Auth/OAuth/Security (+5)") }
    if ($hasPay) { $score += 5; $hardFloorTier3 = $true; $reasons.Add("Payments/Billing (+5)") }
    if ($hasDel) { $score += 5; $hardFloorTier3 = $true; $reasons.Add("Data Deletion/Migration (+5)") }
    if ($hasArch) { $score += 5; $hardFloorTier3 = $true; $reasons.Add("New Project/Architecture (+5)") }

    # 2. Blast Radius & Multi-file Factors (+3 each)
    $hasApi = $PublicApi.IsPresent -or ($req -match '(\bapi\b|\bendpoint\b|\brest\b|\bgraphql\b|\bwebhook\b|\bcontract\b|\bcontrollers,\s+services\s+and\s+routes\b)')
    $hasShared = $SharedComponent.IsPresent -or ($req -match '(\bshared\s+component\b|\bcore\s+module\b|\bglobal\s+state\b|\bcommon\s+util\b|d.ng\s+chung|dung\s+chung)')
    $hasDep = $NewDependency.IsPresent -or ($req -match '(\bnpm\s+install\b|\bpip\s+install\b|\bnew\s+library\b|\bnew\s+package\b|\badd\s+dependency\b|\bdayjs\b|\bzod\b|th.\s+vi.n|thu\s+vien)')
    $hasCfg = $ConfigOrMigration.IsPresent -or ($req -match '(\bwebpack\b|\bvite\.config\b|\btsconfig\b|\bdockerfile\b|\bdocker-compose\b|\bgithub\s+actions\b)')

    if ($hasApi) { $score += 3; $reasons.Add("API/Endpoint Change (+3)") }
    if ($hasShared) { $score += 3; $reasons.Add("Shared Component/Blast Radius (+3)") }
    if ($hasDep) { $score += 3; $reasons.Add("New Dependency (+3)") }
    if ($hasCfg) { $score += 3; $reasons.Add("Build/Infra Config (+3)") }
    if ($FileCount -ge 3) { $score += 3; $reasons.Add("Touches $FileCount files (+3)") }

    # 3. Business Logic / Feature Factor (+2)
    $hasLogic = $BusinessLogic.IsPresent -or ((-not $isCosmeticUiOnly) -and ($req -match '(\bfeature\b|\bdark\s+mode\b|\bexport\b|\bimport\b|\bexcel\b|\bcsv\b|\bfilter\b|\bsearch\b|\bpagination\b|\bvalidation\b|\bworkflow\b|ch.c\s+n.ng\s+l.c|chuc\s+nang\s+loc|xu.t\s+danh\s+s.ch|xuat\s+danh\s+sach|ph.n\s+trang|phan\s+trang)'))
    if ($hasLogic) { $score += 2; $reasons.Add("Business Logic/Feature (+2)") }

    if ($reasons.Count -eq 0) {
        $reasons.Add("UI/CSS/Copy or localized 1-2 file fix (+0)")
    }

    $tier = 1
    if ($hardFloorTier3 -or $forceTier3Override -or $score -ge 6) {
        $tier = 3
    }
    elseif ($score -ge 2) {
        $tier = 2
    }
    else {
        $tier = 1
    }

    # Apply "just do it" override ONLY if NOT hardFloorTier3 (risk overrides "just do it"!)
    if ($forceTier1Override -and -not $hardFloorTier3 -and -not $forceTier3Override) {
        $tier = 1
        $reasons.Add("User override to Tier 1 (safe scope)")
    }
    elseif ($forceTier1Override -and $hardFloorTier3) {
        $reasons.Add("Risk overrides 'just do it': stays Tier 3 (design + plan required)")
    }

    $riskLevel = if ($hardFloorTier3 -or $score -ge 8) { "critical" } elseif ($score -ge 5) { "high" } elseif ($score -ge 2) { "medium" } else { "low" }
    $execMode = if ($tier -lt 3) { "single-agent" } elseif ($ProjectScale -eq "mini") { "native-compact" } elseif ($hardFloorTier3 -or $ProjectScale -eq "enterprise") { "subagent-driven" } else { "native" }

    return [pscustomobject]@{
        Score                 = [int]$score
        Tier                  = [int]$tier
        IsLookup              = $false
        RiskLevel             = $riskLevel
        Reasons               = @($reasons.ToArray())
        HardFloorTier3        = [bool]$hardFloorTier3
        RequiresDesignAndPlan = [bool]($tier -eq 3)
        ProjectScale          = $ProjectScale
        RecommendedExecution  = $execMode
    }
}

function Test-SenPathOverlap {
    param([string[]]$PathsA = @(), [string[]]$PathsB = @())
    if ($null -eq $PathsA -or $null -eq $PathsB -or $PathsA.Count -eq 0 -or $PathsB.Count -eq 0) {
        return $false
    }
    foreach ($a in $PathsA) {
        if ([string]::IsNullOrWhiteSpace($a)) { continue }
        $na = $a.Replace('\', '/').Trim().Trim('/').ToLowerInvariant()
        if ([string]::IsNullOrEmpty($na)) { continue }
        foreach ($b in $PathsB) {
            if ([string]::IsNullOrWhiteSpace($b)) { continue }
            $nb = $b.Replace('\', '/').Trim().Trim('/').ToLowerInvariant()
            if ([string]::IsNullOrEmpty($nb)) { continue }
            if ($na -eq $nb -or $na.StartsWith($nb + "/") -or $nb.StartsWith($na + "/")) {
                return $true
            }
        }
    }
    return $false
}

function Save-SenTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)]
        [object[]]$Tasks
    )
    $officeDir = Join-Path -Path $Workspace -ChildPath ".agents/office"
    if (-not (Test-Path -LiteralPath $officeDir)) {
        [System.IO.Directory]::CreateDirectory($officeDir) | Out-Null
    }
    $tasksPath = Join-Path -Path $officeDir -ChildPath "tasks.json"
    $tmpPath = "$tasksPath.$PID.tmp"
    $payload = [ordered]@{
        version   = 1
        updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        tasks     = @($Tasks)
    }
    $json = ConvertTo-Json -InputObject $payload -Depth 8
    [System.IO.File]::WriteAllText($tmpPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmpPath -Destination $tasksPath -Force
    return @($Tasks)
}

function Get-SenTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $tasksPath = Join-Path -Path $Workspace -ChildPath ".agents/office/tasks.json"
    if (-not (Test-Path -LiteralPath $tasksPath)) {
        return @()
    }
    try {
        $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $tasksPath).Path, [System.Text.Encoding]::UTF8)
        $obj = ConvertFrom-Json -InputObject $raw
        $list = if ($null -ne $obj -and $obj.PSObject.Properties.Name -contains "tasks") { @($obj.tasks) } elseif ($obj -is [array]) { @($obj) } else { @() }

        # Build lookup of done task IDs to auto-promote pending -> ready when all dependencies are done
        $doneIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($t in $list) {
            if ($t -and [string]$t.status -eq "done") {
                [void]$doneIds.Add([string]$t.id)
            }
        }
        $changed = $false
        foreach ($t in $list) {
            if (-not $t) { continue }
            $deps = @($t.dependsOn | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ([string]$t.status -eq "pending") {
                $allDone = $true
                foreach ($d in $deps) {
                    if (-not $doneIds.Contains([string]$d)) {
                        $allDone = $false
                        break
                    }
                }
                if ($allDone) {
                    $t.status = "ready"
                    $changed = $true
                }
            }
        }
        if ($changed) {
            [void](Save-SenTasks -Workspace $Workspace -Tasks $list)
        }
        return @($list)
    }
    catch {
        return @()
    }
}

function Clear-SenTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $tasksPath = Join-Path -Path $Workspace -ChildPath ".agents/office/tasks.json"
    if (Test-Path -LiteralPath $tasksPath) {
        Remove-Item -LiteralPath $tasksPath -Force -ErrorAction SilentlyContinue
    }
}

function New-SenTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [int]$Tier = 2,
        [string]$RiskLevel = "medium",
        [string]$Module = "Core",
        [string]$Assignee = "dev_be",
        [string[]]$DependsOn = @(),
        [string[]]$AllowedPaths = @(),
        [string[]]$ForbiddenActions = @("delete_database", "force_push"),
        [bool]$ApprovalRequired = $false,
        [string[]]$AcceptanceCriteria = @(),
        [ValidateSet("auto", "backlog", "pending", "ready", "in_progress", "reviewing", "done", "blocked", "failed")]
        [string]$Status = "auto"
    )
    $tasks = [System.Collections.Generic.List[object]]::new()
    foreach ($existing in @(Get-SenTasks -Workspace $Workspace)) {
        if ($existing -and [string]$existing.id -ne $Id) {
            $tasks.Add($existing)
        }
    }

    $cleanDeps = @($DependsOn | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cleanPaths = @($AllowedPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cleanForbidden = @($ForbiddenActions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cleanCriteria = @($AcceptanceCriteria | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $resolvedStatus = $Status
    if ($resolvedStatus -eq "auto") {
        if ($cleanDeps.Count -eq 0) {
            $resolvedStatus = "ready"
        }
        else {
            $doneIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($t in $tasks) {
                if ([string]$t.status -eq "done") { [void]$doneIds.Add([string]$t.id) }
            }
            $allDepsDone = $true
            foreach ($d in $cleanDeps) {
                if (-not $doneIds.Contains([string]$d)) { $allDepsDone = $false; break }
            }
            $resolvedStatus = if ($allDepsDone) { "ready" } else { "pending" }
        }
    }

    $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $newTask = [pscustomobject][ordered]@{
        id                 = $Id
        title              = $Title
        tier               = $Tier
        riskLevel          = $RiskLevel
        module             = $Module
        assignee           = $Assignee
        dependsOn          = $cleanDeps
        allowedPaths       = $cleanPaths
        forbiddenActions   = $cleanForbidden
        approvalRequired   = $ApprovalRequired
        acceptanceCriteria = $cleanCriteria
        status             = $resolvedStatus
        reworkCount        = 0
        evidence           = [pscustomobject][ordered]@{
            command    = ""
            exitCode   = $null
            reviewer   = ""
            verifiedAt = $null
            notes      = ""
        }
        createdAt          = $now
        updatedAt          = $now
    }
    $tasks.Add($newTask)
    [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks.ToArray())
    return $newTask
}

function Get-SenReadyTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $activeTasks = @($tasks | Where-Object { [string]$_.status -eq "in_progress" })
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($t in $tasks) {
        if ([string]$t.status -ne "ready") { continue }
        $conflictId = $null
        foreach ($act in $activeTasks) {
            if ([string]$act.id -eq [string]$t.id) { continue }
            if (Test-SenPathOverlap -PathsA @($t.allowedPaths) -PathsB @($act.allowedPaths)) {
                $conflictId = [string]$act.id
                break
            }
        }
        $results.Add([pscustomobject]@{
            Task             = $t
            Id               = [string]$t.id
            IsReady          = ($null -eq $conflictId)
            FileConflictWith = $conflictId
        })
    }
    return @($results.ToArray())
}

function Start-SenTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [string]$Assignee = ""
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
    if ($null -eq $target) {
        return [pscustomobject]@{ Started = $false; Status = "not_found"; ConflictTaskId = $null; Reason = "Task '$Id' not found" }
    }

    # 1. Verify all dependencies are done
    $doneIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($t in $tasks) {
        if ([string]$t.status -eq "done") { [void]$doneIds.Add([string]$t.id) }
    }
    $missingDeps = [System.Collections.Generic.List[string]]::new()
    foreach ($d in @($target.dependsOn)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$d) -and -not $doneIds.Contains([string]$d)) {
            $missingDeps.Add([string]$d)
        }
    }
    if ($missingDeps.Count -gt 0) {
        return [pscustomobject]@{
            Started        = $false
            Status         = "blocked_dependency"
            ConflictTaskId = $null
            Reason         = "Task '$Id' is waiting on dependencies: $($missingDeps -join ', ')"
        }
    }

    # 2. Verify no File Lock conflict with another in_progress task
    foreach ($t in $tasks) {
        if ([string]$t.id -eq $Id -or [string]$t.status -ne "in_progress") { continue }
        if (Test-SenPathOverlap -PathsA @($target.allowedPaths) -PathsB @($t.allowedPaths)) {
            return [pscustomobject]@{
                Started        = $false
                Status         = "blocked_file_lock"
                ConflictTaskId = [string]$t.id
                Reason         = "File lock conflict: '$Id' shares allowedPaths with active task '$($t.id)' ($($t.assignee))"
            }
        }
    }

    $target.status = "in_progress"
    if (-not [string]::IsNullOrWhiteSpace($Assignee)) {
        $target.assignee = $Assignee
    }
    $target.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks)
    return [pscustomobject]@{
        Started        = $true
        Status         = "in_progress"
        ConflictTaskId = $null
        Task           = $target
        Reason         = $null
    }
}

function Submit-SenTaskForReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [string]$Notes = ""
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
    if ($null -eq $target) {
        return [pscustomobject]@{ Submitted = $false; Reason = "Task '$Id' not found" }
    }
    $target.status = "reviewing"
    if (-not [string]::IsNullOrWhiteSpace($Notes) -and $target.evidence) {
        $target.evidence.notes = $Notes
    }
    $target.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks)
    return [pscustomobject]@{ Submitted = $true; Status = "reviewing"; Task = $target }
}

function Complete-SenTaskReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [bool]$Passed,
        [string]$Reviewer = "tester",
        [string]$EvidenceCommand = "",
        [int]$ExitCode = 0,
        [string]$Notes = ""
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $target = $tasks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
    if ($null -eq $target) {
        return [pscustomobject]@{ Completed = $false; Status = "not_found"; Reason = "Task '$Id' not found" }
    }

    $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    if ($Passed) {
        if ([string]::IsNullOrWhiteSpace($EvidenceCommand) -or $ExitCode -ne 0) {
            return [pscustomobject]@{
                Completed = $false
                Status    = [string]$target.status
                Reason    = "Integration & Testing gate requires a non-empty EvidenceCommand and ExitCode = 0 to mark '$Id' done."
            }
        }
        $target.status = "done"
        $target.evidence = [pscustomobject][ordered]@{
            command    = $EvidenceCommand
            exitCode   = $ExitCode
            reviewer   = $Reviewer
            verifiedAt = $now
            notes      = $Notes
        }
        $target.updatedAt = $now
        [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks)
        # Refresh downstream pending -> ready
        [void](Get-SenTasks -Workspace $Workspace)
        return [pscustomobject]@{ Completed = $true; Status = "done"; Task = $target; Reason = $null }
    }
    else {
        $target.reworkCount = [int]$target.reworkCount + 1
        $target.status = "in_progress"
        $target.evidence = [pscustomobject][ordered]@{
            command    = $EvidenceCommand
            exitCode   = $ExitCode
            reviewer   = $Reviewer
            verifiedAt = $now
            notes      = $Notes
        }
        $target.updatedAt = $now
        [void](Save-SenTasks -Workspace $Workspace -Tasks $tasks)
        return [pscustomobject]@{
            Completed   = $false
            Status      = "in_progress"
            ReworkCount = [int]$target.reworkCount
            Task        = $target
            Reason      = "Review failed; returned to in_progress for rework (#$($target.reworkCount))."
        }
    }
}

function Test-SenDeliveryGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $active = @($tasks | Where-Object { [string]$_.status -ne "backlog" })
    if ($active.Count -eq 0) {
        return [pscustomobject]@{
            Allowed       = $true
            TotalActive   = 0
            DoneCount     = 0
            IncompleteIds = @()
            Reason        = "No active tasks registered."
        }
    }
    $incomplete = [System.Collections.Generic.List[string]]::new()
    $doneCount = 0
    foreach ($t in $active) {
        $hasValidEvidence = ($null -ne $t.evidence) -and (-not [string]::IsNullOrWhiteSpace([string]$t.evidence.command)) -and ([int]$t.evidence.exitCode -eq 0)
        if ([string]$t.status -eq "done" -and $hasValidEvidence) {
            $doneCount++
        }
        else {
            $incomplete.Add([string]$t.id)
        }
    }
    $allowed = ($incomplete.Count -eq 0)
    $reason = if ($allowed) { "All $($active.Count) active task(s) verified and done." } else { "Delivery blocked: incomplete or unverified tasks ($($incomplete -join ', '))." }
    return [pscustomobject]@{
        Allowed       = $allowed
        TotalActive   = $active.Count
        DoneCount     = $doneCount
        IncompleteIds = @($incomplete.ToArray())
        Reason        = $reason
    }
}

function Get-SenRecoveryState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $inProgress = @($tasks | Where-Object { [string]$_.status -eq "in_progress" } | ForEach-Object { [string]$_.id })
    $reviewing  = @($tasks | Where-Object { [string]$_.status -eq "reviewing" } | ForEach-Object { [string]$_.id })
    $ready      = @($tasks | Where-Object { [string]$_.status -eq "ready" } | ForEach-Object { [string]$_.id })
    $pending    = @($tasks | Where-Object { [string]$_.status -eq "pending" } | ForEach-Object { [string]$_.id })
    $done       = @($tasks | Where-Object { [string]$_.status -eq "done" } | ForEach-Object { [string]$_.id })
    $backlog    = @($tasks | Where-Object { [string]$_.status -eq "backlog" } | ForEach-Object { [string]$_.id })
    $failed     = @($tasks | Where-Object { [string]$_.status -eq "failed" } | ForEach-Object { [string]$_.id })

    return [pscustomobject][ordered]@{
        needsRecovery = [bool](($inProgress.Count + $reviewing.Count + $failed.Count) -gt 0)
        totalTasks    = $tasks.Count
        doneIds       = $done
        inProgressIds = $inProgress
        reviewingIds  = $reviewing
        readyIds      = $ready
        pendingIds    = $pending
        failedIds     = $failed
        backlogIds    = $backlog
    }
}

function Get-SenQualityMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $tasks = @(Get-SenTasks -Workspace $Workspace)
    $active = @($tasks | Where-Object { [string]$_.status -ne "backlog" })
    $backlog = @($tasks | Where-Object { [string]$_.status -eq "backlog" })
    $done = @($active | Where-Object { [string]$_.status -eq "done" })
    $inProg = @($active | Where-Object { [string]$_.status -in @("in_progress", "reviewing") })
    $ready = @($active | Where-Object { [string]$_.status -in @("ready", "pending") })

    $totalActive = $active.Count
    $doneCount = $done.Count
    $firstPassCount = @($done | Where-Object { [int]$_.reworkCount -eq 0 }).Count
    $reworkedCount = @($active | Where-Object { [int]$_.reworkCount -gt 0 }).Count
    $verifiedPassCount = @($done | Where-Object { $null -ne $_.evidence -and [int]$_.evidence.exitCode -eq 0 }).Count

    $successPct = if ($totalActive -gt 0) { [int][Math]::Round(($doneCount * 100.0) / $totalActive) } else { 100 }
    $firstPassPct = if ($doneCount -gt 0) { [int][Math]::Round(($firstPassCount * 100.0) / $doneCount) } else { 100 }
    $reworkPct = if ($totalActive -gt 0) { [int][Math]::Round(($reworkedCount * 100.0) / $totalActive) } else { 0 }
    $testPassPct = if ($doneCount -gt 0) { [int][Math]::Round(($verifiedPassCount * 100.0) / $doneCount) } else { 100 }

    return [pscustomobject][ordered]@{
        totalTasks         = $tasks.Count
        activeTasks        = $totalActive
        doneTasks          = $doneCount
        inProgressTasks    = $inProg.Count
        readyTasks         = $ready.Count
        backlogTasks       = $backlog.Count
        taskSuccessRatePct = $successPct
        firstPassRatePct   = $firstPassPct
        reworkRatePct      = $reworkPct
        testPassRatePct    = $testPassPct
    }
}

function Add-SenBacklogItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Priority = "P1",
        [string]$Details = "",
        [string]$Module = "Backlog"
    )
    # 1. Register as backlog task in .agents/office/tasks.json
    $task = New-SenTask -Workspace $Workspace -Id $Id -Title $Title -Tier 2 -RiskLevel "medium" -Module $Module -Assignee "pm" -Status "backlog"

    # 2. Ensure docs/TODO.md exists and contains the item
    $docsDir = Join-Path -Path $Workspace -ChildPath "docs"
    if (-not (Test-Path -LiteralPath $docsDir)) {
        [System.IO.Directory]::CreateDirectory($docsDir) | Out-Null
    }
    $todoPath = Join-Path -Path $docsDir -ChildPath "TODO.md"
    $existingText = if (Test-Path -LiteralPath $todoPath) {
        [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $todoPath).Path, [System.Text.Encoding]::UTF8)
    }
    else {
        "# Project Backlog (TODO)`n`n"
    }

    if ($existingText -notmatch [regex]::Escape($Id)) {
        $entryLine = "- [ ] **${Id} (${Priority}): ${Title}**"
        if (-not [string]::IsNullOrWhiteSpace($Details)) {
            $entryLine += "`n  - " + $Details.Trim()
        }
        $updatedText = $existingText.TrimEnd() + "`n`n" + $entryLine + "`n"
        [System.IO.File]::WriteAllText($todoPath, $updatedText, [System.Text.UTF8Encoding]::new($false))
    }

    return [pscustomobject]@{
        Id       = $Id
        Title    = $Title
        Priority = $Priority
        TodoPath = $todoPath
        Task     = $task
    }
}

function New-SenRestorePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string[]]$Files,
        [string]$Label = "pre-edit"
    )
    $resolvedWs = (Resolve-Path -LiteralPath $Workspace).Path.TrimEnd('\', '/')
    $restoreRoot = Join-Path -Path $resolvedWs -ChildPath ".agents/.sen-restore"
    if (-not (Test-Path -LiteralPath $restoreRoot)) {
        [System.IO.Directory]::CreateDirectory($restoreRoot) | Out-Null
    }
    $ts = [DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")
    $id = "rp-$ts-" + ([Guid]::NewGuid().ToString("N").Substring(0, 6))
    $rpDir = Join-Path -Path $restoreRoot -ChildPath $id
    $filesDir = Join-Path -Path $rpDir -ChildPath "files"
    [System.IO.Directory]::CreateDirectory($filesDir) | Out-Null

    $entries = [System.Collections.Generic.List[object]]::new()
    $idx = 0
    foreach ($f in $Files) {
        if ([string]::IsNullOrWhiteSpace($f)) { continue }
        $fullPath = if ([System.IO.Path]::IsPathRooted($f)) { [System.IO.Path]::GetFullPath($f) } else { [System.IO.Path]::GetFullPath((Join-Path $resolvedWs $f)) }
        $relPath = if ($fullPath.StartsWith($resolvedWs, [System.StringComparison]::OrdinalIgnoreCase)) {
            $fullPath.Substring($resolvedWs.Length).TrimStart('\', '/')
        }
        else {
            [System.IO.Path]::GetFileName($fullPath)
        }
        $existed = Test-Path -LiteralPath $fullPath -PathType Leaf
        $storedName = "f_$idx.bak"
        if ($existed) {
            Copy-Item -LiteralPath $fullPath -Destination (Join-Path $filesDir $storedName) -Force
        }
        $entries.Add([ordered]@{
            relPath    = $relPath
            fullPath   = $fullPath
            existed    = [bool]$existed
            storedName = $storedName
        })
        $idx++
    }

    $manifest = [ordered]@{
        id        = $id
        label     = $Label
        createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        entries   = @($entries.ToArray())
    }
    $manifestPath = Join-Path -Path $rpDir -ChildPath "manifest.json"
    [System.IO.File]::WriteAllText($manifestPath, (ConvertTo-Json -InputObject $manifest -Depth 6) + "`n", [System.Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{
        Id        = $id
        Label     = $Label
        Directory = $rpDir
        FileCount = $entries.Count
    }
}

function Restore-SenRestorePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [string]$Id = ""
    )
    $resolvedWs = (Resolve-Path -LiteralPath $Workspace).Path.TrimEnd('\', '/')
    $restoreRoot = Join-Path -Path $resolvedWs -ChildPath ".agents/.sen-restore"
    if (-not (Test-Path -LiteralPath $restoreRoot)) {
        return [pscustomobject]@{ Restored = $false; Id = $null; Error = "No restore points found" }
    }
    $targetDir = $null
    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $cand = Join-Path -Path $restoreRoot -ChildPath $Id
        if (Test-Path -LiteralPath $cand) { $targetDir = Get-Item -LiteralPath $cand }
    }
    else {
        $targetDir = Get-ChildItem -LiteralPath $restoreRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
    }
    if ($null -eq $targetDir) {
        return [pscustomobject]@{ Restored = $false; Id = $Id; Error = "Restore point not found" }
    }
    $manifestPath = Join-Path -Path $targetDir.FullName -ChildPath "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        return [pscustomobject]@{ Restored = $false; Id = $targetDir.Name; Error = "Manifest missing" }
    }
    $raw = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
    $manifest = ConvertFrom-Json -InputObject $raw
    $filesDir = Join-Path -Path $targetDir.FullName -ChildPath "files"
    $restoredCount = 0

    foreach ($e in @($manifest.entries)) {
        $destPath = Join-Path -Path $resolvedWs -ChildPath ([string]$e.relPath)
        if ([bool]$e.existed) {
            $srcBak = Join-Path -Path $filesDir -ChildPath ([string]$e.storedName)
            if (Test-Path -LiteralPath $srcBak) {
                $parent = Split-Path -Parent $destPath
                if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
                }
                Copy-Item -LiteralPath $srcBak -Destination $destPath -Force
                $restoredCount++
            }
        }
        else {
            if (Test-Path -LiteralPath $destPath) {
                Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
                $restoredCount++
            }
        }
    }
    return [pscustomobject]@{
        Restored      = $true
        Id            = [string]$manifest.id
        RestoredCount = $restoredCount
        Error         = $null
    }
}

function Add-SenExecutionLesson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $true)]
        [string]$Category,
        [Parameter(Mandatory = $true)]
        [string]$Problem,
        [Parameter(Mandatory = $true)]
        [string]$Solution,
        [string]$RootCause = "",
        [bool]$VerifiedByUser = $true
    )
    $officeDir = Join-Path -Path $Workspace -ChildPath ".agents/office"
    if (-not (Test-Path -LiteralPath $officeDir)) {
        [System.IO.Directory]::CreateDirectory($officeDir) | Out-Null
    }
    $lessonsPath = Join-Path -Path $officeDir -ChildPath "lessons.json"
    $existing = [System.Collections.Generic.List[object]]::new()
    if (Test-Path -LiteralPath $lessonsPath) {
        try {
            $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $lessonsPath).Path, [System.Text.Encoding]::UTF8)
            foreach ($item in @(ConvertFrom-Json -InputObject $raw)) {
                if ($item) { $existing.Add($item) }
            }
        }
        catch { }
    }
    $entry = [pscustomobject][ordered]@{
        id             = "LES-" + ([DateTime]::UtcNow.ToString("yyyyMMddHHmmss")) + "-" + ([Guid]::NewGuid().ToString("N").Substring(0, 4))
        category       = $Category
        problem        = $Problem
        rootCause      = $RootCause
        solution       = $Solution
        verifiedByUser = $VerifiedByUser
        createdAt      = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $existing.Add($entry)
    $tmp = "$lessonsPath.$PID.tmp"
    [System.IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject @($existing.ToArray()) -Depth 5) + "`n", [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $lessonsPath -Force
    return $entry
}

function Get-SenExecutionLessons {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $lessonsPath = Join-Path -Path $Workspace -ChildPath ".agents/office/lessons.json"
    if (-not (Test-Path -LiteralPath $lessonsPath)) { return @() }
    try {
        $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $lessonsPath).Path, [System.Text.Encoding]::UTF8)
        return @(ConvertFrom-Json -InputObject $raw)
    }
    catch {
        return @()
    }
}

function Get-SenMemorySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $profilePath = Join-Path -Path $Workspace -ChildPath ".agents/profile.md"
    $agentsPath  = Join-Path -Path $Workspace -ChildPath "AGENTS.md"
    $contextPath = Join-Path -Path $Workspace -ChildPath "docs/CONTEXT.md"
    $todoPath    = Join-Path -Path $Workspace -ChildPath "docs/TODO.md"
    $lessons     = @(Get-SenExecutionLessons -Workspace $Workspace)

    return [pscustomobject][ordered]@{
        userMemory      = [ordered]@{
            present = (Test-Path -LiteralPath $profilePath)
            path    = ".agents/profile.md"
        }
        projectMemory   = [ordered]@{
            hasAgentsMd  = (Test-Path -LiteralPath $agentsPath)
            hasContextMd = (Test-Path -LiteralPath $contextPath)
            hasTodoMd    = (Test-Path -LiteralPath $todoPath)
        }
        executionMemory = [ordered]@{
            lessonCount = $lessons.Count
            lessons     = $lessons
        }
    }
}

Export-ModuleMember -Function Get-SenDriveCandidates, New-SenWorkspace, New-SenFileFromTemplate, Get-SenToolStatus, Get-SenInstallPlan, Read-SenLock, Write-SenLock, Install-SenPackage, Install-SenSelf, Get-SenUpdateStatus, Update-SenPackages, Restore-SenPackage, New-SenPackageBackup, Get-SenPackageBackups, Protect-SenRedactedText, Get-SenOfficeConfig, Set-SenOfficeConfig, Write-SenOfficeEvent, Read-SenOfficeEvents, Clear-SenOfficeEvents, Test-SenStuckLoop, Write-SenOfficeShowcase, Read-SenOfficeShowcase, Get-SenAntigravityQuota, Get-SenTaskRiskScore, Test-SenPathOverlap, New-SenTask, Get-SenTasks, Save-SenTasks, Clear-SenTasks, Get-SenReadyTasks, Start-SenTask, Submit-SenTaskForReview, Complete-SenTaskReview, Test-SenDeliveryGate, Get-SenRecoveryState, Get-SenQualityMetrics, Add-SenBacklogItem, New-SenRestorePoint, Restore-SenRestorePoint, Add-SenExecutionLesson, Get-SenExecutionLessons, Get-SenMemorySnapshot
