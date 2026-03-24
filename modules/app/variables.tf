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
  default     = "us-central1-c"
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
  default     = "e2-medium"
}

variable "es_preemptible" {
  description = "Whether to use spot/preemptible pricing for the Elasticsearch VM"
  type        = bool
  default     = false
}

variable "es_compute_disk_size" {
  type        = number
  description = "The size of the es persistant disk."
  default     = 20
}

variable "es_heap_size" {
  type    = string
  default = "2g"
}

variable "api_cpu" {
  type        = string
  description = "CPU limit for the FastAPI service"
  default     = "1"
}

variable "api_memory" {
  type        = string
  description = "Memory limit for the FastAPI service"
  default     = "512Mi"
}

variable "frontend_cpu" {
  type        = string
  description = "CPU limit for the frontend service"
  default     = "1"
}

variable "frontend_memory" {
  type        = string
  description = "Memory limit for the frontend service"
  default     = "512Mi"
}

variable "api_min_instances" {
  type        = number
  description = "Minimum number of API instances (0 = scale to zero)"
  default     = 0
}

variable "api_max_instances" {
  type        = number
  description = "Maximum number of API instances"
  default     = 4
}

variable "frontend_min_instances" {
  type        = number
  description = "Minimum number of frontend instances"
  default     = 0
}

variable "frontend_max_instances" {
  type        = number
  description = "Maximum number of frontend instances"
  default     = 2
}

variable "api_url" {
  type        = string
  description = "Base URL of the deployed Cloud Run API service, baked into the frontend bundle at build time"
  default     = ""
}

variable "max_instances" {
  description = "Maximum number of instances in the autoscaling group (3–10). Must be greater than min_instances. Mutually exclusive with max_throughput."
  type        = number
  default     = null

  validation {
    condition = (
      var.max_instances == null ||
      (var.max_instances >= 3 && var.max_instances <= 10)
    )
    error_message = "max_instances must be between 3 and 10 (inclusive)."
  }
}

variable "max_throughput" {
  description = "Maximum throughput in Mbps (300–1000, multiples of 100). Must be greater than min_throughput. Mutually exclusive with max_instances. This is between ES and the Serverless VPC"
  type        = number
  default     = null

  validation {
    condition = (
      var.max_throughput == null ||
      (
        var.max_throughput >= 300 &&
        var.max_throughput <= 1000 &&
        var.max_throughput % 100 == 0
      )
    )
    error_message = "max_throughput must be a multiple of 100 between 300 and 1000."
  }
}

variable "registry_cleanup_keep_count" {
  description = "Number of most recent images to keep per image stream"
  type        = number
  default     = 1
}

variable "registry_cleanup_older_than_days" {
  description = "Delete images older than this many days (images protected by keep_count are exempt)"
  type        = number
  default     = 7
}
