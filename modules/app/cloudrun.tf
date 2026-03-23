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
resource "google_secret_manager_secret_iam_member" "api_secret_access" {
  for_each = toset([
    google_secret_manager_secret.es_host.secret_id,
    google_secret_manager_secret.es_password.secret_id,
    google_secret_manager_secret.es_user.secret_id,
  ])
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}



# -----------------------------------------------------------------------
# VPC connector — Cloud Run → ES VM on internal IP
# -----------------------------------------------------------------------
resource "google_vpc_access_connector" "connector" {
  name          = "cr-connector-${var.env}"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.chess.name
  ip_cidr_range = "10.8.0.0/28"
  max_throughput = var.max_throughput

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
      image = "${var.artifact_registry_location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.chess-artifact-registry.repository_id}/api:latest"

      resources {
        limits = {
          cpu    = var.api_cpu
          memory = var.api_memory
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
        name = "ES_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.es_password.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "ENV"
        value = var.env
      }
    }

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }
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

    containers {
      image = "${var.artifact_registry_location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.chess-artifact-registry.repository_id}/frontend:latest"

      resources {
        limits = {
          cpu    = var.frontend_cpu
          memory = var.frontend_memory
        }
      }

      env {
        name  = "NEXT_PUBLIC_API_URL"
        value = google_cloud_run_v2_service.api.uri
      }
    }
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

# -----------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------
output "frontend_url" {
  description = "Public URL for the frontend"
  value       = google_cloud_run_v2_service.frontend.uri
}

output "api_url" {
  description = "URL for the API service"
  value       = google_cloud_run_v2_service.api.uri
}
