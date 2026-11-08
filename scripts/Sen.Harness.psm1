# scripts/Sen.Harness.psm1 - Sen Multi-Harness Adapter & Sync
$ErrorActionPreference = "Stop"

function Get-SenSupportedHarnesses {
  [CmdletBinding()] param()
  return @(
    [pscustomobject][ordered]@{ Id = "antigravity"; DisplayName = "Google Antigravity IDE"; RuleTarget = ".agents/rules/AGENTS.md"; HookTarget = ".agents/plugins/sen-method/hooks.json"; SupportsHooks = $true; CapabilityLevel = "full" },
    [pscustomobject][ordered]@{ Id = "claude"; DisplayName = "Claude Code CLI / IDE"; RuleTarget = "CLAUDE.md"; HookTarget = ".claude/settings.json"; SupportsHooks = $true; CapabilityLevel = "full" },
    [pscustomobject][ordered]@{ Id = "cursor"; DisplayName = "Cursor AI IDE"; RuleTarget = ".cursor/rules/sen-method.mdc"; HookTarget = ".cursor/hooks.json"; SupportsHooks = $true; CapabilityLevel = "full" },
    [pscustomobject][ordered]@{ Id = "copilot"; DisplayName = "GitHub Copilot"; RuleTarget = ".github/copilot-instructions.md"; HookTarget = ".github/hooks/sen-hooks.json"; SupportsHooks = $true; CapabilityLevel = "rules-only" },
    [pscustomobject][ordered]@{ Id = "windsurf"; DisplayName = "Windsurf AI IDE"; RuleTarget = ".windsurfrules"; HookTarget = ".windsurf/hooks.json"; SupportsHooks = $true; CapabilityLevel = "partial" },
    [pscustomobject][ordered]@{ Id = "codex"; DisplayName = "Codex CLI / OpenCode"; RuleTarget = "AGENTS.md"; HookTarget = ".codex/hooks.json"; SupportsHooks = $true; CapabilityLevel = "partial" }
  )
}

function Get-SenPropValue {
  param($Obj, [string[]]$Names)
  if ($null -eq $Obj) { return "" }
  foreach ($n in $Names) {
    if ($Obj.PSObject.Properties.Name -contains $n -and $null -ne $Obj.$n -and -not [string]::IsNullOrWhiteSpace([string]$Obj.$n)) { return [string]$Obj.$n }
  }
  return ""
}

function ConvertFrom-SenHookPayload {
  [CmdletBinding()] param([Parameter(Mandatory = $true)]$InputObject)
  $rawTool = ""; $argsObj = $null
  if ($InputObject.PSObject.Properties.Name -contains "toolCall" -and $null -ne $InputObject.toolCall) {
    $rawTool = Get-SenPropValue -Obj $InputObject.toolCall -Names @("name", "toolName")
    if ($InputObject.toolCall.PSObject.Properties.Name -contains "args") { $argsObj = $InputObject.toolCall.args }
  }
  if ([string]::IsNullOrWhiteSpace($rawTool)) { $rawTool = Get-SenPropValue -Obj $InputObject -Names @("tool_name", "toolName", "name", "hook_event_name") }
  if ($null -eq $argsObj) {
    $argsObj = if ($InputObject.PSObject.Properties.Name -contains "tool_input" -and $null -ne $InputObject.tool_input) { $InputObject.tool_input }
    elseif ($InputObject.PSObject.Properties.Name -contains "toolArgs" -and $null -ne $InputObject.toolArgs) { $InputObject.toolArgs } else { $InputObject }
  }
  $canonical = switch -Regex ($rawTool) {
    '^(?i)(run_command|bash|run_terminal_cmd|shell|exec|execute_command)$' { "run_command"; break }
    '^(?i)(write_file|write|create_file|write_to_file|notebookedit)$' { "write_file"; break }
    '^(?i)(edit_file|edit|multiedit|replace_in_file|patch)$' { "edit_file"; break }
    '^(?i)(read_file|read|view_file)$' { "read_file"; break }
    '^(?i)(grep_search|find_by_name|grep|glob|codebase_search|file_search)$' { "grep_search"; break }
    '^(?i)(invoke_subagent|task|dispatch_agent|spawn_agent)$' { "invoke_subagent"; break }
    '^(?i)(send_message|message_agent)$' { "send_message"; break }
    '^(?i)(manage_subagents|manage_task)$' { "manage_subagents"; break }
    default { $rawTool }
  }
  $cmdLine = Get-SenPropValue -Obj $argsObj -Names @("CommandLine", "command", "cmd")
  $targetPath = Get-SenPropValue -Obj $argsObj -Names @("Path", "file_path", "target_file", "path", "SearchPath", "notebook_path")
  $query = Get-SenPropValue -Obj $argsObj -Names @("Query", "Pattern", "pattern", "query")
  $wsList = [System.Collections.Generic.List[string]]::new()
  foreach ($prop in @("workspacePaths", "workspace_roots")) {
    if ($InputObject.PSObject.Properties.Name -contains $prop -and $null -ne $InputObject.$prop) {
      foreach ($w in @($InputObject.$prop)) { if (-not [string]::IsNullOrWhiteSpace([string]$w)) { $wsList.Add([string]$w) } }
    }
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
  $managedBlock = "<!-- SEN-METHOD:START -->`n$($Content.Trim())`n<!-- SEN-METHOD:END -->"
  $dir = [System.IO.Path]::GetDirectoryName($Path)
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { [System.IO.Directory]::CreateDirectory($dir) | Out-Null }
  $existing = if (Test-Path -LiteralPath $Path) { [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) } else { "" }
  $pattern = '(?s)<!-- SEN-METHOD:START -->.*?<!-- SEN-METHOD:END -->'
  if ([string]::IsNullOrWhiteSpace($existing)) { $finalText = if (-not [string]::IsNullOrWhiteSpace($FrontMatter)) { "$($FrontMatter.Trim())`n`n$managedBlock`n" } else { "$managedBlock`n" } }
  elseif ($existing -match $pattern) { $finalText = [regex]::Replace($existing, $pattern, $managedBlock) }
  else {
    $prefix = $existing.TrimEnd()
    if (-not [string]::IsNullOrWhiteSpace($FrontMatter) -and -not $prefix.StartsWith("---")) { $prefix = "$($FrontMatter.Trim())`n`n$prefix" }
    $finalText = "$prefix`n`n$managedBlock`n"
  }
  [System.IO.File]::WriteAllText($Path, $finalText, [System.Text.UTF8Encoding]::new($false)); return $true
}

function Remove-SenManagedBlock {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $existing = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
  $pattern = '(?s)\r?\n?<!-- SEN-METHOD:START -->.*?<!-- SEN-METHOD:END -->\r?\n?'
  if ($existing -notmatch $pattern) { return $false }
  $cleaned = ([regex]::Replace($existing, $pattern, "`n")).Trim()
  if ([string]::IsNullOrWhiteSpace($cleaned) -or $cleaned -match '^---\s*[\s\S]*?---$') { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
  else { [System.IO.File]::WriteAllText($Path, ($cleaned + "`n"), [System.Text.UTF8Encoding]::new($false)) }
  return $true
}

function Build-SenHarnessBridgeText {
  param([string]$Workspace, [string]$HarnessId)
  $pRules = Join-Path $Workspace ".agents/plugins/sen-method/rules/AGENTS.md"
  $rPath = Join-Path $Workspace ".agents/rules/AGENTS.md"
  if (Test-Path -LiteralPath $pRules) {
    $pDir = [System.IO.Path]::GetDirectoryName($rPath)
    if ($pDir -and -not (Test-Path -LiteralPath $pDir)) { [System.IO.Directory]::CreateDirectory($pDir) | Out-Null }
    Copy-Item -LiteralPath $pRules -Destination $rPath -Force
  }
  elseif (-not (Test-Path -LiteralPath $rPath)) { $rPath = Join-Path $Workspace "rules/AGENTS.md" }
  $core = if (Test-Path -LiteralPath $rPath) { [System.IO.File]::ReadAllText($rPath, [System.Text.Encoding]::UTF8).Trim() } else { "# Sen Core Rule" }
  $profP = Join-Path $Workspace ".agents/rules/profile.md"
  $prof = if (Test-Path -LiteralPath $profP) { "`n`n" + [System.IO.File]::ReadAllText($profP, [System.Text.Encoding]::UTF8).Trim() } else { "" }
  $info = "## Multi-Harness Bridge ($HarnessId)`n- **Single Source of Truth:** `.agents/` holds rules, skills (`.agents/plugins/sen-method/skills/` and `.agents/skills/`), state (`.agents/office/tasks.json`), and 3D AI Office.`n- **Two-Way Sync:** Saving `docs/superpowers/plans/*.md` or `docs/TODO.md` auto-syncs tasks into `.agents/office/tasks.json`; completing tasks via `Complete-SenTaskReview` auto-ticks `[x]` in Markdown."
  return ($core + $prof + "`n`n" + $info)
}

function Install-SenHarnessHookFile {
  param([string]$Workspace, [string]$HarnessId, [string]$HookRelPath)
  if ([string]::IsNullOrWhiteSpace($HookRelPath)) { return $null }
  $fullP = Join-Path $Workspace $HookRelPath; $isWin = ($env:OS -eq "Windows_NT"); $ext = if ($isWin) { "ps1" } else { "sh" }
  $pBase = if (Test-Path -LiteralPath (Join-Path $Workspace ".agents/plugins/sen-method/scripts/guard.ps1")) { ".agents/plugins/sen-method/scripts" } else { "scripts" }
  $gCmd = if ($isWin) { "powershell -NoProfile -ExecutionPolicy Bypass -File $pBase/guard.$ext" } else { "sh $pBase/guard.$ext" }
  $pCmd = if ($isWin) { "powershell -NoProfile -ExecutionPolicy Bypass -File $pBase/office-post.$ext" } else { "sh $pBase/office-post.$ext" }
  if ($HarnessId -eq "antigravity") {
    if (-not (Test-Path -LiteralPath $fullP)) {
      $agObj = [ordered]@{ "sen-destructive-command-guard" = [ordered]@{ PreToolUse = @([ordered]@{ matcher = "run_command|write_file|edit_file|read_file"; hooks = @([ordered]@{ type = "command"; command = $gCmd; timeout = 10 }) }); PostToolUse = @([ordered]@{ matcher = "run_command|write_file|edit_file|read_file|grep_search|find_by_name|invoke_subagent|send_message|manage_subagents"; hooks = @([ordered]@{ type = "command"; command = $pCmd; timeout = 5 }) }) } }
      Write-SenAtomicJson -Path $fullP -InputObject $agObj -Depth 8
    }
    return $fullP
  }
  $exObj = Read-SenSafeJson -Path $fullP
  $rHash = if ($null -ne $exObj) { ConvertTo-SenHashtable -InputObject $exObj } else { @{} }
  if ($rHash -isnot [hashtable]) { $rHash = @{} }
  if (-not $rHash.ContainsKey("hooks") -or $rHash["hooks"] -isnot [hashtable]) { $rHash["hooks"] = @{} }
  $rHash["hooks"]["PreToolUse"] = @([ordered]@{ matcher = "Bash|Write|Edit|MultiEdit|Read|run_command|write_file|edit_file|read_file|run_terminal_cmd"; hooks = @([ordered]@{ type = "command"; command = $gCmd; timeout = 10 }) })
  $rHash["hooks"]["PostToolUse"] = @([ordered]@{ matcher = "Bash|Write|Edit|MultiEdit|Read|Grep|Glob|run_command|write_file|edit_file|read_file|grep_search|find_by_name|run_terminal_cmd|invoke_subagent|send_message|manage_subagents"; hooks = @([ordered]@{ type = "command"; command = $pCmd; timeout = 5 }) })
  Write-SenAtomicJson -Path $fullP -InputObject $rHash -Depth 10; return $fullP
}

function Resolve-SenRequestedHarnesses {
  param([string[]]$Harness)
  $cat = @(Get-SenSupportedHarnesses)
  if ($null -eq $Harness -or $Harness.Count -eq 0 -or ($Harness -contains "all")) { return $cat }
  $low = @($Harness | ForEach-Object { ([string]$_).ToLowerInvariant().Trim() })
  return @($cat | Where-Object { $low -contains $_.Id })
}

function Install-SenHarness {
  [CmdletBinding()] param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string[]]$Harness = @("all"))
  $sel = @(Resolve-SenRequestedHarnesses -Harness $Harness)
  $inst = [System.Collections.Generic.List[string]]::new(); $created = [System.Collections.Generic.List[string]]::new()
  foreach ($h in $sel) {
    $bTxt = Build-SenHarnessBridgeText -Workspace $Workspace -HarnessId $h.Id
    $rFull = Join-Path $Workspace $h.RuleTarget
    if ($h.Id -eq "antigravity") {
      $rDir = [System.IO.Path]::GetDirectoryName($rFull)
      if ($rDir -and -not (Test-Path -LiteralPath $rDir)) { [System.IO.Directory]::CreateDirectory($rDir) | Out-Null }
      if (-not (Test-Path -LiteralPath $rFull)) { [System.IO.File]::WriteAllText($rFull, $bTxt, [System.Text.UTF8Encoding]::new($false)) }
    }
    else {
      $fm = if ($h.Id -eq "cursor") { "---`ndescription: Sen Methodology Core Rule & Multi-Harness Bridge`nalwaysApply: true`n---" } else { "" }
      [void](Update-SenManagedBlock -Path $rFull -Content $bTxt -FrontMatter $fm)
    }
    $created.Add($h.RuleTarget)
    if ($h.SupportsHooks -and $h.HookTarget) { [void](Install-SenHarnessHookFile -Workspace $Workspace -HarnessId $h.Id -HookRelPath $h.HookTarget); $created.Add($h.HookTarget) }
    $inst.Add($h.Id)
  }
  $lock = Read-SenLock -Workspace $Workspace
  $exH = if ($lock.ContainsKey("harnesses") -and $null -ne $lock["harnesses"]) { @($lock["harnesses"]) } else { @() }
  $mH = [System.Collections.Generic.List[string]]::new()
  foreach ($eh in $exH) { if ($eh -and -not $mH.Contains([string]$eh)) { $mH.Add([string]$eh) } }
  foreach ($ih in $inst) { if (-not $mH.Contains($ih)) { $mH.Add($ih) } }
  $lock["harnesses"] = @($mH.ToArray()); Write-SenLock -Workspace $Workspace -Lock $lock
  return [pscustomobject][ordered]@{ Workspace = $Workspace; Installed = @($inst.ToArray()); FilesCreated = @($created.ToArray()); UpdatedLock = $true }
}

function Uninstall-SenHarness {
  [CmdletBinding()] param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string[]]$Harness = @())
  $sel = @(Resolve-SenRequestedHarnesses -Harness $Harness)
  $rem = [System.Collections.Generic.List[string]]::new(); $upd = [System.Collections.Generic.List[string]]::new()
  foreach ($h in $sel) {
    if ($h.Id -eq "antigravity") { continue }
    if (Remove-SenManagedBlock -Path (Join-Path $Workspace $h.RuleTarget)) { $upd.Add($h.RuleTarget) }
    if ($h.SupportsHooks -and $h.HookTarget) {
      $hFull = Join-Path $Workspace $h.HookTarget
      $exObj = Read-SenSafeJson -Path $hFull
      if ($null -ne $exObj) {
        $rHash = ConvertTo-SenHashtable -InputObject $exObj
        if ($rHash -is [hashtable] -and $rHash.ContainsKey("hooks")) { $rHash.Remove("hooks"); Write-SenAtomicJson -Path $hFull -InputObject $rHash -Depth 8; $upd.Add($h.HookTarget) }
      }
    }
    $rem.Add($h.Id)
  }
  $lock = Read-SenLock -Workspace $Workspace
  if ($lock.ContainsKey("harnesses") -and $null -ne $lock["harnesses"]) {
    $lock["harnesses"] = @($lock["harnesses"] | Where-Object { $rem -notcontains [string]$_ }); Write-SenLock -Workspace $Workspace -Lock $lock
  }
  return [pscustomobject][ordered]@{ Workspace = $Workspace; Uninstalled = @($rem.ToArray()); FilesUpdated = @($upd.ToArray()) }
}

function Test-SenHarnessStatus {
  [CmdletBinding()] param([Parameter(Mandatory = $true)][string]$Workspace)
  $res = [System.Collections.Generic.List[object]]::new()
  foreach ($h in @(Get-SenSupportedHarnesses)) {
    $rOk = Test-Path -LiteralPath (Join-Path $Workspace $h.RuleTarget)
    $hOk = if ($h.SupportsHooks -and $h.HookTarget) { Test-Path -LiteralPath (Join-Path $Workspace $h.HookTarget) } else { $true }
    $res.Add([pscustomobject][ordered]@{ Id = $h.Id; DisplayName = $h.DisplayName; CapabilityLevel = $h.CapabilityLevel; Installed = [bool]($rOk -and $hOk); RuleExists = [bool]$rOk; HookConfigured = [bool]$hOk; RulePath = $h.RuleTarget; HookPath = $h.HookTarget })
  }
  return @($res.ToArray())
}

function Sync-SenPlanToTasks {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$PlanPath = "")
  $synced = 0; $existingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($t in @(Get-SenTasks -Workspace $Workspace)) { if ($t -and $t.id) { [void]$existingIds.Add([string]$t.id) } }
  $todoPath = Join-Path -Path $Workspace -ChildPath "docs/TODO.md"
  if (Test-Path -LiteralPath $todoPath) {
    $todoText = [System.IO.File]::ReadAllText($todoPath, [System.Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches($todoText, '(?m)^-\s*\[([ xX~])\]\s*\*\*([A-Za-z0-9_-]+)(?:\s*\(([^)]+)\))?:\s*(.+?)\*\*\s*$')) {
      $tid = $m.Groups[2].Value.Trim(); $ttitle = $m.Groups[4].Value.Trim()
      if (-not $existingIds.Contains($tid)) {
        $st = if ($m.Groups[1].Value -match '[xX]') { "done" } else { "backlog" }
        [void](New-SenTask -Workspace $Workspace -Id $tid -Title $ttitle -Tier 2 -Module "Backlog" -Assignee "pm" -Status $st)
        if ($st -eq "done") { [void](Complete-SenTaskReview -Workspace $Workspace -Id $tid -Passed $true -Reviewer "pm" -EvidenceCommand "todo-verified" -ExitCode 0 -Notes "Synced [x] from TODO.md") }
        [void]$existingIds.Add($tid); $synced++
      }
    }
  }
  $planFiles = [System.Collections.Generic.List[string]]::new()
  if (-not [string]::IsNullOrWhiteSpace($PlanPath) -and (Test-Path -LiteralPath $PlanPath)) { $planFiles.Add((Resolve-Path -LiteralPath $PlanPath).Path) }
  elseif (Test-Path -LiteralPath (Join-Path $Workspace "docs/superpowers/plans")) {
    foreach ($pfItem in @(Get-ChildItem -LiteralPath (Join-Path $Workspace "docs/superpowers/plans") -Filter "*.md" -File | Sort-Object Name)) { $planFiles.Add($pfItem.FullName) }
  }
  foreach ($pf in $planFiles) {
    $rawPlan = [System.IO.File]::ReadAllText($pf, [System.Text.Encoding]::UTF8)
    $basePrefix = ([System.IO.Path]::GetFileNameWithoutExtension($pf) -replace '[^A-Za-z0-9_-]', '-').ToUpperInvariant(); $prevTaskId = $null
    foreach ($sec in [regex]::Matches($rawPlan, '(?ms)^###\s+Task\s+(\d+)(?:\s*\(`?([A-Za-z0-9_-]+)`?(?:[^)]*)\))?\s*:\s*([^\r\n]+)(.*?)(?=^###\s+Task\s+\d+|\z)')) {
      $num = $sec.Groups[1].Value.Trim(); $explicitId = $sec.Groups[2].Value.Trim()
      $tid = if (-not [string]::IsNullOrWhiteSpace($explicitId)) { $explicitId } elseif (-not $existingIds.Contains("PLAN-T$num")) { "PLAN-T$num" } else { "$basePrefix-T$num" }
      if ($existingIds.Contains($tid)) { $prevTaskId = $tid; continue }
      $title = $sec.Groups[3].Value.Trim(); $body = $sec.Groups[4].Value
      $paths = @([regex]::Matches($body, '(?m)^-\s*(?:Create|Modify|Test):\s*`([^`:\r\n]+)') | ForEach-Object { $_.Groups[1].Value.Trim() } | Where-Object { $_ })
      $isParallel = ($title -match '(?i)\b(independent|parallel|song\s+song)\b') -or ($body -match '(?i)\b(DependsOn:\s*none|independent\s+task|parallel\s+execution)\b')
      $deps = if ($prevTaskId -and (-not $isParallel)) { @($prevTaskId) } else { @() }
      [void](New-SenTask -Workspace $Workspace -Id $tid -Title $title -Tier 3 -RiskLevel "high" -Module "Plan" -Assignee "dev_be" -DependsOn $deps -AllowedPaths $paths)
      [void]$existingIds.Add($tid); $synced++; $prevTaskId = $tid
    }
  }
  return [pscustomobject][ordered]@{ Workspace = $Workspace; SyncedCount = $synced }
}

function Sync-SenTasksToMarkdown {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
  $doneIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($t in @(Get-SenTasks -Workspace $Workspace)) { if ($t -and [string]$t.status -eq "done") { [void]$doneIds.Add([string]$t.id) } }
  if ($doneIds.Count -eq 0) { return [pscustomobject]@{ UpdatedFiles = 0 } }
  $updatedFiles = 0
  foreach ($tp in @((Join-Path $Workspace "docs/TODO.md"), (Join-Path $Workspace "Code/sen-method/docs/TODO.md"))) {
    if (-not (Test-Path -LiteralPath $tp)) { continue }
    $txt = [System.IO.File]::ReadAllText($tp, [System.Text.Encoding]::UTF8); $orig = $txt
    foreach ($did in $doneIds) { $txt = [regex]::Replace($txt, "(?m)^(-\s*)\[[ ~]\](\s*\*\*$([regex]::Escape($did))\b)", '$1[x]$2') }
    if ($txt -ne $orig) { [System.IO.File]::WriteAllText($tp, $txt, [System.Text.UTF8Encoding]::new($false)); $updatedFiles++ }
  }
  if (Test-Path -LiteralPath (Join-Path $Workspace "docs/superpowers/plans")) {
    foreach ($pf in @(Get-ChildItem -LiteralPath (Join-Path $Workspace "docs/superpowers/plans") -Filter "*.md" -File)) {
      $pTxt = [System.IO.File]::ReadAllText($pf.FullName, [System.Text.Encoding]::UTF8); $pOrig = $pTxt
      foreach ($did in $doneIds) {
        $secPattern = "(?ms)(^###\s+Task\s+\d+[^\r\n]*\b$([regex]::Escape($did))\b[^\r\n]*\r?\n)(.*?)(?=^###\s+Task\s+\d+|\z)"
        if ($pTxt -match $secPattern) { $pTxt = [regex]::Replace($pTxt, $secPattern, { param($m) $m.Groups[1].Value + [regex]::Replace($m.Groups[2].Value, '(?m)^(-\s*)\[ \]', '$1[x]') }) }
      }
      if ($pTxt -ne $pOrig) { [System.IO.File]::WriteAllText($pf.FullName, $pTxt, [System.Text.UTF8Encoding]::new($false)); $updatedFiles++ }
    }
  }
  return [pscustomobject]@{ UpdatedFiles = $updatedFiles }
}

function Get-SenProcessCatalog {
  [CmdletBinding()] param([string]$ManifestPath = "")
  $p = if ($ManifestPath) { $ManifestPath } else { Join-Path $PSScriptRoot "process-manifest.json" }
  $o = Read-SenSafeJson -Path $p; if ($null -eq $o) { throw "Manifest not found: $p" }; return $o
}

function Initialize-SenProcessAudit {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$ProjectName = "Project", [ValidateRange(1, 3)][int]$Tier = 3, [ValidateSet("core", "web_mobile", "all")][string]$ProjectScope = "core", [switch]$PreserveLatched)
  $cat = Get-SenProcessCatalog; $aPath = Join-Path $Workspace ".agents/office/process-audit.json"
  $ex = Read-SenSafeJson -Path $aPath; $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  $same = ($null -ne $ex) -and ([string]$ex.projectName -eq $ProjectName)
  $start = if ($PreserveLatched -and $same -and $ex.PSObject.Properties['startedAt'] -and $ex.startedAt) { [string]$ex.startedAt } else { $now }
  $lMap = @{}
  if ($PreserveLatched -and $same -and $ex.PSObject.Properties.Name -contains "selectedSteps") {
    foreach ($os in @($ex.selectedSteps)) { if ($os -and [bool]$os.latched -and [string]$os.verifiedAt -ge $start) { $lMap[[string]$os.id] = $os } }
  }
  $sel = [System.Collections.Generic.List[object]]::new()
  foreach ($s in @($cat.steps)) {
    if ([int]$s.minTier -gt $Tier -or ([string]$s.scope -eq "web_mobile" -and $ProjectScope -eq "core")) { continue }
    $sid = [string]$s.id; $lat = $lMap.ContainsKey($sid) -or ($sid -in @("S1-RISK", "S1-AUDIT-INIT"))
    $vAt = if ($lMap.ContainsKey($sid)) { [string]$lMap[$sid].verifiedAt } elseif ($lat) { $now } else { $null }
    $sel.Add([pscustomobject][ordered]@{ id = $sid; stage = [int]$s.stage; title = [string]$s.title; passed = [bool]$lat; latched = [bool]$lat; verifiedAt = $vAt })
  }
  $cfg = Get-SenOfficeConfig -Workspace $Workspace; $m = if ($cfg -and $cfg.mode) { [string]$cfg.mode } else { "eco" }; $pt = if ($cfg -and $cfg.port) { [int]$cfg.port } else { 47890 }
  $act = if ($Tier -lt 2) { "none" } elseif ($m -eq "off") { "offer_enable" } else { "auto_start" }
  $obj = [pscustomobject][ordered]@{ manifestVersion = [string]$cat.manifestVersion; projectName = $ProjectName; tier = $Tier; projectScope = $ProjectScope; officeMode = $m; officeUrl = "http://127.0.0.1:$pt/"; officeAction = $act; startedAt = $start; updatedAt = $now; selectedSteps = @($sel.ToArray()) }
  Write-SenAtomicJson -Path $aPath -InputObject $obj -Depth 8; return $obj
}

function Test-SenSingleStepEvidence {
  param([string]$Workspace, [string]$StepId, [string]$SessionStartedAt = "", [string]$ProjectPath = "")
  $targetDir = if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath } else { $Workspace }
  $minUtc = if ([string]::IsNullOrWhiteSpace($SessionStartedAt)) { [DateTime]::MinValue } else { [DateTime]::Parse($SessionStartedAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) }
  switch ($StepId) {
    "S1-RISK" { return $true }
    "S1-AUDIT-INIT" { return (Test-Path -LiteralPath (Join-Path $Workspace ".agents/office/process-audit.json")) }
    "S2-EXPERT-COST" {
      $daFile = Join-Path $Workspace ".agents/office/dialectical-audit.json"
      if ((Test-Path -LiteralPath $daFile) -and (Get-Item -LiteralPath $daFile).LastWriteTimeUtc -ge $minUtc -and [bool](Read-SenSafeJson -Path $daFile).Passed) { return $true }
      $sDir = Join-Path $Workspace "docs/superpowers/specs"
      if (-not (Test-Path -LiteralPath $sDir)) { return $false }
      foreach ($f in @(Get-ChildItem -LiteralPath $sDir -Filter "*.md" -File | Where-Object { $_.LastWriteTimeUtc -ge $minUtc })) {
        if ([System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) -match '(?i)(Resource Cost|T.i nguy.n ti.u t.n|Best-of-the-Best)') { return $true }
      }
      return $false
    }
    "S2-DESIGN-SPEC" {
      $sDir = Join-Path $Workspace "docs/superpowers/specs"
      $specs = if (Test-Path -LiteralPath $sDir) { @(Get-ChildItem -LiteralPath $sDir -Filter "*.md" -File | Where-Object { $_.Length -gt 0 -and $_.LastWriteTimeUtc -ge $minUtc }) } else { @() }
      if ($specs.Count -eq 0) { return $false }
      $sc = Read-SenOfficeShowcase -Workspace $Workspace
      if ($null -eq $sc -or $null -eq $sc.phase1) { [void](Write-SenOfficeShowcase -Workspace $Workspace -Phase 1 -TaskId $specs[0].Name -Title (Split-Path $Workspace -Leaf) -Tier 3 -Blueprint "Design Blueprint: $($specs[0].Name)" -ExpectedOutputs @($specs[0].Name)) }
      return $true
    }
    "S2-IMPL-PLAN" {
      $pDir = Join-Path $Workspace "docs/superpowers/plans"
      return ((Test-Path -LiteralPath $pDir) -and @(Get-ChildItem -LiteralPath $pDir -Filter "*.md" -File | Where-Object { $_.Length -gt 0 -and $_.LastWriteTimeUtc -ge $minUtc }).Count -gt 0)
    }
    "S2-TASK-DAG" {
      [void](Sync-SenPlanToTasks -Workspace $Workspace)
      return (@(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.status -ne "backlog" -and ([string]::IsNullOrWhiteSpace($SessionStartedAt) -or [string]$_.updatedAt -ge $SessionStartedAt -or [string]$_.createdAt -ge $SessionStartedAt) }).Count -gt 0)
    }
    "S3-RESTORE-POINT" {
      $rpDir = Join-Path $Workspace ".agents/.sen-restore"
      if (-not (Test-Path -LiteralPath $rpDir)) { return $false }
      return (@(Get-ChildItem -LiteralPath $rpDir -Directory | Where-Object { $mf = Join-Path $_.FullName "manifest.json"; (Test-Path -LiteralPath $mf) -and (Get-Item -LiteralPath $mf).LastWriteTimeUtc -ge $minUtc }).Count -gt 0)
    }
    "S3-TDD-VERIFY" {
      [void](Sync-SenPlanToTasks -Workspace $Workspace)
      if ((Get-Command Test-SenHungTasks -ErrorAction SilentlyContinue) -and (-not (Test-SenHungTasks -Workspace $Workspace).Healthy)) { return $false }
      $active = @(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.status -ne "backlog" })
      if ($active.Count -eq 0) { return $false }
      $sessDone = @($active | Where-Object { [string]::IsNullOrWhiteSpace($SessionStartedAt) -or [string]$_.updatedAt -ge $SessionStartedAt -or ($_.evidence -and [string]$_.evidence.verifiedAt -ge $SessionStartedAt) })
      if ($sessDone.Count -eq 0) { return $false }
      return (@($active | Where-Object { [string]$_.status -ne "done" -or $null -eq $_.evidence -or [int]$_.evidence.exitCode -ne 0 }).Count -eq 0)
    }
    "S3-TWOWAY-SYNC" {
      [void](Sync-SenPlanToTasks -Workspace $Workspace); [void](Sync-SenTasksToMarkdown -Workspace $Workspace)
      return (@(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.status -ne "backlog" -and [string]$_.status -ne "done" }).Count -eq 0)
    }
    "S4-CLEAN-CODE" { return [bool](Measure-SenCodeHealth -Path $targetDir).Healthy }
    "S4-VN-LAW" { return [bool](Invoke-SenVnLawScan -Path $targetDir).CompliantCodeLevel }
    "S4-CONTEXT-REPORT" {
      $ctxFile = Join-Path $Workspace "docs/CONTEXT.md"
      if (-not ((Test-Path -LiteralPath $ctxFile) -and (Get-Item -LiteralPath $ctxFile).Length -gt 0 -and (Get-Item -LiteralPath $ctxFile).LastWriteTimeUtc -ge $minUtc)) { return $false }
      $sc = Read-SenOfficeShowcase -Workspace $Workspace
      if ($null -eq $sc -or $null -eq $sc.phase2) { [void](Write-SenOfficeShowcase -Workspace $Workspace -Phase 2 -Title (Split-Path $Workspace -Leaf) -Tier 3 -Blueprint "Verified Delivery Output" -VerifiedOutputs @("docs/CONTEXT.md")) }
      return $true
    }
  }
  return $true
}

function Test-SenStageGate {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [ValidateRange(1, 4)][int]$Stage, [switch]$IgnoreLatched, [string]$ProjectPath = "")
  $auditPath = Join-Path -Path $Workspace -ChildPath ".agents/office/process-audit.json"
  $audit = Read-SenSafeJson -Path $auditPath
  if ($null -eq $audit) { $audit = Initialize-SenProcessAudit -Workspace $Workspace -Tier 3 -ProjectScope "core" }
  elseif ([string]$audit.manifestVersion -ne [string](Get-SenProcessCatalog).manifestVersion) {
    $audit = Initialize-SenProcessAudit -Workspace $Workspace -ProjectName ([string]$audit.projectName) -Tier ([int]$audit.tier) -ProjectScope ([string]$audit.projectScope) -PreserveLatched
  }
  $sessStart = if ($audit.PSObject.Properties['startedAt'] -and $audit.startedAt) { [string]$audit.startedAt } else { "" }
  $missing = [System.Collections.Generic.List[string]]::new(); $changed = $false
  foreach ($st in @($audit.selectedSteps)) {
    if ([int]$st.stage -gt $Stage) { continue }
    $isFreshLatch = [bool]$st.latched -and (-not $IgnoreLatched.IsPresent) -and ([string]::IsNullOrWhiteSpace($sessStart) -or [string]$st.verifiedAt -ge $sessStart) -and ([string]$st.id -in @("S1-RISK", "S1-AUDIT-INIT") -or [string]$st.verifiedAt -gt $sessStart -or (Test-SenSingleStepEvidence -Workspace $Workspace -StepId ([string]$st.id) -SessionStartedAt $sessStart -ProjectPath $ProjectPath))
    if ($isFreshLatch) { continue }
    if (Test-SenSingleStepEvidence -Workspace $Workspace -StepId ([string]$st.id) -SessionStartedAt $sessStart -ProjectPath $ProjectPath) {
      $st.passed = $true; $st.latched = $true; $st.verifiedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); $changed = $true
    }
    else {
      if ([bool]$st.passed -or [bool]$st.latched) { $st.passed = $false; $st.latched = $false; $st.verifiedAt = $null; $changed = $true }
      $missing.Add([string]$st.id)
    }
  }
  if ($changed) { $audit.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); Write-SenAtomicJson -Path $auditPath -InputObject $audit -Depth 8 }
  return [pscustomobject][ordered]@{ Stage = $Stage; Passed = ($missing.Count -eq 0); MissingSteps = @($missing.ToArray()); Audit = $audit }
}

function Test-SenProjectCompliance {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$ProjectPath = "")
  $finalStage = Test-SenStageGate -Workspace $Workspace -Stage 4 -ProjectPath $ProjectPath
  $allSteps = @($finalStage.Audit.selectedSteps); $doneSteps = @($allSteps | Where-Object { [bool]$_.passed })
  return [pscustomobject][ordered]@{
    Compliant = $finalStage.Passed; TotalSelected = $allSteps.Count; CompletedCount = $doneSteps.Count; MissingSteps = $finalStage.MissingSteps
    StagesSummary = @(1..4 | ForEach-Object { $sNum = $_; $sItems = @($allSteps | Where-Object { [int]$_.stage -eq $sNum }); $sDone = @($sItems | Where-Object { [bool]$_.passed }); [pscustomobject][ordered]@{ Stage = $sNum; Total = $sItems.Count; Done = $sDone.Count; Passed = ($sDone.Count -eq $sItems.Count) } })
  }
}

function Get-SenRemoteCiStatus {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][string]$RepoSlug = "developerfs0110/Sen", [string]$HeadSha = "", [Alias("WorkspacePath", "RepositoryPath", "RepoPath", "Path")][string]$Workspace = "", [scriptblock]$RestInvoker = $null)
  $invoker = if ($null -ne $RestInvoker) { $RestInvoker } else { { param([string]$Uri) Invoke-RestMethod -Uri $Uri -Headers @{ "User-Agent" = "Sen-CI-Monitor" } -TimeoutSec 15 } }
  try { $runsResp = & $invoker "https://api.github.com/repos/$RepoSlug/actions/runs?per_page=5" }
  catch { return [pscustomobject][ordered]@{ Found = $false; RunId = 0; Status = "error"; Conclusion = "error"; HtmlUrl = ""; HeadSha = $HeadSha; FailedSteps = @("API error: $($_.Exception.Message)") } }
  $runs = if ($runsResp -and $runsResp.workflow_runs) { @($runsResp.workflow_runs) } else { @() }
  $run = if (-not [string]::IsNullOrWhiteSpace($HeadSha)) { $runs | Where-Object { [string]$_.head_sha -like "$HeadSha*" } | Select-Object -First 1 } else { $runs | Select-Object -First 1 }
  if ($null -eq $run) { return [pscustomobject][ordered]@{ Found = $false; RunId = 0; Status = "not_found"; Conclusion = ""; HtmlUrl = ""; HeadSha = $HeadSha; FailedSteps = @() } }
  $failedSteps = [System.Collections.Generic.List[string]]::new()
  if ([string]$run.conclusion -eq "failure" -and $run.jobs_url) {
    try {
      foreach ($j in @((& $invoker ([string]$run.jobs_url)).jobs)) {
        foreach ($bs in @($j.steps | Where-Object { [string]$_.conclusion -eq "failure" } | ForEach-Object { "$($j.name) > $($_.name)" })) { $failedSteps.Add($bs) }
      }
    }
    catch { <# Ignore job detail fetch error #> }
  }
  return [pscustomobject][ordered]@{ Found = $true; RunId = [long]$run.id; Status = [string]$run.status; Conclusion = [string]$run.conclusion; HtmlUrl = [string]$run.html_url; HeadSha = [string]$run.head_sha; FailedSteps = @($failedSteps.ToArray()) }
}

function Invoke-SenCiPushLoop {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$RepoPath, [Parameter(Mandatory = $true)][string]$CommitMessage, [string]$RepoSlug = "developerfs0110/Sen", [int]$PollSeconds = 5, [int]$TimeoutSeconds = 90, [int]$MaxAttempts = 3, [scriptblock]$RestInvoker = $null, [scriptblock]$HealAction = $null, [switch]$SkipPush)
  $pushed = $false; $headSha = ""; $ci = $null; $ciOk = $false
  for ($attempt = 1; $attempt -le [Math]::Max(1, $MaxAttempts); $attempt++) {
    $valScript = Join-Path -Path $RepoPath -ChildPath "scripts/Validate-Repo.ps1"
    if (Test-Path -LiteralPath $valScript) {
      $valErrs = @(& $valScript -Root $RepoPath)
      if ($valErrs.Count -gt 0) { return [pscustomobject][ordered]@{ LocalPassed = $false; Pushed = $false; CiPassed = $false; Attempts = $attempt; HeadSha = ""; Errors = $valErrs; CiStatus = $null } }
    }
    if (-not $SkipPush) {
      $prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"; Push-Location -LiteralPath $RepoPath
      try {
        if (@(git status --porcelain 2>&1).Count -gt 0) { [void](git add -A 2>&1); [void](git commit -m $CommitMessage 2>&1) }
        if ($attempt -eq 1) { [void](git push 2>&1) } else { [void](git push origin HEAD 2>&1) }
        $pushed = ($LASTEXITCODE -eq 0); $headSha = ([string](git rev-parse HEAD 2>&1)).Trim()
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
    $preSuite = if (Get-Command Test-SenSuiteIntegrity -ErrorAction SilentlyContinue) { Test-SenSuiteIntegrity -TestsPath (Join-Path $RepoPath "tests") } else { $null }
    & $HealAction $ci.FailedSteps
    if ($null -ne $preSuite -and $preSuite.AssertionCount -gt 0) {
      $postSuite = Test-SenSuiteIntegrity -TestsPath (Join-Path $RepoPath "tests") -MinFiles $preSuite.FileCount -MinAssertions $preSuite.AssertionCount
      if (-not $postSuite.Passed) { return [pscustomobject][ordered]@{ LocalPassed = $false; Pushed = $pushed; CiPassed = $false; Attempts = $attempt; HeadSha = $headSha; Errors = @("TestTamperBlocked: $($postSuite.Reason)"); CiStatus = $ci } }
    }
  }
  return [pscustomobject][ordered]@{ LocalPassed = $true; Pushed = $pushed; CiPassed = [bool]$ciOk; HeadSha = $headSha; Errors = if ($ci -and $ci.FailedSteps) { $ci.FailedSteps } else { @() }; CiStatus = $ci }
}

function Invoke-SenDialecticalAudit {
  [CmdletBinding()]
  param([Parameter(Mandatory = $false)][Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$ProjectPath = "")
  $targetDir = if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath } else { $Workspace }
  $sDir = Join-Path $Workspace "docs/superpowers/specs"; $hasDialecticalSpec = $false
  if (Test-Path -LiteralPath $sDir) {
    foreach ($f in @(Get-ChildItem -LiteralPath $sDir -Filter "*.md" -File | Where-Object { $_.Length -gt 0 })) {
      $txt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
      if ($txt -match '(?i)(Best-of-the-Best|Resource Cost|T.i nguy.n)' -and $txt -match '(?i)(Critique|Ph.n bi.n|Counterexample|Falsif|Adversarial)') { $hasDialecticalSpec = $true }
    }
  }
  $ch = Measure-SenCodeHealth -Path $targetDir; $vl = Invoke-SenVnLawScan -Path $targetDir
  $tasks = @(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.status -ne "backlog" })
  $badEvidence = @($tasks | Where-Object { [string]$_.status -eq "done" -and ($null -eq $_.evidence -or [int]$_.evidence.exitCode -ne 0 -or ([string]$_.evidence.command -notmatch '[A-Za-z0-9]{3,}')) })
  $vectors = @(
    [pscustomobject]@{ Id = "V1-DIALECTICAL-SPEC"; Passed = [bool]($hasDialecticalSpec -or -not (Test-Path -LiteralPath $sDir)); Detail = "Thesis + Antithesis" },
    [pscustomobject]@{ Id = "V2-BOUNDARY-HEALTH"; Passed = [bool]$ch.Healthy; Detail = "Score=$($ch.Score)" },
    [pscustomobject]@{ Id = "V3-SOCRATIC-EVIDENCE"; Passed = ($badEvidence.Count -eq 0); Detail = "Bad=$($badEvidence.Count)" },
    [pscustomobject]@{ Id = "V4-LEGAL-PARTITION"; Passed = [bool]$vl.CompliantCodeLevel; Detail = "Red=$($vl.CodeRedFlags.Count)" }
  )
  $passedCount = @($vectors | Where-Object { $_.Passed }).Count
  $resObj = [pscustomobject][ordered]@{ Workspace = $Workspace; Passed = ($passedCount -eq $vectors.Count); Score = [int][Math]::Round(($passedCount * 100.0) / $vectors.Count); Vectors = $vectors; verifiedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ") }
  if (Test-Path -LiteralPath (Join-Path $Workspace ".agents/office")) { Write-SenAtomicJson -Path (Join-Path $Workspace ".agents/office/dialectical-audit.json") -InputObject $resObj -Depth 6 }
  return $resObj
}

function Test-SenCapabilityParity {
  [CmdletBinding()] param([Parameter(Mandatory = $false)][string]$SenRoot = "")
  $root = if ($SenRoot) { $SenRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path }
  $missing = [System.Collections.Generic.List[string]]::new()
  $rulePath = Join-Path $root "rules/AGENTS.md"
  $ruleTxt = if (Test-Path -LiteralPath $rulePath) { [System.IO.File]::ReadAllText($rulePath, [System.Text.Encoding]::UTF8) } else { "" }
  foreach ($p in @("Get-SenTaskRiskScore", "Invoke-SenDialecticalAudit", "New-SenRestorePoint", "Restore-SenRestorePoint", "Write-SenOfficeShowcase", "Measure-SenCodeHealth", "Invoke-SenVnLawScan", "Test-SenHungTasks", "Clear-SenHungTasks", "Test-SenCapabilityParity", "Test-SenDeliveryGate", "Invoke-SenCiPushLoop", "Add-SenBacklogItem", "Instant-Ack")) {
    if ($ruleTxt -notmatch "\b$([regex]::Escape($p))\b") { $missing.Add("L1-RuleMissingPrimitive:$p") }
  }
  if ($ruleTxt -match '(?i)\bor inline\b') { $missing.Add("L1-RuleContainsInlineLoophole") }
  $cat = Get-SenProcessCatalog -ManifestPath (Join-Path $root "scripts/process-manifest.json")
  if (@($cat.steps).Count -ne 12) { $missing.Add("L2-ManifestStepCount:$(@($cat.steps).Count)") }
  $stepMap = @{}; foreach ($s in @($cat.steps)) { $stepMap[[string]$s.id] = [string]$s.title }
  if ($stepMap["S2-DESIGN-SPEC"] -notmatch 'Write-SenOfficeShowcase') { $missing.Add("L2-ManifestMissingPhase1Showcase") }
  if ($stepMap["S3-TDD-VERIFY"] -notmatch 'Test-SenHungTasks') { $missing.Add("L2-ManifestMissingHungTaskWatchdog") }
  if ($stepMap["S4-CONTEXT-REPORT"] -notmatch 'Write-SenOfficeShowcase|Test-SenCapabilityParity') { $missing.Add("L2-ManifestMissingPhase2Showcase") }
  $harnessTxt = [System.IO.File]::ReadAllText((Join-Path $root "scripts/Sen.Harness.psm1"), [System.Text.Encoding]::UTF8)
  foreach ($st in @($cat.steps)) { if ($harnessTxt -notmatch ('"' + [regex]::Escape([string]$st.id) + '"')) { $missing.Add("L2-EvidenceMissingStep:$($st.id)") } }
  $skillDirs = if (Test-Path -LiteralPath (Join-Path $root "skills")) { @(Get-ChildItem -LiteralPath (Join-Path $root "skills") -Filter "sen-*" -Directory) } else { @() }
  if ($skillDirs.Count -lt 9) { $missing.Add("L3-SkillCount:$($skillDirs.Count)") }
  foreach ($sd in $skillDirs) {
    $skFile = Join-Path $sd.FullName "SKILL.md"
    if (-not (Test-Path -LiteralPath $skFile) -or ([System.IO.File]::ReadAllText($skFile, [System.Text.Encoding]::UTF8) -notmatch '(?s)^---\s*\r?\n.+?\r?\n---')) { $missing.Add("L3-InvalidSkill:$($sd.Name)") }
  }
  $testFiles = if (Test-Path -LiteralPath (Join-Path $root "tests")) { @(Get-ChildItem -LiteralPath (Join-Path $root "tests") -Filter "*.Tests.ps1" -File) } else { @() }
  $testCorpus = ($testFiles | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8) }) -join "`n"
  $exportedFns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($mf in @(Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter "*.psm1" -File)) {
    $expLine = [regex]::Match([System.IO.File]::ReadAllText($mf.FullName, [System.Text.Encoding]::UTF8), '(?m)^Export-ModuleMember\s+-Function\s+([^\r\n]+)').Groups[1].Value
    foreach ($fn in @($expLine -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
      [void]$exportedFns.Add($fn)
      if ($testCorpus -notmatch "\b$([regex]::Escape($fn))\b") { $missing.Add("L4-UntestedExport:$fn") }
    }
  }
  if (Test-Path -LiteralPath $rulePath) {
    $rBytes = [System.Text.Encoding]::UTF8.GetByteCount($ruleTxt.Replace("`r`n", "`n")); $rLines = @([System.IO.File]::ReadAllLines($rulePath)).Count
    if ($rBytes -gt 5750 -or $rLines -gt 95) { $missing.Add("L5-ContextBudgetExceeded:${rBytes}B/${rLines}L") }
  }
  else { $missing.Add("L5-MissingRuleFile") }
  $rmMain = Join-Path $root "README.md"; $rmVi = Join-Path $root "README.vi.md"
  if ((Test-Path -LiteralPath $rmMain) -and (Test-Path -LiteralPath $rmVi) -and ([System.IO.File]::ReadAllText($rmMain, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n").Trim() -ne [System.IO.File]::ReadAllText($rmVi, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n").Trim())) { $missing.Add("L5-DocSync:README_SYNC") }
  $plugJson = Read-SenSafeJson -Path (Join-Path $root "plugin.json")
  if ($null -ne $plugJson -and $plugJson.version) {
    foreach ($df in @("README.md", "CHANGELOG.md", "docs/CONTEXT.md")) {
      $dp = Join-Path $root $df
      if ((Test-Path -LiteralPath $dp) -and ([System.IO.File]::ReadAllText($dp, [System.Text.Encoding]::UTF8) -notmatch [regex]::Escape([string]$plugJson.version))) { $missing.Add("L5-DocSync:VERSION_DOC_SYNC:$df") }
    }
    if ((Test-Path -LiteralPath (Join-Path $root "docs/releases")) -and (Get-Command Test-SenReleaseNoteGate -ErrorAction SilentlyContinue)) {
      $rnGate = Test-SenReleaseNoteGate -Workspace $root -Version ([string]$plugJson.version)
      if (-not $rnGate.Passed) { foreach ($m in $rnGate.Missing) { $missing.Add("L6-ReleaseNote:$m") } }
    }
  }
  $todoF = Join-Path $root "docs/TODO.md"; $ctxF = Join-Path $root "docs/CONTEXT.md"
  if ((Test-Path -LiteralPath $todoF) -and (Test-Path -LiteralPath $ctxF)) {
    $todoTxt = [System.IO.File]::ReadAllText($todoF, [System.Text.Encoding]::UTF8); $ctxTxt = [System.IO.File]::ReadAllText($ctxF, [System.Text.Encoding]::UTF8)
    $openTodo = @([regex]::Matches($todoTxt, '(?m)^-\s*\[ \]\s*\*\*TASK-\d+')).Count
    $allIds = @([regex]::Matches($todoTxt, '\bTASK-\d+\b') | ForEach-Object { $_.Value })
    $lastId = if ($allIds.Count -gt 0) { $allIds[$allIds.Count - 1] } else { "" }
    if ($openTodo -eq 0 -and $lastId -and ($ctxTxt -notmatch "\b$([regex]::Escape($lastId))\b")) { $missing.Add("L5-DocSync:TODO_CONTEXT_SYNC:$lastId") }
  }
  foreach ($rf in @("README.md", "README.vi.md", "README.en.md")) {
    $rp = Join-Path $root $rf
    if ((Test-Path -LiteralPath $rp) -and $exportedFns.Count -gt 0) {
      $rt = [System.IO.File]::ReadAllText($rp, [System.Text.Encoding]::UTF8)
      if ($rt -notmatch "\b$($exportedFns.Count)\b" -or $rt -match '(?i)\b(68|69|71|73)\s*(exported\s+)?cmdlets\b|\b(68|69|71|73)/\1\b') { $missing.Add("L6-DocsParity:StaleCmdletCount:$rf") }
    }
  }
  foreach ($gf in @("docs/huong-dan.md", "docs/guide.md")) {
    $gp = Join-Path $root $gf
    if (Test-Path -LiteralPath $gp) {
      $gt = [System.IO.File]::ReadAllText($gp, [System.Text.Encoding]::UTF8)
      if ($gt -match '(?i)\b7\s+(sen-\*\s+)?skills?\b|waits for your approval once|duy.t ph..ng .n ..ng m.t l.n' -or $gt -notmatch 'New-SenRestorePoint') { $missing.Add("L6-DocsParity:StaleGuideFlow:$gf") }
    }
  }
  $chgP = Join-Path $root "CHANGELOG.md"
  if ((Test-Path -LiteralPath $chgP) -and ([System.IO.File]::ReadAllText($chgP, [System.Text.Encoding]::UTF8) -notmatch 'officeAction')) { $missing.Add("L6-DocsParity:ChangelogMissingOfficeAction") }
  return [pscustomobject][ordered]@{ Passed = ($missing.Count -eq 0); MissingItems = @($missing.ToArray()); CheckedLayers = 6 }
}

Export-ModuleMember -Function Get-SenSupportedHarnesses, ConvertFrom-SenHookPayload, Update-SenManagedBlock, Remove-SenManagedBlock, Install-SenHarness, Uninstall-SenHarness, Test-SenHarnessStatus, Sync-SenPlanToTasks, Sync-SenTasksToMarkdown, Get-SenProcessCatalog, Initialize-SenProcessAudit, Test-SenStageGate, Test-SenProjectCompliance, Get-SenRemoteCiStatus, Invoke-SenCiPushLoop, Invoke-SenDialecticalAudit, Test-SenCapabilityParity
