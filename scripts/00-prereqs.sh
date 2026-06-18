#!/usr/bin/env bash
# 00 - check tools, set the subscription, install the extension, register the provider.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
need az; need psql

echo "== Azure CLI =="
az version -o table 2>/dev/null || az version

echo; echo "== Subscription =="
ensure_subscription

echo; echo "== horizondb CLI extension =="
az config set extension.use_dynamic_install=yes_without_prompt >/dev/null 2>&1
az config set extension.dynamic_install_allow_preview=true   >/dev/null 2>&1
az extension add --name horizondb --allow-preview >/dev/null 2>&1 \
  || az extension add --name horizondb >/dev/null 2>&1 \
  || echo "(extension will auto-install on first 'az horizondb' call)"
echo "ready."

echo; echo "== Resource provider registration =="
state="$(az provider show --namespace Microsoft.HorizonDb --query registrationState -o tsv 2>/dev/null || echo NotRegistered)"
if [[ "$state" == "Registered" ]]; then
  echo "Microsoft.HorizonDb: Registered"
else
  echo "Registering Microsoft.HorizonDb (current: $state)..."
  if ! err="$(az provider register --namespace Microsoft.HorizonDb 2>&1)"; then
    if grep -q "AuthorizationFailed" <<<"$err"; then
      cat >&2 <<MSG

ERROR: your account can't register resource providers on this subscription.
Fix one of these, then re-run:
  - set SUBSCRIPTION in .env to a subscription where you have rights, OR
  - ask a subscription Owner to run:
      az provider register --namespace Microsoft.HorizonDb
MSG
      exit 1
    fi
    echo "$err" >&2; exit 1
  fi
  echo -n "Waiting for registration"
  for _ in $(seq 1 30); do
    state="$(az provider show --namespace Microsoft.HorizonDb --query registrationState -o tsv 2>/dev/null || echo Unknown)"
    [[ "$state" == "Registered" ]] && break
    echo -n "."; sleep 10
  done
  echo; echo "Microsoft.HorizonDb: $state"
fi
[[ "${state:-}" == "Registered" ]] && echo "Prereqs OK." || { echo "Not registered yet; re-run in a minute."; exit 1; }
