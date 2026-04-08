variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "env" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "elastic_cloud_api_key" {
  description = "Elastic Cloud API key. Generate at https://cloud.elastic.co → Account → API Keys."
  type        = string
  sensitive   = true
}

variable "es_host_secret_id" {
  description = "Full GCP Secret Manager resource ID for the ES host URL (e.g. projects/123/secrets/chess-es-host-prod). Sourced from the app module output."
  type        = string
}

variable "es_password_secret_id" {
  description = "Full GCP Secret Manager resource ID for the ES password. Sourced from the app module output."
  type        = string
}

variable "es_user_secret_id" {
  description = "Full GCP Secret Manager resource ID for the ES username. Sourced from the app module output."
  type        = string
}

variable "cutover_to_managed_elasticsearch" {
  description = "When true, write the serverless cluster endpoint and credentials into the shared ES secrets so Cloud Run picks them up on next revision. Only set this after verifying the cluster is healthy and data is ready."
  type        = bool
  default     = false
}
