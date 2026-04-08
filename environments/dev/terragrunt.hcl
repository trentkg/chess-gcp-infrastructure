locals {
  github_oauth_token = get_env("GITHUB_OAUTH_TOKEN")
  es_preemptible     = get_env("ES_PREEMPTIBLE", "false") == "true"
}

remote_state {
  backend = "gcs"
  config = {
    project  = "chess-dev-411818"
    location = "us"
    bucket   = "chess-dev-tfstate-backend-bucket"
  }
}

terraform {
  source = "../modules/app/"
}

inputs = {
  env                              = "dev"
  project_id                       = "chess-dev-411818"
  github_app_installation_id       = 113815876
  github_oauth_token               = local.github_oauth_token
  es_preemptible                   = local.es_preemptible
  es_compute_disk_size             = 40
  api_url                          = "https://chess-api-dev-c4ltgvivga-uc.a.run.app"
  # frontend url https://chess-frontend-dev-c4ltgvivga-uc.a.run.app/ 
  registry_cleanup_keep_count      = 1
  registry_cleanup_older_than_days = 2
  es_boot_disk_size                = 30
  es_vm_machine_type               = "e2-medium"
  encoder_github_branch            = "develop"
  es_drive_type                    = "pd-standard"
  debug_mode                       = true
  cutover_to_managed_elasticsearch = false
}
