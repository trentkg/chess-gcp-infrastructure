provider "google" {
  project = var.project_id
}

# Elastic Cloud provider — active only when use_managed_elasticsearch = true.
# When the flag is false, the apikey placeholder satisfies the provider's non-empty
# validation but no API calls are ever made (all ec resources have count = 0).
# For real deployments, pass the actual key via the elastic_cloud_api_key variable.
provider "ec" {
  apikey = var.elastic_cloud_api_key
}
