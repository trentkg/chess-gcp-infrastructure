variable "env" {
  type        = string
  description = "The environment of the project (dev, prod, etc)"
}

variable "project_id" {
  type        = string
  description = "The gcp project id"
}

variable "artifact_registry_location" {
  type        = string
  description = "Where the artifact registry is located."
  default     = "us-central1"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "github_owner" {
  type        = string
  description = "GitHub owner / org for the repository"
  default     = "trentkg"
}

variable "github_oauth_token" {
  description = "GitHub Personal Access Token for Cloud Build connection"
  type        = string
  sensitive   = true
}

variable "github_app_installation_id" {
  description = "GitHub App installation ID for Cloud Build"
  type        = number
}

variable "es_desired_status" {
  description = "Desired status of the elasticsearch instance. Either \"RUNNING\", \"SUSPENDED\" or \"TERMINATED\""
  type        = string
  default     = "RUNNING"
}

variable "es_vm_machine_type" {
  description = "Machine type of the elasticsearch compute instance, e.g. e2-standard-4"
  type        = string
  default     = "e2-micro"
}
