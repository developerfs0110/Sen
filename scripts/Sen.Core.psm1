# scripts/Sen.Core.psm1
# Unified ASCII bootstrap loader and Operational Control Plane core helpers for Sen modules.
$ErrorActionPreference = "Stop"

function Get-SenTextDigest {
    param([AllowEmptyString()][string]$Text = "")
    $bytes = [Text.Encoding]::UTF8.GetBytes([string]$Text)
    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
}

function Get-SenRepoCodeRevision {
    param([string]$Workspace)
    if ($Workspace -and (Test-Path -LiteralPath (Join-Path $Workspace ".git"))) {
        try {
            $gc = (& git -C $Workspace rev-parse --short=12 HEAD 2>$null)
            if ($LASTEXITCODE -eq 0 -and $gc) { return ([string]$gc).Trim() }
        }
        catch { <# Ignore git error #> }
    }
    return "uncommitted"
}

function Invoke-SenLiveEvidenceRunner {
    param([string]$Workspace, [string]$Command, [int]$ProvidedExitCode = 0, [string]$ProvidedOutput = "", [switch]$ExecuteCommand, [switch]$ClaimedOnly, [string]$ExecutionId = "", [int]$ProcessId = 0, [string]$OutputHash = "")
    $startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $outTxt = $ProvidedOutput; $ec = $ProvidedExitCode
    if ($ExecuteCommand.IsPresent -and (-not [string]::IsNullOrWhiteSpace($Command))) {
        $pwshBin = if (Get-Command pwsh -EA SilentlyContinue) { "pwsh" } else { "powershell" }
        $liveOut = "" | & $pwshBin -NoProfile -NonInteractive -Command $Command 2>&1
        $ec = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 1 }
        $outTxt = ($liveOut | ForEach-Object { [string]$_ }) -join "`n"
    }
    $completedAt = [DateTime]::UtcNow.ToString("o")
    $rev = Get-SenRepoCodeRevision -Workspace $Workspace
    $execId = if (-not [string]::IsNullOrWhiteSpace($ExecutionId)) { $ExecutionId } else { "exec-" + ([Guid]::NewGuid().ToString("N").Substring(0, 12)) }
    $pidVal = if ($ProcessId -gt 0) { $ProcessId } else { $PID }
    $hashVal = if (-not [string]::IsNullOrWhiteSpace($OutputHash)) { $OutputHash } else { (Get-SenTextDigest -Text "$Command|$ec|$rev|$outTxt").Substring(0, 32) }
    $evType = if ($ClaimedOnly.IsPresent) { "ClaimedEvidence" } else { "VerifiedEvidence" }
    return [pscustomobject][ordered]@{
        ExecutionId = $execId; ProcessId = $pidVal; StartedAt = $startedAt; CompletedAt = $completedAt
        ExitCode = $ec; Output = $outTxt; OutputHash = $hashVal; CodeRevision = $rev; EvidenceType = $evType
    }
}

function Test-SenTaskAcceptanceCriteria {
    param([string]$Workspace, $Task, [bool]$AcceptanceVerified = $true)
    if (-not $AcceptanceVerified) { return [pscustomobject]@{ Passed = $false; Reason = "Acceptance criteria explicitly marked unmet (-AcceptanceVerified:`$false) for task '$($Task.id)'." } }
    if ($null -eq $Task) { return [pscustomobject]@{ Passed = $true; Reason = $null } }
    if ($Task.PSObject.Properties['acceptanceStatus'] -and ([string]$Task.acceptanceStatus -match '^(?i)(failed|unmet|rejected|incomplete)$')) {
        return [pscustomobject]@{ Passed = $false; Reason = "Task '$($Task.id)' has unmet acceptanceStatus '$($Task.acceptanceStatus)'." }
    }
    foreach ($ac in @($Task.acceptanceCriteria)) {
        $acStr = ([string]$ac).Trim()
        if ([string]::IsNullOrWhiteSpace($acStr)) { continue }
        if ($acStr -match '^(?i)(UNMET|FAIL|TODO):\s*(.+)$') {
            return [pscustomobject]@{ Passed = $false; Reason = "Acceptance criterion unmet for '$($Task.id)': $acStr" }
        }
        if ($acStr -match '^(?i)MUST_EXIST:\s*(.+)$') {
            $relP = $matches[1].Trim()
            $fullP = if ([IO.Path]::IsPathRooted($relP)) { $relP } else { Join-Path $Workspace $relP }
            if (-not (Test-Path -LiteralPath $fullP)) {
                return [pscustomobject]@{ Passed = $false; Reason = "Acceptance criterion MUST_EXIST failed for '$($Task.id)': missing '$relP'." }
            }
        }
    }
    return [pscustomobject]@{ Passed = $true; Reason = $null }
}

function Get-SenHungProcessIds {
    param([string]$Workspace, [int]$MaxProcessSeconds = 120, [bool]$HasActiveLongRunning = $false)
    $hungPids = [Collections.Generic.List[int]]::new()
    $maxSec = [Math]::Max(5, $MaxProcessSeconds); $procCutoff = (Get-Date).ToUniversalTime().AddSeconds(-1 * $maxSec)
    $isTempWs = $Workspace -match '(?i)([\\/](temp|tmp|T)[\\/]|sen-(orch|harness|gov|adv|.*-test|test_)|TestDrive)'
    $normWs = $Workspace.Replace('\', '/').TrimEnd('/')
    try {
        $winProcs = if ($env:OS -eq 'Windows_NT' -and (Get-Command Get-CimInstance -EA SilentlyContinue)) { @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -EA SilentlyContinue) } else { @() }
        $anc = [Collections.Generic.HashSet[int]]::new(); $curP = $PID
        for ($k = 0; $k -lt 4; $k++) { [void]$anc.Add($curP); $pe = $winProcs | Where-Object { [int]$_.ProcessId -eq $curP } | Select-Object -First 1; if ($pe -and [int]$pe.ParentProcessId -gt 0) { $curP = [int]$pe.ParentProcessId } else { break } }
        $hiddenOffices = @($winProcs | Where-Object { [string]$_.CommandLine -match '(?i)start-office\.ps1' } | Sort-Object CreationDate)
        $keepPid = if ($hiddenOffices.Count -gt 0) { [int]$hiddenOffices[0].ProcessId } else { 0 }
        foreach ($wp in $winProcs) {
            $wpId = if ($wp) { [int]$wp.ProcessId } else { 0 }; $cmd = [string]$wp.CommandLine
            if ($wpId -le 0 -or $anc.Contains($wpId) -or $wpId -eq $keepPid -or ($cmd -match '(?i)(shellIntegration\.ps1|PowerShellEditorServices|\bvite\b|\bnpm(\.cmd)?\s+run\s+(dev|start|serve|preview)\b)')) { continue }
            if ($isTempWs -and ($cmd.Replace('\', '/').IndexOf($normWs, [StringComparison]::OrdinalIgnoreCase) -lt 0)) { continue }
            $isTarget = ($cmd -match '(?i)(Test-SenDeliveryGate|Invoke-SenPostCodePipeline|Measure-SenCodeHealth|Invoke-SenVnLawScan)') -or (($cmd -match '(?i)start-office\.ps1') -and ($wpId -ne $keepPid)) -or ((-not $HasActiveLongRunning) -and ($cmd -match '(?i)(-Command\s+"try\s*\{\s*\$OutputEncoding|Sen\.psm1)') -and ($cmd -notmatch '(?i)\b(run\.ps1|Invoke-SenCiPushLoop)\b'))
            $proc = if ($isTarget) { Get-Process -Id $wpId -EA SilentlyContinue } else { $null }
            if ($null -ne $proc -and $proc.StartTime.ToUniversalTime() -lt $procCutoff) { $hungPids.Add($wpId) }
        }
        foreach ($up in @(if ($env:OS -ne 'Windows_NT') { Get-Process -Name pwsh, powershell -EA SilentlyContinue } else { @() })) {
            $uCmd = if ($up.PSObject.Properties['CommandLine'] -and $up.CommandLine) { [string]$up.CommandLine } elseif (Test-Path "/proc/$($up.Id)/cmdline") { [IO.File]::ReadAllText("/proc/$($up.Id)/cmdline").Replace([char]0, ' ') } else { (@(& ps -ww -p $up.Id -o command= 2>$null) -join ' ') }
            if ($up.Id -ne $PID -and $up.StartTime.ToUniversalTime() -le $procCutoff -and $uCmd -match '(?i)(Sen\.psm1|Test-SenDeliveryGate|Invoke-SenPostCodePipeline)' -and ((-not $isTempWs) -or ($uCmd.Replace('\', '/').IndexOf($normWs, [StringComparison]::OrdinalIgnoreCase) -ge 0))) { $hungPids.Add([int]$up.Id) }
        }
    }
    catch { <# Ignore process enumeration errors #> }
    return $hungPids.ToArray()
}

function Test-SenSymlinkEscape {
    param([string]$FullTarget, [string[]]$ResolvedWorkspaces)
    $probe = $FullTarget; $cmp = [StringComparison]::OrdinalIgnoreCase; $sep = [IO.Path]::DirectorySeparatorChar
    for ($i = 0; $i -lt 10; $i++) {
        if ([string]::IsNullOrWhiteSpace($probe) -or $probe -eq "/") { break }
        $inWs = $false
        foreach ($rw in $ResolvedWorkspaces) { if ($rw -and ($probe.StartsWith($rw + $sep, $cmp) -or $probe.StartsWith($rw + '/', $cmp))) { $inWs = $true; break } }
        if (-not $inWs) { break }
        $it = if (Test-Path -LiteralPath $probe) { Get-Item -LiteralPath $probe -Force -EA SilentlyContinue } else { $null }
        if (($null -ne $it) -and ([int]($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            $lt = if ($it.PSObject.Properties['Target'] -and $it.Target) { [string](@($it.Target)[0]) } else { "" }
            if (-not $lt) { return $true }
            $par = Split-Path -Parent $probe
            $abs = if ([IO.Path]::IsPathRooted($lt)) { [IO.Path]::GetFullPath($lt) } elseif ($par) { [IO.Path]::GetFullPath((Join-Path $par $lt)) } else { $lt }
            if (@($ResolvedWorkspaces | Where-Object { $abs.StartsWith($_, $cmp) }).Count -eq 0) { return $true }
        }
        $p = Split-Path -Parent $probe; if ([string]::IsNullOrWhiteSpace($p) -or $p -eq $probe -or $p -eq "/") { break }; $probe = $p
    }
    return $false
}

function Build-SenHarnessBridgeText {
    param([string]$Workspace, [string]$HarnessId)
    $pRules = Join-Path $Workspace ".agents/plugins/sen-method/rules/AGENTS.md"
    $rPath = Join-Path $Workspace ".agents/rules/AGENTS.md"
    if (Test-Path -LiteralPath $pRules) {
        $pDir = [IO.Path]::GetDirectoryName($rPath)
        if ($pDir -and -not (Test-Path -LiteralPath $pDir)) { [IO.Directory]::CreateDirectory($pDir) | Out-Null }
        Copy-Item -LiteralPath $pRules -Destination $rPath -Force
    }
    elseif (-not (Test-Path -LiteralPath $rPath)) { $rPath = Join-Path $Workspace "rules/AGENTS.md" }
    $core = if (Test-Path -LiteralPath $rPath) { [IO.File]::ReadAllText($rPath, [Text.Encoding]::UTF8).Trim() } else { "# Sen Core Rule" }
    $profP = Join-Path $Workspace ".agents/rules/profile.md"
    $prof = if (Test-Path -LiteralPath $profP) { "`n`n" + [IO.File]::ReadAllText($profP, [Text.Encoding]::UTF8).Trim() } else { "" }
    $info = "## Multi-Harness Bridge ($HarnessId)`n- **Single Source of Truth:** `.agents/` holds rules, skills (`.agents/plugins/sen-method/skills/` and `.agents/skills/`), state (`.agents/office/tasks.json`), and 3D AI Office.`n- **Two-Way Sync:** Saving `docs/superpowers/plans/*.md` or `docs/TODO.md` auto-syncs tasks into `.agents/office/tasks.json`; completing tasks via `Complete-SenTaskReview` auto-ticks `[x]` in Markdown."
    return ($core + $prof + "`n`n" + $info)
}

function Install-SenHarnessHookFile {
    param([string]$Workspace, [string]$HarnessId, [string]$HookRelPath)
    if ([string]::IsNullOrWhiteSpace($HookRelPath)) { return $null }
    $fullP = Join-Path $Workspace $HookRelPath; $isWin = ($env:OS -eq "Windows_NT"); $ext = if ($isWin) { "ps1" } else { "sh" }
    $pBase = if ((Test-Path -LiteralPath (Join-Path $Workspace ".agents/plugins/sen-method/scripts/guard.ps1")) -or ($HookRelPath -match '\.agents[/\\]plugins[/\\]sen-method')) { ".agents/plugins/sen-method/scripts" } else { "scripts" }
    $gCmd = if ($isWin) { "powershell -NoProfile -ExecutionPolicy Bypass -File $pBase/guard.$ext" } else { "sh $pBase/guard.$ext" }
    $pCmd = if ($isWin) { "powershell -NoProfile -ExecutionPolicy Bypass -File $pBase/office-post.$ext" } else { "sh $pBase/office-post.$ext" }
    if ($HarnessId -eq "antigravity") {
        $agObj = [ordered]@{ "sen-destructive-command-guard" = [ordered]@{ PreToolUse = @([ordered]@{ matcher = "run_command|write_file|edit_file|read_file"; hooks = @([ordered]@{ type = "command"; command = $gCmd; timeout = 10 }) }); PostToolUse = @([ordered]@{ matcher = "run_command|write_file|edit_file|read_file|grep_search|find_by_name|invoke_subagent|send_message|manage_subagents"; hooks = @([ordered]@{ type = "command"; command = $pCmd; timeout = 5 }) }) } }
        Write-SenAtomicJson -Path $fullP -InputObject $agObj -Depth 8
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

function Test-SenHarnessLiveProbe {
    param([string]$Workspace)
    $gScript = Join-Path $Workspace ".agents/plugins/sen-method/scripts/guard.ps1"
    if (-not (Test-Path -LiteralPath $gScript)) { $gScript = Join-Path $Workspace "scripts/guard.ps1" }
    if (-not (Test-Path -LiteralPath $gScript)) { $gScript = Join-Path $PSScriptRoot "guard.ps1" }
    if (-not (Test-Path -LiteralPath $gScript)) { return $false }
    $gItem = Get-Item -LiteralPath $gScript -EA SilentlyContinue
    if ($gItem -and $gItem.Length -lt 200) { return $true }
    $cacheKey = "$($gScript)|$($gItem.LastWriteTimeUtc.Ticks)"
    if ($global:SenLastGuardProbeKey -eq $cacheKey -and $null -ne $global:SenLastGuardProbeResult) { return [bool]$global:SenLastGuardProbeResult }
    try {
        $pwshBin = if (Get-Command pwsh -EA SilentlyContinue) { "pwsh" } else { "powershell" }
        $probeOut = '{"tool_name":"read_file","tool_input":{"path":"README.md"}}' | & $pwshBin -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $gScript 2>$null
        $obj = ((@($probeOut) -join "`n").Trim()) | ConvertFrom-Json -EA SilentlyContinue
        $ok = ($null -ne $obj -and ([string]$obj.decision -in @("ask", "allow")))
        $global:SenLastGuardProbeKey = $cacheKey; $global:SenLastGuardProbeResult = $ok
        return $ok
    }
    catch { return $false }
}

function Sync-SenTodoMarkdownItems {
    param([string]$Workspace, $ExistingIds)
    $todoPath = Join-Path -Path $Workspace -ChildPath "docs/TODO.md"
    if (-not (Test-Path -LiteralPath $todoPath)) { return 0 }
    $todoText = [IO.File]::ReadAllText($todoPath, [Text.Encoding]::UTF8)
    $evFile = Join-Path $Workspace ".agents/office/evidence.json"
    $evItems = if (Test-Path -LiteralPath $evFile) { @(Read-SenSafeJson -Path $evFile) } else { @() }
    $synced = 0
    foreach ($m in [regex]::Matches($todoText, '(?m)^-\s*\[([ xX~])\]\s*\*\*([A-Za-z0-9_-]+)(?:\s*\(([^)]+)\))?:\s*([^\r\n]+)\*\*[ \t]*((?:\r?\n[ \t]+-[^\r\n]+)*)')) {
        $tid = $m.Groups[2].Value.Trim(); $ttitle = $m.Groups[4].Value.Trim(); $isChecked = ($m.Groups[1].Value -match '[xX]')
        $isArchived = ($isChecked -and ($m.Groups[3].Value -match '(?i)(v0\.\d+\.\d+|Ho.n t.t|Completed|\*\*K.t qu.|\*\*N.i dung:)' -or $m.Groups[5].Value -match '(?i)(v0\.\d+\.\d+|Ho.n t.t|Completed|\*\*K.t qu.|\*\*N.i dung:)'))
        $hasEv = (@($evItems | Where-Object { $_ -and ([string]$_.task_id -eq $tid) -and ([string]$_.status -eq "PASS") -and ([string]$_.command -notmatch '^(todo-verified|subagent-verified|verified-in-session|session-verified|hook-telemetry|manual|none)$') }).Count -gt 0)
        if (-not $ExistingIds.Contains($tid)) {
            [void]$ExistingIds.Add($tid)
            if ($isArchived -and -not $hasEv) { continue }
            $st = if (-not $isChecked) { "backlog" } elseif ($hasEv) { "done" } else { "needs_verification" }
            [void](New-SenTask -Workspace $Workspace -Id $tid -Title $ttitle -Tier 2 -Module "Backlog" -Assignee "pm" -Status $st)
            $synced++
        }
        if ($isChecked -and (-not $hasEv)) {
            $curTasks = @(Get-SenTasks -Workspace $Workspace); $changed = $false
            foreach ($ct in $curTasks) {
                if ([string]$ct.id -ne $tid) { continue }
                if ($isArchived -and [string]$ct.status -notin @("done", "backlog")) { $ct.status = "backlog"; $changed = $true }
                elseif ((-not $isArchived) -and [string]$ct.status -ne "done" -and ([string]$ct.status -ne "needs_verification" -or (-not $ct.PSObject.Properties['documentationComplete']))) {
                    $ct.status = "needs_verification"; $ct | Add-Member -NotePropertyName "documentationComplete" -NotePropertyValue $true -Force; $ct | Add-Member -NotePropertyName "executionVerified" -NotePropertyValue $false -Force; $changed = $true
                }
            }
            if ($changed) { [void](Save-SenTasks -Workspace $Workspace -Tasks $curTasks -Internal) }
        }
    }
    return $synced
}

function Get-SenStepArtifactHash {
    param([string]$Workspace, [string]$StepId)
    $parts = [Collections.Generic.List[string]]::new()
    if ($StepId -in @("S2-EXPERT-COST", "S2-DESIGN-SPEC")) {
        $sDir = Join-Path $Workspace "docs/superpowers/specs"
        foreach ($f in @(if (Test-Path -LiteralPath $sDir) { Get-ChildItem -LiteralPath $sDir -Filter "*.md" -File -EA SilentlyContinue | Sort-Object Name } else { @() })) {
            $parts.Add("$($f.Name):" + (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant())
        }
        $scP = Join-Path $Workspace ".agents/office/showcase.json"
        if ($StepId -eq "S2-DESIGN-SPEC" -and (Test-Path -LiteralPath $scP)) { $parts.Add("sc:" + (Get-FileHash -LiteralPath $scP -Algorithm SHA256).Hash.ToLowerInvariant()) }
    }
    elseif ($StepId -eq "S2-IMPL-PLAN") {
        $pDir = Join-Path $Workspace "docs/superpowers/plans"
        foreach ($f in @(if (Test-Path -LiteralPath $pDir) { Get-ChildItem -LiteralPath $pDir -Filter "*.md" -File -EA SilentlyContinue | Sort-Object Name } else { @() })) {
            $parts.Add("$($f.Name):" + (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant())
        }
    }
    elseif ($StepId -in @("S2-TASK-DAG", "S3-TDD-VERIFY", "S3-TWOWAY-SYNC")) {
        $tkP = Join-Path $Workspace ".agents/office/tasks.json"
        if (Test-Path -LiteralPath $tkP) { $parts.Add("tasks:" + (Get-FileHash -LiteralPath $tkP -Algorithm SHA256).Hash.ToLowerInvariant()) }
    }
    elseif ($StepId -eq "S3-RESTORE-POINT") {
        $rpDir = Join-Path $Workspace ".agents/.sen-restore"
        foreach ($d in @(if (Test-Path -LiteralPath $rpDir) { Get-ChildItem -LiteralPath $rpDir -Directory -EA SilentlyContinue | Sort-Object Name } else { @() })) {
            $mf = Join-Path $d.FullName "manifest.json"
            if (Test-Path -LiteralPath $mf) { $parts.Add("$($d.Name):" + (Get-FileHash -LiteralPath $mf -Algorithm SHA256).Hash.ToLowerInvariant()) }
        }
    }
    elseif ($StepId -eq "S4-CONTEXT-REPORT") {
        $ctxP = Join-Path $Workspace "docs/CONTEXT.md"
        if (Test-Path -LiteralPath $ctxP) { $parts.Add("ctx:" + (Get-FileHash -LiteralPath $ctxP -Algorithm SHA256).Hash.ToLowerInvariant()) }
    }
    if ($parts.Count -eq 0) { return "" }
    return (Get-SenTextDigest -Text ($parts -join ";")).Substring(0, 32)
}

function Register-SenHookExecution {
    param([string]$Workspace, [string]$ExecutionId = "", [string]$ToolName = "", [string]$Target = "")
    if ([string]::IsNullOrWhiteSpace($Workspace)) { return $null }
    $offDir = Join-Path $Workspace ".agents/office"
    if (-not (Test-Path -LiteralPath $offDir)) { [IO.Directory]::CreateDirectory($offDir) | Out-Null }
    $ledPath = Join-Path $offDir "execution-ledger.jsonl"
    $eid = if ($ExecutionId) { $ExecutionId } else { "hexec-" + ([Guid]::NewGuid().ToString("N").Substring(0, 10)) }
    $entry = [ordered]@{ executionId = $eid; toolName = $ToolName; target = $Target; status = "pending"; startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ") }
    $line = ($entry | ConvertTo-Json -Compress) + "`n"
    [IO.File]::AppendAllText($ledPath, $line, [Text.UTF8Encoding]::new($false))
    return $entry
}

function Invoke-SenPreToolHookBootstrap {
    param($InputObject, [string]$Workspace, [string]$CanonicalTool = "", [string]$Target = "")
    if ([string]::IsNullOrWhiteSpace($Workspace) -or $null -eq $InputObject) { return }
    try {
        $inFile = Join-Path $Workspace ".agents/office/current-intake.json"
        $reqManual = ($InputObject.PSObject.Properties['requireManualIntake'] -and [bool]$InputObject.requireManualIntake) -or ($env:SEN_REQUIRE_MANUAL_INTAKE -eq "1")
        if ($reqManual -and (-not (Test-Path -LiteralPath $inFile))) {
            $denyObj = [ordered]@{ decision = "deny"; reason = "[SEN GUARD] Blocked: Session intake (.agents/office/current-intake.json) is missing. Run Initialize-SenIntake before invoking tools." }
            [Console]::Out.Write(($denyObj | ConvertTo-Json -Compress))
            exit 0
        }
        $hasOffice = (Test-Path -LiteralPath (Join-Path $Workspace ".agents/office")) -or (Test-Path -LiteralPath (Join-Path $Workspace ".agents/rules")) -or ($InputObject.PSObject.Properties['bootstrapIntake'] -and [bool]$InputObject.bootstrapIntake) -or ($env:SEN_ENFORCE_PRETOOL_INTAKE -eq "1")
        if ($hasOffice -and (-not (Test-Path -LiteralPath $inFile)) -and (Get-Command Initialize-SenIntake -EA SilentlyContinue)) {
            $sealP = Join-Path $Workspace ".agents/office/state-seal.json"
            $sealOk = (Test-Path -LiteralPath $sealP) -and (Get-Command Sync-SenOfficeState -EA SilentlyContinue) -and (-not (Sync-SenOfficeState -Workspace $Workspace -VerifySeal).Tampered)
            $sid = if ($InputObject.PSObject.Properties['sessionId']) { [string]$InputObject.sessionId } else { "" }
            $rid = if ($InputObject.PSObject.Properties['requestId']) { [string]$InputObject.requestId } else { "" }
            [void](Initialize-SenIntake -Workspace $Workspace -TaskId "AUTO-INTAKE" -Request ("PreToolUse: " + $CanonicalTool) -FileCount 1 -SessionId $sid -RequestId $rid -SkipOfficeLaunch)
            if ($sealOk) { [void](Sync-SenOfficeState -Workspace $Workspace -UpdateSeal) }
        }
        $hasExecId = ($InputObject.PSObject.Properties['executionId'] -and -not [string]::IsNullOrWhiteSpace([string]$InputObject.executionId)) -or ($InputObject.PSObject.Properties['trackExecution'] -and [bool]$InputObject.trackExecution) -or ($env:SEN_TRACK_EXECUTION_LEDGER -eq "1")
        if ($hasExecId) {
            $exId = if ($InputObject.PSObject.Properties['executionId']) { [string]$InputObject.executionId } else { "" }
            [void](Register-SenHookExecution -Workspace $Workspace -ExecutionId $exId -ToolName $CanonicalTool -Target $Target)
        }
    }
    catch { <# Non-fatal pre-tool intake/ledger tracking #> }
}

function Complete-SenHookExecution {
    param([string]$Workspace, [string]$ExecutionId = "", [string]$ToolName = "", [string]$Status = "reconciled", [string]$ErrorText = "")
    if ([string]::IsNullOrWhiteSpace($Workspace)) { return }
    $offDir = Join-Path $Workspace ".agents/office"
    $ledPath = Join-Path $offDir "execution-ledger.jsonl"
    if (Test-Path -LiteralPath $ledPath) {
        $lines = @([IO.File]::ReadAllLines($ledPath, [Text.Encoding]::UTF8) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $outLines = [Collections.Generic.List[string]]::new()
        $now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); $matched = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $obj = $lines[$i] | ConvertFrom-Json -EA SilentlyContinue
            if ($null -ne $obj -and [string]$obj.status -eq "pending" -and ((-not $ExecutionId -and (-not $ToolName -or [string]$obj.toolName -eq $ToolName)) -or ([string]$obj.executionId -eq $ExecutionId))) {
                $obj | Add-Member -NotePropertyName "status" -NotePropertyValue $Status -Force
                $obj | Add-Member -NotePropertyName "completedAt" -NotePropertyValue $now -Force
                if ($ErrorText) { $obj | Add-Member -NotePropertyName "error" -NotePropertyValue $ErrorText -Force }
                $outLines.Add(($obj | ConvertTo-Json -Compress)); $matched = $true
            }
            else { $outLines.Add($lines[$i]) }
        }
        if ($matched) { [IO.File]::WriteAllLines($ledPath, $outLines.ToArray(), [Text.UTF8Encoding]::new($false)) }
    }
    if ($Status -in @("unreconciled", "failed", "timeout") -or (-not [string]::IsNullOrWhiteSpace($ErrorText))) {
        if (-not (Test-Path -LiteralPath $offDir)) { [IO.Directory]::CreateDirectory($offDir) | Out-Null }
        $failPath = Join-Path $offDir "hook-failures.jsonl"
        $fObj = [ordered]@{ timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); executionId = $ExecutionId; hook = "office-post"; toolName = $ToolName; status = "unreconciled"; error = $ErrorText }
        [IO.File]::AppendAllText($failPath, (($fObj | ConvertTo-Json -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
    }
}

function Test-SenDeliveryReconciliation {
    param([string]$Workspace, [object[]]$CurrentTasks = @(), [switch]$EnforceIntake)
    $issues = [Collections.Generic.List[string]]::new(); $rems = [Collections.Generic.List[string]]::new()
    $offDir = Join-Path $Workspace ".agents/office"
    $inPath = Join-Path $offDir "current-intake.json"
    $inObj = if (Test-Path -LiteralPath $inPath) { Read-SenSafeJson -Path $inPath } else { $null }
    $enforceIt = ($null -ne $inObj) -and ($EnforceIntake.IsPresent -or ($inObj.PSObject.Properties['enforceDeliveryGate'] -and [bool]$inObj.enforceDeliveryGate))
    $intakeCheck = if ($enforceIt -and (Get-Command Test-SenIntakeCompleteness -EA SilentlyContinue)) { Test-SenIntakeCompleteness -Workspace $Workspace -EnforceAllObligations } else { $null }
    if ($null -ne $intakeCheck -and (-not $intakeCheck.Passed)) {
        $issues.Add("Intake obligations incomplete ($($intakeCheck.MissingElements -join ', '))")
        $rems.Add("Test-SenIntakeCompleteness -Workspace '$Workspace' -EnforceAllObligations")
    }
    $unreconciled = [Collections.Generic.List[string]]::new()
    $ledJsonl = Join-Path $offDir "execution-ledger.jsonl"
    foreach ($ln in @(if (Test-Path -LiteralPath $ledJsonl) { [IO.File]::ReadAllLines($ledJsonl, [Text.Encoding]::UTF8) } else { @() })) {
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        $lo = $ln | ConvertFrom-Json -EA SilentlyContinue
        if ($lo -and [string]$lo.status -in @("pending", "unreconciled", "timeout", "failed")) {
            $unreconciled.Add("$(if ($lo.executionId) { $lo.executionId } else { $lo.toolName }):$($lo.status)")
        }
    }
    $failJsonl = Join-Path $offDir "hook-failures.jsonl"
    foreach ($fl in @(if (Test-Path -LiteralPath $failJsonl) { [IO.File]::ReadAllLines($failJsonl, [Text.Encoding]::UTF8) } else { @() })) {
        if ([string]::IsNullOrWhiteSpace($fl)) { continue }
        $fo = $fl | ConvertFrom-Json -EA SilentlyContinue
        if ($fo -and [string]$fo.status -in @("unresolved", "unreconciled", "failed", "timeout")) {
            $unreconciled.Add("$(if ($fo.hook) { $fo.hook } else { 'hook' }):$($fo.status)")
        }
    }
    if ($unreconciled.Count -gt 0) {
        $issues.Add("Unreconciled hook execution or PostToolUse timeout ($($unreconciled -join ', '))")
        $rems.Add("Complete-SenHookExecution -Workspace '$Workspace' -Status 'reconciled'")
    }
    $presentIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($ct in $CurrentTasks) { if ($ct -and $ct.id) { [void]$presentIds.Add([string]$ct.id) } }
    $droppedIds = [Collections.Generic.List[string]]::new()
    $tkRaw = Read-SenSafeJson -Path (Join-Path $offDir "tasks.json")
    $plannedArr = if ($null -ne $tkRaw -and $tkRaw.PSObject.Properties['plannedTaskIds'] -and $tkRaw.plannedTaskIds) { @($tkRaw.plannedTaskIds) } else { @() }
    foreach ($pidItem in $plannedArr) {
        if ($pidItem -and (-not $presentIds.Contains([string]$pidItem)) -and (-not $droppedIds.Contains([string]$pidItem))) { $droppedIds.Add([string]$pidItem) }
    }
    $reqRaw = Read-SenSafeJson -Path (Join-Path $offDir "requirements.json")
    $rList = if ($null -eq $reqRaw) { @() } elseif ($reqRaw.PSObject.Properties['requirements']) { @($reqRaw.requirements) } else { @($reqRaw) }
    foreach ($r in $rList) {
        $rTasks = if ($r -and [string]$r.status -ne "SUPERSEDED" -and $r.PSObject.Properties['taskIds']) { @($r.taskIds) } else { @() }
        foreach ($rtid in $rTasks) {
            if ($rtid -and (-not $presentIds.Contains([string]$rtid)) -and (-not $droppedIds.Contains([string]$rtid))) { $droppedIds.Add([string]$rtid) }
        }
    }
    if ($droppedIds.Count -gt 0) {
        $issues.Add("DAG reconciliation failed: dropped task(s) missing from tasks.json ($($droppedIds -join ', '))")
        $rems.Add("Sync-SenPlanToTasks -Workspace '$Workspace'")
    }
    return [pscustomobject]@{
        Passed = ($issues.Count -eq 0); Issues = @($issues.ToArray()); RemediationCommands = @($rems.ToArray())
        IntakeCompleteness = $intakeCheck; UnreconciledExecutions = @($unreconciled.ToArray()); DroppedTaskIds = @($droppedIds.ToArray())
    }
}

function Resolve-SenBrowserIdentity {
    param([string]$UserAgent = "", [string]$CachedBrowser = "", [string]$CachedProfile = "")
    $bName = if ($UserAgent -match '(?i)Edg/') { "Microsoft Edge" } elseif ($UserAgent -match '(?i)CocCoc') { "CocCoc" } elseif ($UserAgent -match '(?i)Brave') { "Brave" } elseif ($UserAgent -match '(?i)Firefox/') { "Mozilla Firefox" } elseif ($UserAgent -match '(?i)Chrome/') { "Google Chrome" } elseif ($CachedBrowser) { $CachedBrowser } else { "" }
    if ([string]::IsNullOrWhiteSpace($bName) -and $env:OS -eq 'Windows_NT') {
        try {
            $progId = [string](Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice" -Name "ProgId" -EA SilentlyContinue).ProgId
            $bName = if ($progId -match '(?i)MSEdge') { "Microsoft Edge" } elseif ($progId -match '(?i)Brave') { "Brave" } elseif ($progId -match '(?i)CocCoc') { "CocCoc" } elseif ($progId -match '(?i)Firefox') { "Mozilla Firefox" } else { "Google Chrome" }
        }
        catch { <# Fallback browser name #> $bName = "Default Browser" }
    }
    if ([string]::IsNullOrWhiteSpace($bName)) { $bName = "Default Browser" }
    $prof = if (-not [string]::IsNullOrWhiteSpace($CachedProfile)) { $CachedProfile } else { "Default" }
    return [pscustomobject]@{ BrowserName = $bName; ProfileName = $prof }
}

function Update-SenOfficeTabHeartbeat {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace, [int]$Port = 47890, [string]$UserAgent = "", [string]$QueryString = "", [string]$TabTitle = "", [switch]$Closed, [switch]$Launched)
    $stPath = Join-Path $Workspace ".agents/office/tab-session.state"
    $cur = Read-SenSafeJson -Path $stPath
    $qMap = @{}
    foreach ($kv in @($QueryString.TrimStart('?') -split '&')) {
        if ($kv -match '^([^=]+)=(.*)$') { $qMap[$matches[1]] = [Uri]::UnescapeDataString($matches[2]) }
    }
    $idInfo = Resolve-SenBrowserIdentity -UserAgent $UserAgent -CachedBrowser $(if ($qMap['browser']) { $qMap['browser'] } elseif ($cur) { [string]$cur.browserName } else { "" }) -CachedProfile $(if ($qMap['profile']) { $qMap['profile'] } elseif ($cur) { [string]$cur.profileName } else { "Default" })
    $tTitle = if ($TabTitle) { $TabTitle } elseif ($qMap['title']) { [string]$qMap['title'] } elseif ($cur -and $cur.tabTitle) { [string]$cur.tabTitle } else { "Sen Office 3D" }
    $vis = if ($Closed.IsPresent) { "closed" } elseif ($qMap['vis']) { [string]$qMap['vis'] } elseif ($cur -and $cur.visibilityState) { [string]$cur.visibilityState } else { "visible" }
    $tId = if ($qMap['tabId']) { [string]$qMap['tabId'] } elseif ($cur -and $cur.tabId) { [string]$cur.tabId } else { "tab-" + $Port }
    $nowIso = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $next = [ordered]@{
        workspace = $Workspace; port = $Port; url = "http://127.0.0.1:$Port/"; tabId = $tId
        browserName = $idInfo.BrowserName; profileName = $idInfo.ProfileName; tabTitle = $tTitle
        visibilityState = $vis; tabClosed = [bool]$Closed.IsPresent; lastPingAt = $nowIso
        launchedAt = $(if ($Launched.IsPresent -or (-not $cur)) { $nowIso } else { [string]$cur.launchedAt })
    }
    Write-SenAtomicJson -Path $stPath -InputObject $next -Depth 4
    return [pscustomobject]$next
}

function Get-SenOfficeTabStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Alias("WorkspacePath", "Path")][string]$Workspace, [int]$Port = 0, [int]$HeartbeatTimeoutSeconds = 300, [switch]$SimulateAliveTab)
    $cfg = Get-SenOfficeConfig -Workspace $Workspace
    $usePort = if ($Port -gt 1024) { $Port } else { [int]$cfg.port }
    $stPath = Join-Path $Workspace ".agents/office/tab-session.state"
    if ($SimulateAliveTab.IsPresent) { [void](Update-SenOfficeTabHeartbeat -Workspace $Workspace -Port $usePort -TabTitle "Sen Office 3D (Live)" -Launched) }
    $sess = Read-SenSafeJson -Path $stPath
    $srvAlive = $SimulateAliveTab.IsPresent
    if (-not $srvAlive) {
        $tc = [Net.Sockets.TcpClient]::new()
        try { $ar = $tc.BeginConnect("127.0.0.1", $usePort, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(250, $false) -and $tc.Connected) { $srvAlive = $true } } catch { <# Port closed #> $srvAlive = $false } finally { try { $tc.Close() } catch { <# Ignore #> } }
    }
    $idInfo = Resolve-SenBrowserIdentity -CachedBrowser $(if ($sess) { [string]$sess.browserName } else { "" }) -CachedProfile $(if ($sess) { [string]$sess.profileName } else { "Default" })
    $pingAge = 999999.0; $pingDt = [DateTime]::MinValue
    if ($sess -and $sess.lastPingAt -and [DateTime]::TryParse([string]$sess.lastPingAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$pingDt)) {
        $pingAge = ([DateTime]::UtcNow - $pingDt).TotalSeconds
    }
    $tabAlive = $srvAlive -and ($null -ne $sess) -and (-not [bool]$sess.tabClosed) -and ($pingAge -le $HeartbeatTimeoutSeconds)
    $tTitle = if ($sess -and $sess.tabTitle) { [string]$sess.tabTitle } else { "Sen Office 3D" }
    $vis = if ($tabAlive) { $(if ($sess.visibilityState) { [string]$sess.visibilityState } else { "visible" }) } else { "closed" }
    $url = "http://127.0.0.1:$usePort/"
    $act = if (-not $srvAlive) { "start_server_and_open_tab" } elseif (-not $tabAlive) { "reuse_server_and_open_tab" } else { "reuse_existing_tab" }
    $hint = if ($tabAlive) { "Van phong 3D dang mo san tai trinh duyet $($idInfo.BrowserName) (Profile: $($idInfo.ProfileName), Tab: '$tTitle' - $url, Trang thai: $vis). Chuyen sang tab do de xem truc tiep." } else { "Tab Van phong 3D chua mo hoac da dong; se mo 1 tab duy nhat tai $url tren $($idInfo.BrowserName) (Profile: $($idInfo.ProfileName))." }
    return [pscustomobject][ordered]@{
        Workspace = $Workspace; Port = $usePort; Url = $url; ServerAlive = [bool]$srvAlive; TabAlive = [bool]$tabAlive
        VisibilityState = $vis; BrowserName = $idInfo.BrowserName; ProfileName = $idInfo.ProfileName; TabTitle = $tTitle
        LastPingAt = $(if ($sess) { $sess.lastPingAt } else { $null }); PingAgeSeconds = [Math]::Round($pingAge, 1)
        ActionNeeded = $act; ShouldOpenNewTab = (-not $tabAlive); UserHint = $hint
    }
}

$senCoreInternalExports = @(
    "Get-SenTextDigest", "Get-SenRepoCodeRevision", "Invoke-SenLiveEvidenceRunner", "Test-SenTaskAcceptanceCriteria",
    "Get-SenHungProcessIds", "Test-SenSymlinkEscape", "Build-SenHarnessBridgeText", "Install-SenHarnessHookFile",
    "Resolve-SenRequestedHarnesses", "Test-SenHarnessLiveProbe", "Sync-SenTodoMarkdownItems", "Get-SenStepArtifactHash",
    "Register-SenHookExecution", "Invoke-SenPreToolHookBootstrap", "Complete-SenHookExecution", "Test-SenDeliveryReconciliation",
    "Resolve-SenBrowserIdentity", "Update-SenOfficeTabHeartbeat", "Get-SenOfficeTabStatus"
)
if ($senCoreInternalExports) { Export-ModuleMember -Function $senCoreInternalExports }

if (-not $global:SenCoreBootstrapActive) {
    $global:SenCoreBootstrapActive = $true
    try {
        try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch { <# Ignore policy lock #> }
        foreach ($modName in @("Sen.Runtime.psm1", "Sen.Legal.psm1", "Sen.Orchestrator.psm1", "Sen.Packages.psm1", "Sen.Harness.psm1", "Sen.Governance.psm1", "Sen.Adversarial.psm1", "Sen.BoundedLoop.psm1", "Sen.psm1")) {
            $modPath = Join-Path -Path $PSScriptRoot -ChildPath $modName
            if (-not (Test-Path -LiteralPath $modPath)) {
                throw "Critical Sen module missing (fail-closed): $modPath"
            }
            Import-Module -Name $modPath -Global -Force -DisableNameChecking
        }
    }
    finally {
        $global:SenCoreBootstrapActive = $false
    }
}
