#!/usr/bin/env bash
# 04 - live failover watcher (the on-screen visual).
# Polls an endpoint once a second and prints state continuously, so during a
# portal-triggered forced failover the audience sees reads keep flowing and the
# serving node change as a standby is promoted.
#
#   scripts/04-failover-watch.sh        # reader endpoint (default; reads usually never drop)
#   scripts/04-failover-watch.sh rw     # read/write endpoint (shows the brief write gap)
#
# Failover itself is triggered in the portal: cluster -> High availability -> forced failover.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
need psql

if [[ "${1:-ro}" == "rw" ]]; then CONN="$(rw_conn) connect_timeout=2"; LABEL="read/write ($RW_ENDPOINT)"
else CONN="$(ro_conn) connect_timeout=2"; LABEL="reader ($RO_ENDPOINT)"; fi

echo "Polling $LABEL once/sec. Trigger the failover in the portal. Ctrl-C to stop."
echo "state: WRITABLE=primary  RO=in recovery  DOWN=no connection"
echo "--------------------------------------------------------------------------"
while true; do
  ts="$(date '+%H:%M:%S')"
  if out="$(psql "$CONN" -tAq -c "select coalesce(host(inet_server_addr()),'?')||'|'||pg_is_in_recovery()" 2>/dev/null)"; then
    ip="${out%%|*}"; rec="${out##*|}"
    [[ "$rec" == "f" ]] && st="WRITABLE" || st="RO      "
    echo "$ts  $st node=$ip"
  else
    echo "$ts  DOWN"
  fi
  sleep 1
done
