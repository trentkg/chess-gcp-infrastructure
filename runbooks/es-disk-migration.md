# Migrating ES Data Disk to SSD (Cross-Project)

## Projects
| | Project ID | Project Number |
|---|---|---|
| Dev | `chess-dev-411818` | — |
| Prod | `chess-prod-492000` | `1015442730374` |

Zone: `us-central1-c`

---

## 1. Stop Elasticsearch on Dev

```bash
gcloud compute ssh chess-elasticsearch-dev --zone=us-central1-c --project=chess-dev-411818 \
  --command "sudo systemctl stop elasticsearch"

# Confirm
gcloud compute ssh chess-elasticsearch-dev --zone=us-central1-c --project=chess-dev-411818 \
  --command "systemctl is-active elasticsearch"
# Expected: inactive
```

---

## 2. Snapshot the Dev Disk

```bash
gcloud compute disks snapshot chess-es-data-dev \
  --snapshot-names=<snapshot-name> \
  --zone=us-central1-c --project=chess-dev-411818
```

---

## 3. Grant Prod Access to the Snapshot

```bash
gcloud compute snapshots add-iam-policy-binding <snapshot-name> \
  --member="serviceAccount:1015442730374-compute@developer.gserviceaccount.com" \
  --role="roles/compute.storageAdmin" \
  --project=chess-dev-411818
```

---

## 4. Delete the Existing Prod Disk

```bash
# Check it's not attached first — should return empty
gcloud compute disks describe chess-es-data-prod \
  --zone=us-central1-c --project=chess-prod-492000 --format="get(users)"

gcloud compute disks delete chess-es-data-prod \
  --zone=us-central1-c --project=chess-prod-492000
```

---

## 5. Recreate as SSD from the Snapshot

```bash
gcloud compute disks create chess-es-data-prod \
  --source-snapshot=projects/chess-dev-411818/global/snapshots/<snapshot-name> \
  --type=pd-ssd \
  --size=40 \
  --zone=us-central1-c --project=chess-prod-492000
```

---

## 6. Re-import into Terraform State

```bash
terragrunt run -- state rm 'google_compute_disk.es-data'

terragrunt run -- import 'google_compute_disk.es-data' \
  'projects/chess-prod-492000/zones/us-central1-c/disks/chess-es-data-prod'
```

---

## 7. Ensure `elasticsearch.tf` Has Correct Lifecycle

```hcl
lifecycle {
  prevent_destroy = true
  ignore_changes  = [snapshot, licenses]
}
```

---

## 8. Plan and Apply

```bash
terragrunt run -- plan
terragrunt run -- apply
```

---

## 9. Restart Elasticsearch

```bash
# Dev
gcloud compute ssh chess-elasticsearch-dev --zone=us-central1-c --project=chess-dev-411818 \
  --command "sudo systemctl start elasticsearch"

# Prod
gcloud compute ssh chess-elasticsearch-prod --zone=us-central1-c --project=chess-prod-492000 \
  --command "sudo systemctl start elasticsearch"
```

---

## 10. Verify

```bash
curl -u elastic:<password> http://<prod-ip>:9200/_cat/indices?v
```
