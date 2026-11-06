# tests/Update.Tests.ps1
# Pure ASCII tests for update status, check-updates script, backup/restore and schedule registration

. "$PSScriptRoot/Assert.ps1"

$senModule = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/Sen.psm1"
$checkScript = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/check-updates.ps1"
$registerScript = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/register-schedule.ps1"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "..")).Path
Import-Module -Name $senModule -Force

function New-UpdateTempDir {
    param([string]$Suffix = "")
    $guid = [System.Guid]::NewGuid().ToString("N").Substring(0, 8)
    $p = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("sen-upd-" + $guid + $Suffix)
    [System.IO.Directory]::CreateDirectory($p) | Out-Null
    return $p
}

function Remove-UpdateTempDir {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-UpdateFakeGit {
    param(
        [hashtable]$RemoteHeads = @{},
        [string[]]$FailClones = @(),
        [string]$CloneCommit = "new222commit",
        [string[]]$LogLines = @("feat: support zero-token notice", "fix: handle edge cases"),
        [hashtable]$CallCounter = @{ Count = 0 }
    )
    $remotes = $RemoteHeads
    $fail = $FailClones
    $commit = $CloneCommit
    $logs = $LogLines
    $counter = $CallCounter

    return {
        param([string[]]$GitArgs)
        $counter.Count++

        if ($GitArgs[0] -eq "ls-remote") {
            $repo = $GitArgs[1]
            if ($remotes.ContainsKey($repo)) {
                $head = $remotes[$repo]
                return [pscustomobject]@{ ExitCode = 0; Output = "$head`tHEAD" }
            }
            return [pscustomobject]@{ ExitCode = 0; Output = "defaultHead111`tHEAD" }
        }

        if ($GitArgs[0] -eq "clone") {
            $repo = $GitArgs[$GitArgs.Count - 2]
            $target = $GitArgs[$GitArgs.Count - 1]
            foreach ($f in $fail) {
                if ($repo -like "*$f*") {
                    return [pscustomobject]@{ ExitCode = 128; Output = "fatal: clone failed for $repo" }
                }
            }
            [System.IO.Directory]::CreateDirectory($target) | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $target "SKILL.md"), "content from $repo")
            [System.IO.Directory]::CreateDirectory((Join-Path $target ".git")) | Out-Null
            return [pscustomobject]@{ ExitCode = 0; Output = "" }
        }

        if ($GitArgs -contains "rev-parse") {
            return [pscustomobject]@{ ExitCode = 0; Output = $commit }
        }

        if ($GitArgs -contains "log") {
            return [pscustomobject]@{ ExitCode = 0; Output = ($logs -join "`n") }
        }

        return [pscustomobject]@{ ExitCode = 1; Output = "unsupported fake git call" }
    }.GetNewClosure()
}

Test "Get-SenUpdateStatus reports HasUpdate=true when remote HEAD differs from lock commit" {
    $ws = New-UpdateTempDir
    try {
        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $null
            packages        = @{
                "superpowers" = @{
                    repo        = "https://github.com/obra/superpowers.git"
                    subPath     = ""
                    commit      = "aaa111"
                    installedAt = "2026-11-01T00:00:00Z"
                }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        $git = New-UpdateFakeGit -RemoteHeads @{ "https://github.com/obra/superpowers.git" = "bbb222" } -CloneCommit "bbb222" -LogLines @("feat: update superpowers")
        $status = Get-SenUpdateStatus -Workspace $ws -Git $git

        Assert-Equal 1 @($status).Count
        Assert-Equal "superpowers" $status[0].Id
        Assert-Equal "aaa111" $status[0].Current
        Assert-Equal "bbb222" $status[0].Latest
        Assert-Equal $true $status[0].HasUpdate
        Assert-True ($status[0].Summary -match "update superpowers") "summary contains commit message"
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "Get-SenUpdateStatus reports HasUpdate=false when remote HEAD matches lock commit" {
    $ws = New-UpdateTempDir
    try {
        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $null
            packages        = @{
                "superpowers" = @{
                    repo        = "https://github.com/obra/superpowers.git"
                    subPath     = ""
                    commit      = "aaa111"
                    installedAt = "2026-11-01T00:00:00Z"
                }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        $git = New-UpdateFakeGit -RemoteHeads @{ "https://github.com/obra/superpowers.git" = "aaa111" }
        $status = Get-SenUpdateStatus -Workspace $ws -Git $git

        Assert-Equal 1 @($status).Count
        Assert-Equal $false $status[0].HasUpdate
        Assert-Equal "aaa111" $status[0].Latest
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "check-updates.ps1 writes sen-update-notice.md when updates exist and gate passes" {
    $ws = New-UpdateTempDir
    try {
        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $null
            packages        = @{
                "superpowers" = @{
                    repo        = "https://github.com/obra/superpowers.git"
                    subPath     = ""
                    commit      = "aaa111"
                    installedAt = "2026-11-01T00:00:00Z"
                }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        $git = New-UpdateFakeGit -RemoteHeads @{ "https://github.com/obra/superpowers.git" = "bbb222" } -CloneCommit "bbb222" -LogLines @("feat: superpowers v2")
        & $checkScript -Workspace $ws -Git $git

        $noticePath = Join-Path $ws ".agents/rules/sen-update-notice.md"
        Assert-True (Test-Path -LiteralPath $noticePath) "notice file created"

        $fInfo = Get-Item -LiteralPath $noticePath
        Assert-True ($fInfo.Length -le 800) "notice file <= 800 bytes (was $($fInfo.Length))"

        $content = [System.IO.File]::ReadAllText($noticePath, [System.Text.Encoding]::UTF8)
        $expectedSentence = "Mention these updates once, in the user's language, and offer to run the sen-update skill."
        Assert-True ($content.Contains($expectedSentence)) "must contain required exact sentence"
        Assert-True ($content.Contains("superpowers")) "mentions superpowers package"

        $updatedLock = Read-SenLock -Workspace $ws
        Assert-True (-not [string]::IsNullOrEmpty($updatedLock.lastUpdateCheck)) "lastUpdateCheck updated"
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "check-updates.ps1 deletes notice file when all packages are up to date and gate passes" {
    $ws = New-UpdateTempDir
    try {
        $eightDaysAgo = [DateTime]::UtcNow.AddDays(-8).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $eightDaysAgo
            packages        = @{
                "superpowers" = @{
                    repo        = "https://github.com/obra/superpowers.git"
                    subPath     = ""
                    commit      = "aaa111"
                    installedAt = "2026-10-01T00:00:00Z"
                }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        # Pre-create old notice file
        $noticePath = Join-Path $ws ".agents/rules/sen-update-notice.md"
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($noticePath)) | Out-Null
        [System.IO.File]::WriteAllText($noticePath, "old notice")

        $git = New-UpdateFakeGit -RemoteHeads @{ "https://github.com/obra/superpowers.git" = "aaa111" }
        & $checkScript -Workspace $ws -Git $git

        Assert-True (-not (Test-Path -LiteralPath $noticePath)) "notice file removed when no updates"

        $updatedLock = Read-SenLock -Workspace $ws
        Assert-True ($updatedLock.lastUpdateCheck -ne $eightDaysAgo) "lastUpdateCheck refreshed to now"
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "check-updates.ps1 exits early without git calls when lastUpdateCheck was 2 days ago" {
    $ws = New-UpdateTempDir
    try {
        $twoDaysAgo = [DateTime]::UtcNow.AddDays(-2).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $twoDaysAgo
            packages        = @{
                "superpowers" = @{
                    repo        = "https://github.com/obra/superpowers.git"
                    subPath     = ""
                    commit      = "aaa111"
                    installedAt = "2026-10-01T00:00:00Z"
                }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        $counter = @{ Count = 0 }
        $git = New-UpdateFakeGit -RemoteHeads @{ "https://github.com/obra/superpowers.git" = "bbb222" } -CallCounter $counter
        & $checkScript -Workspace $ws -Git $git

        Assert-Equal 0 $counter.Count "git must not be called when under 7 days"
        $noticePath = Join-Path $ws ".agents/rules/sen-update-notice.md"
        Assert-True (-not (Test-Path -LiteralPath $noticePath)) "no notice file written"

        $currentLock = Read-SenLock -Workspace $ws
        Assert-Equal $twoDaysAgo $currentLock.lastUpdateCheck "lastUpdateCheck unchanged"
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "check-updates.ps1 with -Force bypasses 7-day gate" {
    $ws = New-UpdateTempDir
    try {
        $oneHourAgo = [DateTime]::UtcNow.AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $oneHourAgo
            packages        = @{
                "superpowers" = @{
                    repo        = "https://github.com/obra/superpowers.git"
                    subPath     = ""
                    commit      = "aaa111"
                    installedAt = "2026-10-01T00:00:00Z"
                }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        $counter = @{ Count = 0 }
        $git = New-UpdateFakeGit -RemoteHeads @{ "https://github.com/obra/superpowers.git" = "bbb222" } -CloneCommit "bbb222" -CallCounter $counter
        & $checkScript -Workspace $ws -Force -Git $git

        Assert-True ($counter.Count -gt 0) "git called when -Force is passed"
        $noticePath = Join-Path $ws ".agents/rules/sen-update-notice.md"
        Assert-True (Test-Path -LiteralPath $noticePath) "notice written with -Force"

        $updatedLock = Read-SenLock -Workspace $ws
        Assert-True ($updatedLock.lastUpdateCheck -ne $oneHourAgo) "lastUpdateCheck refreshed"
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "Update-SenPackages creates backup and restores on clone failure" {
    $ws = New-UpdateTempDir
    try {
        $dest = Join-Path $ws ".agents/plugins/superpowers"
        [System.IO.Directory]::CreateDirectory($dest) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dest "SKILL.md"), "original superpowers v1")
        [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), "old111`n")

        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $null
            packages        = @{
                "superpowers" = @{
                    repo        = "https://github.com/obra/superpowers.git"
                    subPath     = ""
                    commit      = "old111"
                    installedAt = "2026-10-01T00:00:00Z"
                }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        $git = New-UpdateFakeGit -FailClones @("superpowers")
        $res = Update-SenPackages -Workspace $ws -Ids @("superpowers") -Git $git

        Assert-Equal 1 @($res).Count
        Assert-Equal "failed" $res[0].Status

        # Backup exists
        $backupDirs = @(Get-ChildItem -LiteralPath (Join-Path $ws ".agents/.sen-backup") -Directory | Where-Object { $_.Name -like "superpowers-old111-*" })
        Assert-True ($backupDirs.Count -gt 0) "backup directory created"
        Assert-Equal "original superpowers v1" ([System.IO.File]::ReadAllText((Join-Path $backupDirs[0].FullName "SKILL.md")))

        # Package dest restored
        Assert-Equal "original superpowers v1" ([System.IO.File]::ReadAllText((Join-Path $dest "SKILL.md")))
        Assert-Equal "old111" ([System.IO.File]::ReadAllText((Join-Path $dest ".sen-commit"))).Trim()

        # Lock unchanged
        $lockBack = Read-SenLock -Workspace $ws
        Assert-Equal "old111" $lockBack.packages["superpowers"].commit
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "Update-SenPackages updates package, refreshes .sen-commit and lock" {
    $ws = New-UpdateTempDir
    try {
        $dest = Join-Path $ws ".agents/plugins/superpowers"
        [System.IO.Directory]::CreateDirectory($dest) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dest "SKILL.md"), "original superpowers v1")
        [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), "old111`n")

        # Sibling file that should not be touched
        $safetyPath = Join-Path $ws ".agents/rules/safety.md"
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($safetyPath)) | Out-Null
        [System.IO.File]::WriteAllText($safetyPath, "untouched safety rule")

        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $null
            packages        = @{
                "superpowers" = @{
                    repo        = "https://github.com/obra/superpowers.git"
                    subPath     = ""
                    commit      = "old111"
                    installedAt = "2026-10-01T00:00:00Z"
                }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        $git = New-UpdateFakeGit -CloneCommit "new222"
        $res = Update-SenPackages -Workspace $ws -Ids @("superpowers") -Git $git

        Assert-Equal 1 @($res).Count
        Assert-Equal "updated" $res[0].Status
        Assert-Equal "new222" $res[0].Commit

        # Backup exists
        $backupDirs = @(Get-ChildItem -LiteralPath (Join-Path $ws ".agents/.sen-backup") -Directory | Where-Object { $_.Name -like "superpowers-old111-*" })
        Assert-True ($backupDirs.Count -gt 0) "backup exists"

        # Dest updated
        Assert-True (Test-Path -LiteralPath (Join-Path $dest "SKILL.md")) "SKILL.md in dest"
        Assert-Equal "new222" ([System.IO.File]::ReadAllText((Join-Path $dest ".sen-commit"))).Trim()

        # Lock updated
        $lockBack = Read-SenLock -Workspace $ws
        Assert-Equal "new222" $lockBack.packages["superpowers"].commit

        # Sibling files outside dest untouched
        Assert-Equal "untouched safety rule" ([System.IO.File]::ReadAllText($safetyPath))
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "Restore-SenPackage reverts to most recent backup, refreshes .sen-commit and lock" {
    $ws = New-UpdateTempDir
    try {
        $dest = Join-Path $ws ".agents/plugins/superpowers"
        [System.IO.Directory]::CreateDirectory($dest) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dest "SKILL.md"), "original superpowers v1")
        [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), "old111`n")

        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $null
            packages        = @{
                "superpowers" = @{
                    repo        = "https://github.com/obra/superpowers.git"
                    subPath     = ""
                    commit      = "old111"
                    installedAt = "2026-10-01T00:00:00Z"
                }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        # First update to new222
        $git = New-UpdateFakeGit -CloneCommit "new222"
        $updateRes = Update-SenPackages -Workspace $ws -Ids @("superpowers") -Git $git
        Assert-Equal "updated" $updateRes[0].Status
        Assert-Equal "new222" (Read-SenLock -Workspace $ws).packages["superpowers"].commit

        # Now restore
        $restoreRes = Restore-SenPackage -Workspace $ws -Id "superpowers"
        Assert-Equal "restored" $restoreRes.Status
        Assert-Equal "old111" $restoreRes.Commit

        # Verify dest has original content and commit
        Assert-Equal "original superpowers v1" ([System.IO.File]::ReadAllText((Join-Path $dest "SKILL.md")))
        Assert-Equal "old111" ([System.IO.File]::ReadAllText((Join-Path $dest ".sen-commit"))).Trim()

        # Verify lock has old commit
        $lockBack = Read-SenLock -Workspace $ws
        Assert-Equal "old111" $lockBack.packages["superpowers"].commit
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "register-schedule.ps1 -DryRun returns expected task name and action without registering" {
    $ws = Join-Path (New-UpdateTempDir) "My Project"
    [System.IO.Directory]::CreateDirectory($ws) | Out-Null
    try {
        $out = & $registerScript -Workspace $ws -DryRun
        Assert-Equal "Sen update check (My Project)" $out.TaskName
        Assert-True ($out.Action -match "check-updates\.ps1") "action points to check-updates.ps1"
        Assert-Equal $true $out.DryRun
    }
    finally {
        Remove-UpdateTempDir (Split-Path $ws -Parent)
    }
}

Test "check-updates.ps1 and Update-SenPackages work in workspace path with spaces and Vietnamese characters" {
    $viName = "D" + [char]0x1EF1 + " " + [char]0x00E1 + "n"
    $root = New-UpdateTempDir
    $ws = Join-Path $root ($viName + "\My Work")
    [System.IO.Directory]::CreateDirectory($ws) | Out-Null
    try {
        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $null
            packages        = @{
                "superpowers" = @{
                    repo        = "https://github.com/obra/superpowers.git"
                    subPath     = ""
                    commit      = "aaa111"
                    installedAt = "2026-11-01T00:00:00Z"
                }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        $dest = Join-Path $ws ".agents/plugins/superpowers"
        [System.IO.Directory]::CreateDirectory($dest) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dest "SKILL.md"), "superpowers v1")
        [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), "aaa111`n")

        $git = New-UpdateFakeGit -RemoteHeads @{ "https://github.com/obra/superpowers.git" = "bbb222" } -CloneCommit "bbb222"
        & $checkScript -Workspace $ws -Git $git

        $noticePath = Join-Path $ws ".agents/rules/sen-update-notice.md"
        Assert-True (Test-Path -LiteralPath $noticePath) "notice created in unicode path"

        # Update package
        $res = Update-SenPackages -Workspace $ws -Ids @("superpowers") -Git $git
        Assert-Equal "updated" $res[0].Status
        Assert-Equal "bbb222" (Read-SenLock -Workspace $ws).packages["superpowers"].commit
    }
    finally {
        Remove-UpdateTempDir $root
    }
}

Test "Atomic backup ignores .partial and missing meta on restore" {
    $ws = New-UpdateTempDir
    try {
        $dest = Join-Path $ws ".agents/plugins/superpowers"
        [System.IO.Directory]::CreateDirectory($dest) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dest "SKILL.md"), "v1")
        [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), "v1-commit`n")

        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $null
            packages        = @{
                "superpowers" = @{
                    repo        = "https://github.com/obra/superpowers.git"
                    subPath     = ""
                    commit      = "v1-commit"
                    installedAt = "2026-11-01T00:00:00Z"
                }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        # Make a valid backup
        $bk = New-SenPackageBackup -Workspace $ws -Id "superpowers" -Dest $dest -Commit "v1-commit"
        Assert-Equal $true $bk.Success
        Assert-True (-not $bk.BackupDir.EndsWith(".partial")) "final backup drops .partial"

        # Create an incomplete .partial backup
        $bkParent = Join-Path $ws ".agents/.sen-backup"
        $partialDir = Join-Path $bkParent "superpowers-v2-corrupt.partial"
        [System.IO.Directory]::CreateDirectory($partialDir) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $partialDir "SKILL.md"), "corrupt")

        # Create a backup lacking meta
        $noMetaDir = Join-Path $bkParent "superpowers-v3-nometa"
        [System.IO.Directory]::CreateDirectory($noMetaDir) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $noMetaDir "SKILL.md"), "nometa")

        # Restore must find v1-commit and ignore the partial/no-meta dirs
        $res = Restore-SenPackage -Workspace $ws -Id "superpowers"
        Assert-Equal "restored" $res.Status
        Assert-Equal "v1-commit" $res.Commit
        Assert-Equal "v1" ([System.IO.File]::ReadAllText((Join-Path $dest "SKILL.md")))
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "Restore selects backups by meta.id and never collides between sen and sen-method" {
    $ws = New-UpdateTempDir
    try {
        $destSen = Join-Path $ws ".agents/plugins/sen"
        $destMethod = Join-Path $ws ".agents/plugins/sen-method"
        [System.IO.Directory]::CreateDirectory($destSen) | Out-Null
        [System.IO.Directory]::CreateDirectory($destMethod) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $destSen "SKILL.md"), "sen content")
        [System.IO.File]::WriteAllText((Join-Path $destMethod "SKILL.md"), "sen-method content")

        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $null
            packages        = @{
                "sen"        = @{ repo = "r1"; subPath = ""; commit = "sen-c1"; dest = ".agents/plugins/sen" }
                "sen-method" = @{ repo = "r2"; subPath = ""; commit = "method-c2"; dest = ".agents/plugins/sen-method" }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        # Create backups for both
        $bk1 = New-SenPackageBackup -Workspace $ws -Id "sen" -Dest $destSen -Commit "sen-c1"
        $bk2 = New-SenPackageBackup -Workspace $ws -Id "sen-method" -Dest $destMethod -Commit "method-c2"
        Assert-True $bk1.Success
        Assert-True $bk2.Success

        # Overwrite dests with dirty content
        [System.IO.File]::WriteAllText((Join-Path $destSen "SKILL.md"), "dirty sen")
        [System.IO.File]::WriteAllText((Join-Path $destMethod "SKILL.md"), "dirty method")

        # Restore sen: must pick sen-c1, not method-c2
        $rSen = Restore-SenPackage -Workspace $ws -Id "sen"
        Assert-Equal "restored" $rSen.Status
        Assert-Equal "sen-c1" $rSen.Commit
        Assert-Equal "sen content" ([System.IO.File]::ReadAllText((Join-Path $destSen "SKILL.md")))

        # Restore sen-method: must pick method-c2
        $rMethod = Restore-SenPackage -Workspace $ws -Id "sen-method"
        Assert-Equal "restored" $rMethod.Status
        Assert-Equal "method-c2" $rMethod.Commit
        Assert-Equal "sen-method content" ([System.IO.File]::ReadAllText((Join-Path $destMethod "SKILL.md")))
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "Restore backs up dest first so restore can be rolled back" {
    $ws = New-UpdateTempDir
    try {
        $dest = Join-Path $ws ".agents/plugins/superpowers"
        [System.IO.Directory]::CreateDirectory($dest) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dest "SKILL.md"), "initial content v1")
        [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), "v1`n")

        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $null
            packages        = @{
                "superpowers" = @{ repo = "r"; subPath = ""; commit = "v1" }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        # Backup v1
        $bk1 = New-SenPackageBackup -Workspace $ws -Id "superpowers" -Dest $dest -Commit "v1"
        Assert-True $bk1.Success

        # Simulate update to v2
        Start-Sleep -Milliseconds 1100
        [System.IO.File]::WriteAllText((Join-Path $dest "SKILL.md"), "updated content v2")
        [System.IO.File]::WriteAllText((Join-Path $dest ".sen-commit"), "v2`n")
        $lock.packages["superpowers"].commit = "v2"
        Write-SenLock -Workspace $ws -Lock $lock

        # Restore to v1: this must backup v2 first
        Start-Sleep -Milliseconds 1100
        $r1 = Restore-SenPackage -Workspace $ws -Id "superpowers"
        Assert-Equal "restored" $r1.Status
        Assert-Equal "v1" $r1.Commit
        Assert-Equal "initial content v1" ([System.IO.File]::ReadAllText((Join-Path $dest "SKILL.md")))

        # Now call restore again: should restore v2 (the pre-restore backup of v2)
        Start-Sleep -Milliseconds 1100
        $r2 = Restore-SenPackage -Workspace $ws -Id "superpowers"
        Assert-Equal "restored" $r2.Status
        Assert-Equal "v2" $r2.Commit
        Assert-Equal "updated content v2" ([System.IO.File]::ReadAllText((Join-Path $dest "SKILL.md")))
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "Get-SenUpdateStatus handles ls-remote error gracefully without throwing and updates lastUpdateCheck" {
    $ws = New-UpdateTempDir
    try {
        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $null
            packages        = @{
                "superpowers" = @{ repo = "https://github.com/obra/superpowers.git"; subPath = ""; commit = "v1" }
            }
        }
        Write-SenLock -Workspace $ws -Lock $lock

        $failingGit = {
            param([string[]]$GitArgs)
            if ($GitArgs[0] -eq "ls-remote") {
                return [pscustomobject]@{ ExitCode = 128; Output = "fatal: could not resolve host" }
            }
            return [pscustomobject]@{ ExitCode = 1; Output = "error" }
        }

        # Should not throw
        $status = Get-SenUpdateStatus -Workspace $ws -Git $failingGit
        Assert-Equal 1 @($status).Count
        Assert-Equal $false $status[0].HasUpdate
        Assert-True ($status[0].Error -match "could not resolve host") "error reported in result"

        # check-updates.ps1 should run and update lastUpdateCheck even with failing git
        & $checkScript -Workspace $ws -Git $failingGit
        $lockAfter = Read-SenLock -Workspace $ws
        Assert-True (-not [string]::IsNullOrEmpty($lockAfter.lastUpdateCheck)) "lastUpdateCheck updated on git failure"
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}

Test "check-updates.ps1 enforces 800-byte limit with 30 packages with long ids" {
    $ws = New-UpdateTempDir
    try {
        $lock = @{
            lockVersion     = 1
            lastUpdateCheck = $null
            packages        = @{}
        }
        $remotes = @{}
        for ($i = 1; $i -le 30; $i++) {
            $longId = "extraordinarily-long-package-identifier-for-antigravity-testing-tool-$i"
            $repo = "https://example.com/repo-$i.git"
            $lock.packages[$longId] = @{
                repo        = $repo
                subPath     = ""
                commit      = "old-commit-sha-number-$i"
                installedAt = "2026-11-01T00:00:00Z"
            }
            $remotes[$repo] = "new-commit-sha-number-$i"
        }
        Write-SenLock -Workspace $ws -Lock $lock

        $git = New-UpdateFakeGit -RemoteHeads $remotes -CloneCommit "newcommit" -LogLines @("feat: update $i")
        & $checkScript -Workspace $ws -Force -Git $git

        $noticePath = Join-Path $ws ".agents/rules/sen-update-notice.md"
        Assert-True (Test-Path -LiteralPath $noticePath) "notice written"

        $fInfo = Get-Item -LiteralPath $noticePath
        Assert-True ($fInfo.Length -le 800) "notice length must be <= 800 bytes, was $($fInfo.Length)"

        $content = [System.IO.File]::ReadAllText($noticePath, [System.Text.Encoding]::UTF8)
        $expectedSentence = "Mention these updates once, in the user's language, and offer to run the sen-update skill."
        Assert-True ($content.Contains($expectedSentence)) "must contain exact required instruction sentence"
        Assert-True ($content.Contains("(+")) "must contain (+N more) indicator when truncated"
    }
    finally {
        Remove-UpdateTempDir $ws
    }
}
