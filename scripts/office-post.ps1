# scripts/office-post.ps1
# Antigravity PostToolUse telemetry hook (ASCII only) for Sen Office v0.2.0.
# Zero-token evidence recorder: maps tool executions to 3D office roles, updates stuck-loop tracker,
# redacts secrets, and appends to <WORKSPACE>/.agents/office/events.jsonl when mode != "off".

$ErrorActionPreference = "SilentlyContinue"

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $payload = $raw | ConvertFrom-Json
    $wsList = @($payload.workspacePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($wsList.Count -eq 0) { exit 0 }
    $ws = [string]$wsList[0]

    $senModule = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Runtime.psm1"
    if (-not (Test-Path -LiteralPath $senModule)) {
        $senModule = Join-Path -Path $PSScriptRoot -ChildPath "Sen.psm1"
    }
    if (-not (Test-Path -LiteralPath $senModule)) { exit 0 }
    Import-Module $senModule -Force -ErrorAction SilentlyContinue

    $cfg = Get-SenOfficeConfig -Workspace $ws
    if ($cfg.mode -eq "off") { exit 0 }

    $toolName = if ($payload.toolCall -and $payload.toolCall.name) { [string]$payload.toolCall.name } elseif ($payload.tool_name) { [string]$payload.tool_name } else { "" }
    $argsObj = if ($payload.toolCall -and $payload.toolCall.args) { $payload.toolCall.args } elseif ($payload.tool_input) { $payload.tool_input } else { $null }
    $pathArg = if ($argsObj -and $argsObj.Path) { [string]$argsObj.Path } elseif ($argsObj -and $argsObj.SearchPath) { [string]$argsObj.SearchPath } else { "" }
    $cmdArg = if ($argsObj -and $argsObj.CommandLine) { [string]$argsObj.CommandLine } else { "" }
    $shortFile = if ($pathArg) { [System.IO.Path]::GetFileName($pathArg) } else { "" }

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
        $q = if ($argsObj.Query) { [string]$argsObj.Query } elseif ($argsObj.Pattern) { [string]$argsObj.Pattern } else { $shortFile }
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
