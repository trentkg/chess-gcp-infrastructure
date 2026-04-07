# Runbook: VM Elasticsearch → Elastic Cloud (managed)

Migrates the chess platform from the self-managed VM-based Elasticsearch instance to a
managed Elastic Cloud deployment. Both instances run in parallel during data migration,
so the only downtime is the brief window when secrets are flipped and Cloud Run is
redeployed (typically 5–15 minutes).

---

## Overview of flags

| `use_managed_elasticsearch` | `cutover_to_managed_elasticsearch` | Effect |
|---|---|---|
| `false` | `false` | Normal VM mode (current state) |
| `true` | `false` | Managed cluster created; VM still serves all traffic |
| `true` | `true` | **Cutover**: secrets point to managed cluster; VM destroyed; data disk preserved |

All flag changes go in `prod/terragrunt.hcl`.

---

## Prerequisites

1. **Elastic Cloud account** — sign up at https://cloud.elastic.co (use the GCP Marketplace listing to keep billing consolidated).
2. **API key** — Account → API Keys → Create API key. Copy the key, you won't see it again.
3. **Add key to prod env-vars.sh** — uncomment and fill in the `EC_API_KEY` line:
   ```bash
   export EC_API_KEY=$(cat /Users/trentgerman/.secrets/elastic-cloud-api-key)
   # or inline:
   export EC_API_KEY="your-key-here"
   ```
4. **GCS bucket for ES snapshots** — create one manually (or reuse an existing bucket with a distinct prefix):
   ```bash
   export PROJECT=chess-prod-492000
   gsutil mb -p $PROJECT -l us-central1 gs://chess-es-snapshots-prod/
   ```
5. **Grant your prod ES service account write access to the snapshot bucket:**
   ```bash
   gsutil iam ch \
     serviceAccount:chess-es-prod@chess-prod-492000.iam.gserviceaccount.com:objectAdmin \
     gs://chess-es-snapshots-prod/
   ```

---

## Phase 1 — Create the managed cluster (zero downtime)

The VM keeps running and serving all traffic during this phase.

### 1.1 Set the flag

In `prod/terragrunt.hcl`:
```hcl
use_managed_elasticsearch        = true
cutover_to_managed_elasticsearch = false   # leave false
```

### 1.2 Apply

```bash
cd prod
source env-vars.sh
./plan.sh     # review: should add ec_deployment + 0 changes to VM/secrets
./apply.sh
```

### 1.3 Note the managed cluster credentials

```bash
# Endpoint (not sensitive)
terragrunt output managed_es_endpoint

# Password (sensitive — pipe carefully)
terragrunt output -json managed_es_password | jq -r .
```

Keep these handy for the snapshot steps below.

### 1.4 Verify the managed cluster is up

```bash
MANAGED_HOST=$(terragrunt output -raw managed_es_endpoint)
MANAGED_PASS=$(terragrunt output -json managed_es_password | jq -r .)

curl -u "elastic:$MANAGED_PASS" "$MANAGED_HOST/_cluster/health?pretty"
# Expect: status green or yellow (no indices yet, so no shards to assign)
```

---

## Phase 2 — Snapshot existing data and restore to managed cluster

The goal is to take an Elasticsearch-level snapshot (not a disk-level snapshot) from the
running VM and restore it into the managed cluster via a shared GCS bucket.

Your existing GCP disk snapshot is useful as a fallback, but ES's native snapshot/restore
is the cleanest migration path and avoids any version-compatibility issues.

### 2.1 Open an IAP tunnel to the prod VM

```bash
source prod/env-vars.sh
gcloud compute start-iap-tunnel chess-elasticsearch-prod 9200 \
  --local-host-port=localhost:9200 \
  --zone=us-central1-c \
  --project=chess-prod-492000
```

Leave this running in a separate terminal.

### 2.2 Get the VM's ES password

```bash
ES_PASS=$(gcloud secrets versions access latest \
  --secret=chess-es-password \
  --project=chess-prod-492000)
```

### 2.3 Register the GCS snapshot repository on the VM's ES

ES 8.x includes the `repository-gcs` plugin built-in. The VM's service account
(`chess-es-prod@`) already has objectAdmin on the bucket from the Prerequisites step,
and the VM uses that service account via ADC — no keyfile needed here.

```bash
curl -X PUT "http://localhost:9200/_snapshot/gcs_migration" \
  -H "Content-Type: application/json" \
  -u "elastic:$ES_PASS" \
  -d '{
    "type": "gcs",
    "settings": {
      "bucket": "chess-es-snapshots-prod",
      "base_path": "migration"
    }
  }'
```

Verify:
```bash
curl -u "elastic:$ES_PASS" "http://localhost:9200/_snapshot/gcs_migration?pretty"
```

### 2.4 Take a snapshot

This captures all indices. `wait_for_completion=true` blocks until done.
For large datasets this may take a while; you can omit it and poll instead.

```bash
curl -X PUT \
  "http://localhost:9200/_snapshot/gcs_migration/snapshot_1?wait_for_completion=true" \
  -u "elastic:$ES_PASS"
```

Verify:
```bash
curl -u "elastic:$ES_PASS" \
  "http://localhost:9200/_snapshot/gcs_migration/snapshot_1?pretty"
# Expect: "state": "SUCCESS"
```

### 2.5 Create a GCS service account key for Elastic Cloud

Elastic Cloud runs outside GCP and cannot use ADC, so it needs an explicit service
account key to read from the snapshot bucket.

```bash
# Create a dedicated read-only SA for EC to access snapshots
gcloud iam service-accounts create ec-snapshot-reader \
  --display-name="Elastic Cloud snapshot reader" \
  --project=chess-prod-492000

# Grant it read access to the snapshot bucket
gsutil iam ch \
  serviceAccount:ec-snapshot-reader@chess-prod-492000.iam.gserviceaccount.com:objectViewer \
  gs://chess-es-snapshots-prod/

# Download a JSON key
gcloud iam service-accounts keys create /tmp/ec-snapshot-reader-key.json \
  --iam-account=ec-snapshot-reader@chess-prod-492000.iam.gserviceaccount.com \
  --project=chess-prod-492000
```

### 2.6 Register the GCS repository on the managed cluster

```bash
MANAGED_HOST=$(cd prod && terragrunt output -raw managed_es_endpoint)
MANAGED_PASS=$(cd prod && terragrunt output -json managed_es_password | jq -r .)

# The keyfile content must be base64-encoded inline in the settings
GCS_KEYFILE_B64=$(base64 -i /tmp/ec-snapshot-reader-key.json)

curl -X PUT "$MANAGED_HOST/_snapshot/gcs_migration" \
  -H "Content-Type: application/json" \
  -u "elastic:$MANAGED_PASS" \
  -d "{
    \"type\": \"gcs\",
    \"settings\": {
      \"bucket\": \"chess-es-snapshots-prod\",
      \"base_path\": \"migration\",
      \"application_name\": \"ec-chess\",
      \"credentials_file\": \"$GCS_KEYFILE_B64\"
    }
  }"
```

> **Note:** Elastic Cloud's GCS repository plugin accepts the credentials JSON either
> as a file path (when using Keystore) or inline as base64 depending on the plugin
> version. If the inline approach above fails, use the Kibana UI instead:
> Stack Management → Snapshot and Restore → Repositories → Add repository → Google Cloud Storage,
> paste the JSON key contents into the credentials field.

Verify the repository can see the snapshot:
```bash
curl -u "elastic:$MANAGED_PASS" \
  "$MANAGED_HOST/_snapshot/gcs_migration/snapshot_1?pretty"
# Expect: "state": "SUCCESS"
```

### 2.7 Restore the snapshot

```bash
curl -X POST "$MANAGED_HOST/_snapshot/gcs_migration/snapshot_1/_restore?wait_for_completion=true" \
  -H "Content-Type: application/json" \
  -u "elastic:$MANAGED_PASS" \
  -d '{
    "include_global_state": false
  }'
```

### 2.8 Verify data on the managed cluster

```bash
# Check index counts match
curl -u "elastic:$MANAGED_PASS" "$MANAGED_HOST/_cat/indices?v"

# Spot check a document count on an index you care about (e.g. chess-games)
curl -u "elastic:$MANAGED_PASS" "$MANAGED_HOST/chess-games/_count?pretty"

# Cluster health
curl -u "elastic:$MANAGED_PASS" "$MANAGED_HOST/_cluster/health?pretty"
# Expect: "status": "green"
```

Run any smoke-test queries you'd normally run against the VM to confirm data looks right.

---

## Phase 3 — Cutover (5–15 minutes downtime)

Do this when you're satisfied the managed cluster is healthy and data is verified.
The VM will be destroyed (disk preserved) and the Cloud Run API will be redeployed.

### 3.1 (Optional) Drain in-flight writes

If anything is writing to Elasticsearch right now, stop it or let it quiesce before
proceeding. With no heavy write load, this step can be skipped.

### 3.2 Set the cutover flag

In `prod/terragrunt.hcl`:
```hcl
use_managed_elasticsearch        = true
cutover_to_managed_elasticsearch = true   # flip this
```

### 3.3 Apply

```bash
cd prod
source env-vars.sh
./plan.sh
```

Review the plan carefully. Expected changes:
- **Destroy**: `google_compute_instance.elasticsearch` (VM)
- **Destroy**: `google_secret_manager_secret_version.es_host[0]` (old VM host secret version)
- **Destroy**: `google_secret_manager_secret_version.es_password[0]` (old VM password secret version)
- **Destroy**: `random_password.es_password[0]`
- **Create**: `google_secret_manager_secret_version.es_host_managed` (managed endpoint)
- **Create**: `google_secret_manager_secret_version.es_password_managed` (managed password)
- **No change**: `google_compute_disk.es-data` (preserved)

If the plan looks correct:
```bash
./apply.sh
```

### 3.4 Force Cloud Run to pick up the new secrets

Cloud Run instances cache secret values at startup. A new revision is needed to pick
up the updated `chess-es-host-prod` and `chess-es-password` secrets.

```bash
source prod/env-vars.sh

gcloud run services update chess-api-prod \
  --region=us-central1 \
  --project=chess-prod-492000 \
  --update-labels=es-cutover=$(date +%s)
```

The `--update-labels` flag forces a new revision without changing any functional config.

Wait for the rollout to complete:
```bash
gcloud run services describe chess-api-prod \
  --region=us-central1 \
  --project=chess-prod-492000 \
  --format="value(status.conditions[0].message)"
```

### 3.5 Verify the API is working

Hit a few API endpoints and confirm responses are coming from the managed cluster.
Check Cloud Run logs in the console for any ES connection errors.

---

## Phase 4 — Cleanup (do this a few days later, when confident)

1. **Delete the GCP disk snapshot** (the one you made before migration):
   ```bash
   gcloud compute snapshots list --project=chess-prod-492000
   gcloud compute snapshots delete <snapshot-name> --project=chess-prod-492000
   ```

2. **Delete the data disk** (currently kept by `prevent_destroy = true`):
   - Remove `prevent_destroy = true` from `google_compute_disk.es-data` in `modules/app/elasticsearch.tf`
   - Or delete it manually:
   ```bash
   gcloud compute disks delete chess-es-data-prod \
     --zone=us-central1-c \
     --project=chess-prod-492000
   ```

3. **Delete the EC snapshot reader service account key** once the migration is complete
   and you no longer need to restore from that snapshot:
   ```bash
   rm /tmp/ec-snapshot-reader-key.json
   gcloud iam service-accounts delete \
     ec-snapshot-reader@chess-prod-492000.iam.gserviceaccount.com \
     --project=chess-prod-492000
   ```

4. **Delete the GCS snapshot bucket** (optional, keep if you want the snapshot as a
   long-term backup):
   ```bash
   gsutil -m rm -r gs://chess-es-snapshots-prod/
   gsutil rb gs://chess-es-snapshots-prod/
   ```

---

## Rollback

If something goes wrong after cutover, rollback is straightforward because the data
disk is still intact.

1. In `prod/terragrunt.hcl`, set both flags back to `false`:
   ```hcl
   use_managed_elasticsearch        = false
   cutover_to_managed_elasticsearch = false
   ```
2. Run `./plan.sh` and `./apply.sh` — this recreates the VM (attached to the existing
   disk) and flips the secrets back to the VM.
3. Force a new Cloud Run revision (`gcloud run services update ...`) to pick up the
   restored secrets.

Note: the managed cluster is NOT destroyed by setting the flags to false (the
`ec_deployment` only has `count = 1` when `use_managed_elasticsearch = true`). If you
want to delete the managed cluster and stop billing, also delete it in the Elastic Cloud
console or destroy it with Terraform while `use_managed_elasticsearch = true`.
