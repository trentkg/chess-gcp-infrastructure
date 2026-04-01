locals {
  encoder_github_repo   = "chess-position-encoder"
  encoder_github_branch = "main"

  cloudbuild_triggers = {
    transformer = { dockerfile_dir = "transformer" }
    loader      = { dockerfile_dir = "loader" }
    extractor   = { dockerfile_dir = "extractor" }
  }

}
