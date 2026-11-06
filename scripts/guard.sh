#!/usr/bin/env bash
# scripts/guard.sh
# Antigravity PreToolUse guard (ASCII only) for macOS/Linux.
# Input: JSON payload on stdin. Output: JSON {"decision": "...", "reason": "..."} on stdout.

set -u

out_decision() {
  local dec="$1"
  local reason="${2:-}"
  if [ -n "$reason" ]; then
    printf '{"decision":"%s","reason":"%s"}' "$dec" "$reason"
  else
    printf '{"decision":"%s"}' "$dec"
  fi
  exit 0
}

RAW="$(cat 2>/dev/null || true)"
if [ -z "$RAW" ]; then
  out_decision "ask" ""
fi

CMD=""
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$RAW" | jq -r '.toolCall.args.CommandLine // empty' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
  CMD="$(python3 -c 'import json,sys
try:
    d=json.loads(sys.stdin.read())
    print(d.get("toolCall",{}).get("args",{}).get("CommandLine",""))
except Exception:
    pass' <<< "$RAW" 2>/dev/null || true)"
else
  CMD="$(printf '%s' "$RAW" | tr '\r\n' ' ' | sed -n 's/.*"CommandLine"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

if [ -z "$CMD" ]; then
  out_decision "ask" ""
fi

deny() {
  out_decision "deny" "[SEN GUARD] Blocked: $1. If you truly need this command, run it manually in your terminal."
}

if printf '%s' "$CMD" | grep -Eiq '(^|[^a-zA-Z0-9_])rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*r'; then
  deny "Recursive delete (rm -r / rm -rf)"
fi
if printf '%s' "$CMD" | grep -Eiq '(^|[^a-zA-Z0-9_])(remove-item|ri)\b[^|;&]*[[:space:]]-r(ecurse)?\b'; then
  deny "Recursive delete (Remove-Item -Recurse)"
fi
if printf '%s' "$CMD" | grep -Eiq '(^|[^a-zA-Z0-9_])(rd|rmdir|del|erase)\b[^|;&]*[[:space:]]/s\b'; then
  deny "Recursive delete (rd/del /s)"
fi
if printf '%s' "$CMD" | grep -Eiq '(^|[^a-zA-Z0-9_])format(\.com)?[[:space:]]+[a-zA-Z]:'; then
  deny "Disk format command"
fi
if printf '%s' "$CMD" | grep -Eiq '(^|[^a-zA-Z0-9_])(diskpart|clear-disk|format-volume|remove-partition|initialize-disk)\b'; then
  deny "Disk or partition modification"
fi
if printf '%s' "$CMD" | grep -Eiq '\bgit\b[^|;&]*\bpush\b[^|;&]*([[:space:]]--force(-with-lease)?\b|[[:space:]]-f\b|[[:space:]]--delete\b|[[:space:]]-d\b|[[:space:]]--mirror\b|[[:space:]]--no-verify\b|[[:space:]]\+[^[:space:]]|[[:space:]]:[^[:space:]])'; then
  deny "Force push, remote branch delete, or hook bypass"
fi
if printf '%s' "$CMD" | grep -Eiq '\bgit\b[^|;&]*\breset\b[^|;&]*--hard'; then
  deny "git reset --hard (discards uncommitted work)"
fi
if printf '%s' "$CMD" | grep -Eiq '\bgit\b[^|;&]*\bclean\b[^|;&]*[[:space:]]-[a-zA-Z]*f'; then
  deny "git clean -f (deletes untracked files)"
fi
if printf '%s' "$CMD" | grep -Eiq '\bgit\b[^|;&]*\b(checkout|restore)\b[^|;&]*[[:space:]](--[[:space:]]+)?\.([[:space:]]|$)'; then
  deny "git checkout/restore . (discards working tree changes)"
fi
if printf '%s' "$CMD" | grep -Eiq '\bgit\b[^|;&]*\bstash[[:space:]]+(drop|clear)\b'; then
  deny "git stash drop/clear"
fi
if printf '%s' "$CMD" | grep -Eiq '\bgit\b[^|;&]*\b(filter-branch|filter-repo)\b'; then
  deny "Git history rewrite"
fi
if printf '%s' "$CMD" | grep -Eiq '\bgh[[:space:]]+repo[[:space:]]+delete\b'; then
  deny "GitHub repository deletion"
fi
if printf '%s' "$CMD" | grep -Eq '\bgit\b[^|;&]*\bbranch\b[^|;&]*([[:space:]]-D\b|--delete[[:space:]]+--force|--force[[:space:]]+--delete)'; then
  deny "git branch -D (force-deletes unmerged branch)"
fi

out_decision "ask" ""

