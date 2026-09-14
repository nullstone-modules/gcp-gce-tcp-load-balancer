locals {
  host = local.has_subdomain ? trimsuffix(local.subdomain_fqdn, ".") : google_compute_address.this.address
  url  = "${var.scheme}://${local.host}:${var.service_port}"

  target_pool_entry = {
    type        = "target_pool"
    name        = local.resource_name
    target_pool = one(google_compute_target_pool.this[*].self_link)
  }

  tcp_entry = {
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
}

# Load-balancer spec consumed by gcp-gce-server. One entry; shape depends on var.mode.
output "load_balancers" {
  value = concat(
    [for e in [local.target_pool_entry] : e if local.target_pool_mode],
    [for e in [local.tcp_entry] : e if !local.target_pool_mode],
  )
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
