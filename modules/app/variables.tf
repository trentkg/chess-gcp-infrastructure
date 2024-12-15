variable env {
	type = string
	description = "The environment of the project (dev, prod, etc)"
}

variable project_id {
	type = string
	description = "The gcp project id"
}

variable artifact_registry_location {
	type = string
	description = "Where the artifact registry is located."
	default = "us-central1"
}
