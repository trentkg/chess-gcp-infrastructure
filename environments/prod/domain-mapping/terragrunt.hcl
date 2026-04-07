# environments/prod/domain-mapping/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules/domain-mapping"
}

dependency "app" {
  config_path = "../app"
}

inputs = {
  domain                 = "chess-thesaurus.com"
  region                 = "us-central1"
  project_id             = "chess-prod-492000"
  cloud_run_service_name = dependency.app.outputs.service_name
}
