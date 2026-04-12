# -----------------------------------------------------------------------
# Service accounts
# -----------------------------------------------------------------------
resource "google_service_account" "api" {
  account_id   = "chess-api-${var.env}"
  display_name = "Chess API (${var.env})"
  project      = var.project_id
}

resource "google_service_account" "frontend" {
  account_id   = "chess-frontend-${var.env}"
  display_name = "Chess Frontend (${var.env})"
  project      = var.project_id
}

# -----------------------------------------------------------------------
# Grant API SA access to ES secrets
# -----------------------------------------------------------------------
resource "google_secret_manager_secret_iam_member" "api_es_host_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.es_host.name
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

resource "google_secret_manager_secret_iam_member" "api_es_password_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.es_password.name
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

resource "google_secret_manager_secret_iam_member" "api_es_user_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.es_user.name
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

# -----------------------------------------------------------------------
# FastAPI service
# -----------------------------------------------------------------------
resource "google_cloud_run_v2_service" "api" {
  name     = "chess-api-${var.env}"
  location = var.region
  project  = var.project_id

  template {
    service_account = google_service_account.api.email

    scaling {
      min_instance_count = var.api_min_instances
      max_instance_count = var.api_max_instances
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello" # Google's hello-world image


      resources {
        limits = {
          cpu    = var.api_cpu
          memory = var.api_memory
        }
      }
      dynamic "env" {
        for_each = var.elasticsearch_ca_certs_path != null ? [1] : []
        content {
          name  = "ES_CA_CERTS_PATH"
          value = var.elasticsearch_ca_certs_path
        }
      }

      env {
        name = "ES_HOST"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.es_host.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "ES_USER"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.es_user.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "ES_PASSWORD_NAME"
        value = google_secret_manager_secret.es_password.secret_id
      }
      env {
        name  = "ENV"
        value = var.env
      }
      env {
        name  = "DEBUG"
        value = var.debug_mode
      }
      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }
    }
    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = google_compute_network.chess.id
        subnetwork = google_compute_subnetwork.chess.id
      }
    }

  }

  lifecycle { # let cloudbuild manage this
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version
    ]
  }
}

# -----------------------------------------------------------------------
# Frontend service
# -----------------------------------------------------------------------
resource "google_cloud_run_v2_service" "frontend" {
  name     = "chess-frontend-${var.env}"
  location = var.region
  project  = var.project_id

  template {
    service_account = google_service_account.frontend.email

    scaling {
      min_instance_count = var.frontend_min_instances
      max_instance_count = var.frontend_max_instances
    }

    containers {                                           # Let cloud build overwrite this, only used for first deploy
      image = "us-docker.pkg.dev/cloudrun/container/hello" # Google's hello-world image

      resources {
        limits = {
          cpu    = var.frontend_cpu
          memory = var.frontend_memory
        }
      }

      env {
        name  = "API_URL"
        value = google_cloud_run_v2_service.api.uri
      }
    }
  }
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version
    ]
  }
}

# -----------------------------------------------------------------------
# IAM — frontend public, API only callable by frontend SA
# -----------------------------------------------------------------------
resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "api_frontend_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.frontend.email}"
}

# --- 
# Allow api to create and use the subnet for use with new egress
#
resource "google_compute_subnetwork_iam_member" "api_network_user" {
  project    = var.project_id
  region     = var.region
  subnetwork = google_compute_subnetwork.chess.name

  role   = "roles/compute.networkUser"
  member = "serviceAccount:${google_service_account.api.email}"
}
# -----------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------
output "frontend_url" {
  description = "Public URL for the frontend"
  value       = google_cloud_run_v2_service.frontend.uri
}

output "service_name" {
  description = "Cloud Run frontend service name for LB module"
  value       = google_cloud_run_v2_service.frontend.name
}

output "api_url" {
  description = "URL for the API service"
  value       = google_cloud_run_v2_service.api.uri
}
