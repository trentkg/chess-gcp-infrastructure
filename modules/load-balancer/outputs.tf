# modules/load-balancer/outputs.tf

output "load_balancer_ip" {
  description = "The external IP to set as your DNS A record in Cloudflare"
  value       = module.lb-http.external_ip
}