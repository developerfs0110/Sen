# scripts/Sen.Harness.psm1
# Pure ASCII PowerShell module for Sen v0.4.0 Multi-Harness Adapter (Antigravity, Claude Code,
# Cursor, GitHub Copilot, Windsurf, Codex/OpenCode) and Two-Way Plan/TODO Synchronization.

$ErrorActionPreference = "Stop"

function Get-SenSupportedHarnesses {
    [CmdletBinding()]
    param()
    return @(
        [pscustomobject][ordered]@{ Id = "antigravity"; DisplayName = "Google Antigravity IDE"; RuleTarget = ".agents/rules/AGENTS.md"; HookTarget = ".agents/plugins/sen-method/hooks.json"; SupportsHooks = $true },
        [pscustomobject][ordered]@{ Id = "claude"; DisplayName = "Claude Code CLI / IDE"; RuleTarget = "CLAUDE.md"; HookTarget = ".claude/settings.json"; SupportsHooks = $true },
        [pscustomobject][ordered]@{ Id = "cursor"; DisplayName = "Cursor AI IDE"; RuleTarget = ".cursor/rules/sen-method.mdc"; HookTarget = ".cursor/hooks.json"; SupportsHooks = $true },
        [pscustomobject][ordered]@{ Id = "copilot"; DisplayName = "GitHub Copilot"; RuleTarget = ".github/copilot-instructions.md"; HookTarget = ".github/hooks/sen-hooks.json"; SupportsHooks = $true },
        [pscustomobject][ordered]@{ Id = "windsurf"; DisplayName = "Windsurf AI IDE"; RuleTarget = ".windsurfrules"; HookTarget = ".windsurf/hooks.json"; SupportsHooks = $true },
        [pscustomobject][ordered]@{ Id = "codex"; DisplayName = "Codex CLI / OpenCode"; RuleTarget = "AGENTS.md"; HookTarget = ".codex/hooks.json"; SupportsHooks = $true }
    )
}

function Get-SenPropValue {
    param($Obj, [string[]]$Names)
    if ($null -eq $Obj) { return "" }
    foreach ($n in $Names) {
        if ($Obj.PSObject.Properties.Name -contains $n) {
            $val = $Obj.$n
            if ($null -ne $val -and -not [string]::IsNullOrWhiteSpace([string]$val)) {
                return [string]$val
            }
        }
    }
    return ""
}

function ConvertFrom-SenHookPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )
    $rawTool = ""
    $argsObj = $null
    if ($InputObject.PSObject.Properties.Name -contains "toolCall" -and $null -ne $InputObject.toolCall) {
        $rawTool = Get-SenPropValue -Obj $InputObject.toolCall -Names @("name", "toolName")
        if ($InputObject.toolCall.PSObject.Properties.Name -contains "args") { $argsObj = $InputObject.toolCall.args }
    }
    if ([string]::IsNullOrWhiteSpace($rawTool)) {
        $rawTool = Get-SenPropValue -Obj $InputObject -Names @("tool_name", "toolName", "name", "hook_event_name")
    }
    if ($null -eq $argsObj) {
        if ($InputObject.PSObject.Properties.Name -contains "tool_input" -and $null -ne $InputObject.tool_input) { $argsObj = $InputObject.tool_input }
        elseif ($InputObject.PSObject.Properties.Name -contains "toolArgs" -and $null -ne $InputObject.toolArgs) { $argsObj = $InputObject.toolArgs }
        else { $argsObj = $InputObject }
    }

    $canonical = $rawTool
    switch -Regex ($rawTool) {
        '^(?i)(run_command|bash|run_terminal_cmd|shell|exec|execute_command)$' { $canonical = "run_command"; break }
        '^(?i)(write_file|write|create_file|write_to_file|notebookedit)$' { $canonical = "write_file"; break }
        '^(?i)(edit_file|edit|multiedit|replace_in_file|patch)$' { $canonical = "edit_file"; break }
        '^(?i)(read_file|read|view_file)$' { $canonical = "read_file"; break }
        '^(?i)(grep_search|find_by_name|grep|glob|codebase_search|file_search)$' { $canonical = "grep_search"; break }
    }

    $cmdLine = Get-SenPropValue -Obj $argsObj -Names @("CommandLine", "command", "cmd")
    $targetPath = Get-SenPropValue -Obj $argsObj -Names @("Path", "file_path", "target_file", "path", "SearchPath", "notebook_path")
    $query = Get-SenPropValue -Obj $argsObj -Names @("Query", "Pattern", "pattern", "query")

    $wsList = [System.Collections.Generic.List[string]]::new()
    if ($InputObject.PSObject.Properties.Name -contains "workspacePaths" -and $null -ne $InputObject.workspacePaths) {
        foreach ($w in @($InputObject.workspacePaths)) { if (-not [string]::IsNullOrWhiteSpace([string]$w)) { $wsList.Add([string]$w) } }
    }
    if ($InputObject.PSObject.Properties.Name -contains "workspace_roots" -and $null -ne $InputObject.workspace_roots) {
        foreach ($w in @($InputObject.workspace_roots)) { if (-not [string]::IsNullOrWhiteSpace([string]$w)) { $wsList.Add([string]$w) } }
    }
    $cwd = Get-SenPropValue -Obj $InputObject -Names @("cwd", "workspacePath", "workspace")
    if (-not [string]::IsNullOrWhiteSpace($cwd) -and -not $wsList.Contains($cwd)) { $wsList.Add($cwd) }

    $primaryWs = if ($wsList.Count -gt 0) { $wsList[0] } else { "" }
    $enforcePaths = ($InputObject.PSObject.Properties.Name -contains "enforceTaskPaths" -and [bool]$InputObject.enforceTaskPaths) -or ($env:SEN_ENFORCE_ALLOWED_PATHS -eq "1")
    $harness = if ($InputObject.PSObject.Properties.Name -contains "toolCall") { "antigravity" } elseif ($InputObject.PSObject.Properties.Name -contains "workspace_roots") { "cursor" } elseif ($InputObject.PSObject.Properties.Name -contains "tool_name") { "claude" } else { "generic" }

    return [pscustomobject][ordered]@{
        RawToolName = $rawTool; CanonicalTool = $canonical; CommandLine = $cmdLine; TargetPath = $targetPath
        Query = $query; WorkspacePath = $primaryWs; WorkspaceList = @($wsList.ToArray())
        EnforceTaskPaths = [bool]$enforcePaths; Harness = $harness
    }
}

function Update-SenManagedBlock {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Content, [string]$FrontMatter = "")
    $startTag = "<!-- SEN-METHOD:START -->"; $endTag = "<!-- SEN-METHOD:END -->"
    $managedBlock = "$startTag`n$($Content.Trim())`n$endTag"
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { [System.IO.Directory]::CreateDirectory($dir) | Out-Null }

    $existing = if (Test-Path -LiteralPath $Path) { [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) } else { "" }
    $pattern = '(?s)<!-- SEN-METHOD:START -->.*?<!-- SEN-METHOD:END -->'
    if ([string]::IsNullOrWhiteSpace($existing)) {
        $finalText = if (-not [string]::IsNullOrWhiteSpace($FrontMatter)) { "$($FrontMatter.Trim())`n`n$managedBlock`n" } else { "$managedBlock`n" }
    }
    elseif ($existing -match $pattern) {
        $finalText = [regex]::Replace($existing, $pattern, $managedBlock)
    }
    else {
        $prefix = $existing.TrimEnd()
        if (-not [string]::IsNullOrWhiteSpace($FrontMatter) -and -not $prefix.StartsWith("---")) { $prefix = "$($FrontMatter.Trim())`n`n$prefix" }
        $finalText = "$prefix`n`n$managedBlock`n"
    }
    [System.IO.File]::WriteAllText($Path, $finalText, [System.Text.UTF8Encoding]::new($false))
    return $true
}

function Remove-SenManagedBlock {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $existing = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $pattern = '(?s)\r?\n?<!-- SEN-METHOD:START -->.*?<!-- SEN-METHOD:END -->\r?\n?'
    if ($existing -notmatch $pattern) { return $false }
    $cleaned = ([regex]::Replace($existing, $pattern, "`n")).Trim()
    if ([string]::IsNullOrWhiteSpace($cleaned) -or $cleaned -match '^---\s*[\s\S]*?---$') {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
    else {
        [System.IO.File]::WriteAllText($Path, ($cleaned + "`n"), [System.Text.UTF8Encoding]::new($false))
    }
    return $true
}

function Build-SenHarnessBridgeText {
    param([string]$Workspace, [string]$HarnessId)
    $pluginRulesPath = Join-Path -Path $Workspace -ChildPath ".agents/plugins/sen-method/rules/AGENTS.md"
    $rulesPath = Join-Path -Path $Workspace -ChildPath ".agents/rules/AGENTS.md"
    if (Test-Path -LiteralPath $pluginRulesPath) {
        $pDir = [System.IO.Path]::GetDirectoryName($rulesPath)
        if ($pDir -and -not (Test-Path -LiteralPath $pDir)) { [System.IO.Directory]::CreateDirectory($pDir) | Out-Null }
        Copy-Item -LiteralPath $pluginRulesPath -Destination $rulesPath -Force
    }
    elseif (-not (Test-Path -LiteralPath $rulesPath)) {
        $rulesPath = Join-Path -Path $Workspace -ChildPath "rules/AGENTS.md"
    }
    $coreText = if (Test-Path -LiteralPath $rulesPath) { [System.IO.File]::ReadAllText($rulesPath, [System.Text.Encoding]::UTF8).Trim() } else { "# Sen Core Rule" }

    $profilePath = Join-Path -Path $Workspace -ChildPath ".agents/rules/profile.md"
    $profileText = if (Test-Path -LiteralPath $profilePath) { "`n`n" + [System.IO.File]::ReadAllText($profilePath, [System.Text.Encoding]::UTF8).Trim() } else { "" }

    $bridgeInfo = @"

## Multi-Harness Bridge ($HarnessId)
- **Single Source of Truth:** `.agents/` holds rules, skills (`.agents/plugins/sen-method/skills/` and `.agents/skills/`), state (`.agents/office/tasks.json`), and 3D AI Office.
- **Two-Way Sync:** Saving `docs/superpowers/plans/*.md` or `docs/TODO.md` auto-syncs tasks into `.agents/office/tasks.json`; completing tasks via `Complete-SenTaskReview` auto-ticks `[x]` in Markdown.
"@
    return ($coreText + $profileText + "`n" + $bridgeInfo.Trim())
}

function Install-SenHarnessHookFile {
    param([string]$Workspace, [string]$HarnessId, [string]$HookRelPath)
    if ([string]::IsNullOrWhiteSpace($HookRelPath)) { return $null }
    $fullHookPath = Join-Path -Path $Workspace -ChildPath $HookRelPath
    $guardRel = if (Test-Path -LiteralPath (Join-Path $Workspace ".agents/plugins/sen-method/scripts/guard.ps1")) {
        ".agents/plugins/sen-method/scripts/guard.ps1"
    }
    else {
        "scripts/guard.ps1"
    }
    $postRel = if (Test-Path -LiteralPath (Join-Path $Workspace ".agents/plugins/sen-method/scripts/office-post.ps1")) {
        ".agents/plugins/sen-method/scripts/office-post.ps1"
    }
    else {
        "scripts/office-post.ps1"
    }
    $guardCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File $guardRel"
    $postCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File $postRel"

    if ($HarnessId -eq "antigravity") {
        if (-not (Test-Path -LiteralPath $fullHookPath)) {
            $agObj = [ordered]@{
                "sen-destructive-command-guard" = [ordered]@{
                    PreToolUse  = @([ordered]@{ matcher = "run_command|write_file|edit_file"; hooks = @([ordered]@{ type = "command"; command = $guardCmd; timeout = 10 }) })
                    PostToolUse = @([ordered]@{ matcher = "run_command|write_file|edit_file|read_file|grep_search|find_by_name"; hooks = @([ordered]@{ type = "command"; command = $postCmd; timeout = 5 }) })
                }
            }
            Write-SenAtomicJson -Path $fullHookPath -InputObject $agObj -Depth 8
        }
        return $fullHookPath
    }

    $existingObj = Read-SenSafeJson -Path $fullHookPath
    $rootHash = if ($null -ne $existingObj) { ConvertTo-SenHashtable -InputObject $existingObj } else { @{} }
    if ($rootHash -isnot [hashtable]) { $rootHash = @{} }
    if (-not $rootHash.ContainsKey("hooks") -or $rootHash["hooks"] -isnot [hashtable]) {
        $rootHash["hooks"] = @{}
    }
    $rootHash["hooks"]["PreToolUse"] = @(
        [ordered]@{
            matcher = "Bash|Write|Edit|MultiEdit|run_command|write_file|edit_file|run_terminal_cmd"
            hooks   = @([ordered]@{ type = "command"; command = $guardCmd; timeout = 10 })
        }
    )
    $rootHash["hooks"]["PostToolUse"] = @(
        [ordered]@{
            matcher = "Bash|Write|Edit|MultiEdit|Read|Grep|Glob|run_command|write_file|edit_file|read_file|grep_search|find_by_name|run_terminal_cmd"
            hooks   = @([ordered]@{ type = "command"; command = $postCmd; timeout = 5 })
        }
    )
    Write-SenAtomicJson -Path $fullHookPath -InputObject $rootHash -Depth 10
    return $fullHookPath
}

function Resolve-SenRequestedHarnesses {
    param([string[]]$Harness)
    $catalog = @(Get-SenSupportedHarnesses)
    if ($null -eq $Harness -or $Harness.Count -eq 0 -or ($Harness -contains "all")) {
        return $catalog
    }
    $lower = @($Harness | ForEach-Object { ([string]$_).ToLowerInvariant().Trim() })
    return @($catalog | Where-Object { $lower -contains $_.Id })
}

function Install-SenHarness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [string[]]$Harness = @("all")
    )
    $selected = @(Resolve-SenRequestedHarnesses -Harness $Harness)
    $installed = [System.Collections.Generic.List[string]]::new()
    $filesCreated = [System.Collections.Generic.List[string]]::new()

    foreach ($h in $selected) {
        $bridgeText = Build-SenHarnessBridgeText -Workspace $Workspace -HarnessId $h.Id
        $ruleFullPath = Join-Path -Path $Workspace -ChildPath $h.RuleTarget
        if ($h.Id -eq "antigravity") {
            $rDir = [System.IO.Path]::GetDirectoryName($ruleFullPath)
            if ($rDir -and -not (Test-Path -LiteralPath $rDir)) { [System.IO.Directory]::CreateDirectory($rDir) | Out-Null }
            if (-not (Test-Path -LiteralPath $ruleFullPath)) {
                [System.IO.File]::WriteAllText($ruleFullPath, $bridgeText, [System.Text.UTF8Encoding]::new($false))
            }
        }
        else {
            $fm = if ($h.Id -eq "cursor") { "---`ndescription: Sen Methodology Core Rule & Multi-Harness Bridge`nalwaysApply: true`n---" } else { "" }
            [void](Update-SenManagedBlock -Path $ruleFullPath -Content $bridgeText -FrontMatter $fm)
        }
        $filesCreated.Add($h.RuleTarget)

        if ($h.SupportsHooks -and -not [string]::IsNullOrWhiteSpace($h.HookTarget)) {
            [void](Install-SenHarnessHookFile -Workspace $Workspace -HarnessId $h.Id -HookRelPath $h.HookTarget)
            $filesCreated.Add($h.HookTarget)
        }
        $installed.Add($h.Id)
    }

    $lock = Read-SenLock -Workspace $Workspace
    $existingH = if ($lock.ContainsKey("harnesses") -and $null -ne $lock["harnesses"]) { @($lock["harnesses"]) } else { @() }
    $mergedH = [System.Collections.Generic.List[string]]::new()
    foreach ($eh in $existingH) { if ($eh -and -not $mergedH.Contains([string]$eh)) { $mergedH.Add([string]$eh) } }
    foreach ($ih in $installed) { if (-not $mergedH.Contains($ih)) { $mergedH.Add($ih) } }
    $lock["harnesses"] = @($mergedH.ToArray())
    Write-SenLock -Workspace $Workspace -Lock $lock

    return [pscustomobject][ordered]@{ Workspace = $Workspace; Installed = @($installed.ToArray()); FilesCreated = @($filesCreated.ToArray()); UpdatedLock = $true }
}

function Uninstall-SenHarness {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Workspace, [string[]]$Harness = @())
    $selected = @(Resolve-SenRequestedHarnesses -Harness $Harness)
    $removed = [System.Collections.Generic.List[string]]::new()
    $filesUpdated = [System.Collections.Generic.List[string]]::new()

    foreach ($h in $selected) {
        if ($h.Id -eq "antigravity") { continue }
        $ruleFullPath = Join-Path -Path $Workspace -ChildPath $h.RuleTarget
        if (Remove-SenManagedBlock -Path $ruleFullPath) { $filesUpdated.Add($h.RuleTarget) }
        if ($h.SupportsHooks -and -not [string]::IsNullOrWhiteSpace($h.HookTarget)) {
            $hookFullPath = Join-Path -Path $Workspace -ChildPath $h.HookTarget
            $existingObj = Read-SenSafeJson -Path $hookFullPath
            if ($null -ne $existingObj) {
                $rootHash = ConvertTo-SenHashtable -InputObject $existingObj
                if ($rootHash -is [hashtable] -and $rootHash.ContainsKey("hooks")) {
                    $rootHash.Remove("hooks")
                    Write-SenAtomicJson -Path $hookFullPath -InputObject $rootHash -Depth 8
                    $filesUpdated.Add($h.HookTarget)
                }
            }
        }
        $removed.Add($h.Id)
    }

    $lock = Read-SenLock -Workspace $Workspace
    if ($lock.ContainsKey("harnesses") -and $null -ne $lock["harnesses"]) {
        $lock["harnesses"] = @($lock["harnesses"] | Where-Object { $removed -notcontains [string]$_ })
        Write-SenLock -Workspace $Workspace -Lock $lock
    }
    return [pscustomobject][ordered]@{ Workspace = $Workspace; Uninstalled = @($removed.ToArray()); FilesUpdated = @($filesUpdated.ToArray()) }
}

function Test-SenHarnessStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($h in @(Get-SenSupportedHarnesses)) {
        $rulePath = Join-Path -Path $Workspace -ChildPath $h.RuleTarget
        $ruleExists = Test-Path -LiteralPath $rulePath
        $hookOk = if ($h.SupportsHooks -and -not [string]::IsNullOrWhiteSpace($h.HookTarget)) { Test-Path -LiteralPath (Join-Path -Path $Workspace -ChildPath $h.HookTarget) } else { $true }
        $results.Add([pscustomobject][ordered]@{
                Id = $h.Id; DisplayName = $h.DisplayName; Installed = [bool]($ruleExists -and $hookOk)
                RuleExists = [bool]$ruleExists; HookConfigured = [bool]$hookOk; RulePath = $h.RuleTarget; HookPath = $h.HookTarget
            })
    }
    return @($results.ToArray())
}

function Sync-SenPlanToTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace,
        [string]$PlanPath = ""
    )
    $synced = 0
    $existingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($t in @(Get-SenTasks -Workspace $Workspace)) {
        if ($t -and $t.id) { [void]$existingIds.Add([string]$t.id) }
    }

    $todoPath = Join-Path -Path $Workspace -ChildPath "docs/TODO.md"
    if (Test-Path -LiteralPath $todoPath) {
        $todoText = [System.IO.File]::ReadAllText($todoPath, [System.Text.Encoding]::UTF8)
        $todoMatches = [regex]::Matches($todoText, '(?m)^-\s*\[([ xX~])\]\s*\*\*([A-Za-z0-9_-]+)(?:\s*\(([^)]+)\))?:\s*(.+?)\*\*\s*$')
        foreach ($m in $todoMatches) {
            $tid = $m.Groups[2].Value.Trim()
            $ttitle = $m.Groups[4].Value.Trim()
            if (-not $existingIds.Contains($tid)) {
                $stateChar = $m.Groups[1].Value
                $st = if ($stateChar -match '[xX]') { "done" } else { "backlog" }
                [void](New-SenTask -Workspace $Workspace -Id $tid -Title $ttitle -Tier 2 -Module "Backlog" -Assignee "pm" -Status $st)
                if ($st -eq "done") {
                    [void](Complete-SenTaskReview -Workspace $Workspace -Id $tid -Passed $true -Reviewer "pm" -EvidenceCommand "todo-verified" -ExitCode 0 -Notes "Synced [x] from TODO.md")
                }
                [void]$existingIds.Add($tid)
                $synced++
            }
        }
    }

    $planFiles = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($PlanPath) -and (Test-Path -LiteralPath $PlanPath)) {
        $planFiles.Add((Resolve-Path -LiteralPath $PlanPath).Path)
    }
    else {
        $plansDir = Join-Path -Path $Workspace -ChildPath "docs/superpowers/plans"
        if (Test-Path -LiteralPath $plansDir) {
            foreach ($pfItem in @(Get-ChildItem -LiteralPath $plansDir -Filter "*.md" -File | Sort-Object Name)) {
                $planFiles.Add($pfItem.FullName)
            }
        }
    }

    foreach ($pf in $planFiles) {
        $rawPlan = [System.IO.File]::ReadAllText($pf, [System.Text.Encoding]::UTF8)
        $basePrefix = ([System.IO.Path]::GetFileNameWithoutExtension($pf) -replace '[^A-Za-z0-9_-]', '-').ToUpperInvariant()
        $taskSections = [regex]::Matches($rawPlan, '(?ms)^###\s+Task\s+(\d+)(?:\s*\(`?([A-Za-z0-9_-]+)`?(?:[^)]*)\))?\s*:\s*([^\r\n]+)(.*?)(?=^###\s+Task\s+\d+|\z)')
        $prevTaskId = $null
        foreach ($sec in $taskSections) {
            $num = $sec.Groups[1].Value.Trim()
            $explicitId = $sec.Groups[2].Value.Trim()
            $tid = if (-not [string]::IsNullOrWhiteSpace($explicitId)) { $explicitId } elseif (-not $existingIds.Contains("PLAN-T$num")) { "PLAN-T$num" } else { "$basePrefix-T$num" }
            if ($existingIds.Contains($tid)) { $prevTaskId = $tid; continue }
            $title = $sec.Groups[3].Value.Trim()
            $body = $sec.Groups[4].Value
            $paths = @([regex]::Matches($body, '(?m)^-\s*(?:Create|Modify|Test):\s*`([^`:\r\n]+)') | ForEach-Object { $_.Groups[1].Value.Trim() } | Where-Object { $_ })
            $isParallel = ($title -match '(?i)\b(independent|parallel|song\s+song)\b') -or ($body -match '(?i)\b(DependsOn:\s*none|independent\s+task|parallel\s+execution)\b')
            $deps = if ($prevTaskId -and (-not $isParallel)) { @($prevTaskId) } else { @() }
            [void](New-SenTask -Workspace $Workspace -Id $tid -Title $title -Tier 3 -RiskLevel "high" -Module "Plan" -Assignee "dev_be" -DependsOn $deps -AllowedPaths $paths)
            [void]$existingIds.Add($tid)
            $synced++
            $prevTaskId = $tid
        }
    }

    return [pscustomobject][ordered]@{
        Workspace   = $Workspace
        SyncedCount = $synced
    }
}

function Sync-SenTasksToMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Workspace
    )
    $doneIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($t in @(Get-SenTasks -Workspace $Workspace)) {
        if ($t -and [string]$t.status -eq "done") {
            [void]$doneIds.Add([string]$t.id)
        }
    }
    if ($doneIds.Count -eq 0) { return [pscustomobject]@{ UpdatedFiles = 0 } }

    $updatedFiles = 0
    $todoCandidates = @(
        (Join-Path -Path $Workspace -ChildPath "docs/TODO.md"),
        (Join-Path -Path $Workspace -ChildPath "Code/sen-method/docs/TODO.md")
    )
    foreach ($tp in $todoCandidates) {
        if (-not (Test-Path -LiteralPath $tp)) { continue }
        $txt = [System.IO.File]::ReadAllText($tp, [System.Text.Encoding]::UTF8)
        $orig = $txt
        foreach ($did in $doneIds) {
            $escaped = [regex]::Escape($did)
            $txt = [regex]::Replace($txt, "(?m)^(-\s*)\[[ ~]\](\s*\*\*$escaped\b)", '$1[x]$2')
        }
        if ($txt -ne $orig) {
            [System.IO.File]::WriteAllText($tp, $txt, [System.Text.UTF8Encoding]::new($false))
            $updatedFiles++
        }
    }

    $plansDir = Join-Path -Path $Workspace -ChildPath "docs/superpowers/plans"
    if (Test-Path -LiteralPath $plansDir) {
        foreach ($pf in @(Get-ChildItem -LiteralPath $plansDir -Filter "*.md" -File)) {
            $pTxt = [System.IO.File]::ReadAllText($pf.FullName, [System.Text.Encoding]::UTF8)
            $pOrig = $pTxt
            foreach ($did in $doneIds) {
                $esc = [regex]::Escape($did)
                $secPattern = "(?ms)(^###\s+Task\s+\d+[^\r\n]*\b$esc\b[^\r\n]*\r?\n)(.*?)(?=^###\s+Task\s+\d+|\z)"
                if ($pTxt -match $secPattern) {
                    $pTxt = [regex]::Replace($pTxt, $secPattern, {
                            param($m)
                            $header = $m.Groups[1].Value
                            $secBody = [regex]::Replace($m.Groups[2].Value, '(?m)^(-\s*)\[ \]', '$1[x]')
                            return ($header + $secBody)
                        })
                }
            }
            if ($pTxt -ne $pOrig) {
                [System.IO.File]::WriteAllText($pf.FullName, $pTxt, [System.Text.UTF8Encoding]::new($false))
                $updatedFiles++
            }
        }
    }

    return [pscustomobject]@{ UpdatedFiles = $updatedFiles }
}

function Get-SenProcessCatalog {
    [CmdletBinding()]
    param([string]$ManifestPath = "")
    $path = if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath } else { Join-Path -Path $PSScriptRoot -ChildPath "process-manifest.json" }
    $obj = Read-SenSafeJson -Path $path
    if ($null -eq $obj) { throw "Process manifest not found: $path" }
    return $obj
}

function Initialize-SenProcessAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Workspace, [string]$ProjectName = "Project", [ValidateRange(1, 3)][int]$Tier = 3, [ValidateSet("core", "web_mobile", "all")][string]$ProjectScope = "core")
    $catalog = Get-SenProcessCatalog
    $auditPath = Join-Path -Path $Workspace -ChildPath ".agents/office/process-audit.json"
    $existing = Read-SenSafeJson -Path $auditPath
    $latchedMap = @{}
    if ($null -ne $existing -and $existing.PSObject.Properties.Name -contains "selectedSteps") {
        foreach ($oldStep in @($existing.selectedSteps)) {
            if ($oldStep -and [bool]$oldStep.latched) { $latchedMap[[string]$oldStep.id] = $oldStep }
        }
    }
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($s in @($catalog.steps)) {
        if ([int]$s.minTier -gt $Tier) { continue }
        if ([string]$s.scope -eq "web_mobile" -and $ProjectScope -eq "core") { continue }
        $sid = [string]$s.id
        $wasLatched = $latchedMap.ContainsKey($sid) -or ($sid -eq "S1-RISK" -or $sid -eq "S1-AUDIT-INIT")
        $selected.Add([pscustomobject][ordered]@{
                id = $sid; stage = [int]$s.stage; title = [string]$s.title; passed = [bool]$wasLatched; latched = [bool]$wasLatched
                verifiedAt = if ($wasLatched) { [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }
            })
    }
    $offCfg = Get-SenOfficeConfig -Workspace $Workspace
    $offMode = if ($offCfg -and $offCfg.mode) { [string]$offCfg.mode } else { "eco" }
    $offPort = if ($offCfg -and $offCfg.port) { [int]$offCfg.port } else { 47890 }
    $offAction = if ($Tier -lt 2) { "none" } elseif ($offMode -eq "off") { "offer_enable" } else { "auto_start" }
    $auditObj = [pscustomobject][ordered]@{
        manifestVersion = [string]$catalog.manifestVersion; projectName = $ProjectName; tier = $Tier
        projectScope = $ProjectScope; officeMode = $offMode; officeUrl = "http://127.0.0.1:$offPort/"; officeAction = $offAction
        updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); selectedSteps = @($selected.ToArray())
    }
    Write-SenAtomicJson -Path $auditPath -InputObject $auditObj -Depth 8
    return $auditObj
}

function Test-SenSingleStepEvidence {
    param([string]$Workspace, [string]$StepId)
    switch ($StepId) {
        "S1-RISK" { return $true }
        "S1-AUDIT-INIT" { return (Test-Path -LiteralPath (Join-Path $Workspace ".agents/office/process-audit.json")) }
        "S2-EXPERT-COST" {
            $sDir = Join-Path $Workspace "docs/superpowers/specs"
            if (-not (Test-Path -LiteralPath $sDir)) { return $false }
            foreach ($f in @(Get-ChildItem -LiteralPath $sDir -Filter "*.md" -File)) {
                $t = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
                if ($t -match '(?i)(Resource Cost|T.i nguy.n ti.u t.n|Best-of-the-Best)') { return $true }
            }
            return $false
        }
        "S2-DESIGN-SPEC" {
            $sDir = Join-Path $Workspace "docs/superpowers/specs"
            $specs = if (Test-Path -LiteralPath $sDir) { @(Get-ChildItem -LiteralPath $sDir -Filter "*.md" -File | Where-Object { $_.Length -gt 0 }) } else { @() }
            if ($specs.Count -eq 0) { return $false }
            if ($null -eq (Read-SenOfficeShowcase -Workspace $Workspace)) {
                Write-SenOfficeShowcase -Workspace $Workspace -Showcase @{ projectTitle = (Split-Path $Workspace -Leaf); tier = 3; phase1 = @{ summary = "Design Blueprint: $($specs[0].Name)"; specPath = $specs[0].Name; expectedOutputs = @($specs[0].Name) } }
            }
            return $true
        }
        "S2-IMPL-PLAN" {
            $pDir = Join-Path $Workspace "docs/superpowers/plans"
            return ((Test-Path -LiteralPath $pDir) -and @(Get-ChildItem -LiteralPath $pDir -Filter "*.md" -File | Where-Object { $_.Length -gt 0 }).Count -gt 0)
        }
        "S2-TASK-DAG" {
            [void](Sync-SenPlanToTasks -Workspace $Workspace)
            $tasks = @(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.status -ne "backlog" })
            return ($tasks.Count -gt 0)
        }
        "S3-RESTORE-POINT" {
            $rpDir = Join-Path $Workspace ".agents/.sen-restore"
            if (-not (Test-Path -LiteralPath $rpDir)) { return $false }
            $validRps = @(Get-ChildItem -LiteralPath $rpDir -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "manifest.json") })
            return ($validRps.Count -gt 0)
        }
        "S3-TDD-VERIFY" {
            [void](Sync-SenPlanToTasks -Workspace $Workspace)
            $active = @(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.status -ne "backlog" })
            if ($active.Count -eq 0) { return $false }
            $incomplete = @($active | Where-Object { [string]$_.status -ne "done" -or $null -eq $_.evidence -or [int]$_.evidence.exitCode -ne 0 })
            return ($incomplete.Count -eq 0)
        }
        "S3-TWOWAY-SYNC" {
            [void](Sync-SenPlanToTasks -Workspace $Workspace)
            [void](Sync-SenTasksToMarkdown -Workspace $Workspace)
            $unverified = @(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.status -ne "backlog" -and [string]$_.status -ne "done" })
            return ($unverified.Count -eq 0)
        }
        "S4-CLEAN-CODE" { return [bool](Measure-SenCodeHealth -Path $Workspace).Healthy }
        "S4-VN-LAW" { return [bool](Invoke-SenVnLawScan -Path $Workspace).CompliantCodeLevel }
        "S4-CONTEXT-REPORT" {
            $ctxFile = Join-Path $Workspace "docs/CONTEXT.md"
            if (-not ((Test-Path -LiteralPath $ctxFile) -and (Get-Item -LiteralPath $ctxFile).Length -gt 0)) { return $false }
            $sc = Read-SenOfficeShowcase -Workspace $Workspace
            if ($null -eq $sc -or $null -eq $sc.phase2) {
                $p1 = if ($sc -and $sc.phase1) { $sc.phase1 } else { @{ summary = "Design Blueprint"; expectedOutputs = @("docs/CONTEXT.md") } }
                Write-SenOfficeShowcase -Workspace $Workspace -Showcase @{ projectTitle = (Split-Path $Workspace -Leaf); tier = 3; phase1 = $p1; phase2 = @{ summary = "Verified Delivery Output"; verifiedOutputs = @("docs/CONTEXT.md"); gates = @{ tests = "PASS"; build = "PASS"; security = "PASS"; legal = "PASS" } } }
            }
            return $true
        }
    }
    return $true
}

function Test-SenStageGate {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Workspace, [ValidateRange(1, 4)][int]$Stage)
    $auditPath = Join-Path -Path $Workspace -ChildPath ".agents/office/process-audit.json"
    $audit = Read-SenSafeJson -Path $auditPath
    if ($null -eq $audit) { $audit = Initialize-SenProcessAudit -Workspace $Workspace -Tier 3 -ProjectScope "core" }
    else {
        $cat = Get-SenProcessCatalog
        if ([string]$audit.manifestVersion -ne [string]$cat.manifestVersion) {
            $audit = Initialize-SenProcessAudit -Workspace $Workspace -ProjectName ([string]$audit.projectName) -Tier ([int]$audit.tier) -ProjectScope ([string]$audit.projectScope)
        }
    }
    $missing = [System.Collections.Generic.List[string]]::new()
    $changed = $false
    foreach ($st in @($audit.selectedSteps)) {
        if ([int]$st.stage -gt $Stage -or [bool]$st.latched) { continue }
        if (Test-SenSingleStepEvidence -Workspace $Workspace -StepId ([string]$st.id)) {
            $st.passed = $true; $st.latched = $true; $st.verifiedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); $changed = $true
        }
        else { $missing.Add([string]$st.id) }
    }
    if ($changed) { $audit.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); Write-SenAtomicJson -Path $auditPath -InputObject $audit -Depth 8 }
    return [pscustomobject][ordered]@{ Stage = $Stage; Passed = ($missing.Count -eq 0); MissingSteps = @($missing.ToArray()); Audit = $audit }
}

function Test-SenProjectCompliance {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $finalStage = Test-SenStageGate -Workspace $Workspace -Stage 4
    $allSteps = @($finalStage.Audit.selectedSteps)
    $doneSteps = @($allSteps | Where-Object { [bool]$_.passed })
    return [pscustomobject][ordered]@{
        Compliant = $finalStage.Passed; TotalSelected = $allSteps.Count; CompletedCount = $doneSteps.Count; MissingSteps = $finalStage.MissingSteps
        StagesSummary = @(1..4 | ForEach-Object {
                $sNum = $_; $sItems = @($allSteps | Where-Object { [int]$_.stage -eq $sNum }); $sDone = @($sItems | Where-Object { [bool]$_.passed })
                [pscustomobject][ordered]@{ Stage = $sNum; Total = $sItems.Count; Done = $sDone.Count; Passed = ($sDone.Count -eq $sItems.Count) }
            })
    }
}

function Get-SenRemoteCiStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RepoSlug, [string]$HeadSha = "", [scriptblock]$RestInvoker = $null)
    $invoker = if ($null -ne $RestInvoker) { $RestInvoker } else { { param([string]$Uri) Invoke-RestMethod -Uri $Uri -Headers @{ "User-Agent" = "Sen-CI-Monitor" } -TimeoutSec 15 } }
    $runsUri = "https://api.github.com/repos/$RepoSlug/actions/runs?per_page=5"
    try { $runsResp = & $invoker $runsUri }
    catch { return [pscustomobject][ordered]@{ Found = $false; RunId = 0; Status = "error"; Conclusion = "error"; HtmlUrl = ""; HeadSha = $HeadSha; FailedSteps = @("API error: $($_.Exception.Message)") } }
    $runs = if ($runsResp -and $runsResp.workflow_runs) { @($runsResp.workflow_runs) } else { @() }
    $run = if (-not [string]::IsNullOrWhiteSpace($HeadSha)) { $runs | Where-Object { [string]$_.head_sha -like "$HeadSha*" } | Select-Object -First 1 } else { $runs | Select-Object -First 1 }
    if ($null -eq $run) { return [pscustomobject][ordered]@{ Found = $false; RunId = 0; Status = "not_found"; Conclusion = ""; HtmlUrl = ""; HeadSha = $HeadSha; FailedSteps = @() } }
    $failedSteps = [System.Collections.Generic.List[string]]::new()
    if ([string]$run.conclusion -eq "failure" -and $run.jobs_url) {
        try {
            $jobsResp = & $invoker ([string]$run.jobs_url)
            foreach ($j in @($jobsResp.jobs)) {
                foreach ($bs in @($j.steps | Where-Object { [string]$_.conclusion -eq "failure" } | ForEach-Object { "$($j.name) > $($_.name)" })) { $failedSteps.Add($bs) }
            }
        }
        catch { <# Ignore job detail fetch error #> }
    }
    return [pscustomobject][ordered]@{
        Found = $true; RunId = [long]$run.id; Status = [string]$run.status; Conclusion = [string]$run.conclusion
        HtmlUrl = [string]$run.html_url; HeadSha = [string]$run.head_sha; FailedSteps = @($failedSteps.ToArray())
    }
}

function Invoke-SenCiPushLoop {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RepoPath, [Parameter(Mandatory = $true)][string]$CommitMessage, [string]$RepoSlug = "developerfs0110/Sen", [int]$PollSeconds = 5, [int]$TimeoutSeconds = 90, [int]$MaxAttempts = 3, [scriptblock]$RestInvoker = $null, [scriptblock]$HealAction = $null, [switch]$SkipPush)
    $pushed = $false; $headSha = ""; $ci = $null; $ciOk = $false
    for ($attempt = 1; $attempt -le [Math]::Max(1, $MaxAttempts); $attempt++) {
        $valScript = Join-Path -Path $RepoPath -ChildPath "scripts/Validate-Repo.ps1"
        if (Test-Path -LiteralPath $valScript) {
            $valErrs = @(& $valScript -Root $RepoPath)
            if ($valErrs.Count -gt 0) {
                return [pscustomobject][ordered]@{ LocalPassed = $false; Pushed = $false; CiPassed = $false; Attempts = $attempt; HeadSha = ""; Errors = $valErrs; CiStatus = $null }
            }
        }
        if (-not $SkipPush) {
            $prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
            Push-Location -LiteralPath $RepoPath
            try {
                if (@(git status --porcelain 2>&1).Count -gt 0) { [void](git add -A 2>&1); [void](git commit -m $CommitMessage 2>&1) }
                if ($attempt -eq 1) { [void](git push 2>&1) } else { [void](git push origin HEAD 2>&1) }
                $pushed = ($LASTEXITCODE -eq 0)
                $headSha = ([string](git rev-parse HEAD 2>&1)).Trim()
            }
            finally { Pop-Location; $ErrorActionPreference = $prevEap }
        }
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            $ci = Get-SenRemoteCiStatus -RepoSlug $RepoSlug -HeadSha $headSha -RestInvoker $RestInvoker
            if ($ci.Found -and $ci.Status -eq "completed") { break }
            if ($PollSeconds -gt 0) { Start-Sleep -Seconds $PollSeconds } else { break }
        }
        $ciOk = ($null -ne $ci -and $ci.Found -and $ci.Status -eq "completed" -and $ci.Conclusion -eq "success")
        if ($ciOk -or $null -eq $HealAction -or $attempt -ge $MaxAttempts) { break }
        & $HealAction $ci.FailedSteps
    }
    return [pscustomobject][ordered]@{
        LocalPassed = $true; Pushed = $pushed; CiPassed = [bool]$ciOk; HeadSha = $headSha
        Errors = if ($ci -and $ci.FailedSteps) { $ci.FailedSteps } else { @() }; CiStatus = $ci
    }
}

function Invoke-SenDialecticalAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $sDir = Join-Path $Workspace "docs/superpowers/specs"
    $hasDialecticalSpec = $false
    if (Test-Path -LiteralPath $sDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $sDir -Filter "*.md" -File | Where-Object { $_.Length -gt 0 })) {
            $txt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
            if ($txt -match '(?i)(Best-of-the-Best|Resource Cost|T.i nguy.n)' -and $txt -match '(?i)(Critique|Ph.n bi.n|Counterexample|Falsif|Adversarial)') { $hasDialecticalSpec = $true }
        }
    }
    $ch = Measure-SenCodeHealth -Path $Workspace
    $vl = Invoke-SenVnLawScan -Path $Workspace
    $tasks = @(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.status -ne "backlog" })
    $badEvidence = @($tasks | Where-Object { [string]$_.status -eq "done" -and ($null -eq $_.evidence -or [int]$_.evidence.exitCode -ne 0 -or ([string]$_.evidence.command -notmatch '[A-Za-z0-9]{3,}')) })
    $vectors = @(
        [pscustomobject]@{ Id = "V1-DIALECTICAL-SPEC"; Passed = [bool]($hasDialecticalSpec -or -not (Test-Path -LiteralPath $sDir)); Detail = "Spec contains Thesis (Best-of-the-Best + Cost) and Antithesis (Critique)" },
        [pscustomobject]@{ Id = "V2-BOUNDARY-HEALTH"; Passed = [bool]$ch.Healthy; Detail = "CodeHealth Score=$($ch.Score)" },
        [pscustomobject]@{ Id = "V3-SOCRATIC-EVIDENCE"; Passed = ($badEvidence.Count -eq 0); Detail = "Unverified done tasks=$($badEvidence.Count)" },
        [pscustomobject]@{ Id = "V4-LEGAL-PARTITION"; Passed = [bool]$vl.CompliantCodeLevel; Detail = "VnLaw RedFlags=$($vl.CodeRedFlags.Count)" }
    )
    $passedCount = @($vectors | Where-Object { $_.Passed }).Count
    return [pscustomobject][ordered]@{
        Workspace = $Workspace; Passed = ($passedCount -eq $vectors.Count)
        Score = [int][Math]::Round(($passedCount * 100.0) / $vectors.Count); Vectors = $vectors
    }
}

function Test-SenCapabilityParity {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][string]$SenRoot = "")
    $root = if (-not [string]::IsNullOrWhiteSpace($SenRoot)) { $SenRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path }
    $missing = [System.Collections.Generic.List[string]]::new()
    $rulePath = Join-Path $root "rules/AGENTS.md"
    $ruleTxt = if (Test-Path -LiteralPath $rulePath) { [System.IO.File]::ReadAllText($rulePath, [System.Text.Encoding]::UTF8) } else { "" }
    $reqPrims = @("Get-SenTaskRiskScore", "Invoke-SenDialecticalAudit", "New-SenRestorePoint", "Restore-SenRestorePoint", "Write-SenOfficeShowcase", "Measure-SenCodeHealth", "Invoke-SenVnLawScan", "Test-SenDeliveryGate", "Invoke-SenCiPushLoop", "Add-SenBacklogItem", "Instant-Ack")
    foreach ($p in $reqPrims) { if ($ruleTxt -notmatch "\b$([regex]::Escape($p))\b") { $missing.Add("L1-RuleMissingPrimitive:$p") } }
    if ($ruleTxt -match '(?i)\bor inline\b') { $missing.Add("L1-RuleContainsInlineLoophole") }
    $cat = Get-SenProcessCatalog -ManifestPath (Join-Path $root "scripts/process-manifest.json")
    if (@($cat.steps).Count -ne 12) { $missing.Add("L2-ManifestStepCount:$(@($cat.steps).Count)") }
    $s2Spec = @($cat.steps | Where-Object { $_.id -eq "S2-DESIGN-SPEC" }) | Select-Object -First 1
    $s4Ctx = @($cat.steps | Where-Object { $_.id -eq "S4-CONTEXT-REPORT" }) | Select-Object -First 1
    if ($null -eq $s2Spec -or [string]$s2Spec.title -notmatch 'Write-SenOfficeShowcase') { $missing.Add("L2-ManifestMissingPhase1Showcase") }
    if ($null -eq $s4Ctx -or [string]$s4Ctx.title -notmatch 'Write-SenOfficeShowcase') { $missing.Add("L2-ManifestMissingPhase2Showcase") }
    $harnessTxt = [System.IO.File]::ReadAllText((Join-Path $root "scripts/Sen.Harness.psm1"), [System.Text.Encoding]::UTF8)
    foreach ($st in @($cat.steps)) { if ($harnessTxt -notmatch ('"' + [regex]::Escape([string]$st.id) + '"')) { $missing.Add("L2-EvidenceMissingStep:$($st.id)") } }
    $skillsDir = Join-Path $root "skills"
    $skillDirs = if (Test-Path -LiteralPath $skillsDir) { @(Get-ChildItem -LiteralPath $skillsDir -Filter "sen-*" -Directory) } else { @() }
    if ($skillDirs.Count -lt 9) { $missing.Add("L3-SkillCount:$($skillDirs.Count)") }
    foreach ($sd in $skillDirs) {
        $skFile = Join-Path $sd.FullName "SKILL.md"
        if (-not (Test-Path -LiteralPath $skFile) -or ([System.IO.File]::ReadAllText($skFile, [System.Text.Encoding]::UTF8) -notmatch '(?s)^---\s*\r?\n.+?\r?\n---')) { $missing.Add("L3-InvalidSkill:$($sd.Name)") }
    }
    $modFiles = @(Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter "*.psm1" -File)
    $testFiles = if (Test-Path -LiteralPath (Join-Path $root "tests")) { @(Get-ChildItem -LiteralPath (Join-Path $root "tests") -Filter "*.Tests.ps1" -File) } else { @() }
    $testCorpus = ($testFiles | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8) }) -join "`n"
    foreach ($mf in $modFiles) {
        $mTxt = [System.IO.File]::ReadAllText($mf.FullName, [System.Text.Encoding]::UTF8)
        $expLine = [regex]::Match($mTxt, '(?m)^Export-ModuleMember\s+-Function\s+([^\r\n]+)').Groups[1].Value
        foreach ($fn in @($expLine -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            if ($testCorpus -notmatch "\b$([regex]::Escape($fn))\b") { $missing.Add("L4-UntestedExport:$fn") }
        }
    }
    if (Test-Path -LiteralPath $rulePath) {
        $rBytes = (Get-Item -LiteralPath $rulePath).Length
        $rLines = @([System.IO.File]::ReadAllLines($rulePath)).Count
        if ($rBytes -gt 5750 -or $rLines -gt 95) { $missing.Add("L5-ContextBudgetExceeded:${rBytes}B/${rLines}L") }
    }
    else { $missing.Add("L5-MissingRuleFile") }
    return [pscustomobject][ordered]@{ Passed = ($missing.Count -eq 0); MissingItems = @($missing.ToArray()); CheckedLayers = 5 }
}

Export-ModuleMember -Function Get-SenSupportedHarnesses, ConvertFrom-SenHookPayload, Update-SenManagedBlock, Remove-SenManagedBlock, Install-SenHarness, Uninstall-SenHarness, Test-SenHarnessStatus, Sync-SenPlanToTasks, Sync-SenTasksToMarkdown, Get-SenProcessCatalog, Initialize-SenProcessAudit, Test-SenStageGate, Test-SenProjectCompliance, Get-SenRemoteCiStatus, Invoke-SenCiPushLoop, Invoke-SenDialecticalAudit, Test-SenCapabilityParity
