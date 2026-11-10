# scripts/Sen.Harness.psm1 - Sen Multi-Harness Adapter & Sync
$ErrorActionPreference = "Stop"
$senAdversarialPath = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Adversarial.psm1"
if ((-not $global:SenCoreBootstrapActive) -and (Test-Path -LiteralPath $senAdversarialPath)) {
  Import-Module -Name $senAdversarialPath -Global -Force
}
function Get-SenSupportedHarnesses {
  [CmdletBinding()] param()
  return @(
    @{ Id = "antigravity"; DisplayName = "Google Antigravity IDE"; RuleTarget = ".agents/rules/AGENTS.md"; HookTarget = ".agents/plugins/sen-method/hooks.json"; SupportsHooks = $true; CapabilityLevel = "full"; CapabilityAlias = "full"; ToolsCovered = @("antigravity") },
    @{ Id = "claude"; DisplayName = "Claude Code CLI / IDE"; RuleTarget = "CLAUDE.md"; HookTarget = ".claude/settings.json"; SupportsHooks = $true; CapabilityLevel = "full"; CapabilityAlias = "full"; ToolsCovered = @("claude") },
    @{ Id = "cursor"; DisplayName = "Cursor AI IDE"; RuleTarget = ".cursor/rules/sen-method.mdc"; HookTarget = ".cursor/hooks.json"; SupportsHooks = $true; CapabilityLevel = "full"; CapabilityAlias = "full"; ToolsCovered = @("cursor") },
    @{ Id = "copilot"; DisplayName = "GitHub Copilot"; RuleTarget = ".github/copilot-instructions.md"; HookTarget = ".github/hooks/sen-hooks.json"; SupportsHooks = $true; CapabilityLevel = "rules-only"; CapabilityAlias = "rules-only"; ToolsCovered = @("copilot") },
    @{ Id = "windsurf"; DisplayName = "Windsurf AI IDE"; RuleTarget = ".windsurfrules"; HookTarget = ".windsurf/hooks.json"; SupportsHooks = $true; CapabilityLevel = "partial"; CapabilityAlias = "rules-and-skills"; ToolsCovered = @("windsurf") },
    @{ Id = "codex"; DisplayName = "Codex CLI / OpenCode"; RuleTarget = "AGENTS.md"; HookTarget = ".codex/hooks.json"; SupportsHooks = $true; CapabilityLevel = "partial"; CapabilityAlias = "rules-and-skills"; ToolsCovered = @("codex", "opencode") }
  ) | ForEach-Object { [pscustomobject]$_ }
}
function Get-SenPropValue {
  param($Obj, [string[]]$Names)
  if ($null -eq $Obj) { return "" }
  foreach ($n in $Names) { if ($Obj.PSObject.Properties.Name -contains $n -and $null -ne $Obj.$n -and -not [string]::IsNullOrWhiteSpace([string]$Obj.$n)) { return [string]$Obj.$n } }
  return ""
}
function ConvertFrom-SenHookPayload {
  [CmdletBinding()] param([Parameter(Mandatory)]$InputObject)
  $rawTool = ""; $a = $null
  if ($InputObject.PSObject.Properties.Name -contains "toolCall" -and $null -ne $InputObject.toolCall) {
    $rawTool = Get-SenPropValue $InputObject.toolCall @("name", "toolName")
    if ($InputObject.toolCall.PSObject.Properties.Name -contains "args") { $a = $InputObject.toolCall.args }
  }
  if (-not $rawTool) { $rawTool = Get-SenPropValue $InputObject @("tool_name", "toolName", "name", "hook_event_name") }
  if ($null -eq $a) {
    $a = if ($InputObject.PSObject.Properties.Name -contains "tool_input" -and $null -ne $InputObject.tool_input) { $InputObject.tool_input }
    elseif ($InputObject.PSObject.Properties.Name -contains "toolArgs" -and $null -ne $InputObject.toolArgs) { $InputObject.toolArgs } else { $InputObject }
  }
  $can = switch -Regex ($rawTool) {
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
  $wsList = [Collections.Generic.List[string]]::new()
  foreach ($p in @("workspacePaths", "workspace_roots")) {
    if ($InputObject.PSObject.Properties.Name -contains $p -and $null -ne $InputObject.$p) { foreach ($w in @($InputObject.$p)) { if (-not [string]::IsNullOrWhiteSpace([string]$w)) { $wsList.Add([string]$w) } } }
  }
  $cwd = Get-SenPropValue $InputObject @("cwd", "workspacePath", "workspace"); if ($cwd -and -not $wsList.Contains($cwd)) { $wsList.Add($cwd) }
  $ep = ($InputObject.PSObject.Properties.Name -contains "enforceTaskPaths" -and [bool]$InputObject.enforceTaskPaths) -or ($env:SEN_ENFORCE_ALLOWED_PATHS -eq "1")
  $hn = if ($InputObject.PSObject.Properties.Name -contains "toolCall") { "antigravity" } elseif ($InputObject.PSObject.Properties.Name -contains "workspace_roots") { "cursor" } elseif ($InputObject.PSObject.Properties.Name -contains "tool_name") { "claude" } else { "generic" }
  $resp = if ($InputObject.PSObject.Properties.Name -contains "tool_response") { $InputObject.tool_response } elseif ($InputObject.PSObject.Properties.Name -contains "toolResult") { $InputObject.toolResult } else { $InputObject }
  $ecRaw = Get-SenPropValue $resp @("exitCode", "exit_code", "returnCode"); if (-not $ecRaw) { $ecRaw = Get-SenPropValue $InputObject @("exitCode", "exit_code", "returnCode") }
  $hasEc = ($ecRaw -match '^-?\d+$'); $ecVal = if ($hasEc) { [int]$ecRaw } else { -1 }
  $isErr = ((Get-SenPropValue $resp @("is_error", "isError", "status")) -match '^(?i)(true|1|error|failed)$') -or ($hasEc -and $ecVal -ne 0)
  $wsPrimary = if ($wsList.Count -gt 0) { [string]$wsList[0] } else { "" }
  $cmdLine = Get-SenPropValue $a @("CommandLine", "command", "cmd")
  $tPath = Get-SenPropValue $a @("Path", "file_path", "target_file", "path", "SearchPath", "notebook_path")
  if ($wsPrimary -and (@(Get-PSCallStack | Where-Object { $_.ScriptName -match 'guard\.ps1$' }).Count -gt 0)) {
    Invoke-SenPreToolHookBootstrap -InputObject $InputObject -Workspace $wsPrimary -CanonicalTool $can -Target $(if ($tPath) { $tPath } else { $cmdLine })
  }
  return [pscustomobject][ordered]@{
    RawToolName = $rawTool; CanonicalTool = $can; CommandLine = $cmdLine
    TargetPath = $tPath
    Query = (Get-SenPropValue $a @("Query", "Pattern", "pattern", "query")); WorkspacePath = $wsPrimary
    WorkspaceList = @($wsList.ToArray()); EnforceTaskPaths = [bool]$ep; Harness = $hn; HasExplicitExitCode = [bool]$hasEc; ExitCode = $ecVal; IsError = [bool]$isErr
  }
}
function Update-SenManagedBlock {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content, [string]$FrontMatter = "")
  $managedBlock = "<!-- SEN-METHOD:START -->`n$($Content.Trim())`n<!-- SEN-METHOD:END -->"
  $dir = [IO.Path]::GetDirectoryName($Path)
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
  $existing = if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) } else { "" }
  $pattern = '(?s)<!-- SEN-METHOD:START -->.*?<!-- SEN-METHOD:END -->'
  if ([string]::IsNullOrWhiteSpace($existing)) { $finalText = if (-not [string]::IsNullOrWhiteSpace($FrontMatter)) { "$($FrontMatter.Trim())`n`n$managedBlock`n" } else { "$managedBlock`n" } }
  elseif ($existing -match $pattern) { $finalText = [regex]::Replace($existing, $pattern, $managedBlock) }
  else {
    $prefix = $existing.TrimEnd()
    if (-not [string]::IsNullOrWhiteSpace($FrontMatter) -and -not $prefix.StartsWith("---")) { $prefix = "$($FrontMatter.Trim())`n`n$prefix" }
    $finalText = "$prefix`n`n$managedBlock`n"
  }
  [IO.File]::WriteAllText($Path, $finalText, [Text.UTF8Encoding]::new($false)); return $true
}
function Remove-SenManagedBlock {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $existing = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
  $pattern = '(?s)\r?\n?<!-- SEN-METHOD:START -->.*?<!-- SEN-METHOD:END -->\r?\n?'
  if ($existing -notmatch $pattern) { return $false }
  $cleaned = ([regex]::Replace($existing, $pattern, "`n")).Trim()
  if ([string]::IsNullOrWhiteSpace($cleaned) -or $cleaned -match '^---\s*[\s\S]*?---$') { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
  else { [IO.File]::WriteAllText($Path, ($cleaned + "`n"), [Text.UTF8Encoding]::new($false)) }
  return $true
}
function Install-SenHarness {
  [CmdletBinding()] param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string[]]$Harness = @("all"))
  $sel = @(Resolve-SenRequestedHarnesses -Harness $Harness)
  $inst = [Collections.Generic.List[string]]::new(); $created = [Collections.Generic.List[string]]::new()
  foreach ($h in $sel) {
    $bTxt = Build-SenHarnessBridgeText -Workspace $Workspace -HarnessId $h.Id
    $rFull = Join-Path $Workspace $h.RuleTarget
    if ($h.Id -eq "antigravity") {
      $rDir = [IO.Path]::GetDirectoryName($rFull)
      if ($rDir -and -not (Test-Path -LiteralPath $rDir)) { [IO.Directory]::CreateDirectory($rDir) | Out-Null }
      if (-not (Test-Path -LiteralPath $rFull)) { [IO.File]::WriteAllText($rFull, $bTxt, [Text.UTF8Encoding]::new($false)) }
    }
    else {
      $fm = if ($h.Id -eq "cursor") { "---`ndescription: Sen Methodology Core Rule & Multi-Harness Bridge`nalwaysApply: true`n---" } else { "" }
      [void](Update-SenManagedBlock -Path $rFull -Content $bTxt -FrontMatter $fm)
    }
    $created.Add($h.RuleTarget)
    if ($h.SupportsHooks -and $h.HookTarget) { [void](Install-SenHarnessHookFile -Workspace $Workspace -HarnessId $h.Id -HookRelPath $h.HookTarget); $created.Add($h.HookTarget) }
    $inst.Add($h.Id)
  }
  $lock = Read-SenLock -Workspace $Workspace; $mH = [Collections.Generic.List[string]]::new()
  if ($lock.ContainsKey("harnesses") -and $null -ne $lock["harnesses"]) { foreach ($eh in @($lock["harnesses"])) { if ($eh -and -not $mH.Contains([string]$eh)) { $mH.Add([string]$eh) } } }
  foreach ($ih in $inst) { if (-not $mH.Contains($ih)) { $mH.Add($ih) } }
  $lock["harnesses"] = @($mH.ToArray()); Write-SenLock -Workspace $Workspace -Lock $lock
  return [pscustomobject][ordered]@{ Workspace = $Workspace; Installed = @($inst.ToArray()); FilesCreated = @($created.ToArray()); UpdatedLock = $true }
}
function Uninstall-SenHarness {
  [CmdletBinding()] param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string[]]$Harness = @())
  $rem = [Collections.Generic.List[string]]::new(); $upd = [Collections.Generic.List[string]]::new()
  foreach ($h in @(Resolve-SenRequestedHarnesses -Harness $Harness)) {
    if ($h.Id -eq "antigravity") { continue }
    if (Remove-SenManagedBlock -Path (Join-Path $Workspace $h.RuleTarget)) { $upd.Add($h.RuleTarget) }
    if ($h.SupportsHooks -and $h.HookTarget) {
      $hFull = Join-Path $Workspace $h.HookTarget; $exObj = Read-SenSafeJson -Path $hFull
      if ($null -ne $exObj) {
        $rHash = ConvertTo-SenHashtable -InputObject $exObj
        if ($rHash -is [hashtable] -and $rHash.ContainsKey("hooks")) { $rHash.Remove("hooks"); Write-SenAtomicJson -Path $hFull -InputObject $rHash -Depth 8; $upd.Add($h.HookTarget) }
      }
    }
    $rem.Add($h.Id)
  }
  $lock = Read-SenLock -Workspace $Workspace
  if ($lock.ContainsKey("harnesses") -and $null -ne $lock["harnesses"]) { $lock["harnesses"] = @($lock["harnesses"] | Where-Object { $rem -notcontains [string]$_ }); Write-SenLock -Workspace $Workspace -Lock $lock }
  return [pscustomobject][ordered]@{ Workspace = $Workspace; Uninstalled = @($rem.ToArray()); FilesUpdated = @($upd.ToArray()) }
}
function Test-SenHarnessStatus {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Workspace)
  $res = [Collections.Generic.List[object]]::new()
  $probeOk = Test-SenHarnessLiveProbe -Workspace $Workspace
  foreach ($h in @(Get-SenSupportedHarnesses)) {
    $rOk = Test-Path -LiteralPath (Join-Path $Workspace $h.RuleTarget); $hOk = if ($h.SupportsHooks -and $h.HookTarget) { Test-Path -LiteralPath (Join-Path $Workspace $h.HookTarget) } else { $true }
    $execOk = if ($h.SupportsHooks) { [bool]($hOk -and $probeOk) } else { $false }
    $res.Add([pscustomobject][ordered]@{ Id = $h.Id; DisplayName = $h.DisplayName; CapabilityLevel = $h.CapabilityLevel; AutomationLevel = $h.CapabilityLevel; Installed = [bool]($rOk -and $hOk); RuleExists = [bool]$rOk; HookConfigured = [bool]$hOk; HookExecutable = $execOk; HookProbePassed = $execOk; RulePath = $h.RuleTarget; HookPath = $h.HookTarget })
  }
  return @($res.ToArray())
}
function Install-SenGitHooks {
  [CmdletBinding()]
  param([Parameter(Mandatory)][Alias("WorkspacePath", "Path")][string]$Workspace, [switch]$Force)
  $hooksDir = Join-Path (Join-Path $Workspace ".git") "hooks"
  if (-not (Test-Path -LiteralPath $hooksDir)) { [IO.Directory]::CreateDirectory($hooksDir) | Out-Null }
  $wsNorm = $Workspace.Replace('\', '/').Replace("'", "''")
  $cmdBody = "\`$m = if (Test-Path '$wsNorm/scripts/Sen.psm1') { '$wsNorm/scripts/Sen.psm1' } else { '$wsNorm/.agents/plugins/sen-method/scripts/Sen.psm1' }; Import-Module \`$m -ErrorAction SilentlyContinue; \`$gate = Test-SenDeliveryGate -Workspace '$wsNorm'; if (-not \`$gate.Passed) { Write-Error (\`$gate.Issues -join '; '); exit 1 }"
  $scriptTxt = "#!/usr/bin/env sh`n# Sen Zero-Trust Physical Git Gate`nif command -v pwsh >/dev/null 2>&1; then pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"$cmdBody`"; else powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"$cmdBody`"; fi`n"
  $utf8 = [Text.UTF8Encoding]::new($false)
  foreach ($hn in @("pre-commit", "pre-push")) {
    $hp = Join-Path $hooksDir $hn
    if ($Force.IsPresent -or (-not (Test-Path -LiteralPath $hp)) -or ([IO.File]::ReadAllText($hp) -match 'Test-SenDeliveryGate')) {
      [IO.File]::WriteAllText($hp, $scriptTxt, $utf8)
    }
  }
  return [pscustomobject][ordered]@{ Installed = $true; Hooks = @("pre-commit", "pre-push"); HooksDir = $hooksDir }
}
function Sync-SenPlanToTasks {
  [CmdletBinding()]
  param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$PlanPath = "")
  $existingIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($t in @(Get-SenTasks -Workspace $Workspace)) { if ($t -and $t.id) { [void]$existingIds.Add([string]$t.id) } }
  $synced = [int](Sync-SenTodoMarkdownItems -Workspace $Workspace -ExistingIds $existingIds)
  $planFiles = [Collections.Generic.List[string]]::new()
  if (-not [string]::IsNullOrWhiteSpace($PlanPath) -and (Test-Path -LiteralPath $PlanPath)) { $planFiles.Add((Resolve-Path -LiteralPath $PlanPath).Path) }
  elseif (Test-Path -LiteralPath (Join-Path $Workspace "docs/superpowers/plans")) {
    foreach ($pfItem in @(Get-ChildItem -LiteralPath (Join-Path $Workspace "docs/superpowers/plans") -Filter "*.md" -File | Sort-Object Name)) { $planFiles.Add($pfItem.FullName) }
  }
  foreach ($pf in $planFiles) {
    $rawPlan = [IO.File]::ReadAllText($pf, [Text.Encoding]::UTF8)
    $basePrefix = ([IO.Path]::GetFileNameWithoutExtension($pf) -replace '[^A-Za-z0-9_-]', '-').ToUpperInvariant(); $prevTaskId = $null
    foreach ($sec in [regex]::Matches($rawPlan, '(?ms)^###\s+Task\s+(\d+)(?:\s*\(`?([A-Za-z0-9_-]+)`?(?:[^)]*)\))?\s*:\s*([^\r\n]+)(.*?)(?=^###\s+Task\s+\d+|\z)')) {
      $num = $sec.Groups[1].Value.Trim(); $explicitId = $sec.Groups[2].Value.Trim()
      $tid = if (-not [string]::IsNullOrWhiteSpace($explicitId)) { $explicitId } elseif (-not $existingIds.Contains("PLAN-T$num")) { "PLAN-T$num" } else { "$basePrefix-T$num" }
      if ($existingIds.Contains($tid)) { $prevTaskId = $tid; continue }
      $title = $sec.Groups[3].Value.Trim(); $body = $sec.Groups[4].Value
      $paths = @([regex]::Matches($body, '(?m)^-\s*(?:Create|Modify|Test):\s*`((?:[A-Za-z]:[\\/])?[^`:\r\n]+)') | ForEach-Object { $_.Groups[1].Value.Trim() } | Where-Object { $_ })
      $isParallel = ($title -match '(?i)\b(independent|parallel|song\s+song)\b') -or ($body -match '(?i)\b(DependsOn:\s*none|independent\s+task|parallel\s+execution)\b')
      $deps = if ($prevTaskId -and (-not $isParallel)) { @($prevTaskId) } else { @() }
      [void](New-SenTask -Workspace $Workspace -Id $tid -Title $title -Tier 3 -RiskLevel "high" -Module "Plan" -Assignee "dev_be" -DependsOn $deps -AllowedPaths $paths)
      [void]$existingIds.Add($tid); $synced++; $prevTaskId = $tid
    }
  }
  return [pscustomobject][ordered]@{ Workspace = $Workspace; SyncedCount = $synced }
}
function Sync-SenTasksToMarkdown {
  [CmdletBinding()] param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path)
  $doneIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($t in @(Get-SenTasks -Workspace $Workspace)) { if ($t -and [string]$t.status -eq "done") { [void]$doneIds.Add([string]$t.id) } }
  if ($doneIds.Count -eq 0) { return [pscustomobject]@{ UpdatedFiles = 0 } }
  $upd = 0; $utf8 = [Text.UTF8Encoding]::new($false)
  foreach ($tp in @((Join-Path $Workspace "docs/TODO.md"))) {
    if (-not (Test-Path -LiteralPath $tp)) { continue }
    $txt = [IO.File]::ReadAllText($tp, $utf8); $orig = $txt
    foreach ($did in $doneIds) { $txt = [regex]::Replace($txt, "(?m)^(-\s*)\[[ ~]\](\s*\*\*$([regex]::Escape($did))\b)", '$1[x]$2') }
    if ($txt -ne $orig) { [IO.File]::WriteAllText($tp, $txt, $utf8); $upd++ }
  }
  $plDir = Join-Path $Workspace "docs/superpowers/plans"
  if (Test-Path -LiteralPath $plDir) {
    foreach ($pf in @(Get-ChildItem -LiteralPath $plDir -Filter "*.md" -File)) {
      $pTxt = [IO.File]::ReadAllText($pf.FullName, $utf8); $pOrig = $pTxt
      foreach ($did in $doneIds) {
        $secPat = "(?ms)(^###\s+Task\s+\d+[^\r\n]*\b$([regex]::Escape($did))\b[^\r\n]*\r?\n)(.*?)(?=^###\s+Task\s+\d+|\z)"
        if ($pTxt -match $secPat) { $pTxt = [regex]::Replace($pTxt, $secPat, { param($m) $m.Groups[1].Value + [regex]::Replace($m.Groups[2].Value, '(?m)^(-\s*)\[ \]', '$1[x]') }) }
      }
      if ($pTxt -ne $pOrig) { [IO.File]::WriteAllText($pf.FullName, $pTxt, $utf8); $upd++ }
    }
  }
  return [pscustomobject]@{ UpdatedFiles = $upd }
}
function Get-SenProcessCatalog {
  [CmdletBinding()] param([string]$ManifestPath = "")
  $p = if ($ManifestPath) { $ManifestPath } else { Join-Path $PSScriptRoot "process-manifest.json" }
  $o = Read-SenSafeJson -Path $p; if ($null -eq $o) { throw "Manifest not found: $p" }; return $o
}
function Initialize-SenProcessAudit {
  [CmdletBinding()]
  param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$ProjectName = "Project", [ValidateRange(1, 3)][int]$Tier = 3, [ValidateSet("core", "web_mobile", "all")][string]$ProjectScope = "core", [switch]$PreserveLatched)
  $cat = Get-SenProcessCatalog; $aPath = Join-Path $Workspace ".agents/office/process-audit.json"
  $ex = Read-SenSafeJson -Path $aPath; $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  $same = ($null -ne $ex) -and ([string]$ex.projectName -eq $ProjectName)
  $start = if ($PreserveLatched -and $same -and $ex.PSObject.Properties['startedAt'] -and $ex.startedAt) { [string]$ex.startedAt } else { $now }
  $lMap = @{}
  if ($PreserveLatched -and $same -and $ex.PSObject.Properties.Name -contains "selectedSteps") {
    foreach ($os in @($ex.selectedSteps)) { if ($os -and [bool]$os.latched -and [string]$os.verifiedAt -ge $start) { $lMap[[string]$os.id] = $os } }
  }
  $sel = [Collections.Generic.List[object]]::new()
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
  $minUtc = if ([string]::IsNullOrWhiteSpace($SessionStartedAt)) { [DateTime]::MinValue } else { [DateTime]::Parse($SessionStartedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) }
  switch ($StepId) {
    "S1-RISK" { return ((Test-Path -LiteralPath (Join-Path $Workspace ".agents/office/process-audit.json")) -or (Test-Path -LiteralPath (Join-Path $Workspace ".agents/office/current-intake.json"))) }
    "S1-AUDIT-INIT" { return (Test-Path -LiteralPath (Join-Path $Workspace ".agents/office/process-audit.json")) }
    "S2-EXPERT-COST" {
      $daFile = Join-Path $Workspace ".agents/office/dialectical-audit.json"
      if ((Test-Path -LiteralPath $daFile) -and (Get-Item -LiteralPath $daFile).LastWriteTimeUtc -ge $minUtc -and [bool](Read-SenSafeJson -Path $daFile).Passed) { return $true }
      $sDir = Join-Path $Workspace "docs/superpowers/specs"
      if (-not (Test-Path -LiteralPath $sDir)) { return $false }
      foreach ($f in @(Get-ChildItem -LiteralPath $sDir -Filter "*.md" -File | Where-Object { $_.LastWriteTimeUtc -ge $minUtc })) {
        $sTxt = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
        if (($sTxt -match '(?i)(Resource Cost|T.i nguy.n ti.u t.n|Best-of-the-Best)') -and ($sTxt -match '(?m)^\s*\|.+\|.+\|')) { return $true }
      }
      return $false
    }
    "S2-DESIGN-SPEC" {
      $sDir = Join-Path $Workspace "docs/superpowers/specs"
      $specs = if (Test-Path -LiteralPath $sDir) { @(Get-ChildItem -LiteralPath $sDir -Filter "*.md" -File | Where-Object { $_.Length -gt 0 -and $_.LastWriteTimeUtc -ge $minUtc }) } else { @() }
      if ($specs.Count -eq 0) { return $false }
      $sc = Read-SenOfficeShowcase -Workspace $Workspace
      return ($null -ne $sc -and $null -ne $sc.phase1)
    }
    "S2-IMPL-PLAN" {
      $pDir = Join-Path $Workspace "docs/superpowers/plans"
      if (-not (Test-Path -LiteralPath $pDir)) { return $false }
      foreach ($pf in @(Get-ChildItem -LiteralPath $pDir -Filter "*.md" -File | Where-Object { $_.Length -gt 0 -and $_.LastWriteTimeUtc -ge $minUtc })) {
        $pt = [IO.File]::ReadAllText($pf.FullName, [Text.Encoding]::UTF8)
        if (($pt -match '(?m)^###\s+Task\s+\d+') -and ($pt -match '(?i)(Step|Files|Verify|Acceptance|Test|-\s*\[[ xX~]\])')) { return $true }
      }
      return $false
    }
    "S2-TASK-DAG" {
      [void](Sync-SenPlanToTasks -Workspace $Workspace)
      return (@(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.status -ne "backlog" -and (-not $SessionStartedAt -or [string]$_.updatedAt -ge $SessionStartedAt -or [string]$_.createdAt -ge $SessionStartedAt) }).Count -gt 0)
    }
    "S3-RESTORE-POINT" {
      $rpDir = Join-Path $Workspace ".agents/.sen-restore"
      if (-not (Test-Path -LiteralPath $rpDir)) { return $false }
      return (@(Get-ChildItem -LiteralPath $rpDir -Directory | Where-Object { $mf = Join-Path $_.FullName "manifest.json"; (Test-Path -LiteralPath $mf) -and (Get-Item -LiteralPath $mf).LastWriteTimeUtc -ge $minUtc }).Count -gt 0)
    }
    "S3-TDD-VERIFY" {
      [void](Sync-SenPlanToTasks -Workspace $Workspace)
      if ((Get-Command Test-SenHungTasks -ErrorAction SilentlyContinue) -and (-not (Test-SenHungTasks -Workspace $Workspace).Healthy)) { return $false }
      $active = @(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.status -ne "backlog" -and (-not ($_.PSObject.Properties['isTelemetryOnly'] -and [bool]$_.isTelemetryOnly)) })
      if ($active.Count -eq 0) { return $false }
      $sessDone = @($active | Where-Object { -not $SessionStartedAt -or [string]$_.updatedAt -ge $SessionStartedAt -or ($_.evidence -and [string]$_.evidence.verifiedAt -ge $SessionStartedAt) })
      if ($sessDone.Count -eq 0) { return $false }
      return (@($active | Where-Object { [string]$_.status -ne "done" -or $null -eq $_.evidence -or [int]$_.evidence.exitCode -ne 0 }).Count -eq 0)
    }
    "S3-TWOWAY-SYNC" {
      [void](Sync-SenPlanToTasks -Workspace $Workspace); [void](Sync-SenTasksToMarkdown -Workspace $Workspace)
      return (@(Get-SenTasks -Workspace $Workspace | Where-Object { [string]$_.status -ne "backlog" -and (-not ($_.PSObject.Properties['isTelemetryOnly'] -and [bool]$_.isTelemetryOnly)) -and [string]$_.status -ne "done" }).Count -eq 0)
    }
    "S4-CLEAN-CODE" { return [bool](Measure-SenCodeHealth -Path $targetDir).Healthy }
    "S4-VN-LAW" { $vl = Invoke-SenVnLawScan -Path $targetDir; return ([bool]$vl.CompliantCodeLevel -and ($vl.Verdict -in @("PASS", "NOT_APPLICABLE"))) }
    "S4-CONTEXT-REPORT" {
      $ctxFile = Join-Path $Workspace "docs/CONTEXT.md"
      if (-not ((Test-Path -LiteralPath $ctxFile) -and (Get-Item -LiteralPath $ctxFile).Length -gt 0 -and (Get-Item -LiteralPath $ctxFile).LastWriteTimeUtc -ge $minUtc)) { return $false }
      $sc = Read-SenOfficeShowcase -Workspace $Workspace
      return ($null -ne $sc -and $null -ne $sc.phase2)
    }
  }
  return $true
}
function Test-SenStageGate {
  [CmdletBinding()]
  param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [ValidateRange(1, 4)][int]$Stage, [switch]$IgnoreLatched, [string]$ProjectPath = "")
  $aPath = Join-Path $Workspace ".agents/office/process-audit.json"; $audit = Read-SenSafeJson -Path $aPath
  if ($null -eq $audit) { $audit = Initialize-SenProcessAudit -Workspace $Workspace -Tier 3 -ProjectScope "core" }
  elseif ([string]$audit.manifestVersion -ne [string](Get-SenProcessCatalog).manifestVersion) {
    $audit = Initialize-SenProcessAudit -Workspace $Workspace -ProjectName ([string]$audit.projectName) -Tier ([int]$audit.tier) -ProjectScope ([string]$audit.projectScope) -PreserveLatched
  }
  $ss = if ($audit.PSObject.Properties['startedAt'] -and $audit.startedAt) { [string]$audit.startedAt } else { "" }
  $miss = [Collections.Generic.List[string]]::new(); $chg = $false
  foreach ($st in @($audit.selectedSteps)) {
    if ([int]$st.stage -gt $Stage) { continue }
    $curHash = Get-SenStepArtifactHash -Workspace $Workspace -StepId ([string]$st.id)
    $savedHash = if ($st.PSObject.Properties['artifactHash'] -and $st.artifactHash) { [string]$st.artifactHash } else { "" }
    $hashOk = ([string]::IsNullOrWhiteSpace($curHash) -or ($savedHash -eq $curHash))
    $fresh = [bool]$st.latched -and (-not $IgnoreLatched.IsPresent) -and $hashOk -and (-not $ss -or [string]$st.verifiedAt -ge $ss) -and ([string]$st.id -in @("S1-RISK", "S1-AUDIT-INIT") -or (Test-SenSingleStepEvidence -Workspace $Workspace -StepId ([string]$st.id) -SessionStartedAt $ss -ProjectPath $ProjectPath))
    if ($fresh) { continue }
    if (Test-SenSingleStepEvidence -Workspace $Workspace -StepId ([string]$st.id) -SessionStartedAt $ss -ProjectPath $ProjectPath) {
      $st.passed = $true; $st.latched = $true; $st.verifiedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
      $st | Add-Member -NotePropertyName "artifactHash" -NotePropertyValue $curHash -Force; $chg = $true
    }
    else {
      if ([bool]$st.passed -or [bool]$st.latched) { $st.passed = $false; $st.latched = $false; $st.verifiedAt = $null; $chg = $true }
      $miss.Add([string]$st.id)
    }
  }
  if ($chg) {
    $sf = Join-Path $Workspace ".agents/office/state-seal.json"
    $sOk = (Test-Path -LiteralPath $sf) -and (Get-Command Sync-SenOfficeState -EA SilentlyContinue) -and (-not (Sync-SenOfficeState -Workspace $Workspace -VerifySeal).Tampered)
    $audit.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); Write-SenAtomicJson -Path $aPath -InputObject $audit -Depth 8
    if ($sOk) { [void](Sync-SenOfficeState -Workspace $Workspace -UpdateSeal) }
  }
  return [pscustomobject][ordered]@{ Stage = $Stage; Passed = ($miss.Count -eq 0); MissingSteps = @($miss.ToArray()); Audit = $audit }
}
function Test-SenProjectCompliance {
  [CmdletBinding()] param([Alias("WorkspacePath", "Path")][string]$Workspace = $PWD.Path, [string]$ProjectPath = "")
  $fin = Test-SenStageGate -Workspace $Workspace -Stage 4 -ProjectPath $ProjectPath
  $all = @($fin.Audit.selectedSteps); $done = @($all | Where-Object { [bool]$_.passed })
  return [pscustomobject][ordered]@{
    Compliant = $fin.Passed; TotalSelected = $all.Count; CompletedCount = $done.Count; MissingSteps = $fin.MissingSteps
    StagesSummary = @(1..4 | ForEach-Object { $n = $_; $si = @($all | Where-Object { [int]$_.stage -eq $n }); $sd = @($si | Where-Object { [bool]$_.passed }); [pscustomobject][ordered]@{ Stage = $n; Total = $si.Count; Done = $sd.Count; Passed = ($sd.Count -eq $si.Count) } })
  }
}
function Get-SenRemoteCiStatus {
  [CmdletBinding()]
  param([string]$RepoSlug = "developerfs0110/Sen", [string]$HeadSha = "", [Alias("WorkspacePath", "RepositoryPath", "RepoPath", "Path")][string]$Workspace = "", [scriptblock]$RestInvoker = $null)
  $inv = if ($RestInvoker) { $RestInvoker } else { { param([string]$Uri) Invoke-RestMethod -Uri $Uri -Headers @{ "User-Agent" = "Sen-CI-Monitor" } -TimeoutSec 15 } }
  try { $resp = & $inv "https://api.github.com/repos/$RepoSlug/actions/runs?per_page=5" }
  catch { return [pscustomobject][ordered]@{ Found = $false; RunId = 0; Status = "error"; Conclusion = "error"; HtmlUrl = ""; HeadSha = $HeadSha; FailedSteps = @("API error: $($_.Exception.Message)") } }
  $runs = if ($resp -and $resp.workflow_runs) { @($resp.workflow_runs) } else { @() }
  $run = if ($HeadSha) { $runs | Where-Object { [string]$_.head_sha -like "$HeadSha*" } | Select-Object -First 1 } else { $runs | Select-Object -First 1 }
  if ($null -eq $run) { return [pscustomobject][ordered]@{ Found = $false; RunId = 0; Status = "not_found"; Conclusion = ""; HtmlUrl = ""; HeadSha = $HeadSha; FailedSteps = @() } }
  $failed = [Collections.Generic.List[string]]::new()
  if ([string]$run.conclusion -eq "failure" -and $run.jobs_url) {
    try { foreach ($j in @((& $inv ([string]$run.jobs_url)).jobs)) { foreach ($bs in @($j.steps | Where-Object { [string]$_.conclusion -eq "failure" } | ForEach-Object { "$($j.name) > $($_.name)" })) { $failed.Add($bs) } } } catch { <# Ignore jobs fetch error #> }
  }
  return [pscustomobject][ordered]@{ Found = $true; RunId = [long]$run.id; Status = [string]$run.status; Conclusion = [string]$run.conclusion; HtmlUrl = [string]$run.html_url; HeadSha = [string]$run.head_sha; FailedSteps = @($failed.ToArray()) }
}
function Invoke-SenCiPushLoop {
  [CmdletBinding()]
  param([string]$RepoPath = $PWD.Path, [string]$CommitMessage = "cap nhat", [string]$RepoSlug = "developerfs0110/Sen", [int]$PollSeconds = 5, [int]$TimeoutSeconds = 90, [int]$MaxAttempts = 3, [scriptblock]$RestInvoker = $null, [scriptblock]$HealAction = $null, [switch]$SkipPush)
  $pushed = $false; $sha = ""; $ci = $null; $ciOk = $false
  $effHeal = if ($HealAction) { $HealAction } elseif (Get-Command Invoke-SenPostCodePipeline -ErrorAction SilentlyContinue) { { param($s) [void](Invoke-SenPostCodePipeline -Workspace $RepoPath -SkipHealth) } } else { $null }
  for ($att = 1; $att -le [Math]::Max(1, $MaxAttempts); $att++) {
    $vScr = Join-Path $RepoPath "scripts/Validate-Repo.ps1"
    if (Test-Path -LiteralPath $vScr) {
      $vErr = @(& $vScr -Root $RepoPath)
      if ($vErr.Count -gt 0) { return [pscustomobject][ordered]@{ LocalPassed = $false; Pushed = $false; CiPassed = $false; Attempts = $att; HeadSha = ""; Errors = $vErr; CiStatus = $null } }
    }
    $loopPath = Join-Path $RepoPath ".agents/office/bounded-loops.json"
    if (Test-Path -LiteralPath $loopPath) {
      $escIds = @(Read-SenSafeJson -Path $loopPath | Where-Object { $_ -and [string]$_.state -in @("ESCALATED", "REJECTED") } | ForEach-Object { [string]$_.claimId })
      if ($escIds.Count -gt 0) { return [pscustomobject][ordered]@{ LocalPassed = $false; Pushed = $false; CiPassed = $false; Attempts = $att; HeadSha = ""; Errors = @("PrePushEscalationGate:QuarantinedClaims=$($escIds -join ',')"); CiStatus = $null } }
    }
    if (-not $SkipPush) {
      $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"; Push-Location -LiteralPath $RepoPath
      try {
        $stLines = @(git status --porcelain -uall 2>&1)
        if (($stLines -join "`n") -match '(?im)^.. (?:"?([^\r\n"]*?(?:^|[/\\])(?:\.env(?:\.(?!example|sample|template)\S+)?|id_rsa|id_ed25519|credentials\.json|\.npmrc|\.netrc|\S+\.(?:pem|pfx|p12|key)))"?)\s*$') {
          return [pscustomobject][ordered]@{ LocalPassed = $false; Pushed = $false; CiPassed = $false; Attempts = $att; HeadSha = ""; Errors = @("SensitiveFileBlocked:$($matches[1])"); CiStatus = $null }
        }
        if ($stLines.Count -gt 0) { [void](git add -A 2>&1); [void](git commit -m $CommitMessage 2>&1) }
        if ($att -eq 1) { [void](git push 2>&1) } else { [void](git push origin HEAD 2>&1) }
        $pushed = ($LASTEXITCODE -eq 0); $sha = ([string](git rev-parse HEAD 2>&1)).Trim()
      }
      finally { Pop-Location; $ErrorActionPreference = $prev }
    }
    $dl = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $dl) {
      $ci = Get-SenRemoteCiStatus -RepoSlug $RepoSlug -HeadSha $sha -RestInvoker $RestInvoker
      if ($ci.Found -and $ci.Status -eq "completed") { break }
      if ($PollSeconds -gt 0) { Start-Sleep -Seconds $PollSeconds } else { break }
    }
    $ciOk = ($null -ne $ci -and $ci.Found -and $ci.Status -eq "completed" -and $ci.Conclusion -eq "success")
    if ($ciOk -or $null -eq $effHeal -or $att -ge $MaxAttempts) { break }
    $preS = if (Get-Command Test-SenSuiteIntegrity -ErrorAction SilentlyContinue) { Test-SenSuiteIntegrity -TestsPath (Join-Path $RepoPath "tests") } else { $null }
    & $effHeal $ci.FailedSteps
    if ($null -ne $preS -and $preS.AssertionCount -gt 0) {
      $postS = Test-SenSuiteIntegrity -TestsPath (Join-Path $RepoPath "tests") -MinFiles $preS.FileCount -MinAssertions $preS.AssertionCount
      if (-not $postS.Passed) { return [pscustomobject][ordered]@{ LocalPassed = $false; Pushed = $pushed; CiPassed = $false; Attempts = $att; HeadSha = $sha; Errors = @("TestTamperBlocked: $($postS.Reason)"); CiStatus = $ci } }
    }
  }
  return [pscustomobject][ordered]@{ LocalPassed = $true; Pushed = $pushed; CiPassed = [bool]$ciOk; HeadSha = $sha; Errors = $(if ($ci -and $ci.FailedSteps) { $ci.FailedSteps } else { @() }); CiStatus = $ci }
}
function Test-SenCapabilityParity {
  [CmdletBinding()] param([Alias("Workspace", "WorkspacePath", "Path")][string]$SenRoot = "")
  $root = if ($SenRoot) { $SenRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path }
  $miss = [Collections.Generic.List[string]]::new(); $utf8 = [Text.Encoding]::UTF8
  $manP = Join-Path $root "scripts/process-manifest.json"
  if (-not (Test-Path -LiteralPath $manP)) {
    if (Test-Path -LiteralPath (Join-Path $root "docs")) { foreach ($df in @("docs/CONTEXT.md", "docs/TODO.md")) { if (-not (Test-Path -LiteralPath (Join-Path $root $df))) { $miss.Add("AppParity-Missing:$df") } } }
    $rmM = Join-Path $root "README.md"; $rmV = Join-Path $root "README.vi.md"
    if ((Test-Path -LiteralPath $rmM) -and (Test-Path -LiteralPath $rmV) -and ([IO.File]::ReadAllText($rmM, $utf8).Replace("`r`n", "`n").Trim() -ne [IO.File]::ReadAllText($rmV, $utf8).Replace("`r`n", "`n").Trim())) { $miss.Add("AppParity-DocSync:README_SYNC") }
    return [pscustomobject][ordered]@{ Passed = ($miss.Count -eq 0); MissingItems = @($miss.ToArray()); CheckedLayers = 6; Mode = "app" }
  }
  $rPath = Join-Path $root "rules/AGENTS.md"; $rTxt = if (Test-Path -LiteralPath $rPath) { [IO.File]::ReadAllText($rPath, $utf8) } else { "" }
  foreach ($p in @("Get-SenTaskRiskScore", "Invoke-SenDialecticalAudit", "New-SenRestorePoint", "Restore-SenRestorePoint", "Write-SenOfficeShowcase", "Measure-SenCodeHealth", "Invoke-SenVnLawScan", "Test-SenHungTasks", "Clear-SenHungTasks", "Test-SenCapabilityParity", "Test-SenDeliveryGate", "Invoke-SenCiPushLoop", "Add-SenBacklogItem", "Instant-Ack")) {
    if ($rTxt -notmatch "\b$([regex]::Escape($p))\b") { $miss.Add("L1-RuleMissingPrimitive:$p") }
  }
  if ($rTxt -match '(?i)\bor inline\b') { $miss.Add("L1-RuleContainsInlineLoophole") }
  $cat = Get-SenProcessCatalog -ManifestPath $manP
  if (@($cat.steps).Count -ne 12) { $miss.Add("L2-ManifestStepCount:$(@($cat.steps).Count)") }
  $sMap = @{}; foreach ($s in @($cat.steps)) { $sMap[[string]$s.id] = [string]$s.title }
  if ($sMap["S2-DESIGN-SPEC"] -notmatch 'Write-SenOfficeShowcase') { $miss.Add("L2-ManifestMissingPhase1Showcase") }
  if ($sMap["S3-TDD-VERIFY"] -notmatch 'Test-SenHungTasks') { $miss.Add("L2-ManifestMissingHungTaskWatchdog") }
  if ($sMap["S4-CONTEXT-REPORT"] -notmatch 'Write-SenOfficeShowcase|Test-SenCapabilityParity') { $miss.Add("L2-ManifestMissingPhase2Showcase") }
  $hTxt = [IO.File]::ReadAllText((Join-Path $root "scripts/Sen.Harness.psm1"), $utf8)
  foreach ($st in @($cat.steps)) { if ($hTxt -notmatch ('"' + [regex]::Escape([string]$st.id) + '"')) { $miss.Add("L2-EvidenceMissingStep:$($st.id)") } }
  $skDirs = if (Test-Path -LiteralPath (Join-Path $root "skills")) { @(Get-ChildItem -LiteralPath (Join-Path $root "skills") -Filter "sen-*" -Directory) } else { @() }
  if ($skDirs.Count -ne 9) { $miss.Add("L3-SkillCount:$($skDirs.Count)") }
  foreach ($sd in $skDirs) {
    $skF = Join-Path $sd.FullName "SKILL.md"
    if (-not (Test-Path -LiteralPath $skF) -or ([IO.File]::ReadAllText($skF, $utf8) -notmatch '(?s)^---\s*\r?\n.+?\r?\n---')) { $miss.Add("L3-InvalidSkill:$($sd.Name)") }
  }
  $tFiles = if (Test-Path -LiteralPath (Join-Path $root "tests")) { @(Get-ChildItem -LiteralPath (Join-Path $root "tests") -Filter "*.Tests.ps1" -File) } else { @() }
  $astCmds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($tf in $tFiles) {
    $tks = $null; $ers = $null; $ast = [System.Management.Automation.Language.Parser]::ParseFile($tf.FullName, [ref]$tks, [ref]$ers)
    foreach ($cAst in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))) {
      $cn = $cAst.GetCommandName(); if ($cn) { [void]$astCmds.Add($cn) }
    }
  }
  $tCorp = ($tFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName, $utf8) }) -join "`n"
  $expFns = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($mf in @(Get-ChildItem -LiteralPath (Join-Path $root "scripts") -Filter "*.psm1" -File)) {
    $eLine = [regex]::Match([IO.File]::ReadAllText($mf.FullName, $utf8), '(?m)^Export-ModuleMember\s+-Function\s+([^\r\n]+)').Groups[1].Value
    foreach ($fn in @($eLine -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
      [void]$expFns.Add($fn)
      if ((-not $astCmds.Contains($fn)) -and ($tCorp -notmatch "\b$([regex]::Escape($fn))\b")) { $miss.Add("L4-UntestedExport:$fn") }
    }
  }
  if (Test-Path -LiteralPath $rPath) {
    $rB = $utf8.GetByteCount($rTxt.Replace("`r`n", "`n")); $rL = @([IO.File]::ReadAllLines($rPath)).Count
    if ($rB -gt 5750 -or $rL -gt 95) { $miss.Add("L5-ContextBudgetExceeded:${rB}B/${rL}L") }
  }
  else { $miss.Add("L5-MissingRuleFile") }
  $rmM = Join-Path $root "README.md"; $rmV = Join-Path $root "README.vi.md"
  if ((Test-Path -LiteralPath $rmM) -and (Test-Path -LiteralPath $rmV) -and ([IO.File]::ReadAllText($rmM, $utf8).Replace("`r`n", "`n").Trim() -ne [IO.File]::ReadAllText($rmV, $utf8).Replace("`r`n", "`n").Trim())) { $miss.Add("L5-DocSync:README_SYNC") }
  $pJson = Read-SenSafeJson -Path (Join-Path $root "plugin.json")
  if ($null -ne $pJson -and $pJson.version) {
    foreach ($df in @("README.md", "CHANGELOG.md", "INSTALL.md", "docs/CONTEXT.md")) {
      $dp = Join-Path $root $df
      if ((Test-Path -LiteralPath $dp) -and ([IO.File]::ReadAllText($dp, $utf8) -notmatch [regex]::Escape([string]$pJson.version))) { $miss.Add("L5-DocSync:VERSION_DOC_SYNC:$df") }
    }
    if ((Test-Path -LiteralPath (Join-Path $root "docs/releases")) -and (Get-Command Test-SenReleaseNoteGate -ErrorAction SilentlyContinue)) {
      $rnG = Test-SenReleaseNoteGate -Workspace $root -Version ([string]$pJson.version)
      if (-not $rnG.Passed) { foreach ($m in $rnG.Missing) { $miss.Add("L6-ReleaseNote:$m") } }
    }
  }
  $todoF = Join-Path $root "docs/TODO.md"; $ctxF = Join-Path $root "docs/CONTEXT.md"
  if ((Test-Path -LiteralPath $todoF) -and (Test-Path -LiteralPath $ctxF)) {
    $tdTxt = [IO.File]::ReadAllText($todoF, $utf8); $cxTxt = [IO.File]::ReadAllText($ctxF, $utf8)
    $allIds = @([regex]::Matches($tdTxt, '\bTASK-\d+\b') | ForEach-Object { $_.Value })
    $lastId = if ($allIds.Count -gt 0) { $allIds[$allIds.Count - 1] } else { "" }
    if (@([regex]::Matches($tdTxt, '(?m)^-\s*\[ \]\s*\*\*TASK-\d+')).Count -eq 0 -and $lastId -and ($cxTxt -notmatch "\b$([regex]::Escape($lastId))\b")) { $miss.Add("L5-DocSync:TODO_CONTEXT_SYNC:$lastId") }
    $instF = Join-Path $root "INSTALL.md"
    if ($lastId -and (Test-Path -LiteralPath $instF) -and ([IO.File]::ReadAllText($instF, $utf8) -notmatch "\b$([regex]::Escape($lastId))\b")) { $miss.Add("L6-DocsParity:StaleInstallTaskCount:$lastId") }
  }
  foreach ($rf in @("README.md", "README.vi.md", "README.en.md", "INSTALL.md")) {
    $rp = Join-Path $root $rf
    if ((Test-Path -LiteralPath $rp) -and $expFns.Count -gt 0) {
      $rt = [IO.File]::ReadAllText($rp, $utf8)
      if ($rt -notmatch "\b$($expFns.Count)\b" -or $rt -match '(?i)\b(68|69|71|73)\s*(exported\s+)?cmdlets\b|\b(68|69|71|73)/\1\b') { $miss.Add("L6-DocsParity:StaleCmdletCount:$rf") }
      if ($rt -match '(?i)\b10\s+(`?sen-\*`?\s+)?(skills?|k. n.ng)\b') { $miss.Add("L6-DocsParity:StaleSkillCount:$rf") }
    }
  }
  foreach ($gf in @("docs/huong-dan.md", "docs/guide.md")) {
    $gp = Join-Path $root $gf
    if (Test-Path -LiteralPath $gp) {
      $gt = [IO.File]::ReadAllText($gp, $utf8)
      if ($gt -match '(?i)\b7\s+(sen-\*\s+)?skills?\b|waits for your approval once|duy.t ph..ng .n ..ng m.t l.n' -or $gt -notmatch 'New-SenRestorePoint') { $miss.Add("L6-DocsParity:StaleGuideFlow:$gf") }
    }
  }
  $chgP = Join-Path $root "CHANGELOG.md"
  if ((Test-Path -LiteralPath $chgP) -and ([IO.File]::ReadAllText($chgP, $utf8) -notmatch 'officeAction')) { $miss.Add("L6-DocsParity:ChangelogMissingOfficeAction") }
  return [pscustomobject][ordered]@{ Passed = ($miss.Count -eq 0); MissingItems = @($miss.ToArray()); CheckedLayers = 6 }
}
Export-ModuleMember -Function Get-SenSupportedHarnesses, ConvertFrom-SenHookPayload, Update-SenManagedBlock, Remove-SenManagedBlock, Install-SenHarness, Uninstall-SenHarness, Test-SenHarnessStatus, Install-SenGitHooks, Sync-SenPlanToTasks, Sync-SenTasksToMarkdown, Get-SenProcessCatalog, Initialize-SenProcessAudit, Test-SenStageGate, Test-SenProjectCompliance, Get-SenRemoteCiStatus, Invoke-SenCiPushLoop, Test-SenCapabilityParity
