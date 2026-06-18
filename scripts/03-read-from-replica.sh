#!/usr/bin/env bash
# 03 - read from a replica via the READER endpoint, then prove it's read-only.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
need psql

CONN="$(ro_conn)"

echo "Running analytics against the reader endpoint ($RO_ENDPOINT)..."
psql "$CONN" -v ON_ERROR_STOP=1 -f "$REPO_ROOT/sql/read-queries.sql"

echo
echo "Now proving the reader endpoint is read-only (this INSERT should fail):"
set +e
psql "$CONN" -c "INSERT INTO products (sku, name, category, unit_price) VALUES ('SKU-TEST','Should Fail','Home',1.00);"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo ">> Good: the write was rejected on the reader endpoint, as expected."
else
  echo ">> Unexpected: the write succeeded. Check that you used the READER endpoint."
fi
