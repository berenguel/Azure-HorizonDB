#!/usr/bin/env python3
"""
05 - measure failover time precisely.

Holds a persistent connection to an endpoint and probes it in a tight loop,
timing the exact window where the WRITE path is unavailable during a failover.
Reconnects fast (short timeouts + TCP keepalives) so the measured gap reflects
the failover, not a client-side hang.

Usage:
  python3 scripts/05-failover-measure.py          # measure the read/write endpoint (default)
  python3 scripts/05-failover-measure.py --ro      # watch the reader endpoint instead

Run it, then trigger a forced failover in the portal. Ctrl-C to stop and print a summary.
Reads connection settings from .env in the repo root.
"""
import os, sys, time, signal, pathlib

# --- load .env ---
ROOT = pathlib.Path(__file__).resolve().parent.parent
env = {}
envfile = ROOT / ".env"
if not envfile.exists():
    sys.exit("ERROR: .env not found. Run from the repo and fill in .env first.")
for line in envfile.read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    env[k.strip()] = v.split("#", 1)[0].strip()

use_ro = "--ro" in sys.argv
host = env["RO_ENDPOINT"] if use_ro else env["RW_ENDPOINT"]
label = "reader" if use_ro else "read/write"
user = env.get("ADMIN_USER", "pgadmin")
pw = env.get("ADMIN_PASSWORD", "")
db = env.get("DB_NAME", "postgres")
if not host:
    sys.exit(f"ERROR: {'RO_ENDPOINT' if use_ro else 'RW_ENDPOINT'} is empty in .env")

# --- pick a driver ---
conninfo = (f"host={host} port=5432 dbname={db} user={user} password={pw} "
            f"sslmode=require connect_timeout=2 "
            f"keepalives=1 keepalives_idle=1 keepalives_interval=1 keepalives_count=1")
try:
    import psycopg                     # v3
    def connect(): return psycopg.connect(conninfo, autocommit=True)
except ImportError:
    try:
        import psycopg2                # v2
        def connect(): c = psycopg2.connect(conninfo); c.autocommit = True; return c
    except ImportError:
        sys.exit("ERROR: need psycopg or psycopg2. Try: pip install --user 'psycopg[binary]'")

PROBE = "SELECT inet_server_addr()::text, pg_is_in_recovery()"

def now_ms(): return time.monotonic() * 1000.0
def clk(): return time.strftime("%H:%M:%S") + f".{int((time.time()%1)*1000):03d}"

print(f"Measuring the {label} endpoint ({host}). Trigger the forced failover in the portal now.")
print("State: UP = writable primary serving | RO = connected but in recovery | DOWN = no connection")
print("-" * 78)

events = []                 # (downtime_ms, from_ip, to_ip)
total_down = 0.0
running = True

def summary(*_):
    global running
    running = False
signal.signal(signal.SIGINT, summary)

conn = None
last_up_ms = None           # monotonic time of last UP probe
last_ip = None
gap_open_ip = None          # ip seen just before the gap
was_down = False

while running:
    state = "DOWN"; ip = "-"; rec = "-"
    try:
        if conn is None:
            conn = connect()
        cur = conn.cursor()
        cur.execute(PROBE)
        row = cur.fetchone()
        ip = row[0] or "(local)"
        rec = "t" if row[1] else "f"
        state = "UP" if row[1] is False else "RO"
    except Exception as e:
        state = "DOWN"
        try:
            if conn: conn.close()
        except Exception:
            pass
        conn = None

    t = now_ms()
    if state == "UP":
        if was_down and last_up_ms is not None:
            gap = t - last_up_ms
            total_down += gap
            events.append((gap, gap_open_ip, ip))
            print(f"{clk()}  >> {label} path RECOVERED after ~{gap:.0f} ms "
                  f"(was {gap_open_ip} -> now {ip})")
            was_down = False
        last_up_ms = t
        last_ip = ip
    else:
        if not was_down:
            gap_open_ip = last_ip or "?"
            print(f"{clk()}  -- {state}: {label} path interrupted "
                  f"(last good node {gap_open_ip})")
        was_down = True

    # quiet heartbeat every ~1s so you can see it's alive without spamming
    if int(t) % 1000 < 60 and state in ("UP", "RO"):
        print(f"{clk()}  {state:4} node={ip} in_recovery={rec}")

    time.sleep(0.05)

print("-" * 78)
if events:
    print(f"Failover events observed: {len(events)}")
    for i, (g, a, b) in enumerate(events, 1):
        print(f"  {i}. {label} unavailable ~{g:.0f} ms   {a} -> {b}")
    print(f"Total measured {label}-path downtime: ~{total_down:.0f} ms")
else:
    print(f"No {label}-path interruption observed (reads often stay up through failover).")
print("Note: resolution is bounded by the ~50 ms probe loop plus TLS reconnect cost.")
