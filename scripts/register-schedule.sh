#!/usr/bin/env bash
# scripts/register-schedule.sh
# Pure ASCII POSIX script to register weekly Sen update check in crontab

set -euo pipefail

WORKSPACE="${1:-$PWD}"
DRY_RUN="${2:-}"

if printf '%s' "$WORKSPACE" | grep -Eq '["'\''`$;|&<>]' || [ "$(printf '%s' "$WORKSPACE" | wc -l)" -gt 0 ]; then
  echo "Error: Invalid WORKSPACE path containing shell metacharacters." >&2
  exit 1
fi

WS_ABS="$(cd "$WORKSPACE" && pwd)"
CHECK_SCRIPT="$WS_ABS/.agents/plugins/sen-method/scripts/check-updates.sh"
if [ ! -f "$CHECK_SCRIPT" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CHECK_SCRIPT="$SCRIPT_DIR/check-updates.sh"
fi

if printf '%s' "$WS_ABS $CHECK_SCRIPT" | grep -Eq '["'\''`$;|&<>]'; then
  echo "Error: Invalid resolved path containing shell metacharacters." >&2
  exit 1
fi

CRON_LINE="0 9 * * 1 bash \"$CHECK_SCRIPT\" \"$WS_ABS\" >/dev/null 2>&1 # SenWeeklyUpdateCheck:$WS_ABS"

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "DryRun: Would register crontab entry: $CRON_LINE"
  exit 0
fi

if command -v crontab >/dev/null 2>&1; then
  (crontab -l 2>/dev/null | grep -v "SenWeeklyUpdateCheck:$WS_ABS" || true; echo "$CRON_LINE") | crontab -
  echo "Registered weekly crontab check for $WS_ABS"
else
  echo "crontab not found; skipping schedule registration."
fi
