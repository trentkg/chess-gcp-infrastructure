locals {
    env_vars = yamldecode(file(find_in_parent_folders("env-vars.yaml")))

}
remote_state {
    backend = "gcs"
    config = {
	    project = local.env_vars["project_id"] 
	    location = "us"
	    bucket = "chess-${local.env_vars["env"]}-tfstate-backend-bucket"
}
}

terraform {
    source = "../../../modules/app/"
}
inputs = {
    env = local.env_vars["env"]
    project_id = local.env_vars["project_id"]
}
