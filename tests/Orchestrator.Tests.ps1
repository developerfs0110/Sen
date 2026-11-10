# tests/Orchestrator.Tests.ps1
# Unit & integration tests for Sen v0.3.0 Orchestrator, Task Manager (DAG + File Lock),
# Risk Scoring, Delivery Gate, Recovery, Quality Metrics, Backlog, Restore Point & 3-Layer Memory (ASCII-only)

. "$PSScriptRoot/Assert.ps1"

$senModule = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/Sen.psm1"
Import-Module $senModule -Force

$guardScript = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/guard.ps1"

function New-OrchTestWorkspace {
    $p = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("sen-orch-" + [Guid]::NewGuid().ToString("N").Substring(0, 10))
    [System.IO.Directory]::CreateDirectory($p) | Out-Null
    return $p
}

Test "Get-SenTaskRiskScore classifies shared component and 3+ files as Tier 2 and Auth/DB as Tier 3" {
    $r1 = Get-SenTaskRiskScore -Request "Update button padding" -FileCount 1
    Assert-Equal 1 $r1.Tier "Simple 1-file UI change should be Tier 1"

    $r2 = Get-SenTaskRiskScore -Request "Update button component" -FileCount 1 -SharedComponent
    Assert-Equal 2 $r2.Tier "Shared component blast radius should elevate 1-file change to Tier 2"

    $r3 = Get-SenTaskRiskScore -Request "Add Google OAuth login, just do it" -FileCount 1
    Assert-Equal 3 $r3.Tier "Auth risk must stay Tier 3 even with 'just do it' override"
    Assert-True $r3.HardFloorTier3 "HardFloorTier3 must be true for Auth"
}

Test "Task Manager DAG auto-promotes pending task to ready only when dependencies are done" {
    $ws = New-OrchTestWorkspace
    try {
        $t1 = New-SenTask -Workspace $ws -Id "T-1" -Title "Design schema" -Tier 3 -Assignee "arch" -AllowedPaths @("docs/specs/")
        $t2 = New-SenTask -Workspace $ws -Id "T-2" -Title "Implement API" -Tier 3 -Assignee "dev_be" -DependsOn @("T-1") -AllowedPaths @("src/api/")

        Assert-Equal "ready" $t1.status "T-1 without dependencies starts as ready"
        Assert-Equal "pending" $t2.status "T-2 with unfinished dependency T-1 starts as pending"

        $tryStartT2 = Start-SenTask -Workspace $ws -Id "T-2"
        Assert-True (-not $tryStartT2.Started) "T-2 must not start before T-1 is done"
        Assert-Equal "blocked_dependency" $tryStartT2.Status "Status should be blocked_dependency"

        $s1 = Start-SenTask -Workspace $ws -Id "T-1"
        Assert-True $s1.Started "T-1 should start"
        [void](Submit-SenTaskForReview -Workspace $ws -Id "T-1")

        # Attempt to complete without evidence command must fail
        $badRev = Complete-SenTaskReview -Workspace $ws -Id "T-1" -Passed $true -EvidenceCommand "" -ExitCode 0
        Assert-True (-not $badRev.Completed) "Review pass without EvidenceCommand must be rejected"

        $goodRev = Complete-SenTaskReview -Workspace $ws -Id "T-1" -Passed $true -Reviewer "tester" -EvidenceCommand "tests/run.ps1" -ExitCode 0
        Assert-True $goodRev.Completed "T-1 review with valid evidence should complete"

        $all = @(Get-SenTasks -Workspace $ws)
        $t2Updated = $all | Where-Object { $_.id -eq "T-2" } | Select-Object -First 1
        Assert-Equal "ready" $t2Updated.status "T-2 must auto-promote to ready once T-1 is done"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Task Manager File Lock prevents two Developers from modifying overlapping allowedPaths concurrently" {
    $ws = New-OrchTestWorkspace
    try {
        [void](New-SenTask -Workspace $ws -Id "DEV-A" -Title "Refactor auth service" -Assignee "dev_fe" -AllowedPaths @("src/services/auth.ts", "src/ui/"))
        [void](New-SenTask -Workspace $ws -Id "DEV-B" -Title "Update auth token handler" -Assignee "dev_be" -AllowedPaths @("src/services/"))
        [void](New-SenTask -Workspace $ws -Id "DEV-C" -Title "Build billing page" -Assignee "dev_be" -AllowedPaths @("src/billing/"))

        $startA = Start-SenTask -Workspace $ws -Id "DEV-A"
        Assert-True $startA.Started "DEV-A should start and acquire lock on src/services/auth.ts"

        $readyList = @(Get-SenReadyTasks -Workspace $ws)
        $bReady = $readyList | Where-Object { $_.Id -eq "DEV-B" } | Select-Object -First 1
        $cReady = $readyList | Where-Object { $_.Id -eq "DEV-C" } | Select-Object -First 1
        Assert-True (-not $bReady.IsReady) "DEV-B overlaps src/services/ with DEV-A and must be marked not ready"
        Assert-Equal "DEV-A" $bReady.FileConflictWith "DEV-B conflict should point to DEV-A"
        Assert-True $cReady.IsReady "DEV-C touches disjoint src/billing/ and must be ready"

        $startB = Start-SenTask -Workspace $ws -Id "DEV-B"
        Assert-True (-not $startB.Started) "Start-SenTask must block DEV-B due to file lock conflict"
        Assert-Equal "blocked_file_lock" $startB.Status "Status must be blocked_file_lock"

        $startC = Start-SenTask -Workspace $ws -Id "DEV-C"
        Assert-True $startC.Started "DEV-C should start in parallel without file conflict"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Rework tracking, Quality Metrics, Recovery State, and Delivery Gate work end-to-end" {
    $ws = New-OrchTestWorkspace
    try {
        # TASK-20 Fix 2: Delivery gate must block when 0 active tasks are registered
        $gateEmpty = Test-SenDeliveryGate -Workspace $ws
        Assert-True (-not $gateEmpty.Allowed) "Delivery gate must block when 0 active tasks are registered in tasks.json"

        [void](New-SenTask -Workspace $ws -Id "M-1" -Title "Core module" -AllowedPaths @("src/core/"))
        [void](Add-SenBacklogItem -Workspace $ws -Id "BL-1" -Title "Future idea" -Priority "P2")

        [void](Start-SenTask -Workspace $ws -Id "M-1")

        # Recovery state while M-1 is in_progress
        $rec1 = Get-SenRecoveryState -Workspace $ws
        Assert-True $rec1.needsRecovery "Recovery state should flag active in_progress task"
        Assert-Equal 1 $rec1.inProgressIds.Count "Should report 1 in_progress task"

        # Delivery gate must block while M-1 is not done
        $gate1 = Test-SenDeliveryGate -Workspace $ws
        Assert-True (-not $gate1.Allowed) "Delivery gate must block when M-1 is still in_progress"

        # Fail review once -> reworkCount increments to 1
        [void](Submit-SenTaskForReview -Workspace $ws -Id "M-1")
        $failRev = Complete-SenTaskReview -Workspace $ws -Id "M-1" -Passed $false -Reviewer "sec" -Notes "Missing input validation"
        Assert-Equal 1 $failRev.ReworkCount "ReworkCount should be 1 after failed review"

        # Pass review on second attempt
        [void](Submit-SenTaskForReview -Workspace $ws -Id "M-1")
        [void](Complete-SenTaskReview -Workspace $ws -Id "M-1" -Passed $true -Reviewer "tester" -EvidenceCommand "tests/run.ps1" -ExitCode 0)

        # Delivery gate now allows (backlog item BL-1 does not block active delivery)
        $gate2 = Test-SenDeliveryGate -Workspace $ws
        Assert-True $gate2.Allowed "Delivery gate should allow once all active tasks are done with verified evidence"

        # TASK-20 Fix 2: Delivery gate must block when all done tasks are older than SessionStartedAt
        $gateStaleSession = Test-SenDeliveryGate -Workspace $ws -SessionStartedAt "2099-01-01T00:00:00Z"
        Assert-True (-not $gateStaleSession.Allowed) "Delivery gate must block when no active tasks were verified in the current session"

        $metrics = Get-SenQualityMetrics -Workspace $ws
        Assert-Equal 100 $metrics.taskSuccessRatePct "Success rate should be 100%"
        Assert-Equal 0 $metrics.firstPassRatePct "First-pass rate should be 0% because M-1 had 1 rework"
        Assert-Equal 100 $metrics.reworkRatePct "Rework rate should be 100%"
        Assert-Equal 1 $metrics.backlogTasks "Backlog count should be 1"
        Assert-True (Test-Path -LiteralPath (Join-Path $ws "docs/TODO.md")) "Add-SenBacklogItem must create docs/TODO.md"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "New-SenRestorePoint and Restore-SenRestorePoint safely revert modified and newly created files" {
    $ws = New-OrchTestWorkspace
    try {
        $f1 = Join-Path $ws "app.txt"
        $f2 = Join-Path $ws "newfile.txt"
        [System.IO.File]::WriteAllText($f1, "original-v1", [System.Text.UTF8Encoding]::new($false))

        $rp = New-SenRestorePoint -Workspace $ws -Files @("app.txt", "newfile.txt") -Label "before-refactor"
        Assert-True (-not [string]::IsNullOrWhiteSpace($rp.Id)) "Restore point ID must be returned"

        # Modify f1 and create f2
        [System.IO.File]::WriteAllText($f1, "corrupted-v2", [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($f2, "unwanted-file", [System.Text.UTF8Encoding]::new($false))

        $restored = Restore-SenRestorePoint -Workspace $ws -Id $rp.Id
        Assert-True $restored.Restored "Restore-SenRestorePoint should succeed"
        Assert-Equal "original-v1" ([System.IO.File]::ReadAllText($f1)) "app.txt must be restored to original-v1"
        Assert-True (-not (Test-Path -LiteralPath $f2)) "newfile.txt that did not exist before must be removed on restore"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "3-Layer Memory stores and retrieves execution lessons and memory snapshot" {
    $ws = New-OrchTestWorkspace
    try {
        [void](Add-SenExecutionLesson -Workspace $ws -Category "PowerShell" -Problem "ExecutionPolicy blocked module load" -RootCause "Default Windows policy" -Solution "Use -ExecutionPolicy Bypass")
        $snap = Get-SenMemorySnapshot -Workspace $ws
        Assert-Equal 1 $snap.executionMemory.lessonCount "Should have 1 execution lesson recorded"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "guard.ps1 blocks direct write to .git/config and enforces Execution Contract allowedPaths when enabled" {
    $ws = New-OrchTestWorkspace
    try {
        [void](New-SenTask -Workspace $ws -Id "T-LOCKED" -Title "Edit UI only" -AllowedPaths @("src/ui/"))
        [void](Start-SenTask -Workspace $ws -Id "T-LOCKED")

        # 1. Test .git/config protection
        $gitCfgPayload = @{
            workspacePaths = @($ws)
            toolCall       = @{
                name = "write_file"
                args = @{ Path = (Join-Path $ws ".git/config") }
            }
        } | ConvertTo-Json -Depth 5 -Compress
        $outGit = $gitCfgPayload | powershell -NoProfile -ExecutionPolicy Bypass -File $guardScript | ConvertFrom-Json
        Assert-Equal "deny" $outGit.decision "guard.ps1 must block direct writes to .git/config"

        # 2. Test Execution Contract allowedPaths enforcement
        $outsideContractPayload = @{
            workspacePaths   = @($ws)
            enforceTaskPaths = $true
            toolCall         = @{
                name = "edit_file"
                args = @{ Path = (Join-Path $ws "src/db/schema.sql") }
            }
        } | ConvertTo-Json -Depth 5 -Compress
        $outContract = $outsideContractPayload | powershell -NoProfile -ExecutionPolicy Bypass -File $guardScript | ConvertFrom-Json
        Assert-Equal "deny" $outContract.decision "guard.ps1 must block file write outside active task allowedPaths when enforceTaskPaths is true"

        $insideContractPayload = @{
            workspacePaths   = @($ws)
            enforceTaskPaths = $true
            toolCall         = @{
                name = "edit_file"
                args = @{ Path = (Join-Path $ws "src/ui/Button.tsx") }
            }
        } | ConvertTo-Json -Depth 5 -Compress
        $outAllowed = $insideContractPayload | powershell -NoProfile -ExecutionPolicy Bypass -File $guardScript | ConvertFrom-Json
        Assert-Equal "ask" $outAllowed.decision "guard.ps1 must allow file write inside active task allowedPaths"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Measure-SenCodeHealth verifies Sen repo passes all 6 ISO/Sonar/PSScriptAnalyzer dimensions and catches smells" {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "..")).Path
    $selfHealth = Measure-SenCodeHealth -Path $repoRoot
    Assert-True $selfHealth.Healthy "Sen repository itself must pass all 6 Clean Code checks (got Score=$($selfHealth.Score), Rec=$($selfHealth.Recommendation))"
    Assert-Equal 100 $selfHealth.Score "Sen repository health score must be 100"
    Assert-Equal 0 $selfHealth.OversizedFiles.Count "0 oversized files"
    Assert-Equal 0 $selfHealth.LongFunctions.Count "0 long functions (>100 lines)"
    Assert-Equal 0 $selfHealth.DeepNesting.Count "0 deeply nested functions (>4 levels)"
    Assert-Equal 0 $selfHealth.DuplicateBlocks.Count "0 duplicate code blocks"
    Assert-Equal 0 $selfHealth.EmptyCatches.Count "0 undocumented empty catch blocks"
    Assert-Equal 0 $selfHealth.DeadFunctions.Count "0 dead functions"

    $ws = New-OrchTestWorkspace
    try {
        $bigLogic = Join-Path $ws "giant.ts"
        $uiFile = Join-Path $ws "dashboard.html"
        $smellyPs = Join-Path $ws "smelly.ps1"
        $lines850 = @(1..850 | ForEach-Object { "const x$_ = $_;" })
        $lines1200 = @(1..1200 | ForEach-Object { "<div>row $_</div>" })
        [System.IO.File]::WriteAllLines($bigLogic, $lines850, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllLines($uiFile, $lines1200, [System.Text.UTF8Encoding]::new($false))

        $psContent = @"
function Invoke-UnusedDeadHelper {
    if (`$true) {
        foreach (`$a in @(1..2)) {
            if (`$a -eq 1) {
                while (`$false) {
                    try {
                        if (`$a -gt 0) { Write-Output `$a }
                    } catch { }
                }
            }
        }
    }
}
"@
        [System.IO.File]::WriteAllText($smellyPs, $psContent, [System.Text.UTF8Encoding]::new($false))

        $h = Measure-SenCodeHealth -Path $ws
        Assert-True (-not $h.Healthy) "Workspace with code smells must be marked unhealthy"
        Assert-Equal 1 $h.OversizedFiles.Count "giant.ts (>800L) flagged; dashboard.html (1200L <= 1500L UI) allowed"
        Assert-Equal 1 $h.DeepNesting.Count "6-level nested function flagged (Sonar:S134/CWE-1121)"
        Assert-Equal 1 $h.EmptyCatches.Count "Bare catch {} flagged (PSAvoidUsingEmptyCatchBlock/CWE-1069)"
        Assert-Equal 1 $h.DeadFunctions.Count "Unreferenced Invoke-UnusedDeadHelper flagged (Sonar:S1144/CWE-561)"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Invoke-SenVnLawScan triages web/mobile apps and catches code-level red flags" {
    $ws = New-OrchTestWorkspace
    try {
        # 1. Level 0 static site
        $staticDir = Join-Path $ws "static-site"
        [System.IO.Directory]::CreateDirectory($staticDir) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $staticDir "index.html"), "<html><body><h1>Hello Portfolio</h1></body></html>")
        $s0 = Invoke-SenVnLawScan -Path $staticDir
        Assert-Equal 0 $s0.Level "Pure static site must be Level 0"
        Assert-True $s0.CompliantCodeLevel "Level 0 static site has no code red flags"

        # 2. Level 2 e-commerce + AI + static tracking without consent + expired ND 13/2023 citation
        $shopDir = Join-Path $ws "shop-app"
        [System.IO.Directory]::CreateDirectory($shopDir) | Out-Null
        $shopHtml = @"
<html>
<head>
  <script src="https://www.googletagmanager.com/gtag/js?id=G-12345"></script>
</head>
<body>
  <form action="/checkout"><input type="email" name="email" /><button>Add to cart</button></form>
  <footer>Tuan thu Nghi dinh 13/2023/ND-CP</footer>
</body>
</html>
"@
        [System.IO.File]::WriteAllText((Join-Path $shopDir "index.html"), $shopHtml)
        [System.IO.File]::WriteAllText((Join-Path $shopDir "chat.ts"), "const url = 'https://api.openai.com/v1/chat';")
        [System.IO.File]::WriteAllText((Join-Path $shopDir "pubspec.yaml"), "name: shop_mobile")
        [System.IO.File]::WriteAllText((Join-Path $shopDir "auth.dart"), "void signIn() { final r = '/login'; }")

        $s2 = Invoke-SenVnLawScan -Path $shopDir
        Assert-Equal 2 $s2.Level "Shop with checkout must be Level 2"
        Assert-True $s2.AI "AI signal must be detected"
        Assert-True $s2.MobileApp "Flutter pubspec.yaml must flag MobileApp"
        Assert-Equal "static" $s2.TrackingConsent "Static gtag script without consent gate must be flagged static"
        Assert-True (-not $s2.CompliantCodeLevel) "Red flags must mark CompliantCodeLevel = false"
        Assert-Equal 3 $s2.CodeRedFlags.Count "Must catch TRACKING_PRELOAD, MOBILE_AUTH_MISSING_ACCOUNT_DELETE, and EXPIRED_VIETNAM_LAW_CITATION"

        # 3. Test-SenDeliveryGate -CheckVnLaw blocks when CodeRedFlags exist
        $gate = Test-SenDeliveryGate -Workspace $ws -ProjectPath $shopDir -CheckVnLaw
        Assert-True (-not $gate.Allowed) "Delivery gate with -CheckVnLaw must block on code red flags"

        # 4. TASK-20 Fix 4: Bot/Backend personal data & receipt photo forwarding detection
        $botDir = Join-Path $ws "bot-app"
        [System.IO.Directory]::CreateDirectory($botDir) | Out-Null
        $botCode = "bot.on('message:photo', async (ctx) => { await ctx.api.forwardMessage(adminId, ctx.chat.id, ctx.message.message_id); });"
        [System.IO.File]::WriteAllText((Join-Path $botDir "handlers.js"), $botCode)
        $sBot = Invoke-SenVnLawScan -Path $botDir
        Assert-True $sBot.BotForwarding "Bot forwarding signal must be detected in handlers.js"
        Assert-Equal 1 $sBot.Level "Bot forwarding must raise triage level to at least 1"
        Assert-True (-not $sBot.CompliantCodeLevel) "Bot forwarding without privacy/consent notice must fail CompliantCodeLevel"
        Assert-Equal 1 @($sBot.CodeRedFlags | Where-Object { $_.Code -eq "BOT_DATA_FORWARDING_WITHOUT_CONSENT" }).Count "Must flag BOT_DATA_FORWARDING_WITHOUT_CONSENT"

        [System.IO.File]::WriteAllText((Join-Path $botDir "PRIVACY.md"), "# Chinh sach bao mat & bao ve du lieu ca nhan theo ND 356/2025/ND-CP")
        $sBotOk = Invoke-SenVnLawScan -Path $botDir
        Assert-True $sBotOk.BotForwarding "Bot forwarding signal still detected"
        Assert-True $sBotOk.CompliantCodeLevel "Bot forwarding with privacy/consent notice passes CompliantCodeLevel"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Security hardening invariants: no Invoke-Expression, DOM XSS escaped, and localhost CSRF protected" {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
    $senPsm1 = [System.IO.File]::ReadAllText((Join-Path $repoRoot "scripts/Sen.psm1"))
    Assert-True ($senPsm1 -notmatch '\bInvoke-Expression\b') "Sen.psm1 must not use Invoke-Expression"

    $officeHtml = [System.IO.File]::ReadAllText((Join-Path $repoRoot "office/index.html"))
    Assert-True ($officeHtml -match 'const\s+escapeHtml\s*=') "office/index.html must define escapeHtml for DOM XSS mitigation"

    $startOffice = [System.IO.File]::ReadAllText((Join-Path $repoRoot "scripts/start-office.ps1"))
    Assert-True ($startOffice -match '65536') "start-office.ps1 must enforce 64KB Content-Length cap"
    Assert-True ($startOffice -match 'forbidden origin') "start-office.ps1 must reject non-localhost Origin on POST"
}

Test "Direct unit coverage for Unlock-SenTask, Clear-SenTasks, Invoke-SenDialecticalAudit, and core helpers" {
    $ws = New-OrchTestWorkspace
    try {
        $jsonPath = Join-Path $ws "atomic.json"
        Write-SenAtomicJson -Path $jsonPath -InputObject @{ ok = $true }
        $readBack = Read-SenSafeJson -Path $jsonPath
        Assert-True ([bool]$readBack.ok) "Write-SenAtomicJson and Read-SenSafeJson roundtrip"
        Assert-True (Test-SenPathOverlap -PathsA @("src/api/user.ts") -PathsB @("src/api")) "Test-SenPathOverlap detects directory prefix overlap"

        [void](New-SenTask -Workspace $ws -Id "T-STUCK" -Title "Stuck Task" -AllowedPaths @("src/api"))
        [void](Start-SenTask -Workspace $ws -Id "T-STUCK")
        $unlocked = Unlock-SenTask -Workspace $ws -Id "T-STUCK"
        Assert-True $unlocked.Unlocked "Unlock-SenTask releases stuck in_progress task"
        Assert-Equal "ready" $unlocked.Task.status "Unlocked task transitions back to ready"

        Clear-SenTasks -Workspace $ws
        Assert-Equal 0 @(Get-SenTasks -Workspace $ws).Count "Clear-SenTasks empties tasks.json"

        [void](Add-SenExecutionLesson -Workspace $ws -Category "Test" -Problem "P" -Solution "S")
        $lessons = @(Get-SenExecutionLessons -Workspace $ws)
        Assert-Equal 1 $lessons.Count "Get-SenExecutionLessons returns stored lessons"

        $mdFile = Join-Path $ws "MANAGED.md"
        Assert-True (Update-SenManagedBlock -Path $mdFile -Content "Managed Rules") "Update-SenManagedBlock creates managed section"
        Assert-True (Remove-SenManagedBlock -Path $mdFile) "Remove-SenManagedBlock removes managed section"

        $lockPath = Get-SenLockPath -Workspace $ws
        Assert-True ($lockPath -match 'sen\.lock\.json$') "Get-SenLockPath resolves sen.lock.json"
        $ht = ConvertTo-SenHashtable -InputObject ([pscustomobject]@{ k = "v" })
        Assert-Equal "v" $ht["k"] "ConvertTo-SenHashtable converts PSCustomObject"
        Assert-True (@((Get-SenPackagesCatalog).packages).Count -ge 3) "Get-SenPackagesCatalog lists companion packages"
        Assert-Equal 0 @(Get-SenPackageBackups -Workspace $ws -Id "sen-method").Count "Get-SenPackageBackups returns empty on clean workspace"
        Assert-True (@(Get-SenSelfPayloadNames).Count -ge 4) "Get-SenSelfPayloadNames returns payload directories"

        $dial = Invoke-SenDialecticalAudit -Workspace $ws
        Assert-True $dial.Passed "Invoke-SenDialecticalAudit passes on clean workspace"
        Assert-Equal 100 $dial.Score "Invoke-SenDialecticalAudit scores 100 on clean workspace"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "TASK-21 Test-SenHungTasks and Clear-SenHungTasks detect and teardown hung tasks and stale subagents" {
    $ws = New-OrchTestWorkspace
    try {
        $rpAlias = New-SenRestorePoint -WorkspacePath $ws -Files @("node_modules/pkg/index.js", "src/ok.js") -Label "alias-and-heavy-skip"
        Assert-True (-not [string]::IsNullOrWhiteSpace($rpAlias.Id)) "New-SenRestorePoint accepts -WorkspacePath alias"
        Assert-Equal 1 $rpAlias.FileCount "New-SenRestorePoint skips heavy node_modules directory"

        [void](New-SenTask -Workspace $ws -Id "HUNG-01" -Title "Stuck background task" -AllowedPaths @("src/"))
        [void](Start-SenTask -Workspace $ws -Id "HUNG-01")
        $freshCheck = Test-SenHungTasks -WorkspacePath $ws -StaleMinutes 15
        Assert-True $freshCheck.Healthy "Fresh in_progress task must not be flagged as hung"

        $oldIso = [DateTime]::UtcNow.AddMinutes(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $tasks = @(Get-SenTasks -Workspace $ws)
        $tasks[0].updatedAt = $oldIso
        $tasks[0].createdAt = $oldIso
        [void](Save-SenTasks -Workspace $ws -Tasks $tasks -Internal)

        $subFile = Join-Path $ws ".agents/office/subagents.json"
        Write-SenAtomicJson -Path $subFile -InputObject @{
            subagents = @(
                @{ id = "sub-stale-01"; status = "running"; startedAt = $oldIso; updatedAt = $oldIso }
            )
        }

        $hungCheck = Test-SenHungTasks -Workspace $ws -StaleMinutes 15
        Assert-True (-not $hungCheck.Healthy) "Stale in_progress task and running subagent must be flagged unhealthy"
        Assert-Equal 1 $hungCheck.StaleTaskIds.Count "Should detect 1 hung task"
        Assert-Equal "HUNG-01" $hungCheck.StaleTaskIds[0] "Should report HUNG-01"
        Assert-Equal 1 $hungCheck.StaleSubagents.Count "Should detect 1 stale subagent"
        Assert-Equal "sub-stale-01" $hungCheck.StaleSubagents[0] "Should report sub-stale-01"

        $delivBlocked = Test-SenDeliveryGate -Workspace $ws -StaleMinutes 15
        Assert-True (-not $delivBlocked.Allowed) "Delivery gate must block when hung tasks or stale subagents exist"
        Assert-True (-not $delivBlocked.HungTasks.Healthy) "Delivery gate must expose HungTasks status"

        $cleared = Clear-SenHungTasks -Workspace $ws -StaleMinutes 15 -Resolution "reset_to_todo"
        Assert-Equal 2 $cleared.ClearedCount "Clear-SenHungTasks must clear both hung task and stale subagent"
        Assert-Equal "todo" $cleared.NewStatus "Resolution reset_to_todo transitions task to todo"

        $afterCheck = Test-SenHungTasks -Workspace $ws -StaleMinutes 15
        Assert-True $afterCheck.Healthy "Workspace must be healthy immediately after Clear-SenHungTasks"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "TASK-22 3-Signal Liveness Probe protects active long-running tasks and catches stdin deadlocks and idle zombies" {
    $ws = New-OrchTestWorkspace
    try {
        $oldIso = [DateTime]::UtcNow.AddMinutes(-45).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $recentIso = [DateTime]::UtcNow.AddMinutes(-2).ToString("yyyy-MM-ddTHH:mm:ssZ")

        [void](New-SenTask -Workspace $ws -Id "LONG-HB" -Title "Long task with heartbeat" -AllowedPaths @("docs/"))
        [void](New-SenTask -Workspace $ws -Id "LONG-FILE" -Title "Long task with file progress" -AllowedPaths @("src/feature/"))
        [void](New-SenTask -Workspace $ws -Id "STALLED-01" -Title "Truly stalled task" -AllowedPaths @("lib/"))
        [void](Start-SenTask -Workspace $ws -Id "LONG-HB")
        [void](Start-SenTask -Workspace $ws -Id "LONG-FILE")
        [void](Start-SenTask -Workspace $ws -Id "STALLED-01")

        $featDir = Join-Path $ws "src/feature"
        [System.IO.Directory]::CreateDirectory($featDir) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $featDir "active.js"), "console.log('alive');")

        $tasks = @(Get-SenTasks -Workspace $ws)
        foreach ($t in $tasks) {
            $t.createdAt = $oldIso
            $t.updatedAt = $oldIso
            if ($t.id -eq "LONG-HB") {
                $t | Add-Member -NotePropertyName "heartbeatAt" -NotePropertyValue $recentIso -Force
            }
        }
        [void](Save-SenTasks -Workspace $ws -Tasks $tasks -Internal)

        # Signal 1: Remove stalled task temporarily to verify active long-running tasks alone report Healthy = true
        $activeOnly = @($tasks | Where-Object { $_.id -ne "STALLED-01" })
        [void](Save-SenTasks -Workspace $ws -Tasks $activeOnly -Internal)
        $liveCheck = Test-SenHungTasks -Workspace $ws -StaleMinutes 15
        Assert-True $liveCheck.Healthy "Long-running tasks with active heartbeat or recent file writes must be Healthy"
        Assert-Equal 2 $liveCheck.ActiveLongRunningIds.Count "Both LONG-HB and LONG-FILE must be in ActiveLongRunningIds"
        Assert-Equal 0 $liveCheck.StaleTaskIds.Count "No active long-running task should be classified as StaleTaskIds"

        # Signal 2: Interactive stdin prompt detected immediately within 1 second
        $stdinCheck = Test-SenHungTasks -Workspace $ws -StaleMinutes 15 -LogContent "cmdlet New-SenRestorePoint at command pipeline position 1`nSupply values for the following parameters:`nWorkspace:"
        Assert-True (-not $stdinCheck.Healthy) "Interactive stdin prompt must immediately mark workspace unhealthy"
        Assert-True ($stdinCheck.DeadlockedItems.Count -ge 1) "DeadlockedItems must capture stdin prompt"

        # Signal 3 & Selective Teardown: Restore STALLED-01 + add idle and stale subagents
        [void](Save-SenTasks -Workspace $ws -Tasks $tasks -Internal)
        $subFile = Join-Path $ws ".agents/office/subagents.json"
        Write-SenAtomicJson -Path $subFile -InputObject @{
            subagents = @(
                @{ id = "sub-idle-01"; state = "idle"; updatedAt = $recentIso },
                @{ id = "sub-stalled-01"; state = "running"; startedAt = $oldIso; updatedAt = $oldIso }
            )
        }
        $mixedCheck = Test-SenHungTasks -Workspace $ws -StaleMinutes 15
        Assert-True (-not $mixedCheck.Healthy) "Stalled task and stalled subagent must be flagged"
        Assert-Equal 1 $mixedCheck.StaleTaskIds.Count "Only STALLED-01 is stale"
        Assert-Equal "STALLED-01" $mixedCheck.StaleTaskIds[0] "Stale task is STALLED-01"
        Assert-Equal 2 $mixedCheck.ActiveLongRunningIds.Count "LONG-HB and LONG-FILE remain protected"
        Assert-Equal 1 $mixedCheck.IdleSubagents.Count "sub-idle-01 detected as IdleSubagents"

        $selectiveClear = Clear-SenHungTasks -Workspace $ws -StaleMinutes 15 -Resolution "reset_to_todo"
        Assert-Equal 2 $selectiveClear.ProtectedLongRunningIds.Count "Clear-SenHungTasks must protect both active long-running tasks"
        Assert-Equal 1 $selectiveClear.ClearedTaskIds.Count "Only STALLED-01 is reset"
        Assert-Equal "STALLED-01" $selectiveClear.ClearedTaskIds[0] "Cleared task is STALLED-01"
        Assert-Equal 1 $selectiveClear.ClosedIdleSubagents.Count "Idle zombie subagent is closed"

        $postTasks = @(Get-SenTasks -Workspace $ws)
        $hbTask = $postTasks | Where-Object { $_.id -eq "LONG-HB" } | Select-Object -First 1
        $fileTask = $postTasks | Where-Object { $_.id -eq "LONG-FILE" } | Select-Object -First 1
        Assert-Equal "in_progress" $hbTask.status "LONG-HB must remain in_progress untouched"
        Assert-Equal "in_progress" $fileTask.status "LONG-FILE must remain in_progress untouched"
        Assert-True ($null -ne $mixedCheck.HungProcessIds) "Test-SenHungTasks must expose HungProcessIds array"
        Assert-True ($null -ne $selectiveClear.KilledProcessIds) "Clear-SenHungTasks must expose KilledProcessIds array"

        $pwshExe = if ((Get-Process -Id $PID).Path) { (Get-Process -Id $PID).Path } elseif (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
        $pArgs = if ($env:OS -eq 'Windows_NT') { @("-NoProfile", "-WindowStyle", "Hidden", "-Command", "Start-Sleep -Seconds 30 # Test-SenDeliveryGate $ws") } else { @("-NoProfile", "-Command", "Start-Sleep -Seconds 30 # Test-SenDeliveryGate $ws") }
        $dummy = if ($env:OS -eq 'Windows_NT') { Start-Process -FilePath $pwshExe -ArgumentList $pArgs -WindowStyle Hidden -PassThru } else { Start-Process -FilePath $pwshExe -ArgumentList $pArgs -PassThru }
        try {
            Start-Sleep -Seconds 7
            $osHung = Test-SenHungTasks -Workspace $ws -StaleMinutes 15 -MaxProcessSeconds 5
            Assert-True ($osHung.HungProcessIds -contains $dummy.Id) "Test-SenHungTasks must detect stuck OS PowerShell gate process"
            $osReap = Clear-SenHungTasks -Workspace $ws -StaleMinutes 15 -MaxProcessSeconds 5
            Assert-True ($osReap.KilledProcessIds -contains $dummy.Id) "Clear-SenHungTasks must kill stuck OS PowerShell gate process"
        }
        finally {
            if ($dummy -and (-not $dummy.HasExited)) { Stop-Process -Id $dummy.Id -Force -ErrorAction SilentlyContinue }
        }
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Get-SenProjectTechStack discovers 5-layer stack from manifests and recommends default stack for greenfield" {
    $ws = Join-Path ([System.IO.Path]::GetTempPath()) ("sen-stack-test-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
    [System.IO.Directory]::CreateDirectory($ws) | Out-Null
    try {
        $green = Get-SenProjectTechStack -Workspace $ws
        Assert-Equal $true $green.IsGreenfield "greenfield workspace has no manifests"
        Assert-True (([string]($green.Layers.Frontend -join ", ")).Contains("Recommend")) "greenfield frontend recommendation present"
        Assert-True ($green.RecommendedOptions.Count -ge 2) "greenfield recommended options present"

        $pkgJson = '{"dependencies":{"next":"15.0.0","react":"19.0.0","tailwindcss":"4.0.0","@prisma/client":"6.0.0"},"devDependencies":{"vitest":"2.0.0","@playwright/test":"1.49.0"}}'
        [System.IO.File]::WriteAllText((Join-Path $ws "package.json"), $pkgJson, [System.Text.UTF8Encoding]::new($false))
        $disc = Get-SenProjectTechStack -Workspace $ws
        Assert-Equal $false $disc.IsGreenfield "package.json discovered"
        Assert-True (($disc.Layers.Frontend -join ", ").Contains("Next.js")) "Next.js detected in Frontend layer"
        Assert-True (($disc.Layers.Database -join ", ").Contains("Prisma")) "Prisma detected in Database layer"
        Assert-True (($disc.Layers.Testing -join ", ").Contains("Playwright")) "Playwright detected in Testing layer"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Test-SenTargetCollision and Register-SenTaskQueue enforce 4-Signal lock and FIFO auto-queue" {
    $ws = Join-Path ([System.IO.Path]::GetTempPath()) ("sen-queue-test-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
    [System.IO.Directory]::CreateDirectory($ws) | Out-Null
    try {
        New-SenTask -Workspace $ws -Id "TASK-A" -Title "Active task on Sen.psm1" -Tier 2 -Assignee "dev_be" -AllowedPaths @("scripts/Sen.psm1") | Out-Null
        Start-SenTask -Workspace $ws -Id "TASK-A" | Out-Null

        $col1 = Test-SenTargetCollision -Workspace $ws -TargetPaths @("scripts/Sen.psm1") -SessionId "sess-b" -QuietWindowSeconds 0
        Assert-Equal $true $col1.HasCollision "collision detected when TASK-A locks scripts/Sen.psm1"
        Assert-Equal $false $col1.Signals.ActiveTaskLockFree "ActiveTaskLockFree is false on collision"

        $qEnq = Register-SenTaskQueue -Workspace $ws -Action "enqueue" -QueueId "TASK-B" -Title "Queued update on Sen.psm1" -Tier 2 -TargetPaths @("scripts/Sen.psm1")
        Assert-Equal 1 $qEnq.PendingCount "queue pending count is 1"
        Assert-Equal "queued" $qEnq.Items[0].status "TASK-B enqueued with status queued while collision active"

        Submit-SenTaskForReview -Workspace $ws -Id "TASK-A" | Out-Null
        Complete-SenTaskReview -Workspace $ws -Id "TASK-A" -Passed $true -Reviewer "tester" -EvidenceCommand "tests/run.ps1" -ExitCode 0 | Out-Null

        $col2 = Test-SenTargetCollision -Workspace $ws -TargetPaths @("scripts/Sen.psm1") -SessionId "sess-b" -QuietWindowSeconds 0
        Assert-Equal $false $col2.HasCollision "collision cleared once TASK-A is done"
        Assert-Equal $true $col2.PreviousSessionComplete "all 4 completion signals green"

        $qPop = Register-SenTaskQueue -Workspace $ws -Action "pop"
        Assert-True ($null -ne $qPop.PoppedItem) "queued task popped after collision clears"
        Assert-Equal "TASK-B" $qPop.PoppedItem.queueId "FIFO head is TASK-B"

        $qDone = Register-SenTaskQueue -Workspace $ws -Action "complete" -QueueId "TASK-B"
        Assert-Equal 0 $qDone.PendingCount "pending count is 0 after completion"
        [void](Register-SenTaskQueue -Workspace $ws -Action "clear")
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

