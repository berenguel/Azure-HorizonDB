#!/usr/bin/env bash
# Sourced by the other scripts. Loads .env, builds psql connection strings,
# and provides a couple of shared helpers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "$REPO_ROOT/.env"; set +a
else
  echo "ERROR: no .env file found." >&2
  echo "Fresh deploy:   cp .env.example .env  (then edit it)" >&2
  echo "Existing cluster: ./scripts/bootstrap-env.sh  (rebuilds .env from Azure)" >&2
  exit 1
fi

: "${DB_NAME:=postgres}"
: "${ADMIN_USER:?ADMIN_USER not set in .env}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD not set in .env}"

# Export so plain psql calls in these scripts never prompt for a password.
export PGPASSWORD="$ADMIN_PASSWORD"

# HorizonDB requires TLS, so sslmode=require on every connection.
rw_conn() { echo "host=${RW_ENDPOINT:?RW_ENDPOINT not set} port=5432 dbname=$DB_NAME user=$ADMIN_USER sslmode=require"; }
ro_conn() { echo "host=${RO_ENDPOINT:?RO_ENDPOINT not set} port=5432 dbname=$DB_NAME user=$ADMIN_USER sslmode=require"; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found on PATH." >&2; exit 1; }; }

# Confirm the active subscription before doing anything destructive or stateful.
# A wrong active subscription shows up later as a misleading AuthorizationFailed.
confirm_subscription() {
  local sub
  sub="$(az account show --query name -o tsv 2>/dev/null || true)"
  if [[ -z "$sub" ]]; then
    echo "ERROR: not logged in. Run 'az login'." >&2; exit 1
  fi
  echo "Active subscription: $sub"
}

# Write the two endpoints into .env in place (used after deploy / bootstrap).
write_endpoints_to_env() {
  local rw="$1" ro="$2" envfile="$REPO_ROOT/.env"
  if grep -q '^RW_ENDPOINT=' "$envfile"; then
    sed -i.bak "s|^RW_ENDPOINT=.*|RW_ENDPOINT=$rw|" "$envfile"
  else
    echo "RW_ENDPOINT=$rw" >> "$envfile"
  fi
  if grep -q '^RO_ENDPOINT=' "$envfile"; then
    sed -i.bak "s|^RO_ENDPOINT=.*|RO_ENDPOINT=$ro|" "$envfile"
  else
    echo "RO_ENDPOINT=$ro" >> "$envfile"
  fi
  rm -f "$envfile.bak"
}
