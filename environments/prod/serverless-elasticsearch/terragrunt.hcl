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
  es_host_secret_id     = dependency.app.outputs.es_host_secret_id
  es_password_secret_id = dependency.app.outputs.es_password_secret_id
  es_user_secret_id     = dependency.app.outputs.es_user_secret_id

  cutover_to_managed_elasticsearch = true
  elasticsearch_ca_certs_path = "/etc/ssl/certs/ca-certificates.crt"
}
