locals {
  elastic_cloud_api_key = get_env("EC_API_KEY")
}

remote_state {
  backend = "gcs"
  config = {
    project  = "chess-prod-492000"
    location = "us"
    bucket   = "chess-prod-tfstate-backend-bucket"
    prefix   = "prod/serverless-elasticsearch"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

terraform {
  source = "../../../modules/serverless-elasticsearch"
}

dependency "app" {
  config_path = "../app"
}

inputs = {
  project_id            = "chess-prod-492000"
  env                   = "prod"
  elastic_cloud_api_key = local.elastic_cloud_api_key

  # Secret resource IDs sourced from the app module so this module can write new versions
  # at cutover time without owning the secret containers themselves.
  es_host_secret_id     = dependency.app.outputs.es_host_secret_id
  es_password_secret_id = dependency.app.outputs.es_password_secret_id
  es_user_secret_id     = dependency.app.outputs.es_user_secret_id

  # Step 1: apply with false to create the cluster and load data (see runbook).
  # Step 2: apply with true to flip secrets and complete the cutover.
  cutover_to_managed_elasticsearch = false
}
