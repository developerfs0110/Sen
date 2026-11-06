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
        $commit = Get-SenGitCommit -Path $clone -Git $Git
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
        return [pscustomobject]@{ Status = "exists"; Error = $null }
    }
    $payload = @("plugin.json", "rules", "skills", "templates", "scripts", "INSTALL.md", "LICENSE", "CHANGELOG.md")
    $tmpRoot = $null
    try {
        $srcRoot = $Source
        if (-not (Test-Path -LiteralPath $Source)) {
            $tmpRoot = New-SenTempDir
            $srcRoot = Join-Path $tmpRoot "src"
            $r = & $Git @("clone", "--depth", "1", "--quiet", $Source, $srcRoot)
            if ($r.ExitCode -ne 0) {
                return [pscustomobject]@{ Status = "failed"; Error = "git clone failed for $Source (exit $($r.ExitCode)): $($r.Output)" }
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $srcRoot "plugin.json"))) {
            return [pscustomobject]@{ Status = "failed"; Error = "plugin.json not found in Sen source $Source" }
        }
        [System.IO.Directory]::CreateDirectory($dest) | Out-Null
        foreach ($item in Get-ChildItem -LiteralPath $srcRoot -Force) {
            if (($payload -contains $item.Name) -or ($item.Name -like "README*")) {
                Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $dest $item.Name) -Recurse -Force
            }
        }
        return [pscustomobject]@{ Status = "installed"; Error = $null }
    }
    catch {
        $err = $_.Exception.Message
        if (Test-Path -LiteralPath $dest) {
            Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
        }
        return [pscustomobject]@{ Status = "failed"; Error = $err }
    }
    finally {
        if ($tmpRoot -and (Test-Path -LiteralPath $tmpRoot)) {
            Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Get-SenDriveCandidates, New-SenWorkspace, New-SenFileFromTemplate, Get-SenToolStatus, Get-SenInstallPlan, Read-SenLock, Write-SenLock, Install-SenPackage, Install-SenSelf
