#!/usr/bin/env bash
# 01 - deploy a HorizonDB cluster via the CLI, then write its endpoints into .env.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
need az

: "${RESOURCE_GROUP:?}" "${LOCATION:?}" "${CLUSTER_NAME:?}"
: "${PG_VERSION:=17}" "${VCORES:=2}" "${REPLICA_COUNT:=2}" "${ZONE_PLACEMENT:=Strict}"

confirm_subscription
echo "Deploying '$CLUSTER_NAME' to '$LOCATION' in resource group '$RESOURCE_GROUP'."

az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none

echo "Creating HorizonDB cluster (several minutes)..."
az horizondb create \
  --name "$CLUSTER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --administrator-login "$ADMIN_USER" \
  --administrator-login-password "$ADMIN_PASSWORD" \
  --version "$PG_VERSION" \
  --v-cores "$VCORES" \
  --replica-count "$REPLICA_COUNT" \
  --zone-placement-policy "$ZONE_PLACEMENT"

echo "Reading endpoints..."
RW="$(az horizondb show -n "$CLUSTER_NAME" -g "$RESOURCE_GROUP" --query properties.fullyQualifiedDomainName -o tsv)"
RO="$(az horizondb show -n "$CLUSTER_NAME" -g "$RESOURCE_GROUP" --query properties.readonlyEndpoint -o tsv)"
write_endpoints_to_env "$RW" "$RO"
echo "Wrote endpoints into .env:"
echo "  RW_ENDPOINT=$RW"
echo "  RO_ENDPOINT=$RO"

cat <<'EOF'

NEXT:
  1) Open the cluster's Networking page in the portal, enable public access,
     and add a firewall rule for your client IP. (Networking is portal-only;
     the CLI extension doesn't expose it yet. Get your IP: curl -s ifconfig.me)
  2) Test the connection:
       source .env && export PGPASSWORD="$ADMIN_PASSWORD"
       psql "host=$RW_ENDPOINT port=5432 dbname=$DB_NAME user=$ADMIN_USER sslmode=require" -c "select version();"
  3) Load data:  ./scripts/02-load-data.sh
EOF
