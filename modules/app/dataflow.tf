resource "google_service_account" "dataflow_worker" {
  account_id   = "chess-dataflow-worker-${var.env}"
  display_name = "Dataflow Worker (${var.env})"
  project      = var.project_id
}

resource "google_project_iam_member" "dataflow_worker_roles" {
  for_each = toset([
    "roles/dataflow.worker",
    "roles/storage.objectAdmin",
    "roles/compute.networkUser",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.dataflow_worker.email}"
}

resource "google_secret_manager_secret_iam_member" "chess_es_access" {
  for_each = { for s in data.google_secret_manager_secrets.chess_es.secrets : s.secret_id => s }

  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.dataflow_worker.email}"
}