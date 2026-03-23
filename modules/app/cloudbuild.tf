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

# -----------------------------------------------------------------------
# Grant Cloud Build SA permission to deploy Cloud Run + act as Cloud Run SAs
# -----------------------------------------------------------------------
resource "google_project_iam_member" "cloudbuild_run_roles" {
  for_each = toset([
    "roles/run.developer",
    "roles/iam.serviceAccountUser",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_service_account_iam_member" "cloudbuild_act_as_api" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_service_account_iam_member" "cloudbuild_act_as_frontend" {
  service_account_id = google_service_account.frontend.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_cloudbuild_trigger" "images" {
  for_each = {
    transformer = { dockerfile_dir = "transformer" }
    loader      = { dockerfile_dir = "loader" }
    extractor   = { dockerfile_dir = "extractor" }
    api         = { dockerfile_dir = "api" }
    frontend    = { dockerfile_dir = "frontend" }
  }

  name            = "${each.key}-trigger"
  description     = "Manual build trigger for ${each.key}"
  project         = var.project_id
  location        = var.region
  service_account = "projects/${var.project_id}/serviceAccounts/${google_service_account.cloudbuild.email}"

  substitutions = {
    _REGION = var.region
    _ENV    = var.env
		_API_URL = var.api_url 
	}
  

  source_to_build {
    repository = google_cloudbuildv2_repository.encoder.id
    ref        = "refs/heads/${local.encoder_github_branch}"
    repo_type  = "GITHUB"
  }

  approval_config {
    approval_required = false
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
