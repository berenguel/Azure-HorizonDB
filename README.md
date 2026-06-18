# Intro to Azure HorizonDB

A short, runnable demo for getting started with **Azure HorizonDB**: deploy a cluster, load data, read from a replica, and survive a failover — proven end to end on a live cluster.

> Azure HorizonDB is in **public preview**. Resource provider `Microsoft.HorizonDb`, API `2026-01-20-preview`. Region availability and the CLI surface change often — pin a tested region and dry-run the whole thing before pointing a customer at it.

---

## What this demonstrates

| Step | What you show | How |
| ---- | ------------- | --- |
| 1 | Deploy a cluster with replicas | CLI (`az horizondb create`) or the button below |
| 2 | Load a synthetic storefront | `psql` against the **read/write** endpoint |
| 3 | Read scale-out from a replica | `psql` against the **reader** endpoint (and watch a write get rejected) |
| 4 | Failover with no read downtime | Force it in the portal; time it from Cloud Shell |

The replicas you provision in step 1 are the same nodes that serve reads in step 3 **and** stand in as failover targets in step 4 — a standby is readable and a failover candidate at once.

---

## Deploy to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fberenguel%2FAzure-HorizonDB%2Fmain%2Finfra%2Fazuredeploy.json)

After you push this repo, edit the button URL above: replace `USER`/`REPO` (and `main` if your default branch differs) so it points at your raw `infra/azuredeploy.json`. The button opens the portal's custom-deployment blade pre-loaded with the template — you supply the admin password and pick a region.

---

## Prerequisites

- **Azure CLI** and a **`psql`** client (an older `psql` against a newer server is fine — `psql` 16 talks to PG 17 here without issue).
- An Azure subscription
- Run `./scripts/00-prereqs.sh` once — it checks your tools, installs the preview `horizondb` extension, and **registers the resource provider** (required once per subscription, see below).

### Two things public preview does *not* save you from

- **Provider registration is still required.** "Public preview" removes the signup gate, but the ARM namespace must still be registered on your subscription or `create` fails with `MissingSubscriptionRegistration`:
  ```bash
  az provider register --namespace Microsoft.HorizonDb   # then wait for "Registered"
  ```

- **The extension is preview-only**, so the first `az horizondb` call prompts to install it. `00-prereqs.sh` pre-sets `extension.dynamic_install_allow_preview=true` so it installs without interrupting a deploy.

---

## Regions

Preview is live in **Central US, West US 2, West US 3, Australia East, Sweden Central**.
The failover step needs availability zones — Central US, Australia East, and Sweden Central all support them.

---

## Quickstart

### Fresh deploy

```bash
chmod +x scripts/*.sh       # a fresh clone may not carry the executable bit
cp .env.example .env        # edit the top block: subscription, region, admin user, password
./scripts/00-prereqs.sh     # subscription + tools + extension + provider registration
./scripts/01-deploy-cli.sh  # create the cluster (several minutes); writes endpoints into .env
```

Set `SUBSCRIPTION` in `.env` (subscription **ID** is simplest — no quoting) and the scripts run `az account set` for you, so you never deploy into the wrong subscription.

Then open the cluster's **Networking** page in the portal, **enable public access**, and **add a firewall rule for your client IP** (`curl -s ifconfig.me`). Networking is portal-only — the CLI extension doesn't expose it yet — so without this step `psql` can't connect.

Test the connection, then run the rest:

```bash
source .env
psql "host=$RW_ENDPOINT port=5432 dbname=$DB_NAME user=$ADMIN_USER sslmode=require" -c "select version();"

./scripts/02-load-data.sh          # schema + synthetic data (read/write endpoint)
./scripts/03-read-from-replica.sh  # analytics on the reader endpoint + proof it's read-only
./scripts/04-failover-watch.sh     # leave running, then force failover in the portal
./scripts/99-teardown.sh           # delete everything when done
```

Tune data size in `.env` (`CUSTOMERS`, `PRODUCTS`, `ORDERS`). Defaults give ~500k orders / ~1.25M line items.
For a quick first take: `CUSTOMERS=5000 PRODUCTS=200 ORDERS=50000 ./scripts/02-load-data.sh`.

### Existing cluster (or Cloud Shell after a disconnect)

Cloud Shell is ephemeral — a closed session loses your `.env`. The cluster is unaffected (it lives in Azure), so just rebuild `.env` from live state:

```bash
./scripts/bootstrap-env.sh                                   # uses rg-horizon-demo / horizon-demo
./scripts/bootstrap-env.sh <resource-group> <cluster-name>   # or name them
```

It pulls both endpoints from Azure and prompts for the admin user and password — **Azure can't return those** (both are write-only and come back `null` from `az horizondb show`), so you must remember them.

---

## Connecting: the two endpoints

| Endpoint | `az horizondb show` field | Use for |
| -------- | ------------------------- | ------- |
| Read/write | `properties.fullyQualifiedDomainName` | writes, schema changes, reads that must see the latest commit |
| Reader | `properties.readonlyEndpoint` | reporting and read scale-out; load-balances across readable HA replicas |

The reader hostname is the read/write hostname with `.ro.` inserted. `01-deploy-cli.sh` and `bootstrap-env.sh` both write these into `.env` automatically. All connections use `sslmode=require`.

---

## The failover demo, three ways

Failover is **triggered in the portal** (cluster -> High availability -> forced failover) — there's no CLI command for it. Pick the script by what you want to capture:

- **`04-failover-watch.sh`** — live continuity, one line/sec. Run against the reader endpoint and you'll see every line stay `WRITABLE`/`RO` (reads don't drop), with the serving node changing as a standby is promoted. The visual for the video.
- **`05-failover-timer.sh`** — a quick *number*. Probes the read/write endpoint back-to-back and prints only state changes; the `(was DOWN for N ms)` line on recovery is your failover time. Quote it as "~N seconds" — resolution is bounded by libpq's ~2s connect-timeout floor.
- **`06-failover-measure.py`** — sub-second precision via a persistent connection that reconnects fast. Needs a driver (`pip install --user "psycopg[binary]"`). Use this if you want a defensible millisecond figure.

The sharpest story runs the reader watcher and the read/write timer side by side: **reads stayed up, writes paused ~1s, then resumed** — stronger than either number alone.

---

## Cost

This provisions a multi-replica preview cluster that bills while it runs. Tear it down as soon as you're done: `./scripts/99-teardown.sh` (or delete the resource group).

---

## Gotchas learned the hard way

- **Wrong subscription -> misleading `AuthorizationFailed`.** After a Cloud Shell reconnect you can land on a different active subscription; the resulting error looks like a permissions problem on the cluster. Always confirm `az account show` first.
- **Admin login *and* password are unrecoverable.** Both return `null` from `az horizondb show`. Lose them and your only paths are a portal password reset (if available for your cluster) or redeploy. Save them when you create the cluster.
- **Cloud Shell egress IP can change** between sessions — if `psql` suddenly times out after a reconnect, re-add your firewall rule.
- **Seed fan-out.** The per-order item count is derived from `order_id` (`1 + order_id % 4`), not from `random()` inside `generate_series()` — a random bound there collapsed to exactly one item per order on HorizonDB. Deterministic count, random product/quantity, works on both engines.

---

## Repo layout

```
infra/      azuredeploy.json (button target), azuredeploy.parameters.json, main.bicep (source)
scripts/    00 prereqs, 01 deploy, 02 load, 03 replica read, 04 watch, 05 timer,
            06 measure (python), 99 teardown, bootstrap-env, _common.sh
sql/        schema.sql, seed.sql, read-queries.sql
.env.example
```
