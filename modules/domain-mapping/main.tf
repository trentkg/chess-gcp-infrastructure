# modules/cloud-run-domain-mapping/main.tf

resource "google_cloud_run_domain_mapping" "prod" {
  name     = var.domain
  location = var.region

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = var.cloud_run_service_name
  }
}