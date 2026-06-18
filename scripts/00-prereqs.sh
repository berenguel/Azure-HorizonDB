#!/usr/bin/env bash
# 00 - check tools, log in state, the horizondb extension, and the resource provider.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found on PATH." >&2; exit 1; }; }
need az
need psql

echo "== Azure CLI =="
az version -o table 2>/dev/null || az version

echo
echo "== Account =="
az account show --query "{subscription:name, id:id, user:user.name}" -o table \
  || { echo "Not logged in. Run 'az login'."; exit 1; }
echo "If that's not the subscription you want to bill, run: az account set --subscription <name-or-id>"

echo
echo "== horizondb CLI extension =="
# The extension is preview-only, so allow preview installs and skip the prompt.
az config set extension.use_dynamic_install=yes_without_prompt >/dev/null
az config set extension.dynamic_install_allow_preview=true >/dev/null
az extension add --name horizondb --allow-preview 2>/dev/null \
  || az extension add --name horizondb 2>/dev/null \
  || echo "(extension will auto-install on first 'az horizondb' call)"

echo
echo "== Resource provider registration =="
# Required once per subscription, even in public preview.
state="$(az provider show --namespace Microsoft.HorizonDb --query registrationState -o tsv 2>/dev/null || echo NotRegistered)"
if [[ "$state" != "Registered" ]]; then
  echo "Registering Microsoft.HorizonDb (current: $state)..."
  az provider register --namespace Microsoft.HorizonDb
  echo -n "Waiting for registration"
  for _ in $(seq 1 30); do
    state="$(az provider show --namespace Microsoft.HorizonDb --query registrationState -o tsv 2>/dev/null || echo Unknown)"
    [[ "$state" == "Registered" ]] && break
    echo -n "."; sleep 10
  done
  echo
fi
echo "Microsoft.HorizonDb: $state"
[[ "$state" == "Registered" ]] && echo "Prereqs OK." || echo "Provider not registered yet; re-run this script in a minute."
