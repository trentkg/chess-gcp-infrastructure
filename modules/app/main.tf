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
  repository_id = "chess-artficat-registry-${var.env}"
  description   = "Docker repository"
  format        = "DOCKER"
}
