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
      if [ -e "$SRC/$name" ]; then
        if ! out="$(cp -R "$SRC/$name" "$SEN_DEST/$name" 2>&1)"; then
          SEN_ERROR="copy of $name failed: $out"
          break
        fi
      fi
    done
    if [ -n "$SEN_ERROR" ]; then
      rm -rf "$SEN_DEST"
    else
      SEN_STATUS="installed"
    fi
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

# 4. Packages from packages.json.
# NOTE: packages.json is parsed with sed: keep one "key": value per line and no spaces inside values.
LOCK="$WORKSPACE/.agents/sen.lock.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PKG_JSON=""
NEW_ENTRIES=""   # newline-separated '"id":{...}' lines to add or replace
NEW_IDS=" "
REQUIRED_OK=1

field() { printf '%s\n' "$1" | sed -n "s/.*\"$2\": *\"\{0,1\}\([^\", }]*\).*/\1/p" | head -n 1; }
# The lock is written with one package entry per line: "id":{"repo":...,"commit":"..."}
old_entry() {
  [ -f "$LOCK" ] || return 0
  grep -F "\"$1\":{\"repo\"" "$LOCK" | head -n 1
}
old_commit() {
  old_entry "$1" | sed -n "s/^ *\"$1\":{.*\"commit\":\"\([^\"]*\)\".*/\1/p"
}

install_pkg() {
  id="$1"; repo="$2"; sub="$3"; dest="$WORKSPACE/$4"
  status="installed"; commit=""; err=""
  if [ -e "$dest" ]; then
    status="exists"; commit="unknown"
    if [ -d "$dest/.git" ]; then
      commit="$(git -C "$dest" rev-parse HEAD 2>/dev/null || echo unknown)"
    elif [ -f "$dest/.sen-commit" ]; then
      commit="$(tr -d '\r\n ' < "$dest/.sen-commit")"
      [ -z "$commit" ] && commit="unknown"
    fi
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
        if (cd "$src" && tar --exclude=.git -cf - .) | (cd "$dest" && tar -xf -); then
          printf '%s\n' "$commit" > "$dest/.sen-commit"
        else
          status="failed"; err="copy failed"; rm -rf "$dest"
        fi
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
  c_json="null"; [ -n "$commit" ] && c_json="\"$(json_escape "$commit")\""
  PKG_JSON="$PKG_JSON${PKG_JSON:+,}{\"id\":\"$id\",\"status\":\"$status\",\"commit\":$c_json,\"error\":$e_json}"
  if [ "$status" = "failed" ]; then
    [ "$req" = "true" ] && REQUIRED_OK=0
    continue
  fi
  # Existing package that already has a lock entry: keep that entry untouched.
  if [ "$status" = "exists" ] && [ -n "$(old_commit "$id")" ]; then continue; fi
  [ -z "$commit" ] && commit="unknown"
  entry="\"$id\":{\"repo\":\"$(json_escape "$repo")\",\"subPath\":\"$(json_escape "$sub")\",\"commit\":\"$(json_escape "$commit")\",\"installedAt\":\"$NOW\"}"
  NEW_ENTRIES="$NEW_ENTRIES${NEW_ENTRIES:+
}$entry"
  NEW_IDS="$NEW_IDS$id "
done <<EOF
$BLOCKS
EOF

[ "$REQUIRED_OK" -eq 1 ] || OK=0

# 5. Lock file: only when everything required succeeded; written atomically.
# Existing entries and lastUpdateCheck are preserved; unchanged locks are not rewritten.
LOCK_WRITTEN=false
if [ "$OK" -eq 1 ] && { [ -n "$NEW_ENTRIES" ] || [ ! -f "$LOCK" ]; }; then
  LAST_CHECK="null"
  ENTRIES=""
  if [ -f "$LOCK" ]; then
    lc="$(sed -n 's/^ *"lastUpdateCheck": *\(.*[^,]\),\{0,1\} *$/\1/p' "$LOCK" | head -n 1)"
    [ -n "$lc" ] && LAST_CHECK="$lc"
    while IFS= read -r line; do
      oid="$(printf '%s' "$line" | sed -n 's/^ *"\([^"]*\)":{"repo".*/\1/p')"
      [ -z "$oid" ] && continue
      case "$NEW_IDS" in *" $oid "*) continue ;; esac
      ENTRIES="$ENTRIES${ENTRIES:+,
}$(printf '%s' "$line" | sed 's/^ *//; s/,$//')"
    done < "$LOCK"
  fi
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    ENTRIES="$ENTRIES${ENTRIES:+,
}$line"
  done <<EOF
$NEW_ENTRIES
EOF
  tmp_lock="$LOCK.$$.tmp"
  {
    printf '{\n"lockVersion":1,\n"lastUpdateCheck":%s,\n"packages":{\n' "$LAST_CHECK"
    [ -n "$ENTRIES" ] && printf '%s\n' "$ENTRIES"
    printf '}\n}\n'
  } > "$tmp_lock" && mv -f "$tmp_lock" "$LOCK" && LOCK_WRITTEN=true
fi

SEN_JSON="{\"status\":\"$SEN_STATUS\"}"
[ -n "$SEN_ERROR" ] && SEN_JSON="{\"status\":\"$SEN_STATUS\",\"error\":\"$(json_escape "$SEN_ERROR")\"}"
printf '{"workspace":"%s","sen":%s,"packages":[%s],"lockWritten":%s,"safetyCreated":%s}\n' \
  "$(json_escape "$WORKSPACE")" "$SEN_JSON" "$PKG_JSON" "$LOCK_WRITTEN" "$SAFETY_CREATED"

[ "$OK" -eq 1 ] && exit 0 || exit 1
