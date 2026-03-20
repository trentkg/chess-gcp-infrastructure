locals {
  encoder_github_repo   = "chess-position-encoder"
  encoder_github_branch = "main"

  cloudbuild_triggers = {
    transformer = { disabled = false, dockerfile_dir = "transformer" }
    loader      = { disabled = true, dockerfile_dir = "loader" }
    extractor   = { disabled = true, dockerfile_dir = "extractor" }
  }

}
