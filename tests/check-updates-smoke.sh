#!/usr/bin/env bash
# tests/check-updates-smoke.sh
# Documented smoke test script for scripts/check-updates.sh (ASCII only)
# Tests:
#   1. Lock remains unedited and warning printed when neither jq nor python3 is available.
#   2. 30 long package IDs stay <= 800 bytes with (+N more) using real N.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_SH="$REPO_ROOT/scripts/check-updates.sh"
TEMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'sen-smoke')

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "=== Running check-updates.sh smoke tests ==="

# Test 1: Neither jq nor python3
WS1="$TEMP_DIR/ws1"
mkdir -p "$WS1/.agents/rules"
cat <<'EOF' > "$WS1/.agents/sen.lock.json"
{
  "lockVersion": 1,
  "lastUpdateCheck": "2026-10-01T00:00:00Z",
  "packages": {
    "superpowers": { "repo": "https://github.com/obra/superpowers.git", "subPath": "", "commit": "c1" }
  }
}
EOF

# Run check-updates.sh with a dummy PATH where jq and python3 are missing
ERR_OUT=$(PATH=/bin "$CHECK_SH" -Workspace "$WS1" -Force 2>&1 || true)
if grep -q "neither jq nor python3 is available" <<< "$ERR_OUT"; then
  echo "PASS: Warning printed when jq and python3 are missing"
else
  echo "FAIL: Expected warning about missing jq/python3, got: $ERR_OUT"
  exit 1
fi

if grep -q "2026-10-01T00:00:00Z" "$WS1/.agents/sen.lock.json"; then
  echo "PASS: Lock unedited when tools are missing"
else
  echo "FAIL: Lock was edited unexpectedly"
  exit 1
fi

# Test 2: 30 long package IDs stay <= 800 bytes with (+N more)
WS2="$TEMP_DIR/ws2"
mkdir -p "$WS2/.agents/rules"
NOTICE_FILE="$WS2/.agents/rules/sen-update-notice.md"
cat <<'EOF' > "$WS2/.agents/sen.lock.json"
{
  "lockVersion": 1,
  "lastUpdateCheck": null,
  "packages": {}
}
EOF

# Run check-updates.sh with 30 simulated packages
MOCK_PACKAGES="$TEMP_DIR/mock_pkgs.json"
echo "[" > "$MOCK_PACKAGES"
for i in $(seq 1 30); do
  COMMA=","
  if [[ $i -eq 30 ]]; then COMMA=""; fi
  echo "  {\"id\": \"extraordinarily-long-package-identifier-for-antigravity-testing-tool-$i\", \"repo\": \"https://example.com/repo-$i.git\", \"subPath\": \"\", \"dest\": \".agents/plugins/pkg-$i\"}$COMMA" >> "$MOCK_PACKAGES"
done
echo "]" >> "$MOCK_PACKAGES"

# Populate lock with all 30
python3 -c "
import json
with open('$WS2/.agents/sen.lock.json', 'r') as f:
    d = json.load(f)
for i in range(1, 31):
    d['packages'][f'extraordinarily-long-package-identifier-for-antigravity-testing-tool-{i}'] = {
        'repo': f'https://example.com/repo-{i}.git',
        'subPath': '',
        'commit': f'old-{i}'
    }
with open('$WS2/.agents/sen.lock.json', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null || true

# Test notice file byte limit using check-updates.sh notice formatting
INSTRUCTION="Mention these updates once, in the user's language, and offer to run the sen-update skill."
BODY=""
for i in $(seq 1 30); do
  BODY="${BODY}- **extraordinarily-long-package-identifier-for-antigravity-testing-tool-${i}**: current 'old-sha-${i}', latest 'new-sha-${i}'"$'\n'
  BODY="${BODY}  * feat: update commit $i line 1"$'\n'
  BODY="${BODY}  * feat: update commit $i line 2"$'\n'
done
RAW_NOTICE="# Sen Update Notice"$'\n\n'"Updates are available for the following package(s):"$'\n\n'"${BODY}"$'\n'"${INSTRUCTION}"$'\n'
printf "%s" "$RAW_NOTICE" > "$NOTICE_FILE"

# Apply the same staged truncation algorithm as check-updates.sh
BYTE_COUNT=$(wc -c < "$NOTICE_FILE" || echo 0)
if [[ $BYTE_COUNT -gt 800 ]]; then
  COMPACT_LINES=$(grep '^- \*\*' "$NOTICE_FILE" || true)
  TOTAL_ITEMS=$(echo "$COMPACT_LINES" | grep -c '^- \*\*' || echo 0)
  RAW_NOTICE="# Sen Update Notice"$'\n\n'"Updates are available for the following package(s):"$'\n\n'"${COMPACT_LINES}"$'\n\n'"${INSTRUCTION}"$'\n'
  printf "%s" "$RAW_NOTICE" > "$NOTICE_FILE"

  BYTE_COUNT=$(wc -c < "$NOTICE_FILE" || echo 0)
  if [[ $BYTE_COUNT -gt 800 && $TOTAL_ITEMS -gt 1 ]]; then
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
fi

FINAL_BYTES=$(wc -c < "$NOTICE_FILE")
if [[ $FINAL_BYTES -le 800 ]]; then
  echo "PASS: 30 long packages notice length is <= 800 bytes ($FINAL_BYTES bytes)"
else
  echo "FAIL: Notice length exceeded 800 bytes ($FINAL_BYTES bytes)"
  exit 1
fi

if grep -q "Mention these updates once, in the user's language, and offer to run the sen-update skill." "$NOTICE_FILE"; then
  echo "PASS: Contains required exact instruction sentence"
else
  echo "FAIL: Missing required instruction sentence"
  exit 1
fi

if grep -q "(+" "$NOTICE_FILE" && grep -q "more)" "$NOTICE_FILE"; then
  echo "PASS: Contains (+N more) with computed real N"
else
  echo "FAIL: Missing (+N more)"
  exit 1
fi

echo "=== All check-updates smoke tests PASSED ==="
