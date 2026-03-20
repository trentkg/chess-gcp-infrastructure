# ES IAM
moved {
  from = google_project_iam_member.es-logging
  to   = google_project_iam_member.es_roles["roles/logging.logWriter"]
}
moved {
  from = google_project_iam_member.es-monitoring
  to   = google_project_iam_member.es_roles["roles/monitoring.metricWriter"]
}
moved {
  from = google_project_iam_member.es-secret-access
  to   = google_project_iam_member.es_roles["roles/secretmanager.secretAccessor"]
}

# Cloud Build IAM
moved {
  from = google_project_iam_member.cloudbuild_storage_admin
  to   = google_project_iam_member.cloudbuild_roles["roles/storage.admin"]
}
moved {
  from = google_project_iam_member.cloudbuild_artifact_registry_writer
  to   = google_project_iam_member.cloudbuild_roles["roles/artifactregistry.writer"]
}
moved {
  from = google_project_iam_member.cloudbuild_artifact_log_writer
  to   = google_project_iam_member.cloudbuild_roles["roles/logging.logWriter"]
}