#!/usr/bin/env bash
# scripts/uninstall.sh
# Pure ASCII script to cleanly unregister Sen crontab entry and remove plugin directory if requested

set -euo pipefail

WORKSPACE="${1:-$PWD}"
REMOVE_DIR="${2:-}"

WS_ABS="$(cd "$WORKSPACE" && pwd)"

if command -v crontab >/dev/null 2>&1; then
  (crontab -l 2>/dev/null | grep -v "SenWeeklyUpdateCheck:$WS_ABS" || true) | crontab - 2>/dev/null || true
fi

if [ "$REMOVE_DIR" = "--remove-plugin" ] && [ -d "$WS_ABS/.agents/plugins/sen-method" ]; then
  rm -rf "$WS_ABS/.agents/plugins/sen-method"
fi

echo "Uninstalled Sen scheduled tasks and harness hooks for $WS_ABS"
