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
    }
    else {
        $wsCandidates = [System.Collections.Generic.List[string]]::new()
        if ($payload.workspacePaths) { foreach ($w in @($payload.workspacePaths)) { if (-not [string]::IsNullOrWhiteSpace([string]$w)) { $wsCandidates.Add([string]$w) } } }
        if ($payload.workspace_roots) { foreach ($w in @($payload.workspace_roots)) { if (-not [string]::IsNullOrWhiteSpace([string]$w)) { $wsCandidates.Add([string]$w) } } }
        if ($payload.cwd -and -not [string]::IsNullOrWhiteSpace([string]$payload.cwd)) { $wsCandidates.Add([string]$payload.cwd) }
        $wsList = @($wsCandidates.ToArray())
        $ws = if ($wsList.Count -gt 0) { [string]$wsList[0] } else { "" }
        $toolName = ""; $pathArg = ""; $cmdArg = ""; $queryArg = ""
    }
    if ([string]::IsNullOrWhiteSpace($ws)) { exit 0 }
    $shortFile = if ($pathArg) { [System.IO.Path]::GetFileName($pathArg) } else { "" }

    # Zero-token Auto-Orchestration: sync Plan / TODO Markdown to .agents/office/tasks.json on write/edit
    if (($toolName -eq "write_file" -or $toolName -eq "edit_file") -and $pathArg -match '(?i)(plans[\\/][^\\/]+\.md|TODO\.md)$') {
        if (Get-Command Sync-SenPlanToTasks -ErrorAction SilentlyContinue) {
            $planTarget = if ($pathArg -match '(?i)plans[\\/][^\\/]+\.md$') { $pathArg } else { "" }
            [void](Sync-SenPlanToTasks -Workspace $ws -PlanPath $planTarget)
        }
        if ((Test-Path -LiteralPath (Join-Path $ws ".agents/office/process-audit.json")) -and (Get-Command Test-SenStageGate -ErrorAction SilentlyContinue)) {
            [void](Test-SenStageGate -Workspace $ws -Stage 2)
        }
    }

    $cfg = Get-SenOfficeConfig -Workspace $ws
    if ($cfg.mode -eq "off") { exit 0 }

    $from = "be"
    $to = "sys"
    $lane = "Execution"
    $kind = "ok"
    $ecoText = "$toolName"
    $model = "inherit"

    if ($toolName -eq "grep_search" -or $toolName -eq "find_by_name") {
        $from = "r1"
        $lane = "Scout"
        $model = "flash_lite"
        $q = if (-not [string]::IsNullOrWhiteSpace($queryArg)) { $queryArg } else { $shortFile }
        $ecoText = "Search: $q"
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
    }
    elseif ($toolName -eq "write_file" -or $toolName -eq "edit_file") {
        Test-SenStuckLoop -Workspace $ws -ToolName $toolName -Target $pathArg -Reset | Out-Null
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
    }
    elseif ($toolName -eq "run_command") {
        if ($cmdArg -match '(?i)(Validate-Repo|security|audit)') {
            $from = "sec"
            $lane = "Security Gate"
            $model = "pro"
            $ecoText = "Security/Repo check"
        }
        elseif ($cmdArg -match '(?i)(test|run\.ps1|pytest|jest|vitest)') {
            $from = "qa"
            $lane = "QA Gate"
            $ecoText = "Run test suite"
        }
        else {
            $from = "be"
            $lane = "System Cmd"
            $shortCmd = if ($cmdArg.Length -gt 48) { $cmdArg.Substring(0, 45) + "..." } else { $cmdArg }
            $ecoText = "Run: $shortCmd"
        }
    }

    $targetVal = if ($pathArg) { $pathArg } else { $cmdArg }
    Write-SenOfficeEvent -Workspace $ws -From $from -To $to -Lane $lane -EcoText $ecoText -FullText $ecoText `
        -Kind $kind -Hold 1 -Source "hook-post" -Tool $toolName -Target $targetVal -Command $cmdArg -Model $model | Out-Null
}
catch { <# PostToolUse telemetry is best-effort and must never fail a tool call #> }
exit 0
