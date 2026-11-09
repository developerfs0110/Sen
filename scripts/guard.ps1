# scripts/guard.ps1
# Antigravity PreToolUse guard (ASCII only): hard-blocks destructive shell/git commands,
# out-of-workspace file writes, and 3x stuck loops; records denied command cards to sen-office.
# Input: JSON payload on stdin. Output: JSON {"decision": "...", "reason": "..."} on stdout.

$ErrorActionPreference = "Stop"

$script:senRuntimeLoaded = $false
function Import-SenRuntimeModule {
    if ($script:senRuntimeLoaded) { return }
    $runtimeMod = Join-Path -Path $PSScriptRoot -ChildPath "Sen.psm1"
    if (-not (Test-Path -LiteralPath $runtimeMod)) {
        $runtimeMod = Join-Path -Path $PSScriptRoot -ChildPath "Sen.Runtime.psm1"
    }
    if (Test-Path -LiteralPath $runtimeMod) {
        try {
            Import-Module $runtimeMod -Force -ErrorAction SilentlyContinue
            $script:senRuntimeLoaded = $true
        }
        catch { <# Non-fatal if runtime module fails to load; guard still enforces static rules #> }
    }
}

function Out-Decision([string]$decision, [string]$reason, [string]$ws = "", [string]$tool = "", [string]$target = "", [string]$cmdText = "") {
    if ($decision -eq "deny" -and -not [string]::IsNullOrWhiteSpace($ws)) {
        try {
            Import-SenRuntimeModule
            if (Get-Command Write-SenOfficeEvent -ErrorAction SilentlyContinue) {
                Write-SenOfficeEvent -Workspace $ws -From "sec" -To "pm" -Lane "Security Gate" `
                    -EcoText ("BLOCKED: " + $reason) -FullText $reason -Kind "alert" -Hold 2 `
                    -Source "guard-denied" -Tool $tool -Target $target -Command $cmdText -Model "pro" | Out-Null
            }
        }
        catch { <# Telemetry failure must never prevent guard decision output #> }
    }
    $obj = [ordered]@{ decision = $decision }
    if ($reason) { $obj.reason = $reason }
    [Console]::Out.Write(($obj | ConvertTo-Json -Compress))
    exit 0
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw) -and $input) {
        $raw = (@($input) -join "`n")
    }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Out-Decision "ask" $null
    }
    $payload = $raw | ConvertFrom-Json
    Import-SenRuntimeModule
    if (Get-Command ConvertFrom-SenHookPayload -ErrorAction SilentlyContinue) {
        $norm = ConvertFrom-SenHookPayload -InputObject $payload
        $rawTool = $norm.RawToolName
        $toolName = $norm.CanonicalTool
        $wsList = @($norm.WorkspaceList)
        $primaryWs = $norm.WorkspacePath
        $normTarget = $norm.TargetPath
        $normCmd = $norm.CommandLine
    }
    else {
        $rawTool = if ($payload.toolCall -and $payload.toolCall.name) { [string]$payload.toolCall.name } elseif ($payload.tool_name) { [string]$payload.tool_name } else { "" }
        $toolName = $rawTool
        switch -Regex ($rawTool) {
            '^(?i)(run_command|bash|run_terminal_cmd|shell|exec)$' { $toolName = "run_command"; break }
            '^(?i)(write_file|write|create_file|write_to_file|notebookedit)$' { $toolName = "write_file"; break }
            '^(?i)(edit_file|edit|multiedit|replace_in_file|patch)$' { $toolName = "edit_file"; break }
            '^(?i)(read_file|read|view_file)$' { $toolName = "read_file"; break }
        }
        $wsCandidates = [System.Collections.Generic.List[string]]::new()
        if ($payload.workspacePaths) { foreach ($w in @($payload.workspacePaths)) { if (-not [string]::IsNullOrWhiteSpace([string]$w)) { $wsCandidates.Add([string]$w) } } }
        if ($payload.workspace_roots) { foreach ($w in @($payload.workspace_roots)) { if (-not [string]::IsNullOrWhiteSpace([string]$w)) { $wsCandidates.Add([string]$w) } } }
        if ($payload.cwd -and -not [string]::IsNullOrWhiteSpace([string]$payload.cwd)) { $wsCandidates.Add([string]$payload.cwd) }
        $wsList = @($wsCandidates.ToArray())
        $primaryWs = if ($wsList.Count -gt 0) { [string]$wsList[0] } else { "" }
        $normTarget = ""; $normCmd = ""
    }
    if (-not [string]::IsNullOrWhiteSpace($primaryWs) -and (Get-Command Resolve-SenWorkspaceRoot -ErrorAction SilentlyContinue)) {
        $primaryWs = Resolve-SenWorkspaceRoot -StartPath $primaryWs
    }
    $toolArgs = if ($payload.toolCall -and $payload.toolCall.args) { $payload.toolCall.args } elseif ($payload.tool_input) { $payload.tool_input } else { $null }
}
catch {
    Out-Decision "ask" "guard: failed to parse payload, falling back to user confirmation"
}

try {
# 1. Enforce sensitive host path, symlink escape, and workspace boundary on read_file / write_file / edit_file
if ($toolName -in @("write_file", "edit_file", "read_file")) {
    $targetPath = if (-not [string]::IsNullOrWhiteSpace($normTarget)) { $normTarget } elseif ($toolArgs -and $toolArgs.Path) { [string]$toolArgs.Path } elseif ($toolArgs -and $toolArgs.file_path) { [string]$toolArgs.file_path } elseif ($toolArgs -and $toolArgs.target_file) { [string]$toolArgs.target_file } elseif ($toolArgs -and $toolArgs.path) { [string]$toolArgs.path } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($targetPath)) {
        if ($targetPath.Replace('\', '/') -match '(?i)(^|/)(\.ssh|\.aws|\.gnupg|\.kube)(/|$)|(^|/)(id_rsa|id_ed25519|\.npmrc|\.pypirc|\.netrc)$') {
            Out-Decision "deny" "[SEN GUARD] Blocked: access to sensitive host credential path ($targetPath)." $primaryWs $toolName $targetPath $targetPath
        }
        if ((Get-Command Test-SenSafeWorkspacePath -ErrorAction SilentlyContinue) -and $wsList.Count -gt 0) {
            $safeRes = Test-SenSafeWorkspacePath -TargetPath $targetPath -WorkspaceList $wsList -ToolName $toolName
            if (-not $safeRes.Allowed) {
                Out-Decision "deny" ("[SEN GUARD] Blocked: " + $safeRes.Reason) $primaryWs $toolName $targetPath $targetPath
            }
        }
    }
    if ($toolName -eq "read_file") {
        Out-Decision "ask" $null
    }
    if (-not [string]::IsNullOrWhiteSpace($targetPath) -and $wsList.Count -gt 0) {
        try {
            $fullTarget = [System.IO.Path]::GetFullPath($targetPath).TrimEnd('\', '/')
            $inside = $false
            foreach ($ws in $wsList) {
                $fullWs = [System.IO.Path]::GetFullPath([string]$ws).TrimEnd('\', '/')
                if ($fullTarget.Equals($fullWs, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $fullTarget.StartsWith($fullWs + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $fullTarget.StartsWith($fullWs + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $inside = $true
                    break
                }
            }
            # Also allow Antigravity appData / scratch / .gemini paths
            $userProfile = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
            if (-not $inside -and $userProfile) {
                $geminiDir = [System.IO.Path]::GetFullPath((Join-Path $userProfile ".gemini")).TrimEnd('\', '/')
                if ($fullTarget.StartsWith($geminiDir + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $inside = $true
                }
            }
            if (-not $inside) {
                Out-Decision "deny" "[SEN GUARD] Blocked: file write outside active workspace ($fullTarget)." $primaryWs $toolName $fullTarget $fullTarget
            }
            # Block direct writes to .git/config, .git/hooks, .agents/office state, or .agents/plugins/sen-method guard
            $normCheck = $fullTarget.Replace('\', '/')
            if ($normCheck -match '(?i)/\.git/(config|hooks(/|$))') {
                Out-Decision "deny" "[SEN GUARD] Blocked: direct modification of protected Git metadata ($fullTarget)." $primaryWs $toolName $fullTarget $fullTarget
            }
            if (($env:SEN_TRUSTED_INSTALLER -ne "1") -and ($normCheck -match '(?i)(/\.agents/(office/[^/]+\.(json|jsonl)$|sen\.lock\.json$|plugins/sen-method/(scripts/|hooks\.json$|plugin\.json$))|/(\.claude/settings\.json|\.cursor/hooks\.json|guard\.(ps1|sh))$)' )) {
                Out-Decision "deny" "[SEN GUARD] Blocked: direct tampering with Sen protected state, runtime scripts, lockfile, or hook config ($fullTarget). Use Sen cmdlets instead." $primaryWs $toolName $fullTarget $fullTarget
            }
            # Auto-Create or Append Restore Point before modifying any project source file (Zero-Amnesia Pre-Edit Backup)
            if ($primaryWs -and ($normCheck -notmatch '(?i)/(\.agents|docs)/') -and ($primaryWs -notmatch '(?i)([\\/](temp|tmp|T)[\\/]|sen-(harness|gov|adv|.*-test)|TestDrive)')) {
                $rpDir = Join-Path $primaryWs ".agents/.sen-restore"
                $recentRp = $false; $latestRp = $null
                if (Test-Path -LiteralPath $rpDir) {
                    $latestRp = Get-ChildItem -LiteralPath $rpDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
                    if ($latestRp -and (([DateTime]::UtcNow - $latestRp.LastWriteTimeUtc).TotalMinutes -lt 10)) { $recentRp = $true }
                }
                Import-SenRuntimeModule
                if (-not $recentRp) {
                    if (Get-Command New-SenRestorePoint -ErrorAction SilentlyContinue) {
                        try { [void](New-SenRestorePoint -Workspace $primaryWs -Files @($fullTarget) -Label "auto-pre-edit") } catch { <# Non-fatal #> }
                    }
                }
                elseif ($null -ne $latestRp -and (Get-Command Read-SenSafeJson -ErrorAction SilentlyContinue)) {
                    try {
                        $mfFile = Join-Path $latestRp.FullName "manifest.json"
                        $mfObj = Read-SenSafeJson -Path $mfFile
                        if ($null -ne $mfObj -and (@($mfObj.entries | Where-Object { [string]$_.fullPath -ieq $fullTarget }).Count -eq 0)) {
                            $existed = Test-Path -LiteralPath $fullTarget -PathType Leaf
                            $storedName = "f_$(@($mfObj.entries).Count).bak"
                            if ($existed) { Copy-Item -LiteralPath $fullTarget -Destination (Join-Path (Join-Path $latestRp.FullName "files") $storedName) -Force }
                            $relP = if ($fullTarget.StartsWith($primaryWs, [System.StringComparison]::OrdinalIgnoreCase)) { $fullTarget.Substring($primaryWs.Length).TrimStart('\', '/') } else { [System.IO.Path]::GetFileName($fullTarget) }
                            $mfObj.entries = @($mfObj.entries) + @([ordered]@{ relPath = $relP; fullPath = $fullTarget; existed = [bool]$existed; storedName = $storedName })
                            Write-SenAtomicJson -Path $mfFile -InputObject $mfObj -Depth 6
                        }
                    }
                    catch { <# Non-fatal #> }
                }
            }
            # Enforce Pre-Edit Restore Point Gate during active Tier 2/3 workflow
            $auditFile = if ($primaryWs) { Join-Path $primaryWs ".agents/office/process-audit.json" } else { "" }
            if ($auditFile -and (Test-Path -LiteralPath $auditFile) -and ($normCheck -notmatch '(?i)/(\.agents|docs)/')) {
                $auditObj = [System.IO.File]::ReadAllText($auditFile) | ConvertFrom-Json
                $rpDir = Join-Path $primaryWs ".agents/.sen-restore"
                $hasRp = (Test-Path -LiteralPath $rpDir) -and (@(Get-ChildItem -LiteralPath $rpDir -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "manifest.json") }).Count -gt 0)
                if ($auditObj -and [int]$auditObj.tier -ge 2 -and (-not $hasRp)) {
                    Out-Decision "deny" "[SEN GUARD] Blocked: Tier $($auditObj.tier) workflow requires New-SenRestorePoint before modifying project files ($fullTarget)." $primaryWs $toolName $fullTarget $fullTarget
                }
            }
            # Optional Execution Contract allowedPaths enforcement when enforceTaskPaths is enabled
            $enforceContract = ($payload.PSObject.Properties.Name -contains "enforceTaskPaths" -and [bool]$payload.enforceTaskPaths) -or ($env:SEN_ENFORCE_ALLOWED_PATHS -eq "1")
            if ($enforceContract -and $primaryWs) {
                Import-SenRuntimeModule
            }
            if ($enforceContract -and $primaryWs -and (Get-Command Get-SenTasks -ErrorAction SilentlyContinue)) {
                $activeTasks = @(Get-SenTasks -Workspace $primaryWs | Where-Object { [string]$_.status -eq "in_progress" -and @($_.allowedPaths).Count -gt 0 })
                if ($activeTasks.Count -gt 0) {
                    $fullWsPrimary = [System.IO.Path]::GetFullPath($primaryWs).TrimEnd('\', '/')
                    $relTarget = if ($fullTarget.StartsWith($fullWsPrimary, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $fullTarget.Substring($fullWsPrimary.Length).TrimStart('\', '/')
                    }
                    else {
                        $fullTarget
                    }
                    $allowedByContract = $false
                    foreach ($at in $activeTasks) {
                        if (Test-SenPathOverlap -PathsA @($relTarget) -PathsB @($at.allowedPaths)) {
                            $allowedByContract = $true
                            break
                        }
                    }
                    if (-not $allowedByContract) {
                        Out-Decision "deny" "[SEN GUARD] Blocked by Execution Contract: '$relTarget' is outside allowedPaths of active task(s)." $primaryWs $toolName $fullTarget $fullTarget
                    }
                }
            }
        }
        catch { <# Fall back to ask if path normalization fails on malformed path #> }
    }
    Out-Decision "ask" $null
}

$cmd = if (-not [string]::IsNullOrWhiteSpace($normCmd)) { $normCmd } elseif ($toolArgs -and $toolArgs.CommandLine) { [string]$toolArgs.CommandLine } elseif ($toolArgs -and $toolArgs.command) { [string]$toolArgs.command } elseif ($toolArgs -and $toolArgs.cmd) { [string]$toolArgs.cmd } else { "" }
if ([string]::IsNullOrWhiteSpace($cmd)) {
    Out-Decision "ask" $null
}

# 2. Check Stuck Loop Breaker (3 consecutive identical failures on this command, exempting read-only inspection)
$isReadOnlyDiag = $cmd -match '(?i)^\s*(git\s+(status|log|diff|branch|show)|Get-ChildItem|dir|ls|pwd|Get-Location)\b'
if ((-not $isReadOnlyDiag) -and (-not [string]::IsNullOrWhiteSpace($primaryWs)) -and (Test-Path -LiteralPath (Join-Path $primaryWs ".agents/office/loops.json"))) {
    Import-SenRuntimeModule
    if (Get-Command Test-SenStuckLoop -ErrorAction SilentlyContinue) {
        try {
            $loopCheck = Test-SenStuckLoop -Workspace $primaryWs -ToolName $toolName -Target $cmd
            if ($loopCheck.IsStuck) {
                Out-Decision "deny" ("[SEN GUARD] " + $loopCheck.Reason) $primaryWs $toolName $cmd $cmd
            }
        }
        catch { <# Ignore stuck-loop read error and continue to static command rules #> }
    }
}

# 3. Case-insensitive destructive command patterns for run_command
if ($cmd -match '(?i)(\bcat\b|\btype\b|\bget-content\b|\bgc\b|\bhead\b|\btail\b|\bgrep\b|\brg\b|\bselect-string\b)[^|;&]*([/\\]\.ssh[/\\]|[/\\]\.aws[/\\]|[/\\]\.gnupg[/\\]|[/\\]\.kube[/\\]|id_rsa|id_ed25519)') {
    Out-Decision "deny" "[SEN GUARD] Blocked: Reading sensitive host credential/key files via shell. If you truly need this command, run it manually in your terminal." $primaryWs $toolName $cmd $cmd
}

$cmdScan = [regex]::Replace($cmd, '(?i)(\bgit\b[^|;&]*\bcommit\b[^|;&]*\s(?:-m|--message)\s+)(?:"[^"`$]+"|''[^'']+'')', '$1""')
if ($cmdScan -match '(?i)^\s*(echo|write-host|write-output|grep|rg|select-string)\b' -and $cmdScan -notmatch '[|;&`$><]') {
    $cmdScan = ""
}
if (-not [string]::IsNullOrWhiteSpace($cmdScan)) {
    $cmdDeobf = [regex]::Replace($cmdScan, '([a-zA-Z])\\([a-zA-Z])', '$1$2')
    $cmdDeobf = [regex]::Replace($cmdDeobf, '([a-zA-Z])"([a-zA-Z]*)"([a-zA-Z]*)', '$1$2$3')
    $cmdDeobf = [regex]::Replace($cmdDeobf, "([a-zA-Z])'([a-zA-Z]*)'([a-zA-Z]*)", '$1$2$3')
    if ($cmdDeobf -ne $cmdScan) { $cmdScan = "$cmdScan ; $cmdDeobf" }
}

$rules = @(
    @{ re = '\brm\b[^|;&]*(\s-[a-z]*r|\s--recursive\b)'; why = 'Recursive delete (rm -r / rm -rf / rm --recursive)' },
    @{ re = '\b(remove-item|ri|del|erase|rd|rmdir)\b[^|;&]*\s-r(e(c(u(r(s(e)?)?)?)?)?)?\b'; why = 'Recursive delete (Remove-Item -Recurse)' },
    @{ re = '\b(get-childitem|gci|dir|ls)\b[^;]*-r(e(c(u(r(s(e)?)?)?)?)?)?\b[^;]*\|\s*(remove-item|ri|del|erase)\b'; why = 'Piped recursive delete (Get-ChildItem -Recurse | Remove-Item)' },
    @{ re = '\b(rd|rmdir|del|erase)\b[^|;&]*\s/s\b'; why = 'Recursive delete (rd/del /s)' },
    @{ re = '\b(system\.io\.)?directory\]::delete\s*\('; why = '.NET Directory::Delete call' },
    @{ re = '\bfs\.(rm|rmdir)(Sync)?\s*\('; why = 'Node.js fs.rm/rmdir delete' },
    @{ re = '\b(npx\s+)?rimraf\b'; why = 'rimraf recursive delete' },
    @{ re = '\brobocopy(\.exe)?\b[^|;&]*\s/mir\b'; why = 'robocopy /MIR mirror delete' },
    @{ re = '\bfind\b[^|;&]*\s-delete\b'; why = 'Recursive find -delete' },
    @{ re = '\b(shutil\s*\.\s*rmtree|from\s+shutil\s+import\s+rmtree)\b|\brmtree\s*\('; why = 'Python shutil.rmtree recursive delete' },
    @{ re = '\b(drop\s+(database|table|schema)|truncate\s+(table\s+)?[a-z0-9_."`\[\]]+)\b'; why = 'Destructive SQL (DROP / TRUNCATE)' },
    @{ re = '\bdelete\s+from\s+[a-z0-9_."`\[\]]+\s*(;|$)'; why = 'Unbounded SQL DELETE FROM without WHERE clause' },
    @{ re = '\bformat(\.com)?\s+[a-z]:'; why = 'Disk format command' },
    @{ re = '\b(diskpart|clear-disk|format-volume|remove-partition|initialize-disk)\b'; why = 'Disk or partition modification' },
    @{ re = '\bgit\b[^|;&]*\bpush\b[^|;&]*(\s--force(-with-lease)?\b|\s-f\b|\s--delete\b|\s-d\b|\s--mirror\b|\s--no-verify\b|\s["'']?\+\S|\s["'']?:\S)'; why = 'Force push, remote branch delete, or hook bypass' },
    @{ re = '\bgit\b[^|;&]*\bcommit\b[^|;&]*\s(--no-verify|-n)\b'; why = 'git commit --no-verify/-n (hook bypass)' },
    @{ re = '\bgit\b[^|;&]*\breset\b[^|;&]*--hard'; why = 'git reset --hard (discards uncommitted work)' },
    @{ re = '\bgit\b[^|;&]*\bclean\b[^|;&]*(\s-[a-z]*f|\s--force\b)'; why = 'git clean -f/--force (deletes untracked files)' },
    @{ re = '\bgit\b[^|;&]*\bcheckout\b[^|;&]*(\s(--\s+)?\.(\s|$)|\s-f\b|\s--force\b)'; why = 'git checkout . or -f (discards working tree changes)' },
    @{ re = '\bgit\b[^|;&]*\bstash\s+(drop|clear)\b'; why = 'git stash drop/clear' },
    @{ re = '\bgit\b[^|;&]*\breflog\s+(expire|delete)\b'; why = 'git reflog expire/delete' },
    @{ re = '\bgit\b[^|;&]*\b(filter-branch|filter-repo)\b'; why = 'Git history rewrite' },
    @{ re = '\bgh\s+repo\s+delete\b'; why = 'GitHub repository deletion' },
    @{ re = '\bdocker(-compose|\s+compose)\b[^|;&]*\bdown\b[^|;&]*\s(-v|--volumes)\b'; why = 'docker compose down -v (destroys volumes)' },
    @{ re = '\b(terraform\s+destroy|prisma\s+migrate\s+reset)\b'; why = 'Destructive infrastructure/database reset' },
    @{ re = '(\biex\b|\binvoke-expression\b)\s*\(?\s*(\birm\b|\binvoke-restmethod\b|\biwr\b|\binvoke-webrequest\b|\bcurl\b|\bwget\b|new-object\s+net\.webclient)'; why = 'Remote script download and execution (IEX / IRM)' },
    @{ re = '(\birm\b|\binvoke-restmethod\b|\biwr\b|\binvoke-webrequest\b|\bcurl\b|\bwget\b)[^|;\r\n]*\|\s*(\biex\b|\binvoke-expression\b)'; why = 'Piped remote script execution (IRM/IWR/curl | IEX)' },
    @{ re = '(\bcurl\b|\bwget\b)[^;\r\n]*\|\s*(sh|bash|zsh|pwsh|powershell|python|python3|node)\b'; why = 'Piped remote script execution (curl/wget | sh/bash/pwsh)' },
    @{ re = '\bbase64\s+(-d|--decode)[^|;\r\n]*\|\s*(sh|bash|zsh|pwsh|powershell|python|python3)\b'; why = 'Piped base64 decode to shell execution' },
    @{ re = '\b(powershell|pwsh)(\.exe)?\b[^|;&]*\s-(e|ec|enc|encodedcommand)\s+[A-Za-z0-9+/=]{8,}'; why = 'Encoded PowerShell command execution' },
    @{ re = '(>|>>|\b(set-content|out-file|add-content|tee-object|tee|cp|mv|copy-item|move-item|remove-item|del|rm)\b|writeall(text|lines|bytes)|appendall(text|lines)|streamwriter|filestream|open\s*\(|fs\.(write|append|unlink|rm))[^|;&]*(^|[\s"''/\\])\.agents[/\\]office([/\\]|$)|(^|[\s"''/\\])\.agents[/\\]office[/\\][^|;&]*(>|>>|\b(set-content|out-file|add-content|tee-object|tee)\b|\.write\s*\()'; why = 'Direct shell/script tampering with protected .agents/office state JSON' }
)
if ($env:SEN_TRUSTED_INSTALLER -ne "1") {
    $rules += @{ re = '(>|>>|\b(set-content|out-file|add-content|tee-object|tee|cp|mv|copy-item|move-item|remove-item|del|rm)\b|writeall(text|lines|bytes))[^|;&]*((^|[\s"''/\\])guard\.(ps1|sh)\b|\.agents[/\\](sen\.lock\.json|plugins[/\\]sen-method[/\\](scripts[/\\]|hooks\.json|plugin\.json))|(\.claude[/\\]settings\.json|\.cursor[/\\]hooks\.json))|((^|[\s"''/\\])guard\.(ps1|sh)\b|\.agents[/\\](sen\.lock\.json|plugins[/\\]sen-method[/\\](scripts[/\\]|hooks\.json|plugin\.json))|(\.claude[/\\]settings\.json|\.cursor[/\\]hooks\.json))[^|;&]*(>|>>|\b(set-content|out-file|add-content|tee-object|tee)\b)'; why = 'Direct shell tampering with Sen runtime scripts, lockfile, or hook configuration' }
}

if (-not [string]::IsNullOrWhiteSpace($cmdScan)) {
    foreach ($r in $rules) {
        if ($cmdScan -match $r.re) {
            Out-Decision "deny" ("[SEN GUARD] Blocked: " + $r.why + ". If you truly need this command, run it manually in your terminal.") $primaryWs $toolName $cmd $cmd
        }
    }
    if ($cmdScan -match '(?i)\bgit\b[^|;&]*\brestore\b[^|;&]*(\s(--\s+)?\.(\s|$)|\s-f\b|\s--force\b|\s-W\b|\s--worktree\b)') {
        $isStageOnly = ($cmdScan -match '(?i)\bgit\b[^|;&]*\brestore\b[^|;&]*\s(--staged|-S)\b') -and ($cmdScan -notmatch '(?i)\bgit\b[^|;&]*\brestore\b[^|;&]*\s(--worktree|-W|-f|--force)\b')
        if (-not $isStageOnly) {
            Out-Decision "deny" "[SEN GUARD] Blocked: git checkout/restore . or -f (discards working tree changes). If you truly need this command, run it manually in your terminal." $primaryWs $toolName $cmd $cmd
        }
    }
}

if (($env:SEN_TRUSTED_HOOK -ne "1") -and ($cmd -match '(?i)\bSync-SenOfficeState\b[^|;&]*\s-UpdateSeal\b|\bLock-SenQualityBaseline\b[^|;&]*\s-Force\b')) {
    Out-Decision "deny" "[SEN GUARD] Blocked: Untrusted self-resealing of state-seal.json or quality-baseline.json via run_command is prohibited." $primaryWs $toolName $cmd $cmd
}

# 4. Non-destructive media safety rule: block ffmpeg in-place overwrite of the same input file path
function Test-SenFfmpegInPlaceOverwrite([string]$CommandText) {
    if ($CommandText -notmatch '(?i)\bffmpeg(\.exe)?\b') { return $false }
    $tokenPattern = '"([^"]*)"|''([^'']*)''|(\S+)'
    foreach ($seg in ($CommandText -split '[;&|]+')) {
        if ($seg -notmatch '(?i)\bffmpeg(\.exe)?\b') { continue }
        $mList = [regex]::Matches($seg, $tokenPattern)
        $tokens = [System.Collections.Generic.List[string]]::new()
        foreach ($m in $mList) {
            $val = if ($m.Groups[1].Success) { $m.Groups[1].Value } elseif ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[3].Value }
            $tokens.Add($val)
        }
        $inputs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $inputIndices = [System.Collections.Generic.HashSet[int]]::new()
        for ($i = 0; $i -lt $tokens.Count; $i++) {
            if ($tokens[$i] -ieq "-i" -and ($i + 1) -lt $tokens.Count) {
                $normIn = ($tokens[$i + 1].Trim().Replace('\', '/') -replace '^\./', '').ToLowerInvariant()
                if ($normIn -and $normIn -ne "-") {
                    [void]$inputs.Add($normIn)
                    [void]$inputIndices.Add($i + 1)
                }
                $i++
            }
        }
        if ($inputs.Count -eq 0) { continue }
        $outIdx = $tokens.Count - 1
        while ($outIdx -gt 0 -and $tokens[$outIdx] -match '^(?i)-(y|n|v|nostdin|stats|benchmark)$') { $outIdx-- }
        if ($outIdx -ge 0 -and (-not $inputIndices.Contains($outIdx)) -and (-not $tokens[$outIdx].StartsWith("-"))) {
            $normOut = ($tokens[$outIdx].Trim().Replace('\', '/') -replace '^\./', '').ToLowerInvariant()
            if ($inputs.Contains($normOut)) { return $true }
        }
    }
    return $false
}

if (Test-SenFfmpegInPlaceOverwrite -CommandText $cmd) {
    Out-Decision "deny" "[SEN GUARD] Blocked: Non-destructive media guard: ffmpeg in-place overwrite of input file is prohibited. Write output to a separate file or output/ folder." $primaryWs $toolName $cmd $cmd
}

# Case-sensitive pattern: git branch -D (force-deletes unmerged branch)
if ($cmd -cmatch '\bgit\b[^|;&]*\bbranch\b[^|;&]*(\s-D\b|--delete\s+--force|--force\s+--delete)') {
    Out-Decision "deny" "[SEN GUARD] Blocked: git branch -D (force-deletes unmerged branch). If you truly need this command, run it manually." $primaryWs $toolName $cmd $cmd
}

# 5. Zero-Amnesia Pre-Commit / Pre-Push Auto-Seal, CodeHealth & DOM XSS Gate
if ($cmd -match '(?i)\bgit\b[^|;&]*\b(commit|push)\b') {
    $gitTargetDir = $primaryWs
    if ($cmd -match '(?i)\bgit\s+-C\s+(?:"([^"]+)"|''([^'']+)''|(\S+))') {
        $gitTargetDir = if ($matches[1]) { $matches[1] } elseif ($matches[2]) { $matches[2] } else { $matches[3] }
    }
    elseif ($cmd -match '(?i)\b(?:Set-Location|cd|Push-Location)\s+(?:-(?:Path|LiteralPath)\s+)?(?:"([^"]+)"|''([^'']+)''|([^|;&\s]+))') {
        $gitTargetDir = if ($matches[1]) { $matches[1] } elseif ($matches[2]) { $matches[2] } else { $matches[3] }
    }
    if ($gitTargetDir -and (Test-Path -LiteralPath (Join-Path $gitTargetDir "src"))) {
        $targetSrc = Join-Path $gitTargetDir "src"
        Import-SenRuntimeModule
        if (Get-Command Measure-SenCodeHealth -ErrorAction SilentlyContinue) {
            $repoHealth = Measure-SenCodeHealth -Path $targetSrc
            if (-not $repoHealth.Healthy) {
                $dirtyRelFiles = @()
                try {
                    $gitStatusLines = @(git -C $gitTargetDir status --porcelain 2>$null)
                    if ($LASTEXITCODE -eq 0 -and $gitStatusLines.Count -gt 0) {
                        foreach ($gLine in $gitStatusLines) {
                            if ($gLine.Length -gt 3) {
                                $relF = $gLine.Substring(3).Trim().Trim('"').Replace('\', '/')
                                if ($relF.StartsWith("src/")) { $relF = $relF.Substring(4) }
                                $dirtyRelFiles += $relF
                            }
                        }
                    }
                }
                catch { <# Fallback to full repo check #> }
                $shouldBlockHealth = $true
                if ($dirtyRelFiles.Count -gt 0) {
                    $violatingPaths = @()
                    foreach ($vItem in @($repoHealth.OversizedFiles) + @($repoHealth.LongFunctions) + @($repoHealth.DeepNesting) + @($repoHealth.EmptyCatches)) {
                        if ($vItem -and $vItem.path) { $violatingPaths += ([string]$vItem.path).Replace('\', '/') }
                    }
                    $touchedViolation = $false
                    foreach ($vp in $violatingPaths) {
                        if ($dirtyRelFiles -contains $vp) { $touchedViolation = $true; break }
                    }
                    $shouldBlockHealth = $touchedViolation
                }
                if ($shouldBlockHealth) {
                    Out-Decision "deny" "[SEN GUARD] Blocked: Code health check failed on target repo (Score=$($repoHealth.Score)). Run Measure-SenCodeHealth and fix violations before committing/pushing." $primaryWs $toolName $targetSrc $cmd
                }
            }
        }
        $uiScripts = @(Get-ChildItem -LiteralPath $targetSrc -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '(?i)^\.(js|ts|jsx|tsx)$' })
        foreach ($uf in $uiScripts) {
            $uTxt = [System.IO.File]::ReadAllText($uf.FullName, [System.Text.Encoding]::UTF8)
            foreach ($uLine in ($uTxt -split '\r?\n')) {
                if ($uLine -match '\.innerHTML\s*\+?=\s*(`[^`]*\$\{|[^;]*\+\s*[a-zA-Z_$(])' -and $uLine -notmatch '(?i)\b(escapeHtml|DOMPurify|sanitize|esc)\b') {
                    Out-Decision "deny" "[SEN GUARD] Blocked: Potential DOM XSS (CWE-79) unescaped innerHTML interpolation detected." $primaryWs $toolName $uf.FullName $cmd
                }
            }
        }
    }
    if ($primaryWs -and ($primaryWs -notmatch '(?i)([\\/](temp|tmp|T)[\\/]|sen-(harness|gov|adv|.*-test)|TestDrive)')) {
        Import-SenRuntimeModule
        if (Get-Command Sync-SenOfficeState -ErrorAction SilentlyContinue) {
            $sealPath = Join-Path $primaryWs ".agents/office/state-seal.json"
            if (Test-Path -LiteralPath $sealPath) {
                $sealVerify = Sync-SenOfficeState -Workspace $primaryWs -VerifySeal
                if ($sealVerify.Tampered) {
                    Out-Decision "deny" "[SEN GUARD] Blocked: .agents/office state seal is tampered ($($sealVerify.TamperedFiles -join ', ')). Restore or verify state before committing/pushing." $primaryWs $toolName $cmd $cmd
                }
            }
            try { $env:SEN_TRUSTED_HOOK = "1"; [void](Sync-SenOfficeState -Workspace $primaryWs -PruneStale -UpdateSeal) } catch { <# Non-fatal #> }
        }
        if (Get-Command Install-SenGitHooks -ErrorAction SilentlyContinue) {
            try { [void](Install-SenGitHooks -Workspace $primaryWs) } catch { <# Non-fatal #> }
        }
    }
}

Out-Decision "ask" $null
}
catch {
    Out-Decision "deny" ("[SEN GUARD] Internal guard error (fail-closed): " + $_.Exception.Message) $primaryWs $toolName $normTarget $normCmd
}
