locals {
  host = local.has_subdomain ? trimsuffix(local.subdomain_fqdn, ".") : google_compute_address.this.address
  url  = "${var.scheme}://${local.host}:${var.service_port}"
}

# Load-balancer spec consumed by gcp-gce-server (>= 0.1.0).
output "load_balancers" {
  value = [
    {
      type         = "tcp"
      name         = local.resource_name
      ip_address   = google_compute_address.this.address
      service_port = var.service_port
      server_port  = local.server_port
      health_check = {
        interval_sec        = var.health_check_interval_sec
        timeout_sec         = var.health_check_timeout_sec
        healthy_threshold   = var.health_check_healthy_threshold
        unhealthy_threshold = var.health_check_unhealthy_threshold
      }
    }
  ]
}

output "public_urls" {
  value = [
    {
      url = local.url
    }
  ]
}

# Empty unless server_port is set; gcp-gce-server merges these into the VM cloud-init.
output "cloud_init_stanzas" {
  description = "Cloud-init write_files and runcmd contributed to the parent gcp-gce-server module."
  value       = local.cloud_init_stanzas
}
