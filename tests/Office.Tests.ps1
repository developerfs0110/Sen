# tests/Office.Tests.ps1
# ASCII-only tests for sen-office v0.2.0 state engine, hooks, server, and 3D UI

. "$PSScriptRoot/Assert.ps1"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "..")).Path
Import-Module (Join-Path -Path $repoRoot -ChildPath "scripts/Sen.psm1") -Force

function New-OfficeTempDir {
    $d = Join-Path ([System.IO.Path]::GetTempPath()) ("sen-office-test-" + [Guid]::NewGuid().ToString("N"))
    [System.IO.Directory]::CreateDirectory($d) | Out-Null
    return $d
}

function Remove-OfficeTempDir([string]$Path) {
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        [System.IO.Directory]::Delete($Path, $true)
    }
}

Test "Protect-SenRedactedText masks Bearer tokens, API keys, passwords, JWTs, and URL credentials" {
    $raw = "curl -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc123456' " +
           "https://admin:mySecretPass@example.com/api?api_key=sk-proj-1234567890abcdef " +
           "GH_TOKEN=ghp_1234567890abcdefghij SLACK=xoxb-1234567890-abcdef password=supersecret"
    $red = Protect-SenRedactedText -Text $raw
    Assert-True (-not $red.Contains("eyJhbGciOi")) "JWT must be redacted"
    Assert-True (-not $red.Contains("mySecretPass")) "URL password must be redacted"
    Assert-True (-not $red.Contains("sk-proj-1234567890abcdef")) "sk- key must be redacted"
    Assert-True (-not $red.Contains("ghp_1234567890abcdefghij")) "ghp_ token must be redacted"
    Assert-True (-not $red.Contains("xoxb-1234567890-abcdef")) "Slack token must be redacted"
    Assert-True (-not $red.Contains("supersecret")) "password= value must be redacted"
    Assert-True ($red.Contains("[REDACTED]")) "redacted placeholder must appear"
}

Test "Get-SenOfficeConfig returns eco default and Set-SenOfficeConfig persists mode and port atomically" {
    $ws = New-OfficeTempDir
    try {
        $cfg0 = Get-SenOfficeConfig -Workspace $ws
        Assert-Equal "eco" $cfg0.mode "default mode is eco"
        Assert-Equal 47890 $cfg0.port "default port is 47890"

        $cfg1 = Set-SenOfficeConfig -Workspace $ws -Mode "full" -Port 48001
        Assert-Equal "full" $cfg1.mode "updated mode is full"
        Assert-Equal 48001 $cfg1.port "updated port is 48001"

        $cfg2 = Get-SenOfficeConfig -Workspace $ws
        Assert-Equal "full" $cfg2.mode "persisted mode is full"
        Assert-Equal 48001 $cfg2.port "persisted port is 48001"
    } finally { Remove-OfficeTempDir $ws }
}

Test "Write-SenOfficeEvent skips when mode is off, writes redacted JSONL when eco/full, and caps at 200 events" {
    $ws = New-OfficeTempDir
    try {
        Set-SenOfficeConfig -Workspace $ws -Mode "off" | Out-Null
        $w0 = Write-SenOfficeEvent -Workspace $ws -From "fe" -To "sys" -Lane "FE" -EcoText "Edit app.js"
        Assert-Equal $false $w0 "must return false when mode is off"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $ws ".agents/office/events.jsonl"))) "no events.jsonl created when off"

        Set-SenOfficeConfig -Workspace $ws -Mode "eco" | Out-Null
        $w1 = Write-SenOfficeEvent -Workspace $ws -From "be" -To "sys" -Lane "BE" -EcoText "Run with token=sk-1234567890abcdef" -Command "curl -H 'Bearer secret123456789'"
        Assert-Equal $true $w1 "must return true when mode is eco"

        $evs = @(Read-SenOfficeEvents -Workspace $ws)
        Assert-Equal 1 $evs.Count "1 event recorded"
        Assert-Equal "be" $evs[0].from
        Assert-True (-not $evs[0].ecoText.Contains("sk-1234567890abcdef")) "ecoText secret redacted"
        Assert-True (-not $evs[0].command.Contains("secret123456789")) "command secret redacted"

        for ($i = 1; $i -le 210; $i++) {
            Write-SenOfficeEvent -Workspace $ws -From "qa" -To "sys" -Lane "Test" -EcoText "Step $i" | Out-Null
        }
        $capped = @(Read-SenOfficeEvents -Workspace $ws -Limit 300)
        Assert-Equal 200 $capped.Count "events.jsonl capped at 200 lines"
        Assert-Equal "Step 210" $capped[$capped.Count - 1].ecoText "latest event kept"

        Clear-SenOfficeEvents -Workspace $ws
        $afterClear = @(Read-SenOfficeEvents -Workspace $ws)
        Assert-Equal 0 $afterClear.Count "events cleared"
    } finally { Remove-OfficeTempDir $ws }
}

Test "Test-SenStuckLoop triggers on 3 identical failures and resets on success or file edit" {
    $ws = New-OfficeTempDir
    try {
        $r1 = Test-SenStuckLoop -Workspace $ws -ToolName "run_command" -Target "npm test" -Failed -ErrorText "FAIL src/app.test.js at 12:00:01"
        Assert-Equal $false $r1.IsStuck
        Assert-Equal 1 $r1.Streak

        $r2 = Test-SenStuckLoop -Workspace $ws -ToolName "run_command" -Target "npm test" -Failed -ErrorText "FAIL src/app.test.js at 12:00:05"
        Assert-Equal $false $r2.IsStuck
        Assert-Equal 2 $r2.Streak

        $r3 = Test-SenStuckLoop -Workspace $ws -ToolName "run_command" -Target "npm test" -Failed -ErrorText "FAIL src/app.test.js at 12:00:09"
        Assert-Equal $true $r3.IsStuck "3rd identical failure marks session stuck"
        Assert-Equal 3 $r3.Streak

        # Querying without -Failed returns current stuck state for PreToolUse guard
        $check = Test-SenStuckLoop -Workspace $ws -ToolName "run_command" -Target "npm test"
        Assert-Equal $true $check.IsStuck

        # Editing a file or resetting clears the stuck state
        $reset = Test-SenStuckLoop -Workspace $ws -ToolName "edit_file" -Target "src/app.js" -Reset
        Assert-Equal $false $reset.IsStuck
        $checkAfter = Test-SenStuckLoop -Workspace $ws -ToolName "run_command" -Target "npm test"
        Assert-Equal $false $checkAfter.IsStuck "streak cleared after edit"
    } finally { Remove-OfficeTempDir $ws }
}

Test "Write-SenOfficeShowcase and Read-SenOfficeShowcase round-trip Dual-Phase project data" {
    $ws = New-OfficeTempDir
    try {
        $show = @{
            projectTitle = "Sen Office v0.2.0"
            domain       = "web-ui"
            tier         = "Tier 3"
            phase1       = @{
                summary         = "Phase 1 Blueprint"
                expectedOutputs = @("3D Chibi Cast", "Inspector Drawer")
            }
            phase2       = @{
                summary = "Phase 2 Verified"
                gates   = @{
                    tests    = "PASS"
                    build    = "PASS"
                    security = "PASS"
                    legal    = "PASS"
                }
            }
        }
        Write-SenOfficeShowcase -Workspace $ws -Showcase $show
        $loaded = Read-SenOfficeShowcase -Workspace $ws
        Assert-Equal "Sen Office v0.2.0" $loaded.projectTitle
        Assert-Equal "Phase 1 Blueprint" $loaded.phase1.summary
        Assert-Equal "PASS" $loaded.phase2.gates.tests

        # TASK-20 Fix 3: Sequential -Phase 1 and -Phase 2 calls preserve both phases without overwriting
        Remove-Item -LiteralPath (Join-Path $ws ".agents/office/showcase.json") -Force -ErrorAction SilentlyContinue
        [void](Write-SenOfficeShowcase -Workspace $ws -Phase 1 -TaskId "TASK-20" -Title "Dual Phase Sequential" -Blueprint "Expected Blueprint P1")
        $afterP1 = Read-SenOfficeShowcase -Workspace $ws
        Assert-Equal "Expected Blueprint P1" $afterP1.phase1.summary "Phase 1 summary written"

        [void](Write-SenOfficeShowcase -Workspace $ws -Phase 2 -TaskId "TASK-20" -Blueprint "Verified Output P2")
        $afterP2 = Read-SenOfficeShowcase -Workspace $ws
        Assert-Equal "Expected Blueprint P1" $afterP2.phase1.summary "Phase 1 summary preserved after Phase 2 write"
        Assert-Equal "Verified Output P2" $afterP2.phase2.summary "Phase 2 summary written"
        Assert-Equal "PASS" $afterP2.phase2.gates.tests "Phase 2 default gates populated"
    } finally { Remove-OfficeTempDir $ws }
}

Test "Get-SenAntigravityQuota returns safe read-only structure without throwing" {
    $q = Get-SenAntigravityQuota
    Assert-True ($null -ne $q) "quota object returned"
    Assert-True ($q.ContainsKey("available")) "contains available key"
    Assert-True ($q.ContainsKey("models")) "contains models key"
}

Test "guard.ps1 logs guard-denied alert to office events.jsonl when blocking a destructive command" {
    $ws = New-OfficeTempDir
    try {
        Set-SenOfficeConfig -Workspace $ws -Mode "eco" | Out-Null
        $guardScript = Join-Path -Path $repoRoot -ChildPath "scripts/guard.ps1"
        $payload = @{
            tool_name = "run_command"
            tool_input = @{ CommandLine = "git push --force origin main" }
            workspacePaths = @($ws)
        } | ConvertTo-Json -Compress -Depth 4
        $out = $payload | & powershell -NoProfile -ExecutionPolicy Bypass -File $guardScript
        $parsed = $out | ConvertFrom-Json
        Assert-Equal "deny" $parsed.decision

        $evs = @(Read-SenOfficeEvents -Workspace $ws)
        Assert-Equal 1 $evs.Count "1 guard-denied event logged"
        Assert-Equal "guard-denied" $evs[0].source
        Assert-Equal "alert" $evs[0].kind
        Assert-Equal "sec" $evs[0].from
        Assert-True ($evs[0].command.Contains("git push --force")) "command recorded for Copy Command card"
    } finally { Remove-OfficeTempDir $ws }
}

Test "guard.ps1 blocks 4th consecutive identical failing command via Stuck Loop Breaker" {
    $ws = New-OfficeTempDir
    try {
        Set-SenOfficeConfig -Workspace $ws -Mode "eco" | Out-Null
        Test-SenStuckLoop -Workspace $ws -ToolName "run_command" -Target "npm run broken" -Failed -ErrorText "Exit code 1" | Out-Null
        Test-SenStuckLoop -Workspace $ws -ToolName "run_command" -Target "npm run broken" -Failed -ErrorText "Exit code 1" | Out-Null
        Test-SenStuckLoop -Workspace $ws -ToolName "run_command" -Target "npm run broken" -Failed -ErrorText "Exit code 1" | Out-Null

        $guardScript = Join-Path -Path $repoRoot -ChildPath "scripts/guard.ps1"
        $payload = @{
            tool_name = "run_command"
            tool_input = @{ CommandLine = "npm run broken" }
            workspacePaths = @($ws)
        } | ConvertTo-Json -Compress -Depth 4
        $out = $payload | & powershell -NoProfile -ExecutionPolicy Bypass -File $guardScript
        $parsed = $out | ConvertFrom-Json
        Assert-Equal "deny" $parsed.decision "4th attempt must be denied by Stuck Loop Breaker"
        Assert-True ($parsed.reason.Contains("Stuck loop")) "reason mentions Stuck loop"
    } finally { Remove-OfficeTempDir $ws }
}

Test "office-post.ps1 records telemetry in eco mode and writes nothing in off mode" {
    $ws = New-OfficeTempDir
    try {
        $postScript = Join-Path -Path $repoRoot -ChildPath "scripts/office-post.ps1"
        Set-SenOfficeConfig -Workspace $ws -Mode "off" | Out-Null
        $payloadOff = @{
            tool_name = "edit_file"
            tool_input = @{ Path = "$ws/src/App.tsx" }
            workspacePaths = @($ws)
        } | ConvertTo-Json -Compress -Depth 4
        $payloadOff | & powershell -NoProfile -ExecutionPolicy Bypass -File $postScript | Out-Null
        Assert-Equal 0 @(Read-SenOfficeEvents -Workspace $ws).Count "no event when mode is off"

        Set-SenOfficeConfig -Workspace $ws -Mode "eco" | Out-Null
        $payloadEco = @{
            tool_name = "edit_file"
            tool_input = @{ Path = "$ws/src/App.tsx" }
            workspacePaths = @($ws)
        } | ConvertTo-Json -Compress -Depth 4
        $payloadEco | & powershell -NoProfile -ExecutionPolicy Bypass -File $postScript | Out-Null
        $evs = @(Read-SenOfficeEvents -Workspace $ws)
        Assert-Equal 1 $evs.Count "1 event recorded in eco mode"
        Assert-Equal "fe" $evs[0].from "App.tsx mapped to Frontend Dev (fe)"
        Assert-Equal "hook-post" $evs[0].source
    } finally { Remove-OfficeTempDir $ws }
}

Test "start-office.ps1 -DryRun returns valid server metadata and office/index.html contains all 10 features" {
    $ws = New-OfficeTempDir
    try {
        $startScript = Join-Path -Path $repoRoot -ChildPath "scripts/start-office.ps1"
        $json = & powershell -NoProfile -ExecutionPolicy Bypass -File $startScript -Workspace $ws -Port 47895 -DryRun
        $meta = $json | ConvertFrom-Json
        Assert-Equal 47895 $meta.port
        Assert-Equal $true $meta.dryRun
        Assert-True (Test-Path -LiteralPath $meta.htmlPath) "office/index.html exists"

        $html = [System.IO.File]::ReadAllText($meta.htmlPath, [System.Text.Encoding]::UTF8)
        foreach ($marker in @(
            "SEN OFFICE 3D",
            "skin3d",
            "dualPhase",
            "view2d",
            "replayRange",
            "streamer-redact",
            "quotaPill",
            "selectActor",
            "denied-card",
            "khanh020905/my-office",
            "DEMO_IDLE",
            "LIVE_STREAMING",
            "HIBERNATED_SNAPSHOT",
            "liveMissionBar",
            "syncRealTelemetry"
        )) {
            Assert-True ($html.Contains($marker)) "office/index.html must contain marker: $marker"
        }
    } finally { Remove-OfficeTempDir $ws }
}

Test "office-post.ps1 tracks invoke_subagent as in_progress SUBAGENT-LIVE and completes it on send_message" {
    $ws = New-OfficeTempDir
    try {
        $postScript = Join-Path -Path $repoRoot -ChildPath "scripts/office-post.ps1"
        Set-SenOfficeConfig -Workspace $ws -Mode "eco" | Out-Null

        $payloadSpawn = @{
            toolCall = @{
                name = "invoke_subagent"
                args = @{
                    TypeName = "self"
                    Role     = "Frontend Engineer"
                    Prompt   = "Upgrade 3D Office live streaming and hibernation"
                    Model    = "pro"
                }
            }
            workspacePaths = @($ws)
        } | ConvertTo-Json -Compress -Depth 6
        $payloadSpawn | & powershell -NoProfile -ExecutionPolicy Bypass -File $postScript | Out-Null

        $evs1 = @(Read-SenOfficeEvents -Workspace $ws)
        Assert-Equal 1 $evs1.Count "invoke_subagent event recorded"
        Assert-Equal "pm" $evs1[0].from "invoke_subagent originates from pm"
        Assert-Equal "fe" $evs1[0].to "Frontend Engineer role maps to fe"
        Assert-Equal "Subagent" $evs1[0].lane "lane is Subagent"

        $tks1 = @(Get-SenTasks -Workspace $ws)
        $subTask1 = $tks1 | Where-Object { $_.id -eq "SUBAGENT-LIVE" } | Select-Object -First 1
        Assert-True ($null -ne $subTask1) "SUBAGENT-LIVE task auto-created"
        Assert-Equal "in_progress" $subTask1.status "SUBAGENT-LIVE starts as in_progress"

        $payloadReport = @{
            toolCall = @{
                name = "send_message"
                args = @{
                    Recipient = "parent-id"
                    Message   = "Completed 3-Phase State Machine and verified all tests"
                }
            }
            workspacePaths = @($ws)
        } | ConvertTo-Json -Compress -Depth 6
        $payloadReport | & powershell -NoProfile -ExecutionPolicy Bypass -File $postScript | Out-Null

        $tks2 = @(Get-SenTasks -Workspace $ws)
        $subTask2 = $tks2 | Where-Object { $_.id -eq "SUBAGENT-LIVE" } | Select-Object -First 1
        Assert-Equal "done" $subTask2.status "SUBAGENT-LIVE transitions to done on send_message"
    } finally { Remove-OfficeTempDir $ws }
}


