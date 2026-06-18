#!/usr/bin/env bash
# 04 - live failover watcher with timing.
# Prints, in plain language, whether the endpoint is serving - once a second -
# and when a failover interrupts it, prints a highlighted line with how long
# service was unavailable. That recovery line is the number to show on camera.
#
#   scripts/04-failover-watch.sh        # reader endpoint (default): reads usually never drop
#   scripts/04-failover-watch.sh rw     # read/write endpoint: shows + times the write gap
#
# Failover is triggered in the portal: cluster -> High availability -> forced failover.
# Timing resolution is ~1-2s (one poll + connect timeout). For sub-second precision
# use scripts/06-failover-measure.py.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
need psql

if [[ "${1:-ro}" == "rw" ]]; then
  CONN="$(rw_conn) connect_timeout=2"; WHICH="read/write endpoint"; MODE=rw
else
  CONN="$(ro_conn) connect_timeout=2"; WHICH="reader endpoint"; MODE=ro
fi

echo "Watching the $WHICH once/sec. Trigger the failover in the portal. Ctrl-C to stop."
echo "------------------------------------------------------------------------------"

serving=init        # whether the endpoint is doing its job (rw: writable; ro: reachable)
down_at=0
while true; do
  ts="$(date '+%H:%M:%S')"; now="$(date +%s)"
  if rec="$(psql "$CONN" -tAq -c "select pg_is_in_recovery()" 2>/dev/null)"; then
    if [[ "$rec" == "f" ]]; then line="up   - primary, accepting writes"; ok=1
    else                        line="up   - replica, serving reads";     ok=$([[ "$MODE" == rw ]] && echo 0 || echo 1); fi
  else
    line="DOWN - not reachable"; ok=0
  fi

  # detect transitions and time the outage
  if [[ "$ok" == 1 ]]; then
    if [[ "$serving" == 0 ]]; then
      gap=$(( now - down_at ))
      echo ">>>>>> FAILOVER: $WHICH was unavailable for ~${gap}s <<<<<<"
    fi
    serving=1
  else
    [[ "$serving" != 0 ]] && down_at="$now"
    serving=0
  fi

  echo "$ts   $line"
  sleep 1
done
