

resource "google_storage_bucket" "chess-games" {
  name          = "chess-games-raw-${var.env}"
  location      = "US"
  force_destroy = false
  project       = var.project_id

  public_access_prevention = "enforced"
}

resource "google_storage_bucket_object" "sources-365" {
  depends_on = [google_storage_bucket.chess-games]
  name       = "sources/365-chess/" # folder name should end with '/'
  content    = " "                  # content is ignored but should be non-empty
  bucket     = google_storage_bucket.chess-games.name
}

resource "google_artifact_registry_repository" "chess-artifact-registry" {
  location      = var.artifact_registry_location
  repository_id = "chess-artifact-registry-${var.env}"
  description   = "Docker repository"
  format        = "DOCKER"
}

resource "google_compute_network" "chess" {
  name                    = "chess-vpc-${var.env}"
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "chess" {
  name                     = "chess-subnet-${var.env}"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.chess.id
  ip_cidr_range            = "10.10.0.0/24"
  private_ip_google_access = true # lets Beam workers reach GCS/Dataflow APIs without a NAT
}

# Cloud NAT so VMs with no public IP can still pull Docker images, apt packages, etc.
resource "google_compute_router" "chess" {
  name    = "chess-router-${var.env}"
  project = var.project_id
  region  = var.region
  network = google_compute_network.chess.id
}

resource "google_compute_router_nat" "chess" {
  name                               = "chess-nat-${var.env}"
  project                            = var.project_id
  router                             = google_compute_router.chess.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# ── Firewall rules ─────────────────────────────────────────────────────────────

# Beam workers → Elasticsearch (9200 HTTP, 9300 transport)
resource "google_compute_firewall" "beam-to-es" {
  name    = "chess-beam-to-es-${var.env}"
  project = var.project_id
  network = google_compute_network.chess.id

  allow {
    protocol = "tcp"
    ports    = ["9200", "9300"]
  }

  # Beam workers will carry the "beam-worker" tag; ES carries "elasticsearch"
  source_tags = ["beam-worker"]
  target_tags = ["elasticsearch"]
}

# Internal VPC → Elasticsearch port 9200 (any service within the subnet)
resource "google_compute_firewall" "vpc-to-es" {
  name    = "chess-vpc-to-es-${var.env}"
  project = var.project_id
  network = google_compute_network.chess.id

  allow {
    protocol = "tcp"
    ports    = ["9200"]
  }

  source_ranges = [google_compute_subnetwork.chess.ip_cidr_range]
  target_tags   = ["elasticsearch"]
}

# IAP SSH into the ES node for debugging
resource "google_compute_firewall" "iap-ssh" {
  name    = "chess-iap-ssh-${var.env}"
  project = var.project_id
  network = google_compute_network.chess.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["elasticsearch"]
}

# ── Elasticsearch ──────────────────────────────────────────────────────────────

resource "google_service_account" "elasticsearch" {
  account_id   = "chess-es-${var.env}"
  display_name = "Elasticsearch (${var.env})"
  project      = var.project_id
}

resource "google_project_iam_member" "es-logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.elasticsearch.email}"
}

resource "google_project_iam_member" "es-monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.elasticsearch.email}"
}

resource "google_compute_disk" "es-data" {
  name    = "chess-es-data-${var.env}"
  project = var.project_id
  zone    = var.zone
  type    = "pd-standard"
  size    = 20

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_compute_instance" "elasticsearch" {
  name         = "chess-elasticsearch-${var.env}"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-standard-4"
  tags         = ["elasticsearch"]

  labels = {
    env     = var.env
    service = "elasticsearch"
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  attached_disk {
    source      = google_compute_disk.es-data.self_link
    device_name = "es-data"
  }

  network_interface {
    network    = google_compute_network.chess.id
    subnetwork = google_compute_subnetwork.chess.id
    # No access_config block = no public IP; outbound via Cloud NAT above
  }

  metadata = {
    startup-script         = local.es_startup_script
    block-project-ssh-keys = "true"
  }

  service_account {
    email  = google_service_account.elasticsearch.email
    scopes = ["cloud-platform"]
  }

  scheduling {
    preemptible         = var.env == "dev" ? true : false
    on_host_maintenance = var.env == "dev" ? "TERMINATE" : "MIGRATE"
    automatic_restart   = var.env == "dev" ? false : true
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  desired_status            = var.es_desired_status
  allow_stopping_for_update = true

  lifecycle {
    ignore_changes = [metadata["startup-script"]]
  }
}

locals {
  es_startup_script = <<-EOT
    #!/bin/bash
    set -euxo pipefail

    # ── Format & mount the data disk on first boot ──────────────────
    DATA_DISK="/dev/disk/by-id/google-es-data"
    MOUNT_POINT="/opt/elasticsearch/data"

    if ! blkid "$DATA_DISK"; then
      mkfs.ext4 -F "$DATA_DISK"
    fi

    mkdir -p "$MOUNT_POINT"
    mount -o discard,defaults "$DATA_DISK" "$MOUNT_POINT"
    echo "$DATA_DISK $MOUNT_POINT ext4 discard,defaults 0 2" >> /etc/fstab
    chmod 777 "$MOUNT_POINT"

    # ── Install Docker ───────────────────────────────────────────────
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # ── Kernel settings required by ES ──────────────────────────────
    sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf

    # ── Fetch ES password from Secret Manager ───────────────────────
    # gcloud is pre-installed on Debian GCE images
    ELASTIC_PASSWORD=$(gcloud secrets versions access latest \
      --secret="chess-es-password-${var.env}" \
      --project="${var.project_id}")

    # ── Write docker-compose and start ──────────────────────────────
    mkdir -p /opt/elasticsearch
    cat > /opt/elasticsearch/docker-compose.yml <<COMPOSE
version: "3.8"
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.13.4
    container_name: elasticsearch
    restart: unless-stopped
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=true
      - xpack.security.transport.ssl.enabled=false
      - xpack.security.http.ssl.enabled=false
      - ELASTIC_PASSWORD=$ELASTIC_PASSWORD
      - ES_JAVA_OPTS=-Xms4g -Xmx4g
      - cluster.name=chess-${var.env}
      - node.name=chess-es-node
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - /opt/elasticsearch/data:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"
      - "9300:9300"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
COMPOSE

    docker compose -f /opt/elasticsearch/docker-compose.yml up -d
  EOT

  encoder_github_repo   = "chess-position-encoder"
  encoder_github_branch = "main"
}


resource "random_password" "es_password" {
  length           = 32
  special          = true
  override_special = "!#%&*-_=+?" # removed $ from here
}

resource "google_secret_manager_secret" "es_password" {
  secret_id = "chess-es-password-${var.env}"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = {
    env     = var.env
    service = "elasticsearch"
  }
}

resource "google_secret_manager_secret_version" "es_password" {
  secret      = google_secret_manager_secret.es_password.id
  secret_data = random_password.es_password.result
}

resource "google_compute_firewall" "dataflow-internal" {
  name    = "chess-dataflow-internal-${var.env}"
  project = var.project_id
  network = google_compute_network.chess.id

  allow {
    protocol = "tcp"
    ports    = ["12345", "12346"]
  }

  source_tags = ["beam-worker"]
  target_tags = ["beam-worker"]
}

resource "google_secret_manager_secret" "es_host" {
  secret_id = "chess-es-host-${var.env}"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "es_host" {
  secret = google_secret_manager_secret.es_host.id
  # The internal IP of your ES instance
  secret_data = google_compute_instance.elasticsearch.network_interface[0].network_ip
}

resource "google_service_account" "dataflow_worker" {
  account_id   = "chess-dataflow-worker-${var.env}"
  display_name = "Dataflow Worker (${var.env})"
  project      = var.project_id
}


# Project-level roles
resource "google_project_iam_member" "dataflow_worker_roles" {
  for_each = toset([
    "roles/dataflow.worker",
    "roles/storage.objectAdmin",
    "roles/compute.networkUser",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.dataflow_worker.email}"
}

# Secret Manager access for secrets named chess-es-*
data "google_secret_manager_secrets" "chess_es" {
  project = var.project_id
  filter  = "name:chess-es-"
}

# Give dataflow access to any secret with chess-es- in the name.
resource "google_secret_manager_secret_iam_member" "chess_es_access" {
  for_each = { for s in data.google_secret_manager_secrets.chess_es.secrets : s.secret_id => s }

  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.dataflow_worker.email}"
}

resource "google_secret_manager_secret" "es_ca_cert" {
  secret_id = "chess-es-ca-cert-${var.env}"
  project   = var.project_id
  replication {
    auto {}
  }
}

# The ES user (elastic is the built-in superuser)
resource "google_secret_manager_secret" "es_user" {
  secret_id = "chess-es-user-${var.env}"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "es_user" {
  secret      = google_secret_manager_secret.es_user.id
  secret_data = "elastic"
}

resource "google_compute_firewall" "iap-es" {
  name    = "chess-iap-es-${var.env}"
  project = var.project_id
  network = google_compute_network.chess.id

  allow {
    protocol = "tcp"
    ports    = ["9200"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["elasticsearch"]
}

resource "google_project_iam_member" "es-secret-access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.elasticsearch.email}"
}

# Create Cloud Build service account
resource "google_service_account" "cloudbuild" {
  account_id   = "cloudbuild-${var.env}"
  display_name = "Cloud Build Service Account (${var.env})"
  project      = var.project_id
}

# Grant Storage Admin
resource "google_project_iam_member" "cloudbuild_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Grant Artifact Registry Writer
resource "google_project_iam_member" "cloudbuild_artifact_registry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Grant log writing to actual service acount doing the builds
resource "google_project_iam_member" "cloudbuild_artifact_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Also grant log writing to the internal service agent that manages the builds itself
resource "google_project_iam_member" "cloudbuild_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# Output the Cloud Build service account email
output "cloudbuild_service_account" {
  value = google_service_account.cloudbuild.email
}

resource "google_cloudbuildv2_repository" "encoder" {
  name              = local.encoder_github_repo
  location          = var.region
  project           = var.project_id
  parent_connection = google_cloudbuildv2_connection.github.id
  remote_uri        = "https://github.com/${var.github_owner}/${local.encoder_github_repo}.git"
}

resource "google_cloudbuild_trigger" "transformer" {
  name            = "transformer-trigger"
  description     = "Trigger build for transformer image"
  project         = var.project_id
  location        = var.region
  service_account = "projects/${var.project_id}/serviceAccounts/${google_service_account.cloudbuild.email}"

  substitutions = {
    _REGION = var.region
    _ENV    = var.env
  }

  repository_event_config {
    repository = google_cloudbuildv2_repository.encoder.id
    push {
      branch = local.encoder_github_branch
    }
  }

  filename = "dockerfiles/transformer/cloudbuild.yaml"
}

resource "google_cloudbuild_trigger" "loader" {
  name            = "loader-trigger"
  disabled        = true
  description     = "Trigger build for loader image"
  project         = var.project_id
  location        = var.region
  service_account = "projects/${var.project_id}/serviceAccounts/${google_service_account.cloudbuild.email}"

  substitutions = {
    _REGION = var.region
    _ENV    = var.env
  }

  repository_event_config {
    repository = google_cloudbuildv2_repository.encoder.id
    push {
      branch = local.encoder_github_branch
    }
  }

  filename = "dockerfiles/loader/cloudbuild.yaml"
}

resource "google_cloudbuild_trigger" "extractor" {
  name            = "extractor-trigger"
  disabled        = true
  description     = "Trigger build for extractor image"
  project         = var.project_id
  location        = var.region
  service_account = "projects/${var.project_id}/serviceAccounts/${google_service_account.cloudbuild.email}"

  substitutions = {
    _REGION = var.region
    _ENV    = var.env
  }

  repository_event_config {
    repository = google_cloudbuildv2_repository.encoder.id
    push {
      branch = local.encoder_github_branch
    }
  }

  filename = "dockerfiles/extractor/cloudbuild.yaml"
}

resource "google_secret_manager_secret" "github_oauth_token" {
  secret_id = "github-oauth-token-${var.env}"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "github_oauth_token" {
  secret      = google_secret_manager_secret.github_oauth_token.id
  secret_data = var.github_oauth_token
}

resource "google_cloudbuildv2_connection" "github" {
  name     = "github-connection-${var.env}"
  location = var.region
  project  = var.project_id

  github_config {
    app_installation_id = var.github_app_installation_id
    authorizer_credential {
      oauth_token_secret_version = "${google_secret_manager_secret.github_oauth_token.id}/versions/latest"
    }
  }

  lifecycle {
    ignore_changes = [github_config[0].authorizer_credential[0].oauth_token_secret_version]
  }
}

data "google_project" "project" {
  project_id = var.project_id
}

resource "google_secret_manager_secret_iam_member" "cloudbuild_sa_github_token" {
  secret_id = google_secret_manager_secret.github_oauth_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
  project   = var.project_id
}
