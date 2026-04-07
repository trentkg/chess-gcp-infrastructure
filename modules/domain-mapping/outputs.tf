# modules/cloud-run-domain-mapping/outputs.tf

output "dns_records" {
  description = "DNS records to add to Cloudflare"
  value       = google_cloud_run_domain_mapping.prod.status[0].resource_records
}