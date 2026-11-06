# scripts/Sen.Packages.psm1
# Pure ASCII PowerShell module for Sen lockfile, package install, update, backup, and restore.

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
    $rawObj = Read-SenSafeJson -Path $lockPath
    if ($null -eq $rawObj) { return $lock }
    $parsed = ConvertTo-SenHashtable -InputObject $rawObj
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
    Write-SenAtomicJson -Path $lockPath -InputObject $Lock -Depth 10
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
    $payload = Get-SenSelfPayloadNames
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

function Invoke-SenSinglePackageUpdateCheck {
    param(
        [string]$Id,
        [string]$CurrentCommit,
        [string]$Repo,
        [string]$TmpRoot,
        [scriptblock]$Git
    )
    try {
        $r = & $Git @("ls-remote", $Repo, "HEAD")
        if ($r.ExitCode -ne 0) {
            $errMsg = if ($r.Output) { $r.Output } else { "git ls-remote failed with exit $($r.ExitCode)" }
            return [pscustomobject]@{
                Id        = $Id
                Current   = $CurrentCommit
                Latest    = "unknown"
                HasUpdate = $false
                Summary   = ""
                Error     = $errMsg
            }
        }

        $latestCommit = "unknown"
        if (-not [string]::IsNullOrWhiteSpace($r.Output)) {
            $tokens = $r.Output.Trim() -split '\s+'
            if ($tokens.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($tokens[0])) {
                $latestCommit = $tokens[0].Trim()
            }
        }

        $hasUpdate = ($latestCommit -ne "unknown" -and $CurrentCommit -ne "unknown" -and $latestCommit -ne $CurrentCommit)
        $summary = ""
        if ($hasUpdate) {
            $cloneTmp = Join-Path $TmpRoot ("src-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
            try {
                $cRes = & $Git @("clone", "--depth", "5", "--quiet", $Repo, $cloneTmp)
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

        return [pscustomobject]@{
            Id        = $Id
            Current   = $CurrentCommit
            Latest    = $latestCommit
            HasUpdate = [bool]$hasUpdate
            Summary   = [string]$summary
            Error     = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Id        = $Id
            Current   = $CurrentCommit
            Latest    = "unknown"
            HasUpdate = $false
            Summary   = ""
            Error     = $_.Exception.Message
        }
    }
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
            if (-not $lock.packages.ContainsKey($id)) { continue }
            [void]$checkedIds.Add($id)
            $currentCommit = if ($lock.packages[$id] -and $lock.packages[$id].commit) { [string]$lock.packages[$id].commit } else { "unknown" }
            $repo = if ($lock.packages[$id] -and $lock.packages[$id].repo) { [string]$lock.packages[$id].repo } else { [string]$pkg.repo }
            $results.Add((Invoke-SenSinglePackageUpdateCheck -Id $id -CurrentCommit $currentCommit -Repo $repo -TmpRoot $tmpRoot -Git $Git))
        }

        foreach ($id in $lock.packages.Keys) {
            if ($checkedIds.Contains($id)) { continue }
            [void]$checkedIds.Add($id)
            $currentCommit = if ($lock.packages[$id] -and $lock.packages[$id].commit) { [string]$lock.packages[$id].commit } else { "unknown" }
            $repo = if ($lock.packages[$id] -and $lock.packages[$id].repo) { [string]$lock.packages[$id].repo } else { continue }
            $results.Add((Invoke-SenSinglePackageUpdateCheck -Id $id -CurrentCommit $currentCommit -Repo $repo -TmpRoot $tmpRoot -Git $Git))
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

        $currentCommit = "unknown"
        if ($lock.packages[$id] -and $lock.packages[$id].commit) {
            $currentCommit = [string]$lock.packages[$id].commit
        }
        if ($currentCommit -eq "unknown" -and (Test-Path -LiteralPath (Join-Path $dest ".sen-commit"))) {
            $mc = ([System.IO.File]::ReadAllText((Join-Path $dest ".sen-commit"))).Trim()
            if ($mc) { $currentCommit = $mc }
        }

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
                    $senPayload = Get-SenSelfPayloadNames
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

                if ($destRenamed -and (Test-Path -LiteralPath $oldDest)) {
                    Remove-Item -LiteralPath $oldDest -Recurse -Force -ErrorAction SilentlyContinue
                }

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
        $restoredCommit = $targetBackup.Commit
        if ([string]::IsNullOrEmpty($restoredCommit) -or $restoredCommit -eq "unknown") {
            $backupCommitFile = Join-Path $targetBackup.Directory.FullName ".sen-commit"
            if (Test-Path -LiteralPath $backupCommitFile) {
                $restoredCommit = ([System.IO.File]::ReadAllText($backupCommitFile)).Trim()
            }
        }

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

Export-ModuleMember -Function Get-SenLockPath, Read-SenLock, Write-SenLock, Install-SenPackage, Install-SenSelf, Get-SenPackagesCatalog, New-SenPackageBackup, Get-SenPackageBackups, Get-SenUpdateStatus, Update-SenPackages, Restore-SenPackage
