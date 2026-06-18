#!/usr/bin/env bash
# 02 - create the schema and load synthetic data via the READ/WRITE endpoint.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
need psql

: "${CUSTOMERS:=50000}" "${PRODUCTS:=1000}" "${ORDERS:=500000}"
CONN="$(rw_conn)"

echo "Creating schema on the read/write endpoint..."
psql "$CONN" -v ON_ERROR_STOP=1 -f "$REPO_ROOT/sql/schema.sql"

echo "Seeding data (customers=$CUSTOMERS products=$PRODUCTS orders=$ORDERS)..."
psql "$CONN" -v ON_ERROR_STOP=1 \
  -v customers="$CUSTOMERS" -v products="$PRODUCTS" -v orders="$ORDERS" \
  -f "$REPO_ROOT/sql/seed.sql"

echo "Done. Next: scripts/03-read-from-replica.sh"
