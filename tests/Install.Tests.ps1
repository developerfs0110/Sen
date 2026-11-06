# tests/Install.Tests.ps1
# Pure ASCII tests for lock file, package install and install.ps1 (no network)

. "$PSScriptRoot/Assert.ps1"

$senModule = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/Sen.psm1"
$installScript = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "../scripts/install.ps1") -ErrorAction SilentlyContinue)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "..")).Path
Import-Module -Name $senModule -Force

# Vietnamese "Du an" with diacritics, built from code points to keep this file ASCII.
$viName = "D" + [char]0x1EF1 + " " + [char]0x00E1 + "n"

function New-InstallTempDir {
    param([string]$Suffix = "")
    $guid = [System.Guid]::NewGuid().ToString("N").Substring(0, 8)
    $p = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("sen-inst-" + $guid + $Suffix)
    [System.IO.Directory]::CreateDirectory($p) | Out-Null
    return $p
}

function Remove-InstallTempDir {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Fake git: "clone" writes SKILL.md files into the target; rev-parse returns a fixed commit.
# Repos whose URL contains a string listed in $FailRepos fail with a 404 message.
function New-FakeGit {
    param([string[]]$FailRepos = @(), [string]$Commit = "abc1234def")
    $fail = $FailRepos
    $c = $Commit
    return {
        param([string[]]$GitArgs)
        if ($GitArgs[0] -eq "clone") {
            $repo = $GitArgs[$GitArgs.Count - 2]
            $target = $GitArgs[$GitArgs.Count - 1]
            foreach ($f in $fail) {
                if ($repo -like "*$f*") {
                    return [pscustomobject]@{ ExitCode = 128; Output = "fatal: repository '$repo' not found (404)" }
                }
            }
            foreach ($rel in @("SKILL.md", "skills/security-audit/SKILL.md", "plugins/vn-law-check/skills/vn-law-check/SKILL.md")) {
                $fp = Join-Path $target $rel
                [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($fp)) | Out-Null
                [System.IO.File]::WriteAllText($fp, "fake from $repo")
            }
            [System.IO.Directory]::CreateDirectory((Join-Path $target ".git")) | Out-Null
            return [pscustomobject]@{ ExitCode = 0; Output = "" }
        }
        if ($GitArgs -contains "rev-parse") {
            return [pscustomobject]@{ ExitCode = 0; Output = $c }
        }
        return [pscustomobject]@{ ExitCode = 1; Output = "unsupported fake git call" }
    }.GetNewClosure()
}

function Invoke-InstallScript {
    param([string]$Workspace, [scriptblock]$Git, [switch]$WithVnLawCheck)
    $lines = @(& $installScript.Path -Workspace $Workspace -SenSource $repoRoot -Git $Git -WithVnLawCheck:$WithVnLawCheck)
    $code = $LASTEXITCODE
    $last = $lines[$lines.Count - 1]
    return [pscustomobject]@{ ExitCode = $code; Json = ($last | ConvertFrom-Json); Lines = $lines }
}

$saPackage = [pscustomobject]@{ id = "security-audit"; repo = "https://github.com/cloudflare/security-audit-skill.git"; subPath = "skills/security-audit"; dest = ".agents/skills/security-audit"; required = $true }

Test "packages.json lists the three packages with verified subPaths" {
    $pk = Get-Content -LiteralPath (Join-Path $repoRoot "scripts/packages.json") -Raw | ConvertFrom-Json
    Assert-Equal 3 @($pk).Count
    Assert-Equal "skills/security-audit" (@($pk | Where-Object id -eq "security-audit")[0].subPath)
    Assert-Equal $true (@($pk | Where-Object id -eq "vn-law-check")[0].required)
    Assert-Equal ".agents/skills/vn-law-check" (@($pk | Where-Object id -eq "vn-law-check")[0].dest)
}

Test "Read-SenLock returns default when no lock exists" {
    $ws = New-InstallTempDir
    try {
        $lock = Read-SenLock -Workspace $ws
        Assert-True ($lock -is [hashtable]) "lock must be hashtable"
        Assert-Equal 1 $lock.lockVersion
        Assert-Equal 0 $lock.packages.Count
        Assert-Equal $null $lock.lastUpdateCheck
    } finally { Remove-InstallTempDir $ws }
}

Test "Write-SenLock then Read-SenLock round-trips and leaves no temp file" {
    $ws = New-InstallTempDir
    try {
        $lock = @{ lockVersion = 1; lastUpdateCheck = $null; packages = @{ "x" = @{ repo = "r"; subPath = ""; commit = "c1"; installedAt = "t" } } }
        Write-SenLock -Workspace $ws -Lock $lock
        $back = Read-SenLock -Workspace $ws
        Assert-Equal "c1" $back.packages["x"].commit
        $back.packages["x"].commit = "c2"
        Write-SenLock -Workspace $ws -Lock $back
        Assert-Equal "c2" (Read-SenLock -Workspace $ws).packages["x"].commit "overwrite existing lock"
        $left = @(Get-ChildItem -LiteralPath (Join-Path $ws ".agents") -File | Where-Object { $_.Name -ne "sen.lock.json" })
        Assert-Equal 0 $left.Count "no temp files left behind"
    } finally { Remove-InstallTempDir $ws }
}

Test "Install-SenPackage with fake clone returns installed and copies subPath only" {
    $ws = New-InstallTempDir
    try {
        $r = Install-SenPackage -Workspace $ws -Package $saPackage -Git (New-FakeGit)
        Assert-Equal "installed" $r.Status
        Assert-Equal "abc1234def" $r.Commit
        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".agents/skills/security-audit/SKILL.md")) "SKILL.md copied"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $ws ".agents/skills/security-audit/skills"))) "only subPath copied"
    } finally { Remove-InstallTempDir $ws }
}

Test "Install-SenPackage leaves existing dest unchanged and returns exists" {
    $ws = New-InstallTempDir
    try {
        $dest = Join-Path $ws ".agents/skills/security-audit"
        [System.IO.Directory]::CreateDirectory($dest) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dest "SKILL.md"), "user content")
        $r = Install-SenPackage -Workspace $ws -Package $saPackage -Git (New-FakeGit)
        Assert-Equal "exists" $r.Status
        Assert-Equal "unknown" $r.Commit
        Assert-Equal "user content" ([System.IO.File]::ReadAllText((Join-Path $dest "SKILL.md")))
    } finally { Remove-InstallTempDir $ws }
}

Test "Install-SenPackage returns failed with error on 404 and creates no dest" {
    $ws = New-InstallTempDir
    try {
        $r = Install-SenPackage -Workspace $ws -Package $saPackage -Git (New-FakeGit -FailRepos @("security-audit"))
        Assert-Equal "failed" $r.Status
        Assert-True ($r.Error -match "404") "error carries git message"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $ws ".agents/skills/security-audit"))) "no dest"
    } finally { Remove-InstallTempDir $ws }
}

Test "install.ps1 success writes lock with commits, safety.md and Sen payload" {
    $ws = Join-Path (New-InstallTempDir) "ws"
    try {
        $res = Invoke-InstallScript -Workspace $ws -Git (New-FakeGit)
        Assert-Equal 0 $res.ExitCode
        Assert-Equal $true $res.Json.lockWritten
        Assert-Equal $true $res.Json.safetyCreated
        Assert-Equal "installed" $res.Json.sen.status
        $lock = Read-SenLock -Workspace $ws
        Assert-Equal "abc1234def" $lock.packages["superpowers"].commit
        Assert-Equal "abc1234def" $lock.packages["security-audit"].commit
        Assert-Equal "abc1234def" $lock.packages["vn-law-check"].commit "vn-law-check installed by default"
        $senDir = Join-Path $ws ".agents/plugins/sen-method"
        Assert-True (Test-Path -LiteralPath (Join-Path $senDir "plugin.json")) "plugin.json copied"
        Assert-True (Test-Path -LiteralPath (Join-Path $senDir "scripts/Sen.psm1")) "scripts copied"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $senDir "tests"))) "tests excluded"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $senDir "docs"))) "docs excluded"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $senDir ".git"))) ".git excluded"
        $safety = [System.IO.File]::ReadAllText((Join-Path $ws ".agents/rules/safety.md"))
        Assert-True ($safety.Contains($ws)) "WORKSPACE_ROOT substituted"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $ws ".agents/rules/profile.md"))) "profile.md not created"
    } finally { Remove-InstallTempDir (Split-Path $ws -Parent) }
}

Test "install.ps1 with 404 on security-audit exits non-zero and writes no lock" {
    $ws = Join-Path (New-InstallTempDir) "ws"
    try {
        $res = Invoke-InstallScript -Workspace $ws -Git (New-FakeGit -FailRepos @("security-audit-skill"))
        Assert-True ($res.ExitCode -ne 0) "exit code must be non-zero"
        Assert-Equal $false $res.Json.lockWritten
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $ws ".agents/sen.lock.json"))) "no lock file"
        $sa = @($res.Json.packages | Where-Object id -eq "security-audit")[0]
        Assert-Equal "failed" $sa.status
        Assert-True ($sa.error -match "404") "error message reported"
    } finally { Remove-InstallTempDir (Split-Path $ws -Parent) }
}

Test "install.ps1 required vn-law-check failure blocks the lock" {
    $ws = Join-Path (New-InstallTempDir) "ws"
    try {
        $res = Invoke-InstallScript -Workspace $ws -Git (New-FakeGit -FailRepos @("vn-law-check"))
        Assert-True ($res.ExitCode -ne 0) "exit code must be non-zero when required vn-law-check fails"
        Assert-Equal $false $res.Json.lockWritten
        Assert-Equal "failed" (@($res.Json.packages | Where-Object id -eq "vn-law-check")[0].status)
    } finally { Remove-InstallTempDir (Split-Path $ws -Parent) }
}

Test "install.ps1 run twice: all exists, lock commits kept, safety untouched" {
    $ws = Join-Path (New-InstallTempDir) "ws"
    try {
        $first = Invoke-InstallScript -Workspace $ws -Git (New-FakeGit -Commit "first111")
        Assert-Equal 0 $first.ExitCode
        $safetyPath = Join-Path $ws ".agents/rules/safety.md"
        [System.IO.File]::WriteAllText($safetyPath, "user edited")
        $second = Invoke-InstallScript -Workspace $ws -Git (New-FakeGit -Commit "second222")
        Assert-Equal 0 $second.ExitCode
        Assert-Equal "exists" $second.Json.sen.status
        foreach ($p in @($second.Json.packages)) { Assert-Equal "exists" $p.status "package $($p.id)" }
        Assert-Equal $false $second.Json.safetyCreated
        Assert-Equal "user edited" ([System.IO.File]::ReadAllText($safetyPath))
        $lock = Read-SenLock -Workspace $ws
        Assert-Equal "first111" $lock.packages["superpowers"].commit
        Assert-Equal "first111" $lock.packages["security-audit"].commit
    } finally { Remove-InstallTempDir (Split-Path $ws -Parent) }
}

Test "install.ps1 works in a path with spaces and Vietnamese diacritics" {
    $root = New-InstallTempDir
    $ws = Join-Path $root ($viName + "\My Work")
    try {
        $res = Invoke-InstallScript -Workspace $ws -Git (New-FakeGit)
        Assert-Equal 0 $res.ExitCode
        Assert-Equal $ws $res.Json.workspace
        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".agents/sen.lock.json")) "lock written"
        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".agents/skills/security-audit/SKILL.md")) "package installed"
        $safety = [System.IO.File]::ReadAllText((Join-Path $ws ".agents/rules/safety.md"), [System.Text.Encoding]::UTF8)
        Assert-True ($safety.Contains($ws)) "unicode workspace path substituted"
    } finally { Remove-InstallTempDir $root }
}

Test "install.ps1 retry after partial failure records the first run's commit from .sen-commit" {
    $ws = Join-Path (New-InstallTempDir) "ws"
    try {
        $first = Invoke-InstallScript -Workspace $ws -Git (New-FakeGit -FailRepos @("security-audit-skill") -Commit "run1sha")
        Assert-True ($first.ExitCode -ne 0) "run 1 fails"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $ws ".agents/sen.lock.json"))) "no lock after run 1"
        $second = Invoke-InstallScript -Workspace $ws -Git (New-FakeGit -Commit "run2sha")
        Assert-Equal 0 $second.ExitCode
        Assert-Equal "exists" (@($second.Json.packages | Where-Object id -eq "superpowers")[0].status)
        $lock = Read-SenLock -Workspace $ws
        Assert-Equal "run1sha" $lock.packages["superpowers"].commit "superpowers keeps its real commit"
        Assert-Equal "run2sha" $lock.packages["security-audit"].commit
    } finally { Remove-InstallTempDir (Split-Path $ws -Parent) }
}

Test "install.ps1 with a Sen source lacking plugin.json fails without lock" {
    $root = New-InstallTempDir
    $ws = Join-Path $root "ws"
    $badSrc = Join-Path $root "badsrc"
    [System.IO.Directory]::CreateDirectory($badSrc) | Out-Null
    try {
        $lines = @(& $installScript.Path -Workspace $ws -SenSource $badSrc -Git (New-FakeGit))
        $code = $LASTEXITCODE
        $json = $lines[$lines.Count - 1] | ConvertFrom-Json
        Assert-Equal 1 $code
        Assert-Equal $false $json.lockWritten
        Assert-Equal "failed" $json.sen.status
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $ws ".agents/sen.lock.json"))) "no lock file"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $ws ".agents/plugins/sen-method"))) "no partial Sen dest"
    } finally { Remove-InstallTempDir $root }
}

function Invoke-SenGuardPs1 {
    param([string]$InputJson)
    $guardPath = (Resolve-Path -LiteralPath (Join-Path $repoRoot "scripts/guard.ps1")).Path
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$guardPath`""
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($InputJson)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    return ConvertFrom-Json -InputObject $out
}

Test "hooks.json and guard.ps1 are copied by Install-SenSelf and block destructive commands" {
    $ws = Join-Path (New-InstallTempDir) "ws"
    try {
        $res = Invoke-InstallScript -Workspace $ws -Git (New-FakeGit)
        Assert-Equal 0 $res.ExitCode
        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".agents/plugins/sen-method/hooks.json")) "hooks.json copied"
        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".agents/plugins/sen-method/scripts/guard.ps1")) "guard.ps1 copied"
        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".agents/plugins/sen-method/scripts/guard.sh")) "guard.sh copied"

        # Destructive commands must be hard-blocked with decision = deny
        foreach ($badCmd in @(
            "git push origin main --force",
            "git push -f origin main",
            "git reset --hard HEAD~1",
            "rm -rf /tmp/something",
            "Remove-Item -Path .\foo -Recurse -Force",
            "rmdir /s /q build",
            "git clean -fd",
            "git branch -D feature-x",
            "gh repo delete owner/repo",
            "find /var/tmp -name '*.log' -delete",
            "python -c `"import shutil; shutil.rmtree('dist')`"",
            "[System.IO.Directory]::Delete('C:\\temp\\build', `$true)",
            "node -e `"fs.rmSync('dist', {recursive:true})`"",
            "psql -c 'DROP TABLE users;'",
            "TRUNCATE TABLE orders"
        )) {
            $payload = @{ toolCall = @{ name = "run_command"; args = @{ CommandLine = $badCmd } } } | ConvertTo-Json -Compress
            $dec = Invoke-SenGuardPs1 -InputJson $payload
            Assert-Equal "deny" $dec.decision "must deny destructive command: $badCmd"
        }

        # write_file / edit_file outside workspacePaths must be denied; inside workspacePaths allowed (ask)
        $outsidePayload = @{
            workspacePaths = @($ws)
            toolCall = @{
                name = "write_file"
                args = @{ Path = "C:\Windows\System32\drivers\etc\hosts" }
            }
        } | ConvertTo-Json -Compress
        $outsideDec = Invoke-SenGuardPs1 -InputJson $outsidePayload
        Assert-Equal "deny" $outsideDec.decision "write_file outside workspacePaths must be denied"

        $insidePayload = @{
            workspacePaths = @($ws)
            toolCall = @{
                name = "edit_file"
                args = @{ Path = (Join-Path $ws "Code\app.js") }
            }
        } | ConvertTo-Json -Compress
        $insideDec = Invoke-SenGuardPs1 -InputJson $insidePayload
        Assert-Equal "ask" $insideDec.decision "edit_file inside workspacePaths must return ask"

        # Safe commands must return decision = ask
        foreach ($goodCmd in @(
            "git status",
            "git push origin main",
            "git branch -d merged-branch",
            "npm test",
            "Remove-Item -LiteralPath .\temp.txt"
        )) {
            $payload = @{ toolCall = @{ name = "run_command"; args = @{ CommandLine = $goodCmd } } } | ConvertTo-Json -Compress
            $dec = Invoke-SenGuardPs1 -InputJson $payload
            Assert-Equal "ask" $dec.decision "must allow/ask safe command: $goodCmd"
        }

        # Malformed JSON falls back to ask safely
        $badJsonDec = Invoke-SenGuardPs1 -InputJson "{not valid json"
        Assert-Equal "ask" $badJsonDec.decision "malformed json falls back to ask"

        # sen-method itself is recorded in sen.lock.json and .sen-commit
        $lock = Read-SenLock -Workspace $ws
        Assert-True ($lock.packages.ContainsKey("sen-method")) "sen-method recorded in sen.lock.json"
        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".agents/plugins/sen-method/.sen-commit")) "sen-method .sen-commit written"
    } finally { Remove-InstallTempDir (Split-Path $ws -Parent) }
}

