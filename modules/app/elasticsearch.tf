resource "google_service_account" "elasticsearch" {
  account_id   = "chess-es-${var.env}"
  display_name = "elasticsearch (${var.env})"
  project      = var.project_id
}

resource "google_project_iam_member" "es_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/secretmanager.secretAccessor",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.elasticsearch.email}"
}

# The data disk is NEVER removed by Terraform — prevent_destroy guards it and it serves
# as a backup even after cutover. Detach / delete it manually once you are confident.
resource "google_compute_disk" "es-data" {
  name    = "chess-es-data-${var.env}"
  project = var.project_id
  zone    = var.zone
  type    = var.es_drive_type
  size    = var.es_compute_disk_size

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [snapshot, licenses]
  }
}

# VM is destroyed and VM-mode secrets are removed when cutover is true.
# The serverless-elasticsearch module writes the new secrets before this is set.
locals {
  cutover_complete = var.cutover_to_managed_elasticsearch
}

resource "google_compute_instance" "elasticsearch" {
  count        = local.cutover_complete ? 0 : 1
  name         = "chess-elasticsearch-${var.env}"
  project      = var.project_id
  zone         = var.zone
  machine_type = var.es_vm_machine_type
  tags         = ["elasticsearch"]

  labels = {
    env     = var.env
    service = "elasticsearch"
  }

  boot_disk {
    initialize_params {
      image = "projects/${var.project_id}/global/images/family/chess-elasticsearch"
      size  = var.es_boot_disk_size
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
  }

  metadata = {
    block-project-ssh-keys = "true"
    es-heap-size           = var.es_heap_size
  }

  service_account {
    email  = google_service_account.elasticsearch.email
    scopes = ["cloud-platform"]
  }

  scheduling {
    preemptible         = var.es_preemptible
    on_host_maintenance = var.es_preemptible ? "TERMINATE" : "MIGRATE"
    automatic_restart   = var.es_preemptible ? false : true
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  allow_stopping_for_update = true

  lifecycle {
    # Manage status in the terminal to save costs
    ignore_changes = [desired_status]
  }
}

resource "random_password" "es_password" {
  count            = local.cutover_complete ? 0 : 1
  length           = 32
  special          = true
  override_special = "!#%&*-_=+?"
}

resource "google_secret_manager_secret" "es_password" {
  secret_id = "chess-es-password"
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
  count       = local.cutover_complete ? 0 : 1
  secret      = google_secret_manager_secret.es_password.id
  secret_data = random_password.es_password[0].result
}

resource "google_secret_manager_secret" "es_host" {
  secret_id = "chess-es-host-${var.env}"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "es_host" {
  count  = local.cutover_complete ? 0 : 1
  secret = google_secret_manager_secret.es_host.id
  # change to https if using ssl
  secret_data = "http://${google_compute_instance.elasticsearch[0].network_interface[0].network_ip}:${var.es_port}"
}

resource "google_secret_manager_secret" "es_ca_cert" {
  secret_id = "chess-es-ca-cert-${var.env}"
  project   = var.project_id
  replication {
    auto {}
  }
}

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
