#!/usr/bin/env bash
# scripts/office-post.sh
# Antigravity PostToolUse telemetry hook for macOS/Linux (Sen Office v0.2.0).

set -u
RAW="$(cat 2>/dev/null || true)"
[ -z "$RAW" ] && exit 0

if command -v python3 >/dev/null 2>&1; then
  python3 -c '
import json, os, re, sys, time, uuid

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

try:
    d = json.loads(sys.stdin.read())
    ws_list = [w for w in (d.get("workspacePaths") or []) if w]
    if not ws_list: sys.exit(0)
    ws = ws_list[0]
    off_dir = os.path.join(ws, ".agents", "office")
    cfg_path = os.path.join(off_dir, "config.json")
    mode = "eco"
    if os.path.isfile(cfg_path):
        try:
            mode = json.load(open(cfg_path, "r", encoding="utf-8")).get("mode", "eco")
        except Exception:
            mode = "eco"
    if mode == "off": sys.exit(0)

    tc = d.get("toolCall") or {}
    tname = tc.get("name") or ""
    args = tc.get("args") or {}
    path_arg = args.get("Path") or args.get("SearchPath") or ""
    cmd_arg = args.get("CommandLine") or ""
    short_file = os.path.basename(path_arg) if path_arg else ""

    role, lane, model, eco = "be", "Execution", "inherit", tname
    if tname in ("grep_search", "find_by_name"):
        role, lane, model = "r1", "Scout", "flash_lite"
        eco = "Search: " + (args.get("Query") or args.get("Pattern") or short_file)
    elif tname == "read_file":
        if re.search(r"(?i)(specs|templates|README|docs)", path_arg):
            role, lane, eco = "ba", "Design", "Read spec: " + short_file
        else:
            role, lane, model, eco = "r2", "Scout", "flash", "Read: " + short_file
    elif tname in ("write_file", "edit_file"):
        loops_p = os.path.join(off_dir, "loops.json")
        if os.path.isfile(loops_p):
            try: os.remove(loops_p)
            except Exception: pass
        if re.search(r"(?i)\.(html|css|tsx|jsx|vue|svg)$", path_arg):
            role, lane, eco = "fe", "FE Track", "Edit UI: " + short_file
        else:
            role, lane, model, eco = "be", "BE Track", "pro", "Edit code: " + short_file
    elif tname == "run_command":
        if re.search(r"(?i)(Validate-Repo|security|audit)", cmd_arg):
            role, lane, model, eco = "sec", "Security Gate", "pro", "Security/Repo check"
        elif re.search(r"(?i)(test|run\.ps1|pytest|jest|vitest)", cmd_arg):
            role, lane, eco = "qa", "QA Gate", "Run test suite"
        else:
            role, lane, eco = "be", "System Cmd", "Run: " + cmd_arg[:48]

    os.makedirs(off_dir, exist_ok=True)
    ev_path = os.path.join(off_dir, "events.jsonl")
    ts = int(time.time() * 1000)
    ev = {
        "id": f"ev-{ts}-{uuid.uuid4().hex[:6]}",
        "ts": ts,
        "from": role,
        "to": "sys",
        "lane": lane,
        "kind": "ok",
        "hold": 1,
        "ecoText": redact(eco),
        "fullText": redact(eco),
        "source": "hook-post",
        "tool": tname,
        "target": redact(path_arg or cmd_arg),
        "command": redact(cmd_arg),
        "model": model
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

