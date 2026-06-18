#!/usr/bin/env bash
# 05 - quick failover timer. Probes the read/write endpoint back-to-back and
# prints ONLY state changes, each with how long the previous state lasted.
# The "(was DOWN for N ms)" line on recovery is your failover number.
#
#   scripts/05-failover-timer.sh        # read/write endpoint (default)
#   scripts/05-failover-timer.sh ro     # reader endpoint
#
# Run it, wait for the first '-> WRITABLE', then trigger a forced failover in the portal.
# Resolution is bounded by libpq's ~2s connect-timeout floor, so quote "~N s", not exact ms.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
need psql

if [[ "${1:-rw}" == "ro" ]]; then CONN="$(ro_conn) connect_timeout=2"; LABEL="reader"
else CONN="$(rw_conn) connect_timeout=2"; LABEL="read/write"; fi

echo "Timing the $LABEL path. Wait for '-> WRITABLE', then force the failover in the portal. Ctrl-C to stop."
state=init; t0=0
while true; do
  now=$(date +%s%3N); ts=$(date '+%H:%M:%S.%3N')
  if out=$(psql "$CONN" -tAq -c "select pg_is_in_recovery()" 2>/dev/null); then
    [[ "$out" == "f" ]] && new=WRITABLE || new=READONLY
  else
    new=DOWN
  fi
  if [[ "$new" != "$state" ]]; then
    if [[ "$state" != init ]]; then
      echo "$ts  -> $new   (was $state for $((now - t0)) ms)"
    else
      echo "$ts  -> $new"
    fi
    state=$new; t0=$now
  fi
done
