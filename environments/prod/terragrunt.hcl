# environments/prod/terragrunt.hcl

remote_state {
  backend = "gcs"
  config = {
    project  = "chess-prod-492000"
    location = "us"
    bucket   = "chess-prod-tfstate-backend-bucket"
    prefix   = "${path_relative_to_include()}/terraform.tfstate"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}
