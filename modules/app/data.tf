data "google_project" "project" {
  project_id = var.project_id
}

data "google_secret_manager_secrets" "chess_es" {
  project = var.project_id
  filter  = "name:chess-es-"
}