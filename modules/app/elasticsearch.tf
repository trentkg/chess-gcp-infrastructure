resource "google_service_account" "elasticsearch" {
  account_id   = "chess-es-${var.env}"
  display_name = "Elasticsearch (${var.env})"
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

resource "google_compute_disk" "es-data" {
  name    = "chess-es-data-${var.env}"
  project = var.project_id
  zone    = var.zone
  type    = "pd-standard"
  size    = var.es_compute_disk_size

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_compute_instance" "elasticsearch" {
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

  desired_status            = var.es_desired_status
  allow_stopping_for_update = true

  lifecycle {
    ignore_changes = [metadata["startup-script"]]
  }
}

resource "random_password" "es_password" {
  length           = 32
  special          = true
  override_special = "!#%&*-_=+?"
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

resource "google_secret_manager_secret" "es_host" {
  secret_id = "chess-es-host-${var.env}"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "es_host" {
  secret      = google_secret_manager_secret.es_host.id
  secret_data = google_compute_instance.elasticsearch.network_interface[0].network_ip
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
