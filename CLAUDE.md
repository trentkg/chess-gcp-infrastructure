# chess-gcp-infrastructure

GCP infrastructure for the chess data platform, managed with Terraform + Terragrunt.

## Structure

```
modules/
  app/              # Single Terraform module containing all resources
    main.tf         # All resource definitions
    variables.tf    # Input variables
    outputs.tf      # Outputs (IPs, secret names, tunnel commands)
    provider.tf     # Google provider config
    backend.tf      # GCS backend config (populated by Terragrunt)

tiers/
  pre-prod/
    env-vars.yaml   # Environment variables: env, project_id
    dev/
      terragrunt.hcl  # Wires env-vars.yaml → modules/app, configures GCS state backend

create-tf-sa.sh     # One-time script to bootstrap the Terraform service account
```

## GCP Project

| Key | Value |
|---|---|
| Project ID | `chess-dev-411818` |
| Region | `us-central1` |
| Zone | `us-central1-a` |
| State bucket | `chess-dev-tfstate-backend-bucket` |
| Terraform SA | `terraform@chess-dev-411818.iam.gserviceaccount.com` |
| Credentials | `GOOGLE_APPLICATION_CREDENTIALS=/Users/trentgerman/Code/keys/terraform-sa-key.json` |

## Running Terraform

Always run from the environment directory, not the module directly:

```bash
cd tiers/pre-prod/dev
GOOGLE_APPLICATION_CREDENTIALS=/Users/trentgerman/Code/keys/terraform-sa-key.json terragrunt plan
GOOGLE_APPLICATION_CREDENTIALS=/Users/trentgerman/Code/keys/terraform-sa-key.json terragrunt apply
```

## Resources Managed

- **GCS bucket** — `chess-games-raw-dev`, holds raw game data
- **Artifact Registry** — `chess-artifact-registry-dev`, Docker images (us-central1)
- **VPC** — `chess-vpc-dev`, subnet `10.10.0.0/24`, Cloud NAT for outbound
- **Elasticsearch VM** — `chess-elasticsearch-dev`, `e2-standard-4`, `us-central1-a`, private IP `10.10.0.4`
  - Runs Elasticsearch 8.13.4 via Docker Compose; 4 GB JVM heap
  - 20 GB boot disk (pd-balanced) + 20 GB data disk (pd-standard, mounted at `/opt/elasticsearch/data`)
  - No public IP; outbound via Cloud NAT; inbound via firewall rules below
  - Dev: preemptible. Non-dev: standard with live migration.
- **Firewall rules**
  - `chess-beam-to-es-dev` — beam-worker tag → elasticsearch tag, TCP 9200/9300
  - `chess-vpc-to-es-dev` — 10.10.0.0/24 → elasticsearch tag, TCP 9200
  - `chess-iap-ssh-dev` — IAP range (35.235.240.0/20) → elasticsearch tag, TCP 22
- **Secret Manager** — `chess-es-password-dev` stores the generated ES password
- **Service account** — `chess-es-dev@chess-dev-411818.iam.gserviceaccount.com` with logging/monitoring writer roles

## Conventions

- Resource names follow the pattern `chess-<resource>-${var.env}` (e.g., `chess-vpc-dev`)
- All resources take `env` and `project_id` as inputs from `env-vars.yaml`
- The `modules/app` module is environment-agnostic; environment-specific behaviour is driven by `var.env` conditionals (e.g., preemptible in dev)
- Startup scripts are defined as `locals` in `main.tf` and referenced via `metadata.startup-script`
- `lifecycle { ignore_changes = [metadata["startup-script"]] }` is set on the ES instance so startup script changes don't trigger VM replacement

## Terraform SA Roles

The SA needs these roles (not all are granted by default — Secret Manager Admin had to be added manually):

```
roles/artifactregistry.repoAdmin
roles/compute.admin
roles/iam.serviceAccountAdmin
roles/iam.serviceAccountUser
roles/pubsub.admin
roles/resourcemanager.projectIamAdmin
roles/secretmanager.admin        # must be added manually; Secret Manager API must also be enabled
roles/storage.admin
```

## Debugging Elasticsearch

SSH or tunnel via IAP (no public IP on the VM):

```bash
# Open a local tunnel to ES port 9200
gcloud compute start-iap-tunnel chess-elasticsearch-dev 9200 \
  --local-host-port=localhost:9200 \
  --zone=us-central1-a \
  --project=chess-dev-411818

# Then in another terminal
curl http://localhost:9200/_cluster/health
```

## Known Gaps

- `beam_worker` service account and Dataflow/Beam pipeline resources are not yet defined; the corresponding outputs were removed pending that work
