# Elastic Cloud Serverless Elasticsearch project.
# Note: ec_elasticsearch_project is currently in technical preview in the elastic/ec provider.
#
# IMPORTANT — credentials behaviour:
#   The elastic/ec provider only returns credentials.username and credentials.password on
#   the *first* apply (when the project is created). Subsequent API reads return empty
#   values. `lifecycle { ignore_changes = [credentials] }` keeps the initial credentials
#   in Terraform state so downstream secret versions can reference them.
#   If you ever destroy and recreate this resource, re-apply with cutover = false first
#   to let Terraform capture the new credentials, then re-apply with cutover = true.

resource "ec_elasticsearch_project" "this" {
  name      = "chess-elasticsearch-${var.env}"
  region_id = "gcp-us-central1"

  lifecycle {
    ignore_changes = [credentials]
  }
}

# Secret versions below are only written during cutover.
# Until then, the VM-mode versions in the app module remain the latest/active versions.

resource "google_secret_manager_secret_version" "es_host" {
  count       = var.cutover_to_managed_elasticsearch ? 1 : 0
  secret      = var.es_host_secret_id
  secret_data = ec_elasticsearch_project.this.endpoints.elasticsearch
}

resource "google_secret_manager_secret_version" "es_password" {
  count       = var.cutover_to_managed_elasticsearch ? 1 : 0
  secret      = var.es_password_secret_id
  secret_data = ec_elasticsearch_project.this.credentials.password
}

resource "google_secret_manager_secret_version" "es_user" {
  count       = var.cutover_to_managed_elasticsearch ? 1 : 0
  secret      = var.es_user_secret_id
  secret_data = ec_elasticsearch_project.this.credentials.username
}
