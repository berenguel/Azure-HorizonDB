#!/usr/bin/env bash
# 99 - tear everything down so a preview cluster doesn't keep billing.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
need az

: "${RESOURCE_GROUP:?}" "${CLUSTER_NAME:?}"

read -r -p "Delete cluster '$CLUSTER_NAME' and resource group '$RESOURCE_GROUP'? [y/N] " ans
[[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Aborted."; exit 0; }

echo "Deleting cluster..."
az horizondb delete --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --yes || true

echo "Deleting resource group (async)..."
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo "Teardown started. The resource group will finish deleting in the background."
