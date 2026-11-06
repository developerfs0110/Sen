#!/usr/bin/env bash
# scripts/install.sh
# Non-interactive Sen installer for macOS/Linux (basic parity with install.ps1).
# Prints one JSON result object as the last stdout line. Exit 0 on success, 1 on failure.
set -u

WORKSPACE=""
WITH_VN=0
SEN_SOURCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    --with-vn-law-check) WITH_VN=1; shift ;;
    --sen-source) SEN_SOURCE="${2:-}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$WORKSPACE" ]; then
  echo "Usage: install.sh --workspace <path> [--with-vn-law-check] [--sen-source <path|url>]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
[ -z "$SEN_SOURCE" ] && SEN_SOURCE="$REPO_ROOT"

mkdir -p "$WORKSPACE" || exit 1
WORKSPACE="$(cd "$WORKSPACE" && pwd)"

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\r\t' '   '
}

OK=1
TMP_ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t sen)"
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT

# 1. Workspace skeleton (never overwrites).
for d in .agents/rules .agents/plugins .agents/skills Code Templates docs; do
  mkdir -p "$WORKSPACE/$d"
done

# 2. Place Sen itself.
SEN_DEST="$WORKSPACE/.agents/plugins/sen-method"
SEN_STATUS="failed"
SEN_ERROR=""
if [ -e "$SEN_DEST" ]; then
  SEN_STATUS="exists"
else
  SRC="$SEN_SOURCE"
  if [ ! -d "$SRC" ]; then
    SRC="$TMP_ROOT/sen-src"
    if ! out="$(git clone --depth 1 --quiet "$SEN_SOURCE" "$SRC" 2>&1)"; then
      SEN_ERROR="git clone failed for $SEN_SOURCE: $out"
    fi
  fi
  if [ -z "$SEN_ERROR" ] && [ ! -f "$SRC/plugin.json" ]; then
    SEN_ERROR="plugin.json not found in Sen source $SEN_SOURCE"
  fi
  if [ -z "$SEN_ERROR" ]; then
    mkdir -p "$SEN_DEST"
    for item in plugin.json rules skills templates scripts INSTALL.md LICENSE CHANGELOG.md "$SRC"/README*; do
      name="$(basename "$item")"
      [ -e "$SRC/$name" ] && cp -R "$SRC/$name" "$SEN_DEST/$name"
    done
    SEN_STATUS="installed"
  fi
fi
[ "$SEN_STATUS" = "failed" ] && OK=0

# 3. safety.md from template (never overwrites).
SAFETY="$WORKSPACE/.agents/rules/safety.md"
SAFETY_CREATED=false
if [ ! -e "$SAFETY" ]; then
  esc_ws="$(printf '%s' "$WORKSPACE" | sed -e 's/[\/&|]/\\&/g')"
  sed "s|{{WORKSPACE_ROOT}}|$esc_ws|g" "$REPO_ROOT/templates/safety.template.md" > "$SAFETY" && SAFETY_CREATED=true
fi

# 4. Packages from packages.json (simple one-field-per-line format).
LOCK="$WORKSPACE/.agents/sen.lock.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PKG_JSON=""
LOCK_ENTRIES=""
REQUIRED_OK=1

field() { printf '%s\n' "$1" | sed -n "s/.*\"$2\": *\"\{0,1\}\([^\", }]*\).*/\1/p" | head -n 1; }
old_commit() {
  [ -f "$LOCK" ] || return 0
  awk -v id="\"$1\"" '$0 ~ id {f=1} f && /"commit"/ {gsub(/.*"commit": *"|".*/, ""); print; exit}' "$LOCK"
}

install_pkg() {
  id="$1"; repo="$2"; sub="$3"; dest="$WORKSPACE/$4"
  status="installed"; commit=""; err=""
  if [ -e "$dest" ]; then
    status="exists"; commit="unknown"
    [ -d "$dest/.git" ] && commit="$(git -C "$dest" rev-parse HEAD 2>/dev/null || echo unknown)"
  else
    clone="$TMP_ROOT/pkg-$id"
    if ! out="$(git clone --depth 1 --quiet "$repo" "$clone" 2>&1)"; then
      status="failed"; err="git clone failed for $repo: $out"
    else
      commit="$(git -C "$clone" rev-parse HEAD 2>/dev/null || echo unknown)"
      src="$clone"; [ -n "$sub" ] && src="$clone/$sub"
      if [ ! -d "$src" ]; then
        status="failed"; err="subPath '$sub' not found in $repo"
      else
        mkdir -p "$dest"
        (cd "$src" && tar --exclude=.git -cf - .) | (cd "$dest" && tar -xf -) || { status="failed"; err="copy failed"; rm -rf "$dest"; }
      fi
    fi
  fi
}

BLOCKS="$(tr -d '\r' < "$SCRIPT_DIR/packages.json" | tr '\n' ' ' | sed 's/}/}\n/g')"
while IFS= read -r block; do
  id="$(field "$block" id)"
  [ -z "$id" ] && continue
  repo="$(field "$block" repo)"; sub="$(field "$block" subPath)"
  dst="$(field "$block" dest)"; req="$(field "$block" required)"
  if [ "$req" != "true" ] && [ "$WITH_VN" -ne 1 ]; then continue; fi
  install_pkg "$id" "$repo" "$sub" "$dst"
  e_json="null"; [ -n "$err" ] && e_json="\"$(json_escape "$err")\""
  c_json="null"; [ -n "$commit" ] && c_json="\"$commit\""
  PKG_JSON="$PKG_JSON${PKG_JSON:+,}{\"id\":\"$id\",\"status\":\"$status\",\"commit\":$c_json,\"error\":$e_json}"
  if [ "$status" = "failed" ]; then
    [ "$req" = "true" ] && REQUIRED_OK=0
    continue
  fi
  keep="$(old_commit "$id")"
  lock_commit="$commit"
  if [ "$status" = "exists" ] && [ -n "$keep" ]; then lock_commit="$keep"; fi
  [ -z "$lock_commit" ] && lock_commit="unknown"
  LOCK_ENTRIES="$LOCK_ENTRIES${LOCK_ENTRIES:+,}\"$id\":{\"repo\":\"$repo\",\"subPath\":\"$sub\",\"commit\":\"$lock_commit\",\"installedAt\":\"$NOW\"}"
done <<EOF
$BLOCKS
EOF

[ "$REQUIRED_OK" -eq 1 ] || OK=0

# 5. Lock file: only when everything required succeeded; written atomically.
LOCK_WRITTEN=false
if [ "$OK" -eq 1 ]; then
  tmp_lock="$LOCK.$$.tmp"
  printf '{"lockVersion":1,"packages":{%s},"lastUpdateCheck":null}\n' "$LOCK_ENTRIES" > "$tmp_lock" && mv -f "$tmp_lock" "$LOCK" && LOCK_WRITTEN=true
fi

SEN_JSON="{\"status\":\"$SEN_STATUS\"}"
[ -n "$SEN_ERROR" ] && SEN_JSON="{\"status\":\"$SEN_STATUS\",\"error\":\"$(json_escape "$SEN_ERROR")\"}"
printf '{"workspace":"%s","sen":%s,"packages":[%s],"lockWritten":%s,"safetyCreated":%s}\n' \
  "$(json_escape "$WORKSPACE")" "$SEN_JSON" "$PKG_JSON" "$LOCK_WRITTEN" "$SAFETY_CREATED"

[ "$OK" -eq 1 ] && exit 0 || exit 1
