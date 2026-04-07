# modules/cloud-run-domain-mapping/variables.tf

variable "domain" {
  description = "The custom domain to map (e.g. chesssaurus.com)"
  type        = string
}

variable "region" {
  description = "GCP region of the Cloud Run service"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "cloud_run_service_name" {
  description = "Name of the Cloud Run service to map the domain to"
  type        = string
}