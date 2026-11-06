# scripts/guard.ps1
# Antigravity PreToolUse guard (ASCII only): hard-blocks destructive shell/git commands
# and out-of-workspace file writes.
# Input: JSON payload on stdin. Output: JSON {"decision": "...", "reason": "..."} on stdout.

$ErrorActionPreference = "Stop"

function Out-Decision([string]$decision, [string]$reason) {
    $obj = [ordered]@{ decision = $decision }
    if ($reason) { $obj.reason = $reason }
    [Console]::Out.Write(($obj | ConvertTo-Json -Compress))
    exit 0
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Out-Decision "ask" $null
    }
    $payload = $raw | ConvertFrom-Json
    $toolName = [string]$payload.toolCall.name
}
catch {
    Out-Decision "ask" "guard: failed to parse payload, falling back to user confirmation"
}

# 1. Enforce workspace boundary on write_file / edit_file when workspacePaths is provided
if ($toolName -eq "write_file" -or $toolName -eq "edit_file") {
    $targetPath = [string]$payload.toolCall.args.Path
    $wsList = @($payload.workspacePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
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
            $userProfile = $env:USERPROFILE
            if (-not $inside -and $userProfile) {
                $geminiDir = [System.IO.Path]::GetFullPath((Join-Path $userProfile ".gemini")).TrimEnd('\', '/')
                if ($fullTarget.StartsWith($geminiDir + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $inside = $true
                }
            }
            if (-not $inside) {
                Out-Decision "deny" "[SEN GUARD] Blocked: file write outside active workspace ($fullTarget)."
            }
        }
        catch { }
    }
    Out-Decision "ask" $null
}

$cmd = [string]$payload.toolCall.args.CommandLine
if ([string]::IsNullOrWhiteSpace($cmd)) {
    Out-Decision "ask" $null
}

# 2. Case-insensitive destructive command patterns for run_command
$rules = @(
    @{ re = '\brm\s+(-[a-z]*\s+)*-[a-z]*r';                                                                                                  why = 'Recursive delete (rm -r / rm -rf)' },
    @{ re = '\b(remove-item|ri)\b[^|;&]*\s-r(ecurse)?\b';                                                                                    why = 'Recursive delete (Remove-Item -Recurse)' },
    @{ re = '\b(rd|rmdir|del|erase)\b[^|;&]*\s/s\b';                                                                                         why = 'Recursive delete (rd/del /s)' },
    @{ re = '\bfind\b[^|;&]*\s-delete\b';                                                                                                    why = 'Recursive find -delete' },
    @{ re = '\bshutil\.rmtree\s*\(';                                                                                                         why = 'Python shutil.rmtree recursive delete' },
    @{ re = '\b(drop\s+(database|table|schema)|truncate\s+table)\b';                                                                         why = 'Destructive SQL (DROP / TRUNCATE)' },
    @{ re = '\bformat(\.com)?\s+[a-z]:';                                                                                                     why = 'Disk format command' },
    @{ re = '\b(diskpart|clear-disk|format-volume|remove-partition|initialize-disk)\b';                                                      why = 'Disk or partition modification' },
    @{ re = '\bgit\b[^|;&]*\bpush\b[^|;&]*(\s--force(-with-lease)?\b|\s-f\b|\s--delete\b|\s-d\b|\s--mirror\b|\s--no-verify\b|\s\+\S|\s:\S)'; why = 'Force push, remote branch delete, or hook bypass' },
    @{ re = '\bgit\b[^|;&]*\breset\b[^|;&]*--hard';                                                                                          why = 'git reset --hard (discards uncommitted work)' },
    @{ re = '\bgit\b[^|;&]*\bclean\b[^|;&]*\s-[a-z]*f';                                                                                      why = 'git clean -f (deletes untracked files)' },
    @{ re = '\bgit\b[^|;&]*\b(checkout|restore)\b[^|;&]*\s(--\s+)?\.(\s|$)';                                                                 why = 'git checkout/restore . (discards working tree changes)' },
    @{ re = '\bgit\b[^|;&]*\bstash\s+(drop|clear)\b';                                                                                        why = 'git stash drop/clear' },
    @{ re = '\bgit\b[^|;&]*\b(filter-branch|filter-repo)\b';                                                                                 why = 'Git history rewrite' },
    @{ re = '\bgh\s+repo\s+delete\b';                                                                                                        why = 'GitHub repository deletion' }
)

foreach ($r in $rules) {
    if ($cmd -match $r.re) {
        Out-Decision "deny" ("[SEN GUARD] Blocked: " + $r.why + ". If you truly need this command, run it manually in your terminal.")
    }
}

# Case-sensitive pattern: git branch -D (force-deletes unmerged branch)
if ($cmd -cmatch '\bgit\b[^|;&]*\bbranch\b[^|;&]*(\s-D\b|--delete\s+--force|--force\s+--delete)') {
    Out-Decision "deny" "[SEN GUARD] Blocked: git branch -D (force-deletes unmerged branch). If you truly need this command, run it manually."
}

Out-Decision "ask" $null
