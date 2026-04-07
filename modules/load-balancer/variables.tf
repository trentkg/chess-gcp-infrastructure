# modules/load-balancer/variables.tf

variable "name" {
  description = "Name prefix for LB resources"
  type        = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "domain" {
  description = "Domain to provision a managed SSL cert for"
  type        = string
}

variable "cloud_run_service_name" {
  description = "Name of the Cloud Run service to route traffic to"
  type        = string
}