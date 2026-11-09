# scripts/Sen.Packages.psm1
# Pure ASCII PowerShell module for Sen lockfile, package install, update, backup, and restore.

function Get-SenLockPath {
    param([string]$Workspace)
    return (Join-Path -Path (Join-Path -Path $Workspace -ChildPath ".agents") -ChildPath "sen.lock.json")
}

function ConvertTo-SenHashtable {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [DateTime]) { return $InputObject.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
    if ($InputObject -is [DateTimeOffset]) { return $InputObject.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ") }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) {
            $h[$p.Name] = ConvertTo-SenHashtable -InputObject $p.Value
        }
        return $h
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return , @($InputObject | ForEach-Object { ConvertTo-SenHashtable -InputObject $_ })
    }
    return $InputObject
}

function Read-SenLock {
    [CmdletBinding()] param([Parameter(Mandatory = $true)][string]$Workspace)
    $lockPath = Get-SenLockPath -Workspace $Workspace
    $lock = @{ lockVersion = 1; packages = @{}; lastUpdateCheck = $null }
    $rawObj = Read-SenSafeJson -Path $lockPath
    if ($null -eq $rawObj) { return $lock }
    $parsed = ConvertTo-SenHashtable -InputObject $rawObj
    if ($parsed -is [hashtable]) { foreach ($k in $parsed.Keys) { $lock[$k] = $parsed[$k] } }
    if ($lock.packages -isnot [hashtable]) { $lock.packages = @{} }
    return $lock
}

function Write-SenLock {
    [CmdletBinding()] param([Parameter(Mandatory = $true)][string]$Workspace, [Parameter(Mandatory = $true)][hashtable]$Lock)
    Write-SenAtomicJson -Path (Get-SenLockPath -Workspace $Workspace) -InputObject $Lock -Depth 10
}

function Get-SenDirectoryTreeHash {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    $root = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($f in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.Name -notin @(".sen-commit", ".sen-tree-hash") } | Sort-Object FullName)) {
        $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
        $fh = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $entries.Add("${rel}:${fh}")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($entries -join "`n"))
    return ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
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
        $destTarget = Join-Path $Destination $item.Name
        if (Test-Path -LiteralPath $destTarget) {
            Remove-Item -LiteralPath $destTarget -Recurse -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -LiteralPath $item.FullName -Destination $destTarget -Recurse -Force
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
    param([Parameter(Mandatory = $true)][string]$Workspace, [Parameter(Mandatory = $true)]$Package, [scriptblock]$Git = $null, [switch]$VerifyPinnedCommit)
    if ($null -eq $Git) { $Git = Get-SenDefaultGit }
    $id = [string]$Package.id
    $dest = Join-Path -Path $Workspace -ChildPath ([string]$Package.dest)
    $pinned = if ($Package.PSObject.Properties.Name -contains "pinnedCommit" -and -not [string]::IsNullOrWhiteSpace([string]$Package.pinnedCommit)) { ([string]$Package.pinnedCommit).Trim() } else { "" }

    if (Test-Path -LiteralPath $dest) {
        $commit = "unknown"
        if (Test-Path -LiteralPath (Join-Path $dest ".git")) { $commit = Get-SenGitCommit -Path $dest -Git $Git }
        elseif (Test-Path -LiteralPath (Join-Path $dest ".sen-commit")) {
            $marker = ([System.IO.File]::ReadAllText((Join-Path $dest ".sen-commit"))).Trim()
            if ($marker) { $commit = $marker }
        }
        $treeHash = Get-SenDirectoryTreeHash -Path $dest
        $thFile = Join-Path $dest ".sen-tree-hash"
        $savedTreeHash = if (Test-Path -LiteralPath $thFile) { ([System.IO.File]::ReadAllText($thFile)).Trim() } else { "" }
        $commitOk = [string]::IsNullOrWhiteSpace($pinned) -or ($commit -ne "unknown" -and ($commit.StartsWith($pinned, [System.StringComparison]::OrdinalIgnoreCase) -or $pinned.StartsWith($commit, [System.StringComparison]::OrdinalIgnoreCase)))
        $treeOk = [string]::IsNullOrWhiteSpace($savedTreeHash) -or $savedTreeHash.Equals($treeHash, [System.StringComparison]::OrdinalIgnoreCase)
        if ($VerifyPinnedCommit.IsPresent -and (-not $commitOk -or -not $treeOk)) {
            $errMsg = if (-not $commitOk) { "Pinned commit mismatch: expected $pinned, found $commit" } else { "Package tree hash mismatch: expected $savedTreeHash, found $treeHash" }
            return [pscustomobject]@{ Id = $id; Commit = $commit; ExpectedCommit = $pinned; CommitVerified = $false; TreeHash = $treeHash; Status = "mismatch"; Error = $errMsg }
        }
        return [pscustomobject]@{ Id = $id; Commit = $commit; ExpectedCommit = $pinned; CommitVerified = [bool]$commitOk; TreeHash = $treeHash; Status = "exists"; Error = $null }
    }

    $tmpRoot = New-SenTempDir
    $clone = Join-Path $tmpRoot "src"
    try {
        $isSparse = ($Package.PSObject.Properties.Name -contains "sparse" -and [bool]$Package.sparse -and -not [string]::IsNullOrWhiteSpace([string]$Package.subPath))
        $cloneArgs = if ($isSparse) { @("clone", "--filter=blob:none", "--no-checkout", "--depth", "1", "--quiet", [string]$Package.repo, $clone) } else { @("clone", "--depth", "1", "--quiet", [string]$Package.repo, $clone) }
        $r = & $Git $cloneArgs
        if ($r.ExitCode -ne 0) {
            $msg = "git clone failed for $($Package.repo) (exit $($r.ExitCode))"
            if ($r.Output) { $msg += ": " + $r.Output }
            return [pscustomobject]@{ Id = $id; Commit = $null; ExpectedCommit = $pinned; CommitVerified = $false; TreeHash = ""; Status = "failed"; Error = $msg }
        }
        if ($isSparse) {
            try {
                [void](& $Git @("-C", $clone, "sparse-checkout", "init", "--cone"))
                [void](& $Git @("-C", $clone, "sparse-checkout", "set", [string]$Package.subPath))
                if (-not $pinned) { [void](& $Git @("-C", $clone, "checkout", "--quiet", "HEAD")) }
            }
            catch { <# Best-effort sparse-checkout when mock git is used #> }
        }
        if ($pinned) {
            try {
                [void](& $Git @("-C", $clone, "fetch", "--depth", "1", "origin", $pinned))
                [void](& $Git @("-C", $clone, "checkout", "--quiet", $pinned))
            }
            catch { <# Best-effort pinned checkout when mock git is used #> }
        }
        $src = if ([string]::IsNullOrEmpty([string]$Package.subPath)) { $clone } else { Join-Path $clone ([string]$Package.subPath) }
        if ($isSparse -and -not (Test-Path -LiteralPath $src)) {
            try { [void](& $Git @("-C", $clone, "checkout", "--quiet", "HEAD")) } catch { <# Fallback HEAD checkout #> }
        }
        if ($isSparse -and -not (Test-Path -LiteralPath $src)) {
            if (Test-Path -LiteralPath $clone) { Remove-Item -LiteralPath $clone -Recurse -Force -ErrorAction SilentlyContinue }
            $rFallback = & $Git @("clone", "--depth", "1", "--quiet", [string]$Package.repo, $clone)
            if ($rFallback.ExitCode -eq 0 -and $pinned) {
                try {
                    [void](& $Git @("-C", $clone, "fetch", "--depth", "1", "origin", $pinned))
                    [void](& $Git @("-C", $clone, "checkout", "--quiet", $pinned))
                }
                catch { <# Best-effort pinned checkout on fallback #> }
            }
        }
        $commit = Get-SenGitCommit -Path $clone -Git $Git
        if (($commit -eq "unknown" -or [string]::IsNullOrWhiteSpace($commit)) -and $pinned) { $commit = $pinned }
        if (-not (Test-Path -LiteralPath $src)) {
            return [pscustomobject]@{ Id = $id; Commit = $commit; ExpectedCommit = $pinned; CommitVerified = $false; TreeHash = ""; Status = "failed"; Error = "subPath '$($Package.subPath)' not found in $($Package.repo)" }
        }
        $treeHash = ""
        try {
            Copy-SenTree -Source $src -Destination $dest
            [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), $commit + "`n", [System.Text.UTF8Encoding]::new($false))
            $treeHash = Get-SenDirectoryTreeHash -Path $dest
            [System.IO.File]::WriteAllText((Join-Path $dest ".sen-tree-hash"), $treeHash + "`n", [System.Text.UTF8Encoding]::new($false))
        }
        catch {
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
            return [pscustomobject]@{ Id = $id; Commit = $commit; ExpectedCommit = $pinned; CommitVerified = $false; TreeHash = ""; Status = "failed"; Error = "copy failed: $($_.Exception.Message)" }
        }
        $commitOk = [string]::IsNullOrWhiteSpace($pinned) -or ($commit -ne "unknown" -and ($commit.StartsWith($pinned, [System.StringComparison]::OrdinalIgnoreCase) -or $pinned.StartsWith($commit, [System.StringComparison]::OrdinalIgnoreCase)))
        return [pscustomobject]@{ Id = $id; Commit = $commit; ExpectedCommit = $pinned; CommitVerified = [bool]$commitOk; TreeHash = $treeHash; Status = "installed"; Error = $null }
    }
    finally {
        if (Test-Path -LiteralPath $tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Install-SenCreativePack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [Parameter(Mandatory = $false)]
        [string[]]$Pack = @("all"),
        [Parameter(Mandatory = $false)]
        [scriptblock]$Git = $null,
        [Parameter(Mandatory = $false)]
        [scriptblock]$ToolRunner = $null
    )
    if ($null -eq $Git) { $Git = Get-SenDefaultGit }
    $catalog = [System.Collections.Generic.List[object]]::new()
    foreach ($item in (Get-SenPackagesCatalog)) {
        if ($null -ne $item -and $null -ne $item.PSObject.Properties["pack"] -and -not [string]::IsNullOrWhiteSpace([string]$item.pack)) {
            $catalog.Add($item)
        }
    }
    $validNames = @("all") + @($catalog | ForEach-Object { [string]$_.pack }) + @($catalog | ForEach-Object { [string]$_.id })
    foreach ($reqPack in @($Pack)) {
        if ($validNames -notcontains $reqPack) {
            throw "Unknown creative pack '$reqPack'. Valid packs: media-image, media-video, media-3d, all"
        }
    }
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $catalog) {
        if (($Pack -contains "all") -or ($Pack -contains [string]$item.pack) -or ($Pack -contains [string]$item.id)) {
            $selected.Add($item)
        }
    }

    if (-not (Get-Command -Name "Get-SenToolStatus" -ErrorAction SilentlyContinue)) {
        $senRootMod = Join-Path -Path $PSScriptRoot -ChildPath "Sen.psm1"
        if (Test-Path -LiteralPath $senRootMod) {
            Import-Module -Name $senRootMod -Global -Force -ErrorAction SilentlyContinue
        }
    }

    $lock = Read-SenLock -Workspace $Workspace
    $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $pkgResults = [System.Collections.Generic.List[object]]::new()
    $missingTools = [System.Collections.Generic.List[string]]::new()
    $allOk = ($selected.Count -gt 0)

    foreach ($pkg in $selected) {
        $r = Install-SenPackage -Workspace $Workspace -Package $pkg -Git $Git
        $pkgResults.Add([pscustomobject]@{
                Id     = $r.Id
                Pack   = [string]$pkg.pack
                Dest   = [string]$pkg.dest
                Status = $r.Status
                Commit = $r.Commit
                Error  = $r.Error
            })
        if ($r.Status -eq "failed") {
            $allOk = $false
            continue
        }
        $old = $lock.packages[$r.Id]
        if (-not ($r.Status -eq "exists" -and $old -is [hashtable] -and $old.commit)) {
            $commit = if ($r.Commit) { $r.Commit } else { "unknown" }
            $lock.packages[$r.Id] = [ordered]@{ repo = [string]$pkg.repo; subPath = [string]$pkg.subPath; commit = $commit; installedAt = $now }
        }
        if ($pkg.PSObject.Properties.Name -contains "requiredTools" -and (Get-Command Get-SenToolStatus -ErrorAction SilentlyContinue)) {
            foreach ($tid in @($pkg.requiredTools)) {
                if ([string]::IsNullOrWhiteSpace([string]$tid) -or $missingTools.Contains([string]$tid)) { continue }
                $ts = Get-SenToolStatus -Id ([string]$tid) -Runner $ToolRunner
                if ($ts.Status -ne "ok") { $missingTools.Add([string]$tid) }
            }
        }
    }

    $lockWritten = $false
    if ($allOk) {
        Write-SenLock -Workspace $Workspace -Lock $lock
        $lockWritten = $true
    }
    return [pscustomobject]@{
        Workspace    = $Workspace
        Packs        = @($selected | ForEach-Object { [string]$_.pack } | Select-Object -Unique)
        Packages     = @($pkgResults.ToArray())
        MissingTools = @($missingTools.ToArray())
        LockWritten  = [bool]$lockWritten
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
        [scriptblock]$Git = $null,
        [switch]$Force
    )
    if ($null -eq $Git) { $Git = Get-SenDefaultGit }
    $dest = Join-Path -Path $Workspace -ChildPath ".agents/plugins/sen-method"
    if ((Test-Path -LiteralPath $dest) -and (-not $Force.IsPresent)) {
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
                $targetItem = Join-Path $dest $item.Name
                if (Test-Path -LiteralPath $targetItem) {
                    Remove-Item -LiteralPath $targetItem -Recurse -Force -ErrorAction SilentlyContinue
                }
                Copy-Item -LiteralPath $item.FullName -Destination $targetItem -Recurse -Force
            }
        }
        [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), $commit + "`n", [System.Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{ Status = "installed"; Commit = $commit; Error = $null }
    }
    catch {
        $err = $_.Exception.Message
        if ((Test-Path -LiteralPath $dest) -and (-not $Force.IsPresent)) {
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
    $parsed = ConvertFrom-Json -InputObject $raw
    return @($parsed | ForEach-Object { $_ })
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
        catch { <# Ignore malformed backup metadata entry #> }
    }
    $sorted = $valid | Sort-Object -Descending -Property Timestamp
    return @($sorted)
}

function Get-SenRemoteLogSummary {
    param([string]$Repo, [string]$TmpRoot, [scriptblock]$Git)
    $cloneTmp = Join-Path $TmpRoot ("src-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
    try {
        $cRes = & $Git @("clone", "--depth", "5", "--quiet", $Repo, $cloneTmp)
        if ($cRes.ExitCode -ne 0) { return "" }
        $lRes = & $Git @("-C", $cloneTmp, "log", "-5", "--oneline")
        if ($lRes.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($lRes.Output)) { return "" }
        $lines = @($lRes.Output -split "[\r\n]+") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
            $s = ($_ -replace '[<>`$|;]', '').Trim()
            if ($s.Length -gt 100) { $s.Substring(0, 100) } else { $s }
        }
        return (($lines | Select-Object -First 5) -join "`n").Trim()
    }
    catch {
        <# Summary is optional; return empty string if log fetch fails #>
        return ""
    }
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
        $summary = if ($hasUpdate) { Get-SenRemoteLogSummary -Repo $Repo -TmpRoot $TmpRoot -Git $Git } else { "" }

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

function Resolve-SenInstalledCommit {
    param([hashtable]$Lock, [string]$Id, [string]$Dest)
    $commit = "unknown"
    if ($Lock.packages[$Id] -and $Lock.packages[$Id].commit) {
        $commit = [string]$Lock.packages[$Id].commit
    }
    $markerFile = Join-Path $Dest ".sen-commit"
    if ($commit -eq "unknown" -and (Test-Path -LiteralPath $markerFile)) {
        $mc = ([System.IO.File]::ReadAllText($markerFile)).Trim()
        if ($mc) { $commit = $mc }
    }
    return $commit
}

function Invoke-SenAtomicDestSwap {
    param(
        [string]$Dest,
        [string]$Commit,
        [scriptblock]$PopulateAction
    )
    $oldDest = $Dest + ".sen-old"
    $destRenamed = $false
    $newDestCreated = $false
    try {
        if (Test-Path -LiteralPath $oldDest) {
            throw "stale .sen-old present; resolve manually"
        }
        if (Test-Path -LiteralPath $Dest) {
            [System.IO.Directory]::Move($Dest, $oldDest)
            $destRenamed = $true
        }
        [System.IO.Directory]::CreateDirectory($Dest) | Out-Null
        $newDestCreated = $true
        & $PopulateAction $Dest
        [System.IO.File]::WriteAllText((Join-Path $Dest ".sen-commit"), $Commit + "`n", [System.Text.UTF8Encoding]::new($false))
        if ($destRenamed -and (Test-Path -LiteralPath $oldDest)) {
            Remove-Item -LiteralPath $oldDest -Recurse -Force -ErrorAction SilentlyContinue
        }
        return [pscustomobject]@{ Success = $true; Error = $null }
    }
    catch {
        if ($newDestCreated -and (Test-Path -LiteralPath $Dest)) {
            Remove-Item -LiteralPath $Dest -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($destRenamed -and (Test-Path -LiteralPath $oldDest)) {
            try { [System.IO.Directory]::Move($oldDest, $Dest) } catch { <# Keep .sen-old intact if rollback move fails #> }
        }
        return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message }
    }
}

function Update-SenSinglePackage {
    param([string]$Workspace, [string]$Id, [object[]]$CatalogPackages, [scriptblock]$Git)
    $lock = Read-SenLock -Workspace $Workspace
    $pkg = $CatalogPackages | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if ($null -eq $pkg) {
        if (-not ($lock.packages.ContainsKey($Id) -and $lock.packages[$Id].repo)) {
            return [pscustomobject]@{ Id = $Id; Status = "failed"; Commit = $null; Error = "Package '$Id' not found in catalog" }
        }
        $destRel = if ($lock.packages[$Id].dest) { [string]$lock.packages[$Id].dest } else { ".agents/plugins/$Id" }
        $pkg = [pscustomobject]@{ id = $Id; repo = $lock.packages[$Id].repo; subPath = $lock.packages[$Id].subPath; dest = $destRel }
    }
    $dest = Join-Path -Path $Workspace -ChildPath ([string]$pkg.dest)
    $currentCommit = Resolve-SenInstalledCommit -Lock $lock -Id $Id -Dest $dest

    if (Test-Path -LiteralPath $dest) {
        $bk = New-SenPackageBackup -Workspace $Workspace -Id $Id -Dest $dest -Commit $currentCommit
        if (-not $bk.Success) {
            return [pscustomobject]@{ Id = $Id; Status = "failed"; Commit = $currentCommit; Error = "Backup failed: $($bk.Error)" }
        }
    }

    $tmpRoot = New-SenTempDir
    $cloneTmp = Join-Path $tmpRoot "src"
    $repo = if ($lock.packages[$Id] -and $lock.packages[$Id].repo) { [string]$lock.packages[$Id].repo } else { [string]$pkg.repo }
    try {
        $r = & $Git @("clone", "--depth", "1", "--quiet", $repo, $cloneTmp)
        if ($r.ExitCode -ne 0) {
            return [pscustomobject]@{ Id = $Id; Status = "failed"; Commit = $currentCommit; Error = "git clone failed for $($repo): $($r.Output)" }
        }
        $newCommit = Get-SenGitCommit -Path $cloneTmp -Git $Git
        $src = if ([string]::IsNullOrEmpty([string]$pkg.subPath)) { $cloneTmp } else { Join-Path $cloneTmp ([string]$pkg.subPath) }
        if (-not (Test-Path -LiteralPath $src)) {
            return [pscustomobject]@{ Id = $Id; Status = "failed"; Commit = $currentCommit; Error = "subPath '$($pkg.subPath)' not found in $repo" }
        }

        $swap = Invoke-SenAtomicDestSwap -Dest $dest -Commit $newCommit -PopulateAction {
            param($targetDest)
            if ($Id -ne "sen-method") {
                Copy-SenTree -Source $src -Destination $targetDest
                return
            }
            $senPayload = Get-SenSelfPayloadNames
            foreach ($item in Get-ChildItem -LiteralPath $src -Force) {
                if (($senPayload -contains $item.Name) -or ($item.Name -like "README*")) {
                    Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $targetDest $item.Name) -Recurse -Force
                }
            }
        }
        if (-not $swap.Success) {
            return [pscustomobject]@{ Id = $Id; Status = "failed"; Commit = $currentCommit; Error = "Install into dest failed: $($swap.Error)" }
        }

        $lock = Read-SenLock -Workspace $Workspace
        $lock.packages[$Id] = [ordered]@{
            repo        = $repo
            subPath     = $pkg.subPath
            commit      = $newCommit
            installedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        Write-SenLock -Workspace $Workspace -Lock $lock
        return [pscustomobject]@{ Id = $Id; Status = "updated"; Commit = $newCommit; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Id = $Id; Status = "failed"; Commit = $currentCommit; Error = $_.Exception.Message }
    }
    finally {
        if (Test-Path -LiteralPath $tmpRoot) {
            Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
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
        $results.Add((Update-SenSinglePackage -Workspace $Workspace -Id $id -CatalogPackages $catalogPackages -Git $Git))
    }
    return @($results.ToArray())
}

function Restore-SenPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Workspace, [Parameter(Mandatory = $true)][string]$Id)
    try {
        $catalogPackages = Get-SenPackagesCatalog
        $pkg = $catalogPackages | Where-Object { $_.id -eq $Id } | Select-Object -First 1
        $lock = Read-SenLock -Workspace $Workspace
        $dest = if ($null -ne $pkg) { Join-Path -Path $Workspace -ChildPath ([string]$pkg.dest) }
        elseif ($lock.packages.ContainsKey($Id) -and $lock.packages[$Id].dest) { Join-Path -Path $Workspace -ChildPath ([string]$lock.packages[$Id].dest) }
        else {
            $candSkill = Join-Path -Path $Workspace -ChildPath (".agents/skills/" + $Id)
            if (Test-Path -LiteralPath $candSkill) { $candSkill } else { Join-Path -Path $Workspace -ChildPath (".agents/plugins/" + $Id) }
        }
        $backups = @(Get-SenPackageBackups -Workspace $Workspace -Id $Id)
        if ($backups.Count -eq 0) {
            return [pscustomobject]@{ Id = $Id; Status = "failed"; Commit = $null; Error = "No backups found for package '$Id'" }
        }
        $targetBackup = $backups[0]
        $restoredCommit = $targetBackup.Commit
        $backupCommitFile = Join-Path $targetBackup.Directory.FullName ".sen-commit"
        if (([string]::IsNullOrEmpty($restoredCommit) -or $restoredCommit -eq "unknown") -and (Test-Path -LiteralPath $backupCommitFile)) {
            $restoredCommit = ([System.IO.File]::ReadAllText($backupCommitFile)).Trim()
        }
        if (Test-Path -LiteralPath $dest) {
            $currCommit = Resolve-SenInstalledCommit -Lock $lock -Id $Id -Dest $dest
            $preBk = New-SenPackageBackup -Workspace $Workspace -Id $Id -Dest $dest -Commit $currCommit
            if (-not $preBk.Success) {
                return [pscustomobject]@{ Id = $Id; Status = "failed"; Commit = $null; Error = "Pre-restore backup failed: $($preBk.Error)" }
            }
        }
        $swap = Invoke-SenAtomicDestSwap -Dest $dest -Commit $restoredCommit -PopulateAction {
            param($targetDest)
            Copy-SenTree -Source $targetBackup.Directory.FullName -Destination $targetDest -Exclude @(".git", ".sen-backup-meta.json")
        }
        if (-not $swap.Success) {
            return [pscustomobject]@{ Id = $Id; Status = "failed"; Commit = $null; Error = "Restore failed: $($swap.Error)" }
        }
        $lock = Read-SenLock -Workspace $Workspace
        $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        if ($lock.packages.ContainsKey($Id)) {
            $lock.packages[$Id].commit = $restoredCommit
            $lock.packages[$Id].installedAt = $now
        }
        else {
            $lock.packages[$Id] = [ordered]@{ repo = $pkg.repo; subPath = $pkg.subPath; commit = $restoredCommit; installedAt = $now }
        }
        Write-SenLock -Workspace $Workspace -Lock $lock
        return [pscustomobject]@{ Id = $Id; Status = "restored"; Commit = $restoredCommit; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Id = $Id; Status = "failed"; Commit = $null; Error = $_.Exception.Message }
    }
}

Export-ModuleMember -Function Get-SenLockPath, ConvertTo-SenHashtable, Read-SenLock, Write-SenLock, Install-SenPackage, Install-SenCreativePack, Install-SenSelf, Get-SenPackagesCatalog, New-SenPackageBackup, Get-SenPackageBackups, Get-SenUpdateStatus, Update-SenPackages, Restore-SenPackage
