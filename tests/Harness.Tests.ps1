# tests/Harness.Tests.ps1
# Unit and integration tests for Sen v0.4.0 Multi-Harness Adapter & Two-Way Plan/TODO Sync (ASCII-only)

. "$PSScriptRoot/Assert.ps1"

$senModule = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/Sen.psm1"
Import-Module $senModule -Force

$guardScript = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/guard.ps1"
$postScript  = Join-Path -Path $PSScriptRoot -ChildPath "../scripts/office-post.ps1"

function New-HarnessTestWorkspace {
    $p = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("sen-harness-" + [Guid]::NewGuid().ToString("N").Substring(0, 10))
    [System.IO.Directory]::CreateDirectory($p) | Out-Null
    $rulesDir = Join-Path -Path $p -ChildPath ".agents/rules"
    [System.IO.Directory]::CreateDirectory($rulesDir) | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $rulesDir "AGENTS.md"), "# Sen Core Rule`nAlways tier requests.")
    [System.IO.File]::WriteAllText((Join-Path $rulesDir "profile.md"), "# Profile`n- Name: Boss")
    return $p
}

function Invoke-HarnessHookJson([string]$ScriptPath, [hashtable]$PayloadObj) {
    $json = $PayloadObj | ConvertTo-Json -Depth 8 -Compress
    $out = $json | & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath
    $stdout = (@($out) -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($stdout)) { return $null }
    return ($stdout | ConvertFrom-Json)
}

Test "Get-SenSupportedHarnesses returns all 6 target harnesses" {
    $list = @(Get-SenSupportedHarnesses)
    Assert-Equal 6 $list.Count "Should return 6 harnesses"
    $ids = @($list | ForEach-Object { $_.Id })
    foreach ($expected in @("antigravity", "claude", "cursor", "copilot", "windsurf", "codex")) {
        Assert-True ($ids -contains $expected) "Missing harness: $expected"
    }
}

Test "ConvertFrom-SenHookPayload normalizes Antigravity, Claude Code, and Cursor payloads" {
    $ag = [pscustomobject]@{
        toolCall = [pscustomobject]@{ name = "run_command"; args = [pscustomobject]@{ CommandLine = "git status" } }
        workspacePaths = @("D:/ws")
    }
    $nAg = ConvertFrom-SenHookPayload -InputObject $ag
    Assert-Equal "run_command" $nAg.CanonicalTool "Antigravity run_command canonical tool"
    Assert-Equal "git status" $nAg.CommandLine "Antigravity CommandLine extracted"
    Assert-Equal "D:/ws" $nAg.WorkspacePath "Antigravity workspacePaths[0] extracted"

    $cc = [pscustomobject]@{
        tool_name  = "Bash"
        tool_input = [pscustomobject]@{ command = "rm -rf /tmp/x" }
        cwd        = "D:/cc-ws"
    }
    $nCc = ConvertFrom-SenHookPayload -InputObject $cc
    Assert-Equal "run_command" $nCc.CanonicalTool "Claude Code Bash maps to run_command"
    Assert-Equal "rm -rf /tmp/x" $nCc.CommandLine "Claude Code command extracted"
    Assert-Equal "D:/cc-ws" $nCc.WorkspacePath "Claude Code cwd extracted"

    $ccEdit = [pscustomobject]@{
        tool_name  = "MultiEdit"
        tool_input = [pscustomobject]@{ file_path = "D:/cc-ws/src/app.ts" }
        cwd        = "D:/cc-ws"
    }
    $nCcEdit = ConvertFrom-SenHookPayload -InputObject $ccEdit
    Assert-Equal "edit_file" $nCcEdit.CanonicalTool "Claude Code MultiEdit maps to edit_file"
    Assert-Equal "D:/cc-ws/src/app.ts" $nCcEdit.TargetPath "Claude Code file_path extracted"

    $cur = [pscustomobject]@{
        tool_name       = "run_terminal_cmd"
        tool_input      = [pscustomobject]@{ command = "npm test" }
        workspace_roots = @("D:/cur-ws")
    }
    $nCur = ConvertFrom-SenHookPayload -InputObject $cur
    Assert-Equal "run_command" $nCur.CanonicalTool "Cursor run_terminal_cmd maps to run_command"
    Assert-Equal "npm test" $nCur.CommandLine "Cursor command extracted"
    Assert-Equal "D:/cur-ws" $nCur.WorkspacePath "Cursor workspace_roots[0] extracted"
}

Test "Install-SenHarness projects rules and hooks non-destructively across all 6 harnesses" {
    $ws = New-HarnessTestWorkspace
    try {
        # Pre-seed user content in CLAUDE.md and .claude/settings.json
        [System.IO.File]::WriteAllText((Join-Path $ws "CLAUDE.md"), "# Existing Project Notes`nKeep this line!`n")
        $claudeDir = Join-Path $ws ".claude"
        [System.IO.Directory]::CreateDirectory($claudeDir) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $claudeDir "settings.json"), '{"env":{"CUSTOM_FLAG":"1"}}')

        $res = Install-SenHarness -Workspace $ws -Harness @("all")
        Assert-Equal 6 $res.Installed.Count "All 6 harnesses should be installed"

        $claudeMd = [System.IO.File]::ReadAllText((Join-Path $ws "CLAUDE.md"))
        Assert-True ($claudeMd.Contains("Keep this line!")) "User content in CLAUDE.md must be preserved"
        Assert-True ($claudeMd.Contains("<!-- SEN-METHOD:START -->")) "Managed block must be added to CLAUDE.md"

        $claudeSettings = [System.IO.File]::ReadAllText((Join-Path $claudeDir "settings.json")) | ConvertFrom-Json
        Assert-Equal "1" $claudeSettings.env.CUSTOM_FLAG "Pre-existing settings.json keys must be preserved"
        Assert-True ($null -ne $claudeSettings.hooks.PreToolUse) "Claude PreToolUse hook must be configured"
        Assert-True ($null -ne $claudeSettings.hooks.PostToolUse) "Claude PostToolUse hook must be configured"

        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".cursor/rules/sen-method.mdc")) "Cursor .mdc rule created"
        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".cursor/hooks.json")) "Cursor hooks.json created"
        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".github/copilot-instructions.md")) "Copilot instructions created"
        Assert-True (Test-Path -LiteralPath (Join-Path $ws ".windsurfrules")) "Windsurf rules created"
        Assert-True (Test-Path -LiteralPath (Join-Path $ws "AGENTS.md")) "Root AGENTS.md created for Codex/OpenCode"

        $status = @(Test-SenHarnessStatus -Workspace $ws)
        foreach ($st in $status) {
            Assert-True $st.Installed "Harness $($st.Id) should report Installed = true"
        }

        $un = Uninstall-SenHarness -Workspace $ws -Harness @("claude")
        Assert-True ($un.Uninstalled -contains "claude") "Claude harness uninstalled"
        $claudeMdAfter = [System.IO.File]::ReadAllText((Join-Path $ws "CLAUDE.md"))
        Assert-True ($claudeMdAfter.Contains("Keep this line!")) "User content in CLAUDE.md still preserved after uninstall"
        Assert-True (-not $claudeMdAfter.Contains("<!-- SEN-METHOD:START -->")) "Managed block removed after uninstall"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Sync-SenPlanToTasks and Sync-SenTasksToMarkdown perform 2-way sync between Markdown and tasks.json" {
    $ws = New-HarnessTestWorkspace
    try {
        $docsDir = Join-Path $ws "docs"
        $plansDir = Join-Path $ws "docs/superpowers/plans"
        [System.IO.Directory]::CreateDirectory($plansDir) | Out-Null

        $todoContent = "# Backlog`n`n- [ ] **TASK-99 (P0): Auto Sync Test Item**`n"
        [System.IO.File]::WriteAllText((Join-Path $docsDir "TODO.md"), $todoContent)

        $planContent = @'
# Feature Plan

### Task 1 (`AUTO-01`): Build Core Adapter

**Files:**
- Create: `scripts/Adapter.ps1`

- [ ] **Step 1: Write test**

### Task 2 (`AUTO-02`): Build Guard Hook

**Files:**
- Modify: `scripts/guard.ps1`
'@
        $planFile = Join-Path $plansDir "2026-11-07-test-plan.md"
        [System.IO.File]::WriteAllText($planFile, $planContent)

        $syncRes = Sync-SenPlanToTasks -Workspace $ws -PlanPath $planFile
        Assert-True ($syncRes.SyncedCount -ge 3) "Should sync AUTO-01, AUTO-02, and TASK-99"

        $tasks = @(Get-SenTasks -Workspace $ws)
        $auto1 = $tasks | Where-Object { $_.id -eq "AUTO-01" } | Select-Object -First 1
        $auto2 = $tasks | Where-Object { $_.id -eq "AUTO-02" } | Select-Object -First 1
        $t99   = $tasks | Where-Object { $_.id -eq "TASK-99" } | Select-Object -First 1

        Assert-True ($null -ne $auto1) "AUTO-01 created in tasks.json"
        Assert-True ($null -ne $auto2) "AUTO-02 created in tasks.json"
        Assert-True ($null -ne $t99) "TASK-99 created in tasks.json"
        Assert-Equal "ready" $auto1.status "AUTO-01 starts ready"
        Assert-Equal "pending" $auto2.status "AUTO-02 depends on AUTO-01"

        # Complete AUTO-01 and TASK-99, verify Markdown checkboxes auto-tick to [x]
        [void](Start-SenTask -Workspace $ws -Id "AUTO-01")
        [void](Submit-SenTaskForReview -Workspace $ws -Id "AUTO-01")
        [void](Complete-SenTaskReview -Workspace $ws -Id "AUTO-01" -Passed $true -EvidenceCommand "tests/run.ps1" -ExitCode 0)

        $t99.status = "in_progress"
        [void](Save-SenTasks -Workspace $ws -Tasks $tasks)
        [void](Complete-SenTaskReview -Workspace $ws -Id "TASK-99" -Passed $true -EvidenceCommand "tests/run.ps1" -ExitCode 0)

        $updatedTodo = [System.IO.File]::ReadAllText((Join-Path $docsDir "TODO.md"))
        Assert-True ($updatedTodo.Contains("- [x] **TASK-99")) "TODO.md must be auto-updated to [x] for TASK-99"

        $updatedPlan = [System.IO.File]::ReadAllText($planFile)
        Assert-True ($updatedPlan.Contains("[x]")) "Plan file must have [x] ticked after task completion"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "guard.ps1 and office-post.ps1 enforce safety and auto-sync plans on Claude Code and Cursor payloads" {
    $ws = New-HarnessTestWorkspace
    try {
        # 1. Claude Code Bash destructive command must be denied
        $ccRm = Invoke-HarnessHookJson -ScriptPath $guardScript -PayloadObj @{
            tool_name  = "Bash"
            tool_input = @{ command = "rm -rf /important" }
            cwd        = $ws
        }
        Assert-Equal "deny" $ccRm.decision "Claude Code Bash rm -rf must be denied by guard.ps1"

        # 2. Claude Code Write outside workspace must be denied
        $outsidePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "outside-secret.txt"
        $ccWriteOut = Invoke-HarnessHookJson -ScriptPath $guardScript -PayloadObj @{
            tool_name  = "Write"
            tool_input = @{ file_path = $outsidePath }
            cwd        = $ws
        }
        Assert-Equal "deny" $ccWriteOut.decision "Claude Code Write outside cwd must be denied by guard.ps1"

        # 3. Cursor run_terminal_cmd git push --force must be denied
        $curForce = Invoke-HarnessHookJson -ScriptPath $guardScript -PayloadObj @{
            tool_name       = "run_terminal_cmd"
            tool_input      = @{ command = "git push origin main --force" }
            workspace_roots = @($ws)
        }
        Assert-Equal "deny" $curForce.decision "Cursor git push --force must be denied by guard.ps1"

        # 4. office-post.ps1 on Claude Code Write to docs/superpowers/plans/*.md auto-syncs tasks into tasks.json
        $plansDir = Join-Path $ws "docs/superpowers/plans"
        [System.IO.Directory]::CreateDirectory($plansDir) | Out-Null
        $planFile = Join-Path $plansDir "2026-11-07-auto.md"
        $planBody = @'
# Auto Hook Plan

### Task 1 (`HOOK-01`): Hook Auto Task

**Files:**
- Create: `src/hook.ts`
'@
        [System.IO.File]::WriteAllText($planFile, $planBody)

        [void](Invoke-HarnessHookJson -ScriptPath $postScript -PayloadObj @{
            tool_name  = "Write"
            tool_input = @{ file_path = $planFile }
            cwd        = $ws
        })

        $tasks = @(Get-SenTasks -Workspace $ws)
        $hTask = $tasks | Where-Object { $_.id -eq "HOOK-01" } | Select-Object -First 1
        Assert-True ($null -ne $hTask) "office-post.ps1 must auto-sync HOOK-01 from plan file on Write event"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Process Compliance 3-Tier Engine filters (*) and (**), enforces Stage Gates without infinite loops, and auto-updates from manifest" {
    $ws = New-HarnessTestWorkspace
    try {
        $cat = Get-SenProcessCatalog
        Assert-Equal 12 $cat.steps.Count "Master process-manifest.json must contain 12 standard steps"

        [void](Set-SenOfficeConfig -Workspace $ws -Mode "off")
        $auditOff = Initialize-SenProcessAudit -Workspace $ws -ProjectName "SenCore" -Tier 2 -ProjectScope "core"
        Assert-Equal "off" $auditOff.officeMode "When office is off, officeMode should be off"
        Assert-Equal "offer_enable" $auditOff.officeAction "Tier 2 with off mode must set officeAction = offer_enable"
        [void](Set-SenOfficeConfig -Workspace $ws -Mode "eco")

        # Initialize project (*) for Tier 3 Core project (excludes web_mobile S4-VN-LAW -> 11 steps)
        $audit = Initialize-SenProcessAudit -Workspace $ws -ProjectName "SenCore" -Tier 3 -ProjectScope "core"
        Assert-Equal 11 $audit.selectedSteps.Count "Tier 3 core project should select 11 steps (*)"
        Assert-Equal "eco" $audit.officeMode "Default officeMode should be eco"
        Assert-Equal "auto_start" $audit.officeAction "Tier 3 with eco mode must set officeAction = auto_start"
        Assert-Equal "http://127.0.0.1:47890/" $audit.officeUrl "Default officeUrl should be http://127.0.0.1:47890/"

        # Stage 1 gate should pass immediately since S1-RISK and S1-AUDIT-INIT are satisfied
        $g1 = Test-SenStageGate -Workspace $ws -Stage 1
        Assert-True $g1.Passed "Stage 1 gate should pass after initialization"

        # Stage 2 gate should initially fail because Spec, Plan, and DAG are missing
        $g2Before = Test-SenStageGate -Workspace $ws -Stage 2
        Assert-True (-not $g2Before.Passed) "Stage 2 gate must fail when Spec/Plan/DAG are missing"
        Assert-True ($g2Before.MissingSteps -contains "S2-DESIGN-SPEC") "Missing S2-DESIGN-SPEC detected"

        # Create Spec with Resource Cost, Plan, Restore Point, Task, and CONTEXT.md
        $specsDir = Join-Path $ws "docs/superpowers/specs"
        $plansDir = Join-Path $ws "docs/superpowers/plans"
        [System.IO.Directory]::CreateDirectory($specsDir) | Out-Null
        [System.IO.Directory]::CreateDirectory($plansDir) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $specsDir "2026-11-07-spec.md"), "# Spec`nBest-of-the-Best`n| Option | Resource Cost |")
        [System.IO.File]::WriteAllText((Join-Path $plansDir "2026-11-07-plan.md"), "### Task 1 (P-01): Work`n- [x] Step 1")
        [System.IO.File]::WriteAllText((Join-Path $ws "docs/CONTEXT.md"), "# Context`nUpdated")

        [void](New-SenRestorePoint -Workspace $ws -Files @("docs/CONTEXT.md") -Label "test")
        [void](New-SenTask -Workspace $ws -Id "P-01" -Title "Work" -Tier 3)
        [void](Start-SenTask -Workspace $ws -Id "P-01")
        [void](Submit-SenTaskForReview -Workspace $ws -Id "P-01")
        [void](Complete-SenTaskReview -Workspace $ws -Id "P-01" -Passed $true -EvidenceCommand "tests/run.ps1" -ExitCode 0)

        $g2After = Test-SenStageGate -Workspace $ws -Stage 2
        Assert-True $g2After.Passed "Stage 2 gate must pass once Spec, Plan, and DAG exist"
        $sc1 = Read-SenOfficeShowcase -Workspace $ws
        Assert-True ($null -ne $sc1 -and $null -ne $sc1.phase1) "Stage 2 gate must ensure Phase 1 Output Simulation (showcase.json) exists"

        $finalComp = Test-SenProjectCompliance -Workspace $ws
        Assert-True $finalComp.Compliant "End-of-project compliance must verify all (**) and (*) are 100% done"
        Assert-Equal 11 $finalComp.CompletedCount "All 11 selected steps (*) completed and latched"
        $sc2 = Read-SenOfficeShowcase -Workspace $ws
        Assert-True ($null -ne $sc2 -and $null -ne $sc2.phase2) "Stage 4 gate must ensure Phase 2 Output Simulation (showcase.json) exists"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "TASK-20 audit fixes enforce session-scoped stage evidence and reject stale artifacts across sessions" {
    $ws = New-HarnessTestWorkspace
    try {
        $specsDir = Join-Path $ws "docs/superpowers/specs"
        $plansDir = Join-Path $ws "docs/superpowers/plans"
        [System.IO.Directory]::CreateDirectory($specsDir) | Out-Null
        [System.IO.Directory]::CreateDirectory($plansDir) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $specsDir "2026-11-06-old.md"), "# Old Spec`nBest-of-the-Best`n| Option | Resource Cost |")
        [System.IO.File]::WriteAllText((Join-Path $plansDir "2026-11-06-old.md"), "### Task 1 (OLD-01): Work`n- [x] Step 1")
        [System.IO.File]::WriteAllText((Join-Path $ws "docs/CONTEXT.md"), "# Stale Context")
        [void](New-SenRestorePoint -Workspace $ws -Files @("docs/CONTEXT.md") -Label "old-rp")
        [void](New-SenTask -Workspace $ws -Id "OLD-01" -Title "Old Task" -Tier 3)
        [void](Start-SenTask -Workspace $ws -Id "OLD-01")
        [void](Submit-SenTaskForReview -Workspace $ws -Id "OLD-01")
        [void](Complete-SenTaskReview -Workspace $ws -Id "OLD-01" -Passed $true -EvidenceCommand "tests/run.ps1" -ExitCode 0)

        $pastUtc = [DateTime]::UtcNow.AddMinutes(-15)
        foreach ($staleFile in @(
                (Join-Path $specsDir "2026-11-06-old.md"),
                (Join-Path $plansDir "2026-11-06-old.md"),
                (Join-Path $ws "docs/CONTEXT.md")
            )) {
            (Get-Item -LiteralPath $staleFile).LastWriteTimeUtc = $pastUtc
        }
        foreach ($rpManifest in @(Get-ChildItem -LiteralPath (Join-Path $ws ".agents/.sen-restore") -Filter "manifest.json" -Recurse -File)) {
            $rpManifest.LastWriteTimeUtc = $pastUtc
        }
        $staleTasks = @(Get-SenTasks -Workspace $ws)
        foreach ($stTask in $staleTasks) {
            $stTask.createdAt = $pastUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
            $stTask.updatedAt = $pastUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
            if ($stTask.evidence) { $stTask.evidence.verifiedAt = $pastUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") }
        }
        [void](Save-SenTasks -Workspace $ws -Tasks $staleTasks)

        $newAudit = Initialize-SenProcessAudit -Workspace $ws -ProjectName "NewSessionApp" -Tier 3 -ProjectScope "core"
        $latchedStage2Plus = @($newAudit.selectedSteps | Where-Object { [int]$_.stage -ge 2 -and [bool]$_.latched })
        Assert-Equal 0 $latchedStage2Plus.Count "New session audit must not inherit latched Stage 2-4 steps from previous project"
        $staleG2 = Test-SenStageGate -Workspace $ws -Stage 2
        Assert-True (-not $staleG2.Passed) "Stage 2 gate must reject stale Spec/Plan/Task older than session startedAt"
        $staleG3 = Test-SenStageGate -Workspace $ws -Stage 3
        Assert-True (-not $staleG3.Passed) "Stage 3 gate must reject stale RestorePoint/Task older than session startedAt"
        $staleDeliv = Test-SenDeliveryGate -Workspace $ws
        Assert-True (-not $staleDeliv.Allowed) "Delivery gate must block when only stale tasks from previous sessions exist"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Get-SenRemoteCiStatus and Invoke-SenCiPushLoop inspect remote CI runs and extract failed steps" {
    $mockRestFail = {
        param([string]$Uri)
        if ($Uri -like "*/jobs*") {
            return [pscustomobject]@{
                jobs = @(
                    [pscustomobject]@{
                        name  = "Validate & Test"
                        steps = @(
                            [pscustomobject]@{ name = "Checkout"; conclusion = "success" },
                            [pscustomobject]@{ name = "Run tests"; conclusion = "failure" }
                        )
                    }
                )
            }
        }
        return [pscustomobject]@{
            workflow_runs = @(
                [pscustomobject]@{
                    id         = 99001
                    status     = "completed"
                    conclusion = "failure"
                    html_url   = "https://github.com/developerfs0110/Sen/actions/runs/99001"
                    head_sha   = "abc111"
                    jobs_url   = "https://api.github.com/repos/developerfs0110/Sen/actions/runs/99001/jobs"
                }
            )
        }
    }

    $ciFail = Get-SenRemoteCiStatus -RepoSlug "developerfs0110/Sen" -HeadSha "abc111" -RestInvoker $mockRestFail
    Assert-True $ciFail.Found "Should find matching SHA run"
    Assert-Equal "failure" $ciFail.Conclusion "Should report failure conclusion"
    Assert-Equal 1 $ciFail.FailedSteps.Count "Should extract 1 failed step"
    Assert-Equal "Validate & Test > Run tests" $ciFail.FailedSteps[0] "Should format Job > Step name"

    $mockRestPass = {
        param([string]$Uri)
        return [pscustomobject]@{
            workflow_runs = @(
                [pscustomobject]@{
                    id         = 99002
                    status     = "completed"
                    conclusion = "success"
                    html_url   = "https://github.com/developerfs0110/Sen/actions/runs/99002"
                    head_sha   = "def222"
                    jobs_url   = ""
                }
            )
        }
    }
    $ws = New-HarnessTestWorkspace
    try {
        $loopRes = Invoke-SenCiPushLoop -RepoPath $ws -CommitMessage "test" -RestInvoker $mockRestPass -SkipPush -PollSeconds 0
        Assert-True $loopRes.LocalPassed "Local check should pass"
        Assert-True $loopRes.CiPassed "CI check should pass when conclusion is success"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "Test-SenCapabilityParity verifies 6-Layer Zero-Amnesia Isomorphism and guard.ps1 enforces Pre-Edit Restore Point Gate" {
    $senRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
    $parity = Test-SenCapabilityParity -SenRoot $senRoot
    Assert-True $parity.Passed "6-Layer Zero-Amnesia Capability Parity must pass (Missing: $($parity.MissingItems -join ', '))"
    Assert-Equal 6 $parity.CheckedLayers "Must verify all 6 layers"
    Assert-Equal 0 $parity.MissingItems.Count "Zero missing capability parity items"

    $ws = New-HarnessTestWorkspace
    try {
        [void](Initialize-SenProcessAudit -Workspace $ws -ProjectName "Tier2App" -Tier 2 -ProjectScope "core")
        $targetCode = Join-Path $ws "src/app.ts"
        $blockedWrite = Invoke-HarnessHookJson -ScriptPath $guardScript -PayloadObj @{
            toolCall       = @{ name = "write_file"; args = @{ Path = $targetCode } }
            workspacePaths = @($ws)
        }
        Assert-Equal "deny" $blockedWrite.decision "guard.ps1 must block project file write in Tier 2/3 before New-SenRestorePoint is called"

        [void](New-SenRestorePoint -Workspace $ws -Files @("src/app.ts") -Label "pre-edit")
        $allowedWrite = Invoke-HarnessHookJson -ScriptPath $guardScript -PayloadObj @{
            toolCall       = @{ name = "write_file"; args = @{ Path = $targetCode } }
            workspacePaths = @($ws)
        }
        Assert-Equal "ask" $allowedWrite.decision "guard.ps1 must allow project file write in Tier 2/3 after New-SenRestorePoint is called"

        $fakeRoot = Join-Path $ws "fake-sen"
        [System.IO.Directory]::CreateDirectory((Join-Path $fakeRoot "docs")) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $fakeRoot "README.md"), "# v0.4.0 A with 68 cmdlets")
        [System.IO.File]::WriteAllText((Join-Path $fakeRoot "README.vi.md"), "# v0.4.0 B with 68 cmdlets")
        [System.IO.File]::WriteAllText((Join-Path $fakeRoot "plugin.json"), '{"version":"0.4.0"}')
        [System.IO.File]::WriteAllText((Join-Path $fakeRoot "CHANGELOG.md"), "# 0.3.0 only")
        [System.IO.File]::WriteAllText((Join-Path $fakeRoot "docs/TODO.md"), "- [x] **TASK-99: New item**")
        [System.IO.File]::WriteAllText((Join-Path $fakeRoot "docs/CONTEXT.md"), "# Context v0.4.0 without task 99")
        [System.IO.File]::WriteAllText((Join-Path $fakeRoot "docs/guide.md"), "Tier 2 waits for your approval once with 7 sen-* skills")
        [System.IO.Directory]::CreateDirectory((Join-Path $fakeRoot "scripts")) | Out-Null
        Copy-Item -LiteralPath (Join-Path $senRoot "scripts/process-manifest.json") -Destination (Join-Path $fakeRoot "scripts/process-manifest.json") -Force
        Copy-Item -LiteralPath (Join-Path $senRoot "scripts/Sen.Harness.psm1") -Destination (Join-Path $fakeRoot "scripts/Sen.Harness.psm1") -Force
        $badParity = Test-SenCapabilityParity -SenRoot $fakeRoot
        Assert-True (-not $badParity.Passed) "Test-SenCapabilityParity must fail when README, version, or TODO/CONTEXT are out of sync"
        Assert-True ($badParity.MissingItems -contains "L5-DocSync:README_SYNC") "Must flag README_SYNC drift"
        Assert-True ($badParity.MissingItems -contains "L5-DocSync:VERSION_DOC_SYNC:CHANGELOG.md") "Must flag VERSION_DOC_SYNC drift"
        Assert-True ($badParity.MissingItems -contains "L5-DocSync:TODO_CONTEXT_SYNC:TASK-99") "Must flag TODO_CONTEXT_SYNC drift"
        Assert-True ($badParity.MissingItems -contains "L6-DocsParity:StaleCmdletCount:README.md") "Must flag stale cmdlet count in README.md"
        Assert-True ($badParity.MissingItems -contains "L6-DocsParity:StaleGuideFlow:docs/guide.md") "Must flag stale guide flow in docs/guide.md"
        Assert-True ($badParity.MissingItems -contains "L6-DocsParity:ChangelogMissingOfficeAction") "Must flag missing officeAction in CHANGELOG.md"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test "GPT 2.3 Independent Review (Agent A/B/C/D) in Invoke-SenDialecticalAudit rejects self-review, fake verbal evidence, stale evidence, and hung tasks" {
    $ws = New-HarnessTestWorkspace
    try {
        [void](New-SenTask -Workspace $ws -Id "IND-01" -Title "Feature A" -Assignee "qa")
        [void](Start-SenTask -Workspace $ws -Id "IND-01")
        [void](Submit-SenTaskForReview -Workspace $ws -Id "IND-01")
        # Self-review by same assignee ('qa' == 'qa') + fake verbal command "manual" must fail V3 and V6
        [void](Complete-SenTaskReview -Workspace $ws -Id "IND-01" -Passed $true -Reviewer "qa" -EvidenceCommand "manual" -ExitCode 0)

        $auditFail = Invoke-SenDialecticalAudit -Workspace $ws -RequireIndependentReviewer
        Assert-True (-not $auditFail.Passed) "Invoke-SenDialecticalAudit must reject self-reviewed task with verbal placeholder evidence"
        Assert-Equal "REJECTED" $auditFail.IndependentReview.AgentD_Decision "Agent D must reject when V3/V6 fail"
        $v3 = $auditFail.Vectors | Where-Object { $_.Id -eq "V3-SOCRATIC-EVIDENCE" }
        $v6 = $auditFail.Vectors | Where-Object { $_.Id -eq "V6-INDEPENDENT-REVIEW" }
        Assert-True (-not $v3.Passed) "V3 must fail on verbal placeholder evidence ('manual')"
        Assert-True (-not $v6.Passed) "V6 must fail when Reviewer == Assignee ('qa')"

        # Now re-verify with an independent Reviewer ('sec' != 'qa') and executable test command ('tests/run.ps1')
        $tasks = @(Get-SenTasks -Workspace $ws)
        $tasks[0].evidence.reviewer = "sec"
        $tasks[0].evidence.command = "tests/run.ps1"
        [void](Save-SenTasks -Workspace $ws -Tasks $tasks -Internal)

        $auditPass = Invoke-SenDialecticalAudit -Workspace $ws -RequireIndependentReviewer -IndependentProbe { return $true }
        Assert-True $auditPass.Passed "Invoke-SenDialecticalAudit must pass when independent reviewer ('sec' != 'qa') and real test evidence exist"
        Assert-Equal 6 $auditPass.Vectors.Count "Must evaluate all 6 Dialectical + Independent Review vectors (V1..V6)"
        Assert-Equal "APPROVED" $auditPass.IndependentReview.AgentD_Decision "Agent D must approve when all 6 vectors pass"
    }
    finally {
        Remove-Item -LiteralPath $ws -Recurse -Force -ErrorAction SilentlyContinue
    }
}
