#!/usr/bin/env bash
# scripts/start-office.sh
# Zero-dependency Local Office Server for macOS/Linux using python3 http.server.

set -u
WORKSPACE=""
PORT=47890
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    --port) PORT="${2:-47890}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
[ -z "$WORKSPACE" ] && WORKSPACE="$REPO_ROOT"
HTML_PATH="$REPO_ROOT/office/index.html"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '{"workspace":"%s","port":%s,"url":"http://127.0.0.1:%s/","htmlPath":"%s","dryRun":true}\n' "$WORKSPACE" "$PORT" "$PORT" "$HTML_PATH"
  exit 0
fi

python3 - "$WORKSPACE" "$PORT" "$HTML_PATH" <<'PY'
import http.server, json, os, sys

ws, port, html_path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
off_dir = os.path.join(ws, ".agents", "office")

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass
    def _send(self, code, ctype, data):
        b = data if isinstance(data, bytes) else data.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(b)
    def do_GET(self):
        p = self.path.split("?")[0]
        if p in ("/", "/index.html"):
            with open(html_path, "rb") as f:
                self._send(200, "text/html; charset=utf-8", f.read())
        elif p == "/api/state":
            cfg = {"mode": "eco", "port": port}
            cfg_p = os.path.join(off_dir, "config.json")
            if os.path.isfile(cfg_p):
                try: cfg = json.load(open(cfg_p, "r", encoding="utf-8"))
                except Exception: pass
            evs = []
            ev_p = os.path.join(off_dir, "events.jsonl")
            if os.path.isfile(ev_p):
                with open(ev_p, "r", encoding="utf-8") as f:
                    for ln in f.readlines()[-150:]:
                        if ln.strip():
                            try: evs.append(json.loads(ln))
                            except Exception: pass
            sh = None
            sh_p = os.path.join(off_dir, "showcase.json")
            if os.path.isfile(sh_p):
                try: sh = json.load(open(sh_p, "r", encoding="utf-8"))
                except Exception: pass
            tks = []
            tk_p = os.path.join(off_dir, "tasks.json")
            if os.path.isfile(tk_p):
                try:
                    tobj = json.load(open(tk_p, "r", encoding="utf-8"))
                    tks = tobj.get("tasks", []) if isinstance(tobj, dict) else tobj
                except Exception: pass
            les = []
            ls_p = os.path.join(off_dir, "lessons.json")
            if os.path.isfile(ls_p):
                try: les = json.load(open(ls_p, "r", encoding="utf-8"))
                except Exception: pass
            self._send(200, "application/json; charset=utf-8", json.dumps({
                "live": True, "workspace": ws, "config": cfg, "events": evs, "showcase": sh,
                "tasks": tks, "lessons": les,
                "quota": {"available": False, "models": []}
            }))
        else:
            self._send(404, "application/json", '{"error":"not found"}')
    def do_POST(self):
        p = self.path.split("?")[0]
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n).decode("utf-8") if n > 0 else "{}"
        os.makedirs(off_dir, exist_ok=True)
        if p == "/api/config":
            req = json.loads(body or "{}")
            m = req.get("mode", "eco")
            if m not in ("off", "eco", "full"): m = "eco"
            cfg = {"mode": m, "port": port}
            with open(os.path.join(off_dir, "config.json"), "w", encoding="utf-8") as f:
                json.dump(cfg, f)
            self._send(200, "application/json", json.dumps(cfg))
        elif p == "/api/clear":
            ev_p = os.path.join(off_dir, "events.jsonl")
            if os.path.isfile(ev_p): os.remove(ev_p)
            self._send(200, "application/json", '{"cleared":true}')
        else:
            self._send(404, "application/json", '{"error":"not found"}')

srv = http.server.HTTPServer(("127.0.0.1", port), Handler)
print(f"SEN_OFFICE_URL=http://127.0.0.1:{port}/", flush=True)
srv.serve_forever()
PY

