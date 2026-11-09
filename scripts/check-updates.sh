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
INSTRUCTION="Mention these updates once, in the user's language, and offer to run the sen-update skill."

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

          # Cap commit summary at 3 lines per package to conserve token budget in the notice rule.
          TMP_CLONE=$(mktemp -d 2>/dev/null || mktemp -d -t 'sen-clone')
          if git clone --depth 5 --quiet "$REPO" "$TMP_CLONE" 2>/dev/null; then
            LOG_LINES=$(git -C "$TMP_CLONE" log -5 --oneline 2>/dev/null | head -n 3 || true)
            while IFS= read -r line; do
              clean_line="$(printf '%s' "$line" | tr -d '<>`$|;' | cut -c1-100)"
              if [[ -n "$clean_line" ]]; then
                NOTICE_BODY="${NOTICE_BODY}  * ${clean_line}"$'\n'
              fi
            done <<< "$LOG_LINES"
          fi
          rm -rf "$TMP_CLONE"
        fi
      fi
    fi
  done
fi

if [[ $UPDATES_FOUND -eq 1 ]]; then
  mkdir -p "$(dirname "$NOTICE_FILE")"
  # Stage 1: Full notice with commit summaries
  RAW_NOTICE="# Sen Update Notice"$'\n\n'"Updates are available for the following package(s):"$'\n\n'"${NOTICE_BODY}"$'\n'"${INSTRUCTION}"$'\n'
  printf "%s" "$RAW_NOTICE" > "$NOTICE_FILE"

  BYTE_COUNT=$(wc -c < "$NOTICE_FILE" || echo 0)
  if [[ $BYTE_COUNT -gt 800 ]]; then
    # Stage 2: Staged fallback without summaries
    COMPACT_LINES=$(grep '^- \*\*' "$NOTICE_FILE" || true)
    TOTAL_ITEMS=$(echo "$COMPACT_LINES" | grep -c '^- \*\*' || echo 0)
    RAW_NOTICE="# Sen Update Notice"$'\n\n'"Updates are available for the following package(s):"$'\n\n'"${COMPACT_LINES}"$'\n\n'"${INSTRUCTION}"$'\n'
    printf "%s" "$RAW_NOTICE" > "$NOTICE_FILE"

    BYTE_COUNT=$(wc -c < "$NOTICE_FILE" || echo 0)
    if [[ $BYTE_COUNT -gt 800 && $TOTAL_ITEMS -gt 1 ]]; then
      # Stage 3: Truncate package list and write (+N more) with real N
      K=$((TOTAL_ITEMS - 1))
      while [[ $K -ge 1 ]]; do
        OMITTED=$((TOTAL_ITEMS - K))
        SUB_LINES=$(echo "$COMPACT_LINES" | head -n "$K")
        RAW_NOTICE="# Sen Update Notice"$'\n\n'"Updates are available for the following package(s):"$'\n\n'"${SUB_LINES}"$'\n'"- *(+${OMITTED} more)*"$'\n\n'"${INSTRUCTION}"$'\n'
        printf "%s" "$RAW_NOTICE" > "$NOTICE_FILE"
        BYTE_COUNT=$(wc -c < "$NOTICE_FILE" || echo 0)
        if [[ $BYTE_COUNT -le 800 ]]; then
          break
        fi
        K=$((K - 1))
      done
    fi

    # Stage 4: Final fallback guaranteed <= 800 bytes
    BYTE_COUNT=$(wc -c < "$NOTICE_FILE" || echo 0)
    if [[ $BYTE_COUNT -gt 800 ]]; then
      RAW_NOTICE="# Sen Update Notice"$'\n\n'"Updates are available (+${TOTAL_ITEMS} packages)"$'\n\n'"${INSTRUCTION}"$'\n'
      printf "%s" "$RAW_NOTICE" > "$NOTICE_FILE"
    fi
  fi
else
  if [[ -f "$NOTICE_FILE" ]]; then
    rm -f "$NOTICE_FILE"
  fi
fi

# Update lastUpdateCheck in lock file safely using jq or python3
NOW_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
if command -v jq >/dev/null 2>&1; then
  TMP_LOCK="${LOCK_FILE}.tmp.$$"
  if jq --arg now "$NOW_UTC" '.lastUpdateCheck = $now' "$LOCK_FILE" > "$TMP_LOCK" 2>/dev/null; then
    mv "$TMP_LOCK" "$LOCK_FILE"
  else
    rm -f "$TMP_LOCK"
    echo "Warning: jq failed to update lock file" >&2
  fi
elif command -v python3 >/dev/null 2>&1; then
  TMP_LOCK="${LOCK_FILE}.tmp.$$"
  if python3 -c "
import json, sys, os
path = sys.argv[1]
tmp = sys.argv[2]
now_str = sys.argv[3]
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    data['lastUpdateCheck'] = now_str
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)
except Exception as e:
    sys.stderr.write(f'Warning: python3 lock update failed: {e}\n')
    if os.path.exists(tmp):
        try: os.remove(tmp)
        except Exception: pass
    sys.exit(1)
" "$LOCK_FILE" "$TMP_LOCK" "$NOW_UTC"; then
    :
  else
    echo "Warning: python3 failed to update lock file" >&2
  fi
else
  echo "Warning: neither jq nor python3 is available; sen.lock.json lastUpdateCheck was not updated." >&2
fi

exit 0
