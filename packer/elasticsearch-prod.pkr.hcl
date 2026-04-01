packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "~> 1"
    }
  }
}

variable "project_id" {
  type    = string
  default = "chess-prod-492000"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}


source "googlecompute" "elasticsearch" {
  project_id          = var.project_id
  source_image_family = "debian-12"
  source_image_project_id = ["debian-cloud"]
  zone                = var.zone
  machine_type        = "e2-medium"
  image_name          = "chess-elasticsearch-{{timestamp}}"
  image_family        = "chess-elasticsearch"
  image_description   = "Elasticsearch 8.13.4"
  ssh_username        = "packer"
  tags                = ["packer"]
}

build {
  sources = ["source.googlecompute.elasticsearch"]

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "provision.sh"
  }
}
