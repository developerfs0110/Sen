#!/usr/bin/env bash
# scripts/check-updates.sh
# Pure ASCII shell script to check package updates and maintain zero-token notice file
# Mirrors check-updates.ps1 for POSIX systems (Linux/macOS)

set -euo pipefail

WORKSPACE=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--workspace|-Workspace)
      WORKSPACE="$2"
      shift 2
      ;;
    -f|--force|-Force)
      FORCE=1
      shift
      ;;
    *)
      if [[ -z "$WORKSPACE" ]]; then
        WORKSPACE="$1"
        shift
      else
        shift
      fi
      ;;
  esac
done

if [[ -z "$WORKSPACE" ]]; then
  echo "Usage: check-updates.sh -Workspace <path> [-Force]" >&2
  exit 1
fi

LOCK_FILE="$WORKSPACE/.agents/sen.lock.json"
NOTICE_FILE="$WORKSPACE/.agents/rules/sen-update-notice.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/packages.json"

if [[ ! -f "$LOCK_FILE" ]]; then
  exit 0
fi

# 7-day gate check
GATE_PASSED=0
if [[ $FORCE -eq 1 ]]; then
  GATE_PASSED=1
else
  LAST_CHECK=$(grep -o '"lastUpdateCheck"[[:space:]]*:[[:space:]]*"[^"]*"' "$LOCK_FILE" 2>/dev/null | sed 's/.*"lastUpdateCheck"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)
  if [[ -z "$LAST_CHECK" || "$LAST_CHECK" == "null" ]]; then
    GATE_PASSED=1
  else
    NOW_SEC=$(date +%s)
    LAST_SEC=""
    if date -d "$LAST_CHECK" +%s >/dev/null 2>&1; then
      LAST_SEC=$(date -d "$LAST_CHECK" +%s 2>/dev/null || true)
    elif date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_CHECK" +%s >/dev/null 2>&1; then
      LAST_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_CHECK" +%s 2>/dev/null || true)
    fi

    if [[ -n "$LAST_SEC" ]]; then
      DIFF_SEC=$((NOW_SEC - LAST_SEC))
      if [[ $DIFF_SEC -ge 604800 ]]; then
        GATE_PASSED=1
      fi
    else
      GATE_PASSED=1
    fi
  fi
fi

if [[ $GATE_PASSED -eq 0 ]]; then
  exit 0
fi

# Check for updates across packages in packages.json
UPDATES_FOUND=0
NOTICE_BODY=""

if [[ -f "$PACKAGES_FILE" ]]; then
  PKG_IDS=$(grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$PACKAGES_FILE" | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  for PKG_ID in $PKG_IDS; do
    if grep -q "\"$PKG_ID\"" "$LOCK_FILE" 2>/dev/null; then
      REPO=$(grep -A 5 "\"$PKG_ID\"" "$PACKAGES_FILE" | grep -o '"repo"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"repo"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
      CURR_COMMIT=$(grep -A 5 "\"$PKG_ID\"" "$LOCK_FILE" | grep -o '"commit"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"commit"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
      if [[ -n "$REPO" && -n "$CURR_COMMIT" ]]; then
        LATEST_COMMIT=$(git ls-remote "$REPO" HEAD 2>/dev/null | awk '{print $1}' || true)
        if [[ -n "$LATEST_COMMIT" && "$LATEST_COMMIT" != "$CURR_COMMIT" ]]; then
          UPDATES_FOUND=1
          NOTICE_BODY="${NOTICE_BODY}- **${PKG_ID}**: current '${CURR_COMMIT}', latest '${LATEST_COMMIT}'"$'\n'
        fi
      fi
    fi
  done
fi

if [[ $UPDATES_FOUND -eq 1 ]]; then
  mkdir -p "$(dirname "$NOTICE_FILE")"
  cat <<EOF > "$NOTICE_FILE"
# Sen Update Notice

Updates are available for the following package(s):

${NOTICE_BODY}
Mention these updates once, in the user's language, and offer to run the sen-update skill.
EOF
else
  if [[ -f "$NOTICE_FILE" ]]; then
    rm -f "$NOTICE_FILE"
  fi
fi

# Update lastUpdateCheck in lock file
NOW_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
if grep -q '"lastUpdateCheck"' "$LOCK_FILE"; then
  sed -i.bak -e "s/\"lastUpdateCheck\"[[:space:]]*:[[:space:]]*[^,}]*/\"lastUpdateCheck\": \"$NOW_UTC\"/" "$LOCK_FILE" && rm -f "${LOCK_FILE}.bak"
else
  sed -i.bak -e "s/}[[:space:]]*$/  \"lastUpdateCheck\": \"$NOW_UTC\"\n}/" "$LOCK_FILE" && rm -f "${LOCK_FILE}.bak"
fi

exit 0
