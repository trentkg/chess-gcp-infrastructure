resource "google_storage_bucket" "chess-games" {
  name          = "chess-games-raw-${var.env}"
  location      = "US"
  force_destroy = false 
	project			  = var.project_id

  public_access_prevention = "enforced"
}

resource "google_storage_bucket_object" "sources-365" {
	depends_on = [google_storage_bucket.chess-games]
  name   = "sources/365-chess/" # folder name should end with '/'
  content = " "       # content is ignored but should be non-empty
  bucket = google_storage_bucket.chess-games.name 
}

resource "google_artifact_registry_repository" "chess-artifact-registry" {
  location      = "${var.artifact_registry_location}"
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
}

resource "google_compute_instance" "elasticsearch" {
  name         = "chess-elasticsearch-${var.env}"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-medium"
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
    startup-script          = local.es_startup_script
    block-project-ssh-keys  = "true"
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

    # ── Write docker-compose and start ──────────────────────────────
    cat > /opt/elasticsearch/docker-compose.yml <<'COMPOSE'
version: "3.8"
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.13.4
    container_name: elasticsearch
    restart: unless-stopped
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - ES_JAVA_OPTS=-Xms1g -Xmx1g
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
}

