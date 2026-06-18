#!/usr/bin/env bash
# bootstrap-env.sh - (re)build .env from an EXISTING cluster.
# Use this in Cloud Shell after a disconnect, or any time .env is missing but
# the cluster is already deployed. Endpoints are pulled live from Azure.
#
# Azure does NOT return the admin login or password (both are write-only and
# come back null from 'az horizondb show'), so you must supply them yourself.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
command -v az >/dev/null || { echo "az not found"; exit 1; }

RG="${1:-${RESOURCE_GROUP:-rg-horizon-demo}}"
CL="${2:-${CLUSTER_NAME:-horizon-demo}}"

echo "Active subscription: $(az account show --query name -o tsv)"
echo "Cluster: $CL  /  Resource group: $RG"
echo "(override with: ./scripts/bootstrap-env.sh <resource-group> <cluster-name>)"
echo

LOC="$(az horizondb show -n "$CL" -g "$RG" --query location -o tsv)"
RW="$(az horizondb show -n "$CL" -g "$RG" --query properties.fullyQualifiedDomainName -o tsv)"
RO="$(az horizondb show -n "$CL" -g "$RG" --query properties.readonlyEndpoint -o tsv)"
VER="$(az horizondb show -n "$CL" -g "$RG" --query properties.version -o tsv)"
[[ -n "$RW" ]] || { echo "Could not read endpoints. Check the subscription, RG, and cluster name."; exit 1; }

read -r -p "Admin username you deployed with: " ADMIN_USER
read -r -s -p "Admin password you deployed with: " ADMIN_PASSWORD; echo

cat > "$REPO_ROOT/.env" <<EOF
RESOURCE_GROUP=$RG
LOCATION=$LOC
CLUSTER_NAME=$CL
ADMIN_USER=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASSWORD
PG_VERSION=$VER
VCORES=2
REPLICA_COUNT=2
ZONE_PLACEMENT=Strict
RW_ENDPOINT=$RW
RO_ENDPOINT=$RO
DB_NAME=postgres
CUSTOMERS=50000
PRODUCTS=1000
ORDERS=500000
EOF

echo "Wrote .env:"
grep -E 'RESOURCE_GROUP|LOCATION|CLUSTER_NAME|ADMIN_USER|ENDPOINT' "$REPO_ROOT/.env"
echo
echo "Test it: psql \"host=$RW port=5432 dbname=postgres user=$ADMIN_USER sslmode=require\" -c 'select version();'"
