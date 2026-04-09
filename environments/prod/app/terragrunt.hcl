locals {
  github_oauth_token = get_env("GITHUB_OAUTH_TOKEN")
  es_preemptible     = get_env("ES_PREEMPTIBLE", "false") == "true"
}

remote_state {
  backend = "gcs"
  config = {
    project  = "chess-prod-492000"
    location = "us"
    bucket   = "chess-prod-tfstate-backend-bucket"
  }
}

terraform {
  source = "../../../modules/app"
}

inputs = {
  env                              = "prod"
  project_id                       = "chess-prod-492000"
  github_app_installation_id       = 113815876
  github_oauth_token               = local.github_oauth_token
  api_url                          = "https://chess-api-prod-col2a3szia-uc.a.run.app"
  # frontend_url = "https://chess-frontend-prod-col2a3szia-uc.a.run.app"
  registry_cleanup_keep_count      = 1
  registry_cleanup_older_than_days = 2
  # Set to true after the serverless-elasticsearch module has written new secrets
  # and Cloud Run has been verified against them. See runbooks/es-migration-vm-to-managed.md.
  cutover_to_managed_elasticsearch = true
  elasticsearch_ca_certs_path = "/etc/ssl/certs/ca-certificates.crt"
}
