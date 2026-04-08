terraform {
  required_providers {
    ec = {
      source  = "elastic/ec"
      version = "~> 0.12"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "ec" {
  apikey = var.elastic_cloud_api_key
}

provider "google" {
  project = var.project_id
}
