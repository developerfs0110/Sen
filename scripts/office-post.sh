#!/usr/bin/env bash
# scripts/office-post.sh
# Antigravity PostToolUse telemetry hook for macOS/Linux (Sen Office v0.2.0).

set -u
RAW="$(cat 2>/dev/null || true)"
[ -z "$RAW" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "${SEN_FORCE_POSIX_PY:-0}" != "1" ] && command -v pwsh >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/office-post.ps1" ]; then
  printf '%s' "$RAW" | SEN_TRUSTED_HOOK=1 pwsh -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/office-post.ps1" >/dev/null 2>&1 || true
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  python3 -c '
import hashlib, json, os, re, sys, time, uuid
from datetime import datetime, timezone

def redact(s):
    if not s: return ""
    s = re.sub(r"(?i)(\bbearer\s+)[^\s\"'\''&]+", r"\1[REDACTED]", s)
    s = re.sub(r"\b(?:sk|pk|rk)-[A-Za-z0-9_-]{8,}", "[REDACTED]", s)
    s = re.sub(r"\bgh[pousr]_[A-Za-z0-9]{10,}", "[REDACTED]", s)
    s = re.sub(r"\bxox[abpr]-[A-Za-z0-9-]{10,}", "[REDACTED]", s)
    s = re.sub(r"\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]{4,}", "[REDACTED]", s)
    s = re.sub(r"(?i)(\b(?:api[_-]?key|access[_-]?key|token|secret|password|passwd|pwd|authorization|cookie)\b[\"'\'']?\s*[:=]\s*[\"'\'']?)[^\s\"'\''&]+", r"\1[REDACTED]", s)
    s = re.sub(r"(//[^/\s:@]+:)[^/\s@]+(@)", r"\1[REDACTED]\2", s)
    return s

def calc_seal(off_dir):
    fhashes = {}
    if os.path.isdir(off_dir):
        for fn in sorted(os.listdir(off_dir)):
            if fn.endswith(".json") and fn != "state-seal.json":
                fp = os.path.join(off_dir, fn)
                if os.path.isfile(fp):
                    fhashes[fn] = hashlib.sha256(open(fp, "rb").read()).hexdigest().lower()
    raw_pairs = ";".join(f"{k}={fhashes[k]}" for k in fhashes)
    comp = hashlib.sha256(raw_pairs.encode("utf-8")).hexdigest().lower()
    return comp, fhashes

def write_atomic(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.tmp-{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2)
    os.replace(tmp, path)

try:
    d = json.loads(sys.stdin.read())
    ws_list = [w for w in (d.get("workspacePaths") or d.get("workspace_roots") or []) if w]
    if not ws_list and d.get("cwd"): ws_list = [d.get("cwd")]
    if not ws_list: sys.exit(0)
    ws = ws_list[0]
    off_dir = os.path.join(ws, ".agents", "office")
    seal_p = os.path.join(off_dir, "state-seal.json")
    seal_intact = True
    if os.path.isfile(seal_p):
        try:
            saved = json.load(open(seal_p, "r", encoding="utf-8"))
            comp_now, _ = calc_seal(off_dir)
            seal_intact = (saved.get("compositeHash") == comp_now)
        except Exception:
            seal_intact = False
    mutated = False
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    cfg_path = os.path.join(off_dir, "config.json")
    mode = "eco"
    if os.path.isfile(cfg_path):
        try: mode = json.load(open(cfg_path, "r", encoding="utf-8")).get("mode", "eco")
        except Exception: mode = "eco"
    if mode == "off": sys.exit(0)

    tc = d.get("toolCall") or {}
    tname = tc.get("name") or d.get("tool_name") or ""
    args = tc.get("args") or d.get("tool_input") or d.get("toolArgs") or {}
    path_arg = args.get("Path") or args.get("file_path") or args.get("target_file") or args.get("path") or args.get("SearchPath") or ""
    cmd_arg = args.get("CommandLine") or args.get("command") or args.get("cmd") or ""
    short_file = os.path.basename(path_arg) if path_arg else ""
    resp = d.get("tool_response") or d.get("toolResult") or d
    ec_raw = resp.get("exit_code") if "exit_code" in resp else resp.get("exitCode")
    has_ec = isinstance(ec_raw, int) or (isinstance(ec_raw, str) and re.match(r"^-?\d+$", ec_raw))
    ec_val = int(ec_raw) if has_ec else -1
    is_err = bool(resp.get("is_error") or resp.get("isError")) or (has_ec and ec_val != 0)

    tasks_p = os.path.join(off_dir, "tasks.json")
    def load_tasks():
        if not os.path.isfile(tasks_p): return []
        try:
            o = json.load(open(tasks_p, "r", encoding="utf-8"))
            return o.get("tasks", []) if isinstance(o, dict) else o
        except Exception: return []
    def save_tasks(tlist):
        write_atomic(tasks_p, {"version": 1, "updatedAt": now_iso, "tasks": tlist})

    role, lane, model, eco = "be", "Execution", "inherit", tname
    if tname in ("invoke_subagent", "Task"):
        r_arg = args.get("Role") or args.get("TypeName") or "Subagent"
        role, lane, eco = "pm", "Subagent", f"Subagent [{r_arg}]"
        in_p = os.path.join(off_dir, "current-intake.json")
        if not os.path.isfile(in_p):
            write_atomic(in_p, {"taskId": "SUBAGENT-LIVE", "userName": "User", "request": eco, "tier": 2, "requiresDialecticalProof": True, "requiresResourceCostTable": True, "requiresRestorePoint": True, "requiresSubagentInTurn1": True, "requiresMermaidDiagrams": False, "createdAt": now_iso})
        sc_p = os.path.join(off_dir, "showcase.json")
        write_atomic(sc_p, {"projectTitle": eco, "domain": "architecture", "tier": 2, "phase1": {"summary": eco, "specPath": "SUBAGENT-LIVE", "expectedOutputs": ["SUBAGENT-LIVE"], "updatedAt": now_iso}, "updatedAt": now_iso})
        tlist = [t for t in load_tasks() if t.get("id") != "SUBAGENT-LIVE"]
        tlist.append({"id": "SUBAGENT-LIVE", "title": eco, "tier": 2, "status": "in_progress", "assignee": "be", "isTelemetryOnly": True, "updatedAt": now_iso, "_rev": 1})
        save_tasks(tlist); mutated = True
    elif tname == "send_message":
        role, lane, eco = "be", "Subagent", "Report: Subagent message"
        tlist = load_tasks()
        for t in tlist:
            if t.get("id") == "SUBAGENT-LIVE": t["status"] = "done"; t["isTelemetryOnly"] = True; t["updatedAt"] = now_iso; mutated = True
        if mutated: save_tasks(tlist)
    elif tname in ("grep_search", "find_by_name"):
        role, lane, model = "r1", "Scout", "flash_lite"
        eco = "Search: " + (args.get("Query") or args.get("Pattern") or short_file)
    elif tname in ("read_file", "Read"):
        if re.search(r"(?i)(specs|templates|README|docs)", path_arg):
            role, lane, eco = "ba", "Design", "Read spec: " + short_file
        else:
            role, lane, model, eco = "r2", "Scout", "flash", "Read: " + short_file
    elif tname in ("write_file", "edit_file", "Write", "Edit", "MultiEdit"):
        loops_p = os.path.join(off_dir, "loops.json")
        if os.path.isfile(loops_p):
            try: os.remove(loops_p); mutated = True
            except Exception: pass
        if path_arg and not re.search(r"(?i)/(\.agents|docs)/", path_arg.replace("\\", "/")):
            tlist = load_tasks()
            if not any(t.get("status") in ("in_progress", "reviewing") for t in tlist):
                tlist.append({"id": "AUTO-WORK", "title": f"Edit {short_file}", "tier": 1, "status": "in_progress", "assignee": "be", "isTelemetryOnly": True, "updatedAt": now_iso, "_rev": 1})
                save_tasks(tlist); mutated = True
        if re.search(r"(?i)\.(html|css|tsx|jsx|vue|svg)$", path_arg):
            role, lane, eco = "fe", "FE Track", "Edit UI: " + short_file
        else:
            role, lane, model, eco = "be", "BE Track", "pro", "Edit code: " + short_file
    elif tname in ("run_command", "Bash", "run_terminal_cmd"):
        if re.search(r"(?i)(Validate-Repo|security|audit)", cmd_arg):
            role, lane, model, eco = "sec", "Security Gate", "pro", "Security/Repo check"
        elif (not re.search(r"(?i)^\s*(git\s+(commit|log|grep|diff|status|add|push)|grep|rg|select-string|cat|type|get-content|echo|write-host|write-output|true|rem|::)\b", cmd_arg)) and re.search(r"(?i)(^|[;&|]\s*)(&\s*)?((pwsh|powershell|bash|sh)(\.exe)?(\s+-[A-Za-z]+(\s+[^\s;|\"&]+)?)*\s+|python3?(\.exe)?\s+-m\s+)?[\"'']?([^\"''|;&]*[\\/])?(npm\s+test|pnpm\s+test|yarn\s+test|npx\s+(jest|vitest|playwright)|pytest|cargo\s+test|go\s+test|dotnet\s+test|Invoke-Pester|tests[/\\]run\.ps1|run\.ps1)\b", cmd_arg):
            role, lane, eco = "qa", "QA Gate", "Run test suite"
            if has_ec and ec_val == 0 and not is_err:
                tlist = load_tasks()
                ev_paths = []
                code_hashes = {}
                for t in tlist:
                    if t.get("status") in ("in_progress", "reviewing"):
                        for ap in (t.get("allowedPaths") or []):
                            if ap and ap not in ev_paths:
                                ev_paths.append(ap)
                                fp = ap if os.path.isabs(ap) else os.path.join(ws, ap)
                                if os.path.isfile(fp):
                                    code_hashes[ap] = hashlib.sha256(open(fp, "rb").read()).hexdigest().lower()
                    if t.get("id") == "AUTO-WORK":
                        t["status"] = "done"
                        t["updatedAt"] = now_iso
                        t["evidence"] = {"command": cmd_arg.strip(), "exitCode": 0, "verifiedAt": now_iso, "reviewer": "qa"}
                save_tasks(tlist)
                ev_p = os.path.join(off_dir, "evidence.json")
                evs = []
                if os.path.isfile(ev_p):
                    try:
                        eo = json.load(open(ev_p, "r", encoding="utf-8"))
                        evs = eo.get("evidence", []) if isinstance(eo, dict) else eo
                    except Exception: evs = []
                evs = [e for e in evs if e.get("evidence_id") != "EV-AUTO-TEST"]
                subj_p = ev_paths[0] if ev_paths else ""
                subj_h = code_hashes.get(subj_p, "")
                evs.append({"evidence_id": "EV-AUTO-TEST", "task_id": "AUTO-WORK", "type": "unit", "status": "PASS", "command": cmd_arg.strip(), "exitCode": 0, "codePaths": ev_paths, "subjectPath": subj_p, "subjectHash": subj_h, "code_hashes": code_hashes, "timestamp": now_iso, "verified": True})
                write_atomic(ev_p, {"updatedAt": now_iso, "evidence": evs}); mutated = True
        else:
            role, lane, eco = "be", "System Cmd", "Run: " + cmd_arg[:48]

    if seal_intact and mutated and os.path.isfile(seal_p):
        comp_after, fh_after = calc_seal(off_dir)
        write_atomic(seal_p, {"timestamp": now_iso, "compositeHash": comp_after, "fileHashes": fh_after})

    os.makedirs(off_dir, exist_ok=True)
    ev_path = os.path.join(off_dir, "events.jsonl")
    ts = int(time.time() * 1000)
    ev = {
        "id": f"ev-{ts}-{uuid.uuid4().hex[:6]}", "ts": ts, "from": role, "to": "sys", "lane": lane, "kind": "ok", "hold": 1,
        "ecoText": redact(eco), "fullText": redact(eco), "source": "hook-post", "tool": tname, "target": redact(path_arg or cmd_arg), "command": redact(cmd_arg), "model": model
    }
    lines = []
    if os.path.isfile(ev_path):
        with open(ev_path, "r", encoding="utf-8") as f:
            lines = [l.strip() for l in f if l.strip()]
    lines.append(json.dumps(ev, separators=(",", ":")))
    lines = lines[-200:]
    with open(ev_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
except Exception:
    pass
' <<< "$RAW" 2>/dev/null || true
fi
exit 0

