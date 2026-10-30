#!/usr/bin/env bash
set -euo pipefail
RUN_ID="${VERIFY_RUN_ID:-}"
PIDFILE="${1:-}"
if [[ -n "$PIDFILE" && -f "$PIDFILE" ]]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
  echo "stopped $PIDFILE"
  exit 0
fi
if [[ -n "$RUN_ID" && -f "/tmp/milk-tea-verify-$RUN_ID.pid" ]]; then
  kill "$(cat /tmp/milk-tea-verify-$RUN_ID.pid)" 2>/dev/null || true
  rm -f "/tmp/milk-tea-verify-$RUN_ID.pid"
  echo "stopped run $RUN_ID"
  exit 0
fi
echo "usage: cleanup.sh <pidfile>   OR set VERIFY_RUN_ID" >&2
exit 2
