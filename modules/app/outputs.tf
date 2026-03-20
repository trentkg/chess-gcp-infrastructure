output "es_internal_ip" {
  description = "Internal IP of the ES node"
  value       = google_compute_instance.elasticsearch.network_interface[0].network_ip
}
output "es_secret_name" {
  description = "Secret Manager secret ID for the ES password"
  value       = google_secret_manager_secret.es_password.secret_id
}
output "iap_tunnel_command" {
  description = "Tunnel to ES locally for debugging (then hit https://localhost:9200)"
  value       = "gcloud compute start-iap-tunnel chess-elasticsearch-${var.env} 9200 --local-host-port=localhost:9200 --zone=${var.zone} --project=${var.project_id}"
}

output "cloudbuild_trigger_transformer_id" {
  value = google_cloudbuild_trigger.images["transformer"].id
}
output "cloudbuild_trigger_loader_id" {
  value = google_cloudbuild_trigger.images["loader"].id
}
output "cloudbuild_trigger_extractor_id" {
  value = google_cloudbuild_trigger.images["extractor"].id
}

output "cloudbuild_service_account" {
  value = google_service_account.cloudbuild.email
}
