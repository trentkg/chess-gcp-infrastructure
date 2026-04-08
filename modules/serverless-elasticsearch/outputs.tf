output "elasticsearch_endpoint" {
  description = "Public HTTPS endpoint for the serverless Elasticsearch API"
  value       = ec_elasticsearch_project.this.endpoints.elasticsearch
}

output "kibana_endpoint" {
  description = "Public HTTPS endpoint for Kibana"
  value       = ec_elasticsearch_project.this.endpoints.kibana
}

output "elasticsearch_username" {
  description = "Basic auth username (only populated in state after first apply)"
  value       = ec_elasticsearch_project.this.credentials.username
}

output "elasticsearch_password" {
  description = "Basic auth password (only populated in state after first apply)"
  value       = ec_elasticsearch_project.this.credentials.password
  sensitive   = true
}

output "cloud_id" {
  description = "Elastic Cloud ID (for use with Elastic SDKs and Beats)"
  value       = ec_elasticsearch_project.this.cloud_id
}

output "project_id" {
  description = "Elastic Cloud project ID"
  value       = ec_elasticsearch_project.this.id
}
