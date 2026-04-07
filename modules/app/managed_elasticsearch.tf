# Managed Elasticsearch via Elastic Cloud.
#
# Lifecycle flags:
#   use_managed_elasticsearch = true              → create the cluster; VM still serves traffic
#   use_managed_elasticsearch = true              → (after data migration)
#   cutover_to_managed_elasticsearch = true       → flip secrets, destroy VM
#
# Prerequisites before setting use_managed_elasticsearch = true in prod:
#   1. Create an Elastic Cloud account at https://cloud.elastic.co
#   2. Generate an API key under Account → API Keys
#   3. Add EC_API_KEY to prod/env-vars.sh and source it before plan/apply

resource "ec_deployment" "elasticsearch" {
  count = var.use_managed_elasticsearch ? 1 : 0

  name                   = "chess-elasticsearch-${var.env}"
  region                 = "gcp-us-central1"
  version                = "8.13.4"
  deployment_template_id = "gcp-storage-optimized"

  elasticsearch = {
    hot = {
      autoscaling = {}
      size        = var.elastic_cloud_elasticsearch_size
      zone_count  = 1
    }
  }
}

# Secret versions are only written during cutover — until then the VM-mode versions
# (es_host[0], es_password[0]) remain active and traffic stays on the VM.
resource "google_secret_manager_secret_version" "es_host_managed" {
  count       = local.cutover_complete ? 1 : 0
  secret      = google_secret_manager_secret.es_host.id
  secret_data = ec_deployment.elasticsearch[0].elasticsearch.https_endpoint
}

resource "google_secret_manager_secret_version" "es_password_managed" {
  count       = local.cutover_complete ? 1 : 0
  secret      = google_secret_manager_secret.es_password.id
  secret_data = ec_deployment.elasticsearch[0].elasticsearch_password
}

# These outputs are useful during the parallel-run phase for connecting to the managed
# cluster to load snapshot data and verify health before cutover.
output "managed_es_endpoint" {
  description = "HTTPS endpoint of the managed Elasticsearch cluster (null when use_managed_elasticsearch = false)"
  value       = var.use_managed_elasticsearch ? ec_deployment.elasticsearch[0].elasticsearch.https_endpoint : null
}

output "managed_es_username" {
  description = "Username for the managed Elasticsearch cluster"
  value       = var.use_managed_elasticsearch ? ec_deployment.elasticsearch[0].elasticsearch_username : null
}

output "managed_es_password" {
  description = "Password for the managed Elasticsearch cluster (sensitive)"
  value       = var.use_managed_elasticsearch ? ec_deployment.elasticsearch[0].elasticsearch_password : null
  sensitive   = true
}
