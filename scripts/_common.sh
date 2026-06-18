#!/usr/bin/env bash
# Sourced by the other scripts. Loads .env, sets the subscription, builds psql
# connection strings, and provides shared helpers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "$REPO_ROOT/.env"; set +a
else
  echo "ERROR: no .env file found." >&2
  echo "Fresh deploy:     cp .env.example .env  (then edit it)" >&2
  echo "Existing cluster: ./scripts/bootstrap-env.sh  (rebuilds .env from Azure)" >&2
  exit 1
fi

: "${DB_NAME:=postgres}"
export PGPASSWORD="${ADMIN_PASSWORD:-}"

# HorizonDB requires TLS, so sslmode=require on every connection.
rw_conn() {
  : "${ADMIN_USER:?ADMIN_USER not set in .env}" "${ADMIN_PASSWORD:?ADMIN_PASSWORD not set in .env}"
  echo "host=${RW_ENDPOINT:?RW_ENDPOINT not set} port=5432 dbname=$DB_NAME user=$ADMIN_USER sslmode=require"
}
ro_conn() {
  : "${ADMIN_USER:?ADMIN_USER not set in .env}" "${ADMIN_PASSWORD:?ADMIN_PASSWORD not set in .env}"
  echo "host=${RO_ENDPOINT:?RO_ENDPOINT not set} port=5432 dbname=$DB_NAME user=$ADMIN_USER sslmode=require"
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found on PATH." >&2; exit 1; }; }

# Switch to the subscription named in .env (if any) and print the active one.
# A wrong active subscription is the #1 cause of confusing AuthorizationFailed errors.
ensure_subscription() {
  need az
  if [[ -n "${SUBSCRIPTION:-}" ]]; then
    az account set --subscription "$SUBSCRIPTION" 2>/dev/null \
      || { echo "ERROR: couldn't switch to SUBSCRIPTION='$SUBSCRIPTION'. Check the name/id and your access (run 'az login')." >&2; exit 1; }
  fi
  local sub
  sub="$(az account show --query name -o tsv 2>/dev/null || true)"
  [[ -n "$sub" ]] || { echo "ERROR: not logged in. Run 'az login'." >&2; exit 1; }
  echo "Active subscription: $sub"
  if [[ -z "${SUBSCRIPTION:-}" ]]; then
    echo "(Tip: set SUBSCRIPTION in .env to pin this and skip manual 'az account set'.)"
  fi
}

# Write the two endpoints into .env in place (used after deploy / bootstrap).
write_endpoints_to_env() {
  local rw="$1" ro="$2" envfile="$REPO_ROOT/.env"
  grep -q '^RW_ENDPOINT=' "$envfile" && sed -i.bak "s|^RW_ENDPOINT=.*|RW_ENDPOINT=$rw|" "$envfile" || echo "RW_ENDPOINT=$rw" >> "$envfile"
  grep -q '^RO_ENDPOINT=' "$envfile" && sed -i.bak "s|^RO_ENDPOINT=.*|RO_ENDPOINT=$ro|" "$envfile" || echo "RO_ENDPOINT=$ro" >> "$envfile"
  rm -f "$envfile.bak"
}
