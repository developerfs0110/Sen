#!/usr/bin/env bash
# scripts/guard.sh
# Antigravity PreToolUse guard (ASCII only) for macOS/Linux.
# Input: JSON payload on stdin. Output: JSON {"decision": "...", "reason": "..."} on stdout.

set -u

out_decision() {
  local dec="$1"
  local reason="${2:-}"
  if [ -n "$reason" ]; then
    local safe_reason
    safe_reason="$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\r\n\t' '   ')"
    printf '{"decision":"%s","reason":"%s"}' "$dec" "$safe_reason"
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

# Check write_file / edit_file workspace boundary and state seal via python3 when available
if command -v python3 >/dev/null 2>&1; then
  PY_CHECK="$(python3 -c '
import hashlib, json, os, re, sys
try:
    d = json.loads(sys.stdin.read())
    tc = d.get("toolCall") or {}
    tname = tc.get("name") or d.get("tool_name") or ""
    args = tc.get("args") or d.get("tool_input") or {}
    ws_list = [w for w in (d.get("workspacePaths") or d.get("workspace_roots") or []) if w]
    if not ws_list and d.get("cwd"): ws_list = [d.get("cwd")]
    if tname in ("write_file", "edit_file", "read_file", "Write", "Edit", "MultiEdit", "Read"):
        p = args.get("Path") or args.get("file_path") or args.get("target_file") or args.get("path") or ""
        norm_raw = p.replace("\\", "/").lower()
        if any(seg in norm_raw for seg in ("/.ssh/", "/.aws/", "/.gnupg/", "/.kube/", "id_rsa", "id_ed25519")):
            print("DENY_SENS:" + p)
            sys.exit(0)
        if tname in ("read_file", "Read"):
            print("SAFE_TOOL")
            sys.exit(0)
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
            if os.environ.get("SEN_TRUSTED_INSTALLER") != "1" and re.search(r"(?i)(/\.agents/(office/[^/]+\.(json|jsonl)$|sen\.lock\.json$|plugins/sen-method/(scripts/|hooks\.json$|plugin\.json$)|skills/[^/]+/scripts/)|/\.gemini/(config/|settings\.json$|.*hooks\.json$)|/(\.claude/settings\.json|\.cursor/hooks\.json|guard\.(ps1|sh))$)", norm_rp):
                print("DENY_STATE:" + rp)
                sys.exit(0)
            rw0 = os.path.realpath(ws_list[0])
            if rw0 and "/.agents/" not in norm_rp and "/docs/" not in norm_rp and not re.search(r"(?i)(/(temp|tmp|T)/|sen-(harness|gov|adv|.*-test)|TestDrive)", rw0.replace("\\", "/")):
                try:
                    import shutil
                    from datetime import datetime, timezone
                    ts_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
                    snap_d = os.path.join(rw0, ".agents", ".sen-restore", f"auto-pre-edit-{ts_id}")
                    files_d = os.path.join(snap_d, "files")
                    os.makedirs(files_d, exist_ok=True)
                    existed = os.path.isfile(rp)
                    if existed: shutil.copy2(rp, os.path.join(files_d, "f_0.bak"))
                    rel_p = os.path.relpath(rp, rw0).replace("\\", "/") if rp.startswith(rw0) else os.path.basename(rp)
                    mf = {"id": f"auto-pre-edit-{ts_id}", "label": "auto-pre-edit", "createdAt": ts_id, "entries": [{"relPath": rel_p, "fullPath": rp, "existed": existed, "storedName": "f_0.bak"}]}
                    with open(os.path.join(snap_d, "manifest.json"), "w", encoding="utf-8") as f: json.dump(mf, f)
                except Exception: pass
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
    cmd = args.get("CommandLine") or args.get("command") or args.get("cmd") or ""
    if cmd and ws_list and re.search(r"(?i)\bgit\b[^|;&]*\b(commit|push)\b", cmd):
        off_dir = os.path.join(os.path.realpath(ws_list[0]), ".agents", "office")
        seal_p = os.path.join(off_dir, "state-seal.json")
        if os.path.isfile(seal_p):
            saved = json.load(open(seal_p, "r", encoding="utf-8"))
            fh = {}
            for fn in sorted(os.listdir(off_dir)):
                if fn.endswith(".json") and fn != "state-seal.json" and os.path.isfile(os.path.join(off_dir, fn)):
                    fh[fn] = hashlib.sha256(open(os.path.join(off_dir, fn), "rb").read()).hexdigest().lower()
            comp = hashlib.sha256(";".join(f"{k}={fh[k]}" for k in fh).encode("utf-8")).hexdigest().lower()
            if saved.get("compositeHash") and saved.get("compositeHash") != comp:
                print("DENY_SEAL:state-seal.json")
                sys.exit(0)
    print("CMD:" + cmd)
except Exception:
    print("FALLBACK")
' <<< "$RAW" 2>/dev/null || echo "FALLBACK")"

  case "$PY_CHECK" in
    DENY_SENS:*)
      out_decision "deny" "[SEN GUARD] Blocked: access to sensitive host credential path (${PY_CHECK#DENY_SENS:})."
      ;;
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
    DENY_SEAL:*)
      out_decision "deny" "[SEN GUARD] Blocked: .agents/office state seal is tampered (${PY_CHECK#DENY_SEAL:}). Restore or verify state before committing/pushing."
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
  FLAT_RAW="$(printf '%s' "$RAW" | tr '\r\n' ' ')"
  if printf '%s' "$FLAT_RAW" | grep -Eiq '(/\.ssh/|/\.aws/|/\.gnupg/|/\.kube/|id_rsa|id_ed25519|\.npmrc|\.pypirc|\.netrc)'; then
    out_decision "deny" "[SEN GUARD] Blocked: access to sensitive host credential path."
  fi
  if printf '%s' "$FLAT_RAW" | grep -Eiq '"(name|tool_name)"[[:space:]]*:[[:space:]]*"(write_file|edit_file|read_file|Write|Edit|MultiEdit|Read)"'; then
    TARGET_P="$(printf '%s' "$FLAT_RAW" | sed -n 's/.*"\(Path\|file_path\|target_file\|path\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2/p')"
    if printf '%s' "$FLAT_RAW $TARGET_P" | grep -Eiq '(/\.ssh/|/\.aws/|/\.gnupg/|/\.kube/|id_rsa|id_ed25519|\.npmrc|\.pypirc|\.netrc|\.\./|/\.git/(config|hooks)|/\.agents/(office|sen\.lock\.json|plugins/sen-method)|/\.gemini/(config/|settings\.json|.*hooks\.json)|/(\.claude/settings\.json|\.cursor/hooks\.json))'; then
      out_decision "deny" "[SEN GUARD] Blocked: protected state, git metadata, or path traversal detected in POSIX fallback."
    fi
    if printf '%s' "$FLAT_RAW" | grep -Eiq '"(name|tool_name)"[[:space:]]*:[[:space:]]*"(write_file|edit_file|Write|Edit|MultiEdit)"'; then
      WS_P="$(printf '%s' "$FLAT_RAW" | sed -n 's/.*"\(workspacePaths\|workspace_roots\)"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\2/p')"
      [ -z "$WS_P" ] && WS_P="$(printf '%s' "$FLAT_RAW" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      if [ -z "$WS_P" ] || [ -z "$TARGET_P" ] || { [ "${TARGET_P#/}" != "$TARGET_P" ] && [ "${TARGET_P#"$WS_P"/}" = "$TARGET_P" ] && [ "$TARGET_P" != "$WS_P" ]; }; then
        out_decision "deny" "[SEN GUARD] Blocked (fail-closed): file write outside verified workspace boundary in POSIX fallback."
      fi
      out_decision "deny" "[SEN GUARD] Blocked (fail-closed): python3 is required on POSIX to verify canonical symlink/workspace boundaries for file writes."
    fi
    out_decision "ask" ""
  fi
  if command -v jq >/dev/null 2>&1; then
    CMD="$(printf '%s' "$RAW" | jq -r '.toolCall.args.CommandLine // .tool_input.CommandLine // .tool_input.command // empty' 2>/dev/null || true)"
  else
    CMD="$(printf '%s' "$FLAT_RAW" | sed -n 's/.*"\(CommandLine\|command\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2/p')"
  fi
fi

if [ -z "${CMD:-}" ]; then
  out_decision "ask" ""
fi

if printf '%s' "$CMD" | grep -Eiq '(\bcat\b|\btype\b|\bget-content\b|\bgc\b|\bhead\b|\btail\b|\bgrep\b|\brg\b|\bselect-string\b)[^|;&]*([/\\]\.ssh[/\\]|[/\\]\.aws[/\\]|[/\\]\.gnupg[/\\]|[/\\]\.kube[/\\]|id_rsa|id_ed25519)'; then
  deny "Reading sensitive host credential/key files via shell"
fi

CMD_SCAN="$(printf '%s' "$CMD" | sed -E 's/(\bgit\b[^|;&]*\bcommit\b[^|;&]*[[:space:]](-m|--message)[[:space:]]+)("[^"`$]+"|'\''[^'\'']+'\'')/\1""/Ig' 2>/dev/null || printf '%s' "$CMD")"
if printf '%s' "$CMD_SCAN" | grep -Eiq '^[[:space:]]*(echo|write-host|write-output|grep|rg|select-string)\b' && ! printf '%s' "$CMD_SCAN" | grep -Eq '[|;&`$><]'; then
  CMD_SCAN=""
fi
if [ -n "$CMD_SCAN" ]; then
  CMD_DEOBF="$(printf '%s' "$CMD_SCAN" | sed -E 's/([a-zA-Z])\\([a-zA-Z])/\1\2/g; s/([a-zA-Z])"([a-zA-Z]*)"([a-zA-Z]*)/\1\2\3/g; s/([a-zA-Z])'\''([a-zA-Z]*)'\''([a-zA-Z]*)/\1\2\3/g' 2>/dev/null || printf '%s' "$CMD_SCAN")"
  if [ "$CMD_DEOBF" != "$CMD_SCAN" ]; then
    CMD_SCAN="$CMD_SCAN ; $CMD_DEOBF"
  fi
fi

if [ -n "$CMD_SCAN" ]; then
  if printf '%s' "$CMD_SCAN" | grep -Eiq '(^|[^a-zA-Z0-9_])rm\b[^|;&]*([[:space:]]-[a-zA-Z]*r|[[:space:]]--recursive\b)'; then
    deny "Recursive delete (rm -r / rm -rf / rm --recursive)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '(^|[^a-zA-Z0-9_])(remove-item|ri|del|erase|rd|rmdir)\b[^|;&]*[[:space:]]-r(e(c(u(r(s(e)?)?)?)?)?)?\b'; then
    deny "Recursive delete (Remove-Item -Recurse)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '(^|[^a-zA-Z0-9_])(get-childitem|gci|dir|ls)\b[^;]*-r(e(c(u(r(s(e)?)?)?)?)?)?\b[^;]*\|[[:space:]]*(remove-item|ri|del|erase)\b'; then
    deny "Piped recursive delete (Get-ChildItem -Recurse | Remove-Item)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '(^|[^a-zA-Z0-9_])(rd|rmdir|del|erase)\b[^|;&]*[[:space:]]/s\b'; then
    deny "Recursive delete (rd/del /s)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bfs\.(rm|rmdir)(Sync)?[[:space:]]*\(|\b(npx[[:space:]]+)?rimraf\b|\brobocopy(\.exe)?\b[^|;&]*[[:space:]]/mir\b'; then
    deny "Recursive delete (fs.rm / rimraf / robocopy /MIR)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bfind\b[^|;&]*[[:space:]]-delete\b'; then
    deny "Recursive find -delete"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\b(shutil[[:space:]]*\.[[:space:]]*rmtree|from[[:space:]]+shutil[[:space:]]+import[[:space:]]+rmtree)\b|\brmtree[[:space:]]*\('; then
    deny "Python shutil.rmtree recursive delete"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\b(drop[[:space:]]+(database|table|schema)|truncate[[:space:]]+(table[[:space:]]+)?[a-zA-Z0-9_."`]+)\b'; then
    deny "Destructive SQL (DROP / TRUNCATE)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bdelete[[:space:]]+from[[:space:]]+[a-zA-Z0-9_."`]+[[:space:]]*(;|$)'; then
    deny "Unbounded SQL DELETE FROM without WHERE clause"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '(^|[^a-zA-Z0-9_])format(\.com)?[[:space:]]+[a-zA-Z]:'; then
    deny "Disk format command"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '(^|[^a-zA-Z0-9_])(diskpart|clear-disk|format-volume|remove-partition|initialize-disk)\b'; then
    deny "Disk or partition modification"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bgit\b[^|;&]*\bpush\b[^|;&]*([[:space:]]--force(-with-lease)?\b|[[:space:]]-f\b|[[:space:]]--delete\b|[[:space:]]-d\b|[[:space:]]--mirror\b|[[:space:]]--no-verify\b|[[:space:]]["'\'']?\+[^[:space:]]|[[:space:]]["'\'']?:[^[:space:]])'; then
    deny "Force push, remote branch delete, or hook bypass"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bgit\b[^|;&]*\bcommit\b[^|;&]*[[:space:]](--no-verify|-n)\b'; then
    deny "git commit --no-verify/-n (hook bypass)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bgit\b[^|;&]*\breset\b[^|;&]*--hard'; then
    deny "git reset --hard (discards uncommitted work)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bgit\b[^|;&]*\bclean\b[^|;&]*([[:space:]]-[a-zA-Z]*f|[[:space:]]--force\b)'; then
    deny "git clean -f/--force (deletes untracked files)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bgit\b[^|;&]*\bcheckout\b[^|;&]*([[:space:]](--[[:space:]]+)?\.([[:space:]]|$)|[[:space:]]-f\b|[[:space:]]--force\b)'; then
    deny "git checkout . or -f (discards working tree changes)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bgit\b[^|;&]*\brestore\b[^|;&]*([[:space:]](--[[:space:]]+)?\.([[:space:]]|$)|[[:space:]]-f\b|[[:space:]]--force\b|[[:space:]]-W\b|[[:space:]]--worktree\b)'; then
    if ! (printf '%s' "$CMD_SCAN" | grep -Eq '\bgit\b[^|;&]*\brestore\b[^|;&]*[[:space:]](--staged|-S)\b' && ! printf '%s' "$CMD_SCAN" | grep -Eq '\bgit\b[^|;&]*\brestore\b[^|;&]*[[:space:]](--worktree|-W|-f|--force)\b'); then
      deny "git checkout/restore . or -f (discards working tree changes)"
    fi
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bgit\b[^|;&]*\bstash[[:space:]]+(drop|clear)\b'; then
    deny "git stash drop/clear"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bgit\b[^|;&]*\breflog[[:space:]]+(expire|delete)\b'; then
    deny "git reflog expire/delete"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bgit\b[^|;&]*\b(filter-branch|filter-repo)\b'; then
    deny "Git history rewrite"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bgh[[:space:]]+repo[[:space:]]+delete\b'; then
    deny "GitHub repository deletion"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bdocker(-compose|[[:space:]]+compose)\b[^|;&]*\bdown\b[^|;&]*[[:space:]](-v|--volumes)\b|\b(terraform[[:space:]]+destroy|prisma[[:space:]]+migrate[[:space:]]+reset)\b'; then
    deny "Destructive container volume or database/infra reset"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '(\biex\b|\binvoke-expression\b)[[:space:]]*\(?[[:space:]]*(\birm\b|\binvoke-restmethod\b|\biwr\b|\binvoke-webrequest\b|\bcurl\b|\bwget\b)'; then
    deny "Remote script download and execution (IEX / IRM)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '(\birm\b|\binvoke-restmethod\b|\biwr\b|\binvoke-webrequest\b|\bcurl\b|\bwget\b)[^|;]*\|[[:space:]]*(\biex\b|\binvoke-expression\b)'; then
    deny "Piped remote script execution (IRM/IWR/curl | IEX)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '(\bcurl\b|\bwget\b)[^;]*\|[[:space:]]*(sh|bash|zsh|pwsh|powershell|python|python3|node)\b'; then
    deny "Piped remote script execution (curl/wget | sh/bash/pwsh)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bbase64[[:space:]]+(-d|--decode)[^|;]*\|[[:space:]]*(sh|bash|zsh|pwsh|powershell|python|python3)\b'; then
    deny "Piped base64 decode to shell execution"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\b(powershell|pwsh)(\.exe)?\b[^|;&]*[[:space:]]-(e|ec|enc|encodedcommand)[[:space:]]+[A-Za-z0-9+/=]{8,}'; then
    deny "Encoded PowerShell command execution"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eq '\bgit\b[^|;&]*\bbranch\b[^|;&]*([[:space:]]-D\b|--delete[[:space:]]+--force|--force[[:space:]]+--delete)'; then
    deny "git branch -D (force-deletes unmerged branch)"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '\bffmpeg(\.exe)?\b[^|;&]*[[:space:]]-i[[:space:]]+["'\'']?(\./)?([^"'\''[:space:]]+)["'\'']?([[:space:]]+[^|;&]*)*[[:space:]]+["'\'']?(\./)?\3["'\'']?([[:space:]]+-(y|n))*[[:space:]]*($|[|;&])'; then
    deny "Non-destructive media guard: ffmpeg in-place overwrite of input file is prohibited. Write output to a separate file or output/ folder"
  fi
  if printf '%s' "$CMD_SCAN" | grep -Eiq '(>|>>|\b(tee|cp|mv|rm|del|remove-item|set-content|out-file|add-content)\b|writeall(text|lines|bytes)|streamwriter|open\(|fs\.write)[^|;&]*(^|[[:space:]"'\''/\\])\.agents[/\\]office([/\\]|$)|(^|[[:space:]"'\''/\\])\.agents[/\\]office[/\\][^|;&]*(>|>>|\b(tee|set-content|out-file|add-content)\b|\.write\()'; then
    deny "Direct shell tampering with protected .agents/office state JSON"
  fi
  if [ "${SEN_TRUSTED_INSTALLER:-0}" != "1" ] && printf '%s' "$CMD_SCAN" | grep -Eiq '(>|>>|\b(tee|cp|mv|rm|del|remove-item|set-content|out-file|add-content)\b|writeall(text|lines|bytes))[^|;&]*((^|[[:space:]"'\''/\\])guard\.(ps1|sh)\b|\.agents[/\\](sen\.lock\.json|plugins[/\\]sen-method[/\\](scripts[/\\]|hooks\.json|plugin\.json))|\.gemini[/\\](config[/\\]|settings\.json|.*hooks\.json)|(\.claude[/\\]settings\.json|\.cursor[/\\]hooks\.json))|((^|[[:space:]"'\''/\\])guard\.(ps1|sh)\b|\.agents[/\\](sen\.lock\.json|plugins[/\\]sen-method[/\\](scripts[/\\]|hooks\.json|plugin\.json))|\.gemini[/\\](config[/\\]|settings\.json|.*hooks\.json)|(\.claude[/\\]settings\.json|\.cursor[/\\]hooks\.json))[^|;&]*(>|>>|\b(tee|set-content|out-file|add-content)\b)'; then
    deny "Direct shell tampering with Sen runtime scripts, lockfile, or hook configuration"
  fi
fi
if [ "${SEN_TRUSTED_HOOK:-0}" != "1" ] && printf '%s' "$CMD" | grep -Eiq '\bSync-SenOfficeState\b[^|;&]*[[:space:]]-UpdateSeal\b|\bLock-SenQualityBaseline\b[^|;&]*[[:space:]]-Force\b|\bClear-SenTasks\b|\bSEN_TRUSTED_(INSTALLER|HOOK)\b'; then
  deny "Untrusted self-resealing of state-seal.json, quality-baseline.json, Clear-SenTasks, or SEN_TRUSTED bypass via run_command"
fi

out_decision "ask" ""
