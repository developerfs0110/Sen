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

deny() {
  out_decision "deny" "[SEN GUARD] Blocked: $1. If you truly need this command, run it manually in your terminal."
}

# Check write_file / edit_file workspace boundary via python3 when available
if command -v python3 >/dev/null 2>&1; then
  PY_CHECK="$(python3 -c '
import json, os, sys
try:
    d = json.loads(sys.stdin.read())
    tc = d.get("toolCall") or {}
    tname = tc.get("name") or ""
    args = tc.get("args") or {}
    if tname in ("write_file", "edit_file"):
        p = args.get("Path") or ""
        ws_list = [w for w in (d.get("workspacePaths") or []) if w]
        if p and ws_list:
            rp = os.path.realpath(p)
            inside = False
            for w in ws_list:
                rw = os.path.realpath(w)
                if rp == rw or rp.startswith(rw + os.sep):
                    inside = True
                    break
            home_gemini = os.path.realpath(os.path.expanduser("~/.gemini"))
            if not inside and rp.startswith(home_gemini + os.sep):
                inside = True
            if not inside:
                print("DENY_PATH:" + rp)
                sys.exit(0)
            norm_rp = rp.replace("\\", "/").lower()
            if "/.git/config" in norm_rp or "/.git/hooks" in norm_rp:
                print("DENY_GIT:" + rp)
                sys.exit(0)
            if any(x in norm_rp for x in ("/.agents/office/tasks.json", "/.agents/office/process-audit.json", "/.agents/office/loops.json", "/.agents/plugins/sen-method/scripts/guard.")):
                print("DENY_STATE:" + rp)
                sys.exit(0)
            rw0 = os.path.realpath(ws_list[0])
            audit_p = os.path.join(rw0, ".agents", "office", "process-audit.json")
            if os.path.isfile(audit_p) and "/.agents/" not in norm_rp and "/docs/" not in norm_rp:
                aud = json.load(open(audit_p, "r", encoding="utf-8"))
                if int(aud.get("tier") or 1) >= 2:
                    rp_dir = os.path.join(rw0, ".agents", ".sen-restore")
                    has_rp = os.path.isdir(rp_dir) and any(os.path.isfile(os.path.join(rp_dir, k, "manifest.json")) for k in os.listdir(rp_dir))
                    if not has_rp:
                        print("DENY_RP:" + rp)
                        sys.exit(0)
        print("SAFE_TOOL")
        sys.exit(0)
    print("CMD:" + (args.get("CommandLine") or ""))
except Exception:
    print("FALLBACK")
' <<< "$RAW" 2>/dev/null || echo "FALLBACK")"

  case "$PY_CHECK" in
    DENY_PATH:*)
      out_decision "deny" "[SEN GUARD] Blocked: file write outside active workspace (${PY_CHECK#DENY_PATH:})."
      ;;
    DENY_GIT:*)
      out_decision "deny" "[SEN GUARD] Blocked: direct modification of protected Git metadata (${PY_CHECK#DENY_GIT:})."
      ;;
    DENY_STATE:*)
      out_decision "deny" "[SEN GUARD] Blocked: direct tampering with Sen protected state or guard (${PY_CHECK#DENY_STATE:}). Use Sen cmdlets instead."
      ;;
    DENY_RP:*)
      out_decision "deny" "[SEN GUARD] Blocked: Tier 2/3 workflow requires New-SenRestorePoint before modifying project files (${PY_CHECK#DENY_RP:})."
      ;;
    SAFE_TOOL)
      out_decision "ask" ""
      ;;
    CMD:*)
      CMD="${PY_CHECK#CMD:}"
      ;;
    *)
      CMD=""
      ;;
  esac
else
  if command -v jq >/dev/null 2>&1; then
    CMD="$(printf '%s' "$RAW" | jq -r '.toolCall.args.CommandLine // empty' 2>/dev/null || true)"
  else
    CMD="$(printf '%s' "$RAW" | tr '\r\n' ' ' | sed -n 's/.*"CommandLine"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  fi
fi

if [ -z "${CMD:-}" ]; then
  out_decision "ask" ""
fi

if printf '%s' "$CMD" | grep -Eiq '(^|[^a-zA-Z0-9_])rm\b[^|;&]*([[:space:]]-[a-zA-Z]*r|[[:space:]]--recursive\b)'; then
  deny "Recursive delete (rm -r / rm -rf / rm --recursive)"
fi
if printf '%s' "$CMD" | grep -Eiq '(^|[^a-zA-Z0-9_])(remove-item|ri|del|erase|rd|rmdir)\b[^|;&]*[[:space:]]-r(ec(urse)?)?\b'; then
  deny "Recursive delete (Remove-Item -Recurse)"
fi
if printf '%s' "$CMD" | grep -Eiq '(^|[^a-zA-Z0-9_])(get-childitem|gci|dir|ls)\b[^;]*-r(ec(urse)?)?\b[^;]*\|[[:space:]]*(remove-item|ri|del|erase)\b'; then
  deny "Piped recursive delete (Get-ChildItem -Recurse | Remove-Item)"
fi
if printf '%s' "$CMD" | grep -Eiq '(^|[^a-zA-Z0-9_])(rd|rmdir|del|erase)\b[^|;&]*[[:space:]]/s\b'; then
  deny "Recursive delete (rd/del /s)"
fi
if printf '%s' "$CMD" | grep -Eiq '\bfind\b[^|;&]*[[:space:]]-delete\b'; then
  deny "Recursive find -delete"
fi
if printf '%s' "$CMD" | grep -Eiq '\bshutil\.rmtree[[:space:]]*\('; then
  deny "Python shutil.rmtree recursive delete"
fi
if printf '%s' "$CMD" | grep -Eiq '\b(drop[[:space:]]+(database|table|schema)|truncate[[:space:]]+table)\b'; then
  deny "Destructive SQL (DROP / TRUNCATE)"
fi
if printf '%s' "$CMD" | grep -Eiq '(^|[^a-zA-Z0-9_])format(\.com)?[[:space:]]+[a-zA-Z]:'; then
  deny "Disk format command"
fi
if printf '%s' "$CMD" | grep -Eiq '(^|[^a-zA-Z0-9_])(diskpart|clear-disk|format-volume|remove-partition|initialize-disk)\b'; then
  deny "Disk or partition modification"
fi
if printf '%s' "$CMD" | grep -Eiq '\bgit\b[^|;&]*\bpush\b[^|;&]*([[:space:]]--force(-with-lease)?\b|[[:space:]]-f\b|[[:space:]]--delete\b|[[:space:]]-d\b|[[:space:]]--mirror\b|[[:space:]]--no-verify\b|[[:space:]]["'\'']?\+[^[:space:]]|[[:space:]]["'\'']?:[^[:space:]])'; then
  deny "Force push, remote branch delete, or hook bypass"
fi
if printf '%s' "$CMD" | grep -Eiq '\bgit\b[^|;&]*\breset\b[^|;&]*--hard'; then
  deny "git reset --hard (discards uncommitted work)"
fi
if printf '%s' "$CMD" | grep -Eiq '\bgit\b[^|;&]*\bclean\b[^|;&]*([[:space:]]-[a-zA-Z]*f|[[:space:]]--force\b)'; then
  deny "git clean -f/--force (deletes untracked files)"
fi
if printf '%s' "$CMD" | grep -Eiq '\bgit\b[^|;&]*\b(checkout|restore)\b[^|;&]*([[:space:]](--[[:space:]]+)?\.([[:space:]]|$)|[[:space:]]-f\b|[[:space:]]--force\b)'; then
  deny "git checkout/restore . or -f (discards working tree changes)"
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
if printf '%s' "$CMD" | grep -Eiq '(\biex\b|\binvoke-expression\b)[[:space:]]*\(?[[:space:]]*(\birm\b|\binvoke-restmethod\b|\biwr\b|\binvoke-webrequest\b|\bcurl\b|\bwget\b)'; then
  deny "Remote script download and execution (IEX / IRM)"
fi
if printf '%s' "$CMD" | grep -Eiq '\b(powershell|pwsh)(\.exe)?\b[^|;&]*[[:space:]]-(e|ec|enc|encodedcommand)[[:space:]]+[A-Za-z0-9+/=]{8,}'; then
  deny "Encoded PowerShell command execution"
fi
if printf '%s' "$CMD" | grep -Eq '\bgit\b[^|;&]*\bbranch\b[^|;&]*([[:space:]]-D\b|--delete[[:space:]]+--force|--force[[:space:]]+--delete)'; then
  deny "git branch -D (force-deletes unmerged branch)"
fi

out_decision "ask" ""
