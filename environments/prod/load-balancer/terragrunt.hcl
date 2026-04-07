# environments/prod/load-balancer/terragrunt.hcl

remote_state {
  backend = "gcs"
  config = {
    project  = "chess-prod-492000"
    location = "us"
    bucket   = "chess-prod-tfstate-backend-bucket"
    prefix   = "prod/load-balancer"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

terraform {
  source = "../../../modules/load-balancer"
}

dependency "app" {
  config_path = "../app"
}

inputs = {
  name                   = "chess-thesaurus-prod"
  project_id             = "chess-prod-492000"
  region                 = "us-central1"
  domain                 = "www.chess-thesaurus.com"
  cloud_run_service_name = dependency.app.outputs.service_name
}
