resource "google_storage_bucket" "chess-games" {
  name          = "chess-games-raw-${var.env}"
  location      = "US"
  force_destroy = false
  project       = var.project_id

  public_access_prevention = "enforced"
}

resource "google_storage_bucket_object" "sources-365" {
  depends_on = [google_storage_bucket.chess-games]
  name       = "sources/365-chess/"
  content    = " "
  bucket     = google_storage_bucket.chess-games.name
}

resource "google_artifact_registry_repository" "chess-artifact-registry" {
  location      = var.artifact_registry_location
  repository_id = "chess-artifact-registry-${var.env}"
  description   = "Docker repository"
  format        = "DOCKER"

  cleanup_policy_dry_run = false

  # Always keep the N most recent images (protects rollback)
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"

    most_recent_versions {
      keep_count = var.registry_cleanup_keep_count
    }
  }

  # Delete anything older than threshold UNLESS protected above
  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"

    condition {
      older_than = "${var.registry_cleanup_older_than_days * 24 * 3600}s"
    }
  }
}
