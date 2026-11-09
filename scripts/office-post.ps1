# scripts/office-post.ps1
# Antigravity PostToolUse telemetry hook (ASCII only) for Sen Office v0.2.0.
# Zero-token evidence recorder: maps tool executions to 3D office roles, updates stuck-loop tracker,
# redacts secrets, and appends to <WORKSPACE>/.agents/office/events.jsonl when mode != "off".

$ErrorActionPreference = "SilentlyContinue"

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw) -and $input) {
        $raw = (@($input) -join "`n")
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $payload = $raw | ConvertFrom-Json
    $senModule = Join-Path -Path $PSScriptRoot -ChildPath "Sen.psm1"
    if (-not (Test-Path -LiteralPath $senModule)) {
        $senModule = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Runtime.psm1"
    }
    if (-not (Test-Path -LiteralPath $senModule)) { exit 0 }
    Import-Module $senModule -Force -ErrorAction SilentlyContinue

    if (Get-Command ConvertFrom-SenHookPayload -ErrorAction SilentlyContinue) {
        $norm     = ConvertFrom-SenHookPayload -InputObject $payload
        $ws       = $norm.WorkspacePath
        $toolName = $norm.CanonicalTool
        $pathArg  = $norm.TargetPath
        $cmdArg   = $norm.CommandLine
        $queryArg = $norm.Query
        $hasEc    = [bool]$norm.HasExplicitExitCode
        $ecVal    = [int]$norm.ExitCode
        $isErr    = [bool]$norm.IsError
    }
    else {
        $wsCandidates = [System.Collections.Generic.List[string]]::new()
        if ($payload.workspacePaths) { foreach ($w in @($payload.workspacePaths)) { if (-not [string]::IsNullOrWhiteSpace([string]$w)) { $wsCandidates.Add([string]$w) } } }
        if ($payload.workspace_roots) { foreach ($w in @($payload.workspace_roots)) { if (-not [string]::IsNullOrWhiteSpace([string]$w)) { $wsCandidates.Add([string]$w) } } }
        if ($payload.cwd -and -not [string]::IsNullOrWhiteSpace([string]$payload.cwd)) { $wsCandidates.Add([string]$payload.cwd) }
        $wsList = @($wsCandidates.ToArray())
        $ws = if ($wsList.Count -gt 0) { [string]$wsList[0] } else { "" }
        $toolName = ""; $pathArg = ""; $cmdArg = ""; $queryArg = ""; $hasEc = $false; $ecVal = -1; $isErr = $false
    }
    if ([string]::IsNullOrWhiteSpace($ws)) { exit 0 }
    $shortFile = if ($pathArg) { [System.IO.Path]::GetFileName($pathArg) } else { "" }
    $sealFile = Join-Path $ws ".agents/office/state-seal.json"
    $sealIntactBeforeHook = $true
    if ((Test-Path -LiteralPath $sealFile) -and (Get-Command Sync-SenOfficeState -ErrorAction SilentlyContinue)) {
        try { $sealIntactBeforeHook = (-not (Sync-SenOfficeState -Workspace $ws -VerifySeal).Tampered) } catch { $sealIntactBeforeHook = $false }
    }
    $hookMutatedOfficeJson = $false

    # Zero-token Auto-Orchestration: sync Plan / TODO Markdown to .agents/office/tasks.json on write/edit
    if (($toolName -eq "write_file" -or $toolName -eq "edit_file") -and $pathArg -match '(?i)((specs|plans)[\\/][^\\/]+\.md|TODO\.md)$') {
        if ($pathArg -match '(?i)(plans[\\/][^\\/]+\.md|TODO\.md)$' -and (Get-Command Sync-SenPlanToTasks -ErrorAction SilentlyContinue)) {
            $planTarget = if ($pathArg -match '(?i)plans[\\/][^\\/]+\.md$') { $pathArg } else { "" }
            [void](Sync-SenPlanToTasks -Workspace $ws -PlanPath $planTarget)
            $hookMutatedOfficeJson = $true
        }
        if ($pathArg -match '(?i)(specs|plans)[\\/][^\\/]+\.md$' -and (Get-Command Write-SenOfficeShowcase -ErrorAction SilentlyContinue)) {
            [void](Write-SenOfficeShowcase -Workspace $ws -Phase 1 -TaskId $shortFile -Title (Split-Path $ws -Leaf) -Tier 3 -Blueprint "Design Blueprint: $shortFile" -ExpectedOutputs @($shortFile))
            $hookMutatedOfficeJson = $true
        }
        if ((Test-Path -LiteralPath (Join-Path $ws ".agents/office/process-audit.json")) -and (Get-Command Test-SenStageGate -ErrorAction SilentlyContinue)) {
            [void](Test-SenStageGate -Workspace $ws -Stage 2)
            $hookMutatedOfficeJson = $true
        }
    }

    $cfg = Get-SenOfficeConfig -Workspace $ws
    if ($cfg.mode -eq "off") { exit 0 }

    $from = "be"
    $to = "sys"
    $lane = "Execution"
    $kind = "ok"
    $ecoText = "$toolName"
    $fullText = ""
    $model = "inherit"
    $argsObj = if ($payload.toolCall -and $payload.toolCall.args) { $payload.toolCall.args } elseif ($payload.tool_input) { $payload.tool_input } elseif ($payload.toolArgs) { $payload.toolArgs } else { $payload }

    if ($toolName -eq "invoke_subagent") {
        $roleArg = if ($argsObj.Role) { [string]$argsObj.Role } elseif ($argsObj.TypeName) { [string]$argsObj.TypeName } else { "Subagent" }
        $promptArg = if ($argsObj.Prompt) { [string]$argsObj.Prompt } else { $roleArg }
        $cleanPrompt = ($promptArg -replace '[\r\n\t]+', ' ').Trim()
        $shortPrompt = if ($cleanPrompt.Length -gt 64) { $cleanPrompt.Substring(0, 61) + "..." } else { $cleanPrompt }
        $from = "pm"
        $to = if ($roleArg -match '(?i)(research|scout|trinh)') { "r1" } elseif ($roleArg -match '(?i)(ba|arch|design|plan)') { "ba" } elseif ($roleArg -match '(?i)(fe|front|ui|3d|office)') { "fe" } elseif ($roleArg -match '(?i)(qa|test|verify)') { "qa" } elseif ($roleArg -match '(?i)(sec|audit|guard)') { "sec" } elseif ($roleArg -match '(?i)(law|legal)') { "law" } else { "be" }
        $lane = "Subagent"
        $model = if ($argsObj.Model) { [string]$argsObj.Model } else { "inherit" }
        $ecoText = "Subagent [$roleArg]: $shortPrompt"
        $fullText = "Subagent [$roleArg]: " + $(if ($cleanPrompt.Length -gt 180) { $cleanPrompt.Substring(0, 177) + "..." } else { $cleanPrompt })
        $pathArg = $roleArg
        if (Get-Command New-SenTask -ErrorAction SilentlyContinue) {
            $st = New-SenTask -Workspace $ws -Id "SUBAGENT-LIVE" -Title $ecoText -Tier 2 -RiskLevel "medium" -Module "Subagent" -Assignee $to -Status "in_progress"
            $allT = @(Get-SenTasks -Workspace $ws); foreach ($item in $allT) { if ($item -and [string]$item.id -eq "SUBAGENT-LIVE") { $item | Add-Member -NotePropertyName "isTelemetryOnly" -NotePropertyValue $true -Force } }
            [void](Save-SenTasks -Workspace $ws -Tasks $allT -Internal); $hookMutatedOfficeJson = $true
        }
        if (Get-Command Write-SenOfficeShowcase -ErrorAction SilentlyContinue) {
            [void](Write-SenOfficeShowcase -Workspace $ws -TaskId "SUBAGENT-LIVE" -Title $ecoText -Phase 1 -Summary $fullText -Domain "architecture")
            $hookMutatedOfficeJson = $true
        }
    }
    elseif ($toolName -eq "send_message") {
        $msgRaw = if ($argsObj.Message) { ([string]$argsObj.Message -replace '[\r\n\t]+', ' ').Trim() } else { "Subagent report" }
        $shortMsg = if ($msgRaw.Length -gt 68) { $msgRaw.Substring(0, 65) + "..." } else { $msgRaw }
        $from = "be"; $to = "pm"; $lane = "Subagent"; $kind = "ok"
        $ecoText = "Report: $shortMsg"
        $fullText = "Subagent message: " + $(if ($msgRaw.Length -gt 180) { $msgRaw.Substring(0, 177) + "..." } else { $msgRaw })
        if (Get-Command Get-SenTasks -ErrorAction SilentlyContinue) {
            $allT = @(Get-SenTasks -Workspace $ws)
            foreach ($item in $allT) {
                if ($item -and [string]$item.id -eq "SUBAGENT-LIVE") {
                    $item.status = "done"; $item.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    $item | Add-Member -NotePropertyName "isTelemetryOnly" -NotePropertyValue $true -Force
                }
            }
            [void](Save-SenTasks -Workspace $ws -Tasks $allT -Internal); $hookMutatedOfficeJson = $true
        }
        if (Get-Command Write-SenOfficeShowcase -ErrorAction SilentlyContinue) {
            [void](Write-SenOfficeShowcase -Workspace $ws -TaskId "SUBAGENT-LIVE" -Title $ecoText -Phase 2 -Summary $fullText -Domain "architecture")
            $hookMutatedOfficeJson = $true
        }
    }
    elseif ($toolName -eq "manage_subagents") {
        $act = if ($argsObj.Action) { [string]$argsObj.Action } else { "list" }
        $from = "pm"; $to = "sys"; $lane = "Subagent"; $kind = "ok"
        $ecoText = "Subagents: $act"
        if ($act -in @("kill", "kill_all") -and (Get-Command Get-SenTasks -ErrorAction SilentlyContinue)) {
            $allT = @(Get-SenTasks -Workspace $ws)
            foreach ($item in $allT) { if ($item -and [string]$item.id -eq "SUBAGENT-LIVE") { $item.status = "done"; $item | Add-Member -NotePropertyName "isTelemetryOnly" -NotePropertyValue $true -Force } }
            [void](Save-SenTasks -Workspace $ws -Tasks $allT -Internal); $hookMutatedOfficeJson = $true
        }
    }
    elseif ($toolName -eq "grep_search" -or $toolName -eq "find_by_name") {
        $from = "r1"
        $lane = "Scout"
        $model = "flash_lite"
        $q = if (-not [string]::IsNullOrWhiteSpace($queryArg)) { $queryArg } else { $shortFile }
        $ecoText = "Search: $q"
        $fullText = if ($pathArg) { "Search '$q' in $pathArg" } else { "Search: $q" }
    }
    elseif ($toolName -eq "read_file") {
        if ($pathArg -match '(?i)(specs|templates|README|docs)') {
            $from = "ba"
            $lane = "Design"
            $ecoText = "Read spec: $shortFile"
        }
        else {
            $from = "r2"
            $lane = "Scout"
            $model = "flash"
            $ecoText = "Read: $shortFile"
        }
        $fullText = if ($pathArg) { "$ecoText ($pathArg)" } else { $ecoText }
    }
    elseif ($toolName -eq "write_file" -or $toolName -eq "edit_file") {
        Test-SenStuckLoop -Workspace $ws -ToolName $toolName -Target $pathArg -Reset | Out-Null
        if ($pathArg -and ($pathArg.Replace('\', '/') -notmatch '(?i)/(\.agents|docs)/')) {
            if (Get-Command Get-SenTasks -ErrorAction SilentlyContinue) {
                $curTasks = @(Get-SenTasks -Workspace $ws | Where-Object { [string]$_.status -in @("in_progress", "reviewing") })
                if ($curTasks.Count -eq 0 -and (Get-Command New-SenTask -ErrorAction SilentlyContinue)) {
                    [void](New-SenTask -Workspace $ws -Id "AUTO-WORK" -Title "Edit $shortFile" -Tier 1 -RiskLevel "low" -Module "AutoTrack" -Assignee "be" -Status "in_progress")
                    $allT = @(Get-SenTasks -Workspace $ws); foreach ($item in $allT) { if ($item -and [string]$item.id -eq "AUTO-WORK") { $item | Add-Member -NotePropertyName "isTelemetryOnly" -NotePropertyValue $true -Force } }
                    [void](Save-SenTasks -Workspace $ws -Tasks $allT -Internal); $hookMutatedOfficeJson = $true
                }
            }
            if (Get-Command Write-SenOfficeShowcase -ErrorAction SilentlyContinue) {
                [void](Write-SenOfficeShowcase -Workspace $ws -TaskId "AUTO-WORK" -Title "Modifying $shortFile" -Phase 1 -Summary "Editing $pathArg" -Domain "code")
                $hookMutatedOfficeJson = $true
            }
            if (Get-Command Test-SenMidTaskEscalation -ErrorAction SilentlyContinue) {
                $esc = Test-SenMidTaskEscalation -Workspace $ws -ModifiedFiles @($pathArg)
                if ($esc.Escalated) { $hookMutatedOfficeJson = $true }
            }
        }
        if ($pathArg -match '(?i)\.(html|css|tsx|jsx|vue|svg)$') {
            $from = "fe"
            $lane = "FE Track"
            $ecoText = "Edit UI: $shortFile"
        }
        elseif ($pathArg -match '(?i)(specs|plan|design)\.md$') {
            $from = "ba"
            $lane = "Design"
            $ecoText = "Write spec: $shortFile"
        }
        else {
            $from = "be"
            $lane = "BE Track"
            $model = "pro"
            $ecoText = "Edit code: $shortFile"
        }
        $wdNote = if ($pathArg -and ($pathArg.Replace('\', '/') -notmatch '(?i)/(\.agents|docs)/')) { " [SEN WATCHDOG] Run Invoke-SenPostCodePipeline & Test-SenDeliveryGate before completion." } else { "" }
        $fullText = $(if ($pathArg) { "$ecoText ($pathArg)" } else { $ecoText }) + $wdNote
    }
    elseif ($toolName -eq "run_command") {
        $cleanCmd = ($cmdArg -replace '[\r\n\t]+', ' ').Trim()
        if ($cmdArg -match '(?i)(Validate-Repo|security|audit|Measure-SenCodeHealth|Invoke-SenVnLawScan)') {
            $from = "sec"
            $lane = "Security Gate"
            $model = "pro"
            $ecoText = "Security/Repo check"
        }
        elseif (($cmdArg -match '(?i)\b(npm\s+test|pnpm\s+test|yarn\s+test|npx\s+(jest|vitest|playwright)|pytest|cargo\s+test|go\s+test|dotnet\s+test|Invoke-Pester|tests[/\\]run\.ps1|run\.ps1)\b') -and ($cmdArg -notmatch '^(?i)\s*(echo|write-host|write-output|true|rem|::)\b')) {
            $from = "qa"
            $lane = "QA Gate"
            $ecoText = "Run test suite"
            if ($hasEc -and ($ecVal -eq 0) -and (-not $isErr)) {
                if (Get-Command Register-SenEvidence -ErrorAction SilentlyContinue) {
                    [void](Register-SenEvidence -Workspace $ws -EvidenceId "EV-AUTO-TEST" -TaskId "AUTO-WORK" -Type "unit" -Command $cleanCmd -ExitCode $ecVal)
                    $hookMutatedOfficeJson = $true
                }
                if (Get-Command Complete-SenTaskReview -ErrorAction SilentlyContinue) {
                    [void](Complete-SenTaskReview -Workspace $ws -Id "AUTO-WORK" -Passed $true -Reviewer "qa" -EvidenceCommand $cleanCmd -ExitCode $ecVal)
                    $hookMutatedOfficeJson = $true
                }
                if (Get-Command Write-SenOfficeShowcase -ErrorAction SilentlyContinue) {
                    [void](Write-SenOfficeShowcase -Workspace $ws -TaskId "AUTO-WORK" -Title "Verified test suite" -Phase 2 -Summary "Executed: $cleanCmd" -Domain "qa")
                    $hookMutatedOfficeJson = $true
                }
            }
        }
        else {
            $from = "be"
            $lane = "System Cmd"
            $shortCmd = if ($cleanCmd.Length -gt 48) { $cleanCmd.Substring(0, 45) + "..." } else { $cleanCmd }
            $ecoText = "Run: $shortCmd"
        }
        $fullText = "Cmd: " + $(if ($cleanCmd.Length -gt 160) { $cleanCmd.Substring(0, 157) + "..." } else { $cleanCmd })
    }

    if ([string]::IsNullOrWhiteSpace($fullText)) { $fullText = $ecoText }
    if ($sealIntactBeforeHook -and $hookMutatedOfficeJson -and (Test-Path -LiteralPath $sealFile) -and (Get-Command Sync-SenOfficeState -ErrorAction SilentlyContinue)) {
        try { [void](Sync-SenOfficeState -Workspace $ws -UpdateSeal) } catch { <# Non-fatal #> }
    }
    $targetVal = if ($pathArg) { $pathArg } else { $cmdArg }
    Write-SenOfficeEvent -Workspace $ws -From $from -To $to -Lane $lane -EcoText $ecoText -FullText $fullText `
        -Kind $kind -Hold 1 -Source "hook-post" -Tool $toolName -Target $targetVal -Command $cmdArg -Model $model | Out-Null
}
catch { <# PostToolUse telemetry is best-effort and must never fail a tool call #> }
exit 0
