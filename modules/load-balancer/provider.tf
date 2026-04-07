# modules/load-balancer/provider.tf
provider "google" {
  project = var.project_id
}

provider "google-beta" {
  project = var.project_id
}