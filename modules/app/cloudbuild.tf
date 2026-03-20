resource "google_service_account" "cloudbuild" {
  account_id   = "cloudbuild-${var.env}"
  display_name = "Cloud Build Service Account (${var.env})"
  project      = var.project_id
}

resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = toset([
    "roles/storage.admin",
    "roles/artifactregistry.writer",
    "roles/logging.logWriter",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}


resource "google_project_iam_member" "cloudbuild_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
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

resource "google_cloudbuildv2_repository" "encoder" {
  name              = local.encoder_github_repo
  location          = var.region
  project           = var.project_id
  parent_connection = google_cloudbuildv2_connection.github.id
  remote_uri        = "https://github.com/${var.github_owner}/${local.encoder_github_repo}.git"
}

resource "google_cloudbuild_trigger" "images" {
  for_each = {
    transformer = { disabled = false, dockerfile_dir = "transformer" }
    loader      = { disabled = true, dockerfile_dir = "loader" }
    extractor   = { disabled = true, dockerfile_dir = "extractor" }
  }

  name            = "${each.key}-trigger"
  description     = "Trigger build for ${each.key} image"
  disabled        = each.value.disabled
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

  filename = "dockerfiles/${each.value.dockerfile_dir}/cloudbuild.yaml"
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

resource "google_secret_manager_secret_iam_member" "cloudbuild_sa_github_token" {
  secret_id = google_secret_manager_secret.github_oauth_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
  project   = var.project_id
}
