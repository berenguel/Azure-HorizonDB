#!/usr/bin/env bash
# 01 - deploy a HorizonDB cluster via the CLI, then write its endpoints into .env.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
need az

: "${RESOURCE_GROUP:?}" "${LOCATION:?}" "${CLUSTER_NAME:?}"
: "${PG_VERSION:=17}" "${VCORES:=2}" "${REPLICA_COUNT:=2}" "${ZONE_PLACEMENT:=Strict}"
: "${ADMIN_USER:?ADMIN_USER not set in .env}" "${ADMIN_PASSWORD:?ADMIN_PASSWORD not set in .env}"

ensure_subscription

# If the resource group already exists, reuse its region (its location is fixed).
existing_loc="$(az group show --name "$RESOURCE_GROUP" --query location -o tsv 2>/dev/null || true)"
if [[ -n "$existing_loc" ]]; then
  if [[ "$existing_loc" != "$LOCATION" ]]; then
    echo "Note: resource group '$RESOURCE_GROUP' already exists in '$existing_loc'."
    echo "      Using that region and ignoring LOCATION=$LOCATION from .env."
    LOCATION="$existing_loc"
  fi
else
  echo "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none
fi

echo "Deploying cluster '$CLUSTER_NAME' to '$LOCATION' (several minutes)..."
az horizondb create \
  --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" \
  --administrator-login "$ADMIN_USER" --administrator-login-password "$ADMIN_PASSWORD" \
  --version "$PG_VERSION" --v-cores "$VCORES" \
  --replica-count "$REPLICA_COUNT" --zone-placement-policy "$ZONE_PLACEMENT"

echo "Reading endpoints..."
RW="$(az horizondb show -n "$CLUSTER_NAME" -g "$RESOURCE_GROUP" --query properties.fullyQualifiedDomainName -o tsv)"
RO="$(az horizondb show -n "$CLUSTER_NAME" -g "$RESOURCE_GROUP" --query properties.readonlyEndpoint -o tsv)"
write_endpoints_to_env "$RW" "$RO"
echo "Wrote endpoints into .env:"; echo "  RW_ENDPOINT=$RW"; echo "  RO_ENDPOINT=$RO"

cat <<'EOF'

NEXT (the one manual step that can't be scripted):
  Open the cluster's Networking page in the portal, enable public access, and add
  a firewall rule for your client IP (curl -s ifconfig.me). The CLI can't do this yet.
Then:  ./scripts/02-load-data.sh
EOF
