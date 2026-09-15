locals {
  host = local.has_subdomain ? trimsuffix(local.subdomain_fqdn, ".") : local.ip_address
  url  = "${var.scheme}://${local.host}:${var.service_port}"
}

# Load-balancer spec consumed by gcp-gce-server (>= 0.1.0).
output "load_balancers" {
  value = [
    {
      type           = "tcp"
      name           = local.resource_name
      scheme         = var.internal ? "INTERNAL" : "EXTERNAL"
      global         = var.global
      proxy_protocol = var.proxy_protocol
      ip_address     = local.ip_address
      service_port   = var.service_port
      server_port    = local.server_port
      port_name      = "tcp-${local.server_port}" # MIG named port; used only when global
      health_check = {
        interval_sec        = var.health_check.interval_sec
        timeout_sec         = var.health_check.timeout_sec
        healthy_threshold   = var.health_check.healthy_threshold
        unhealthy_threshold = var.health_check.unhealthy_threshold
      }
    }
  ]
}

output "public_urls" {
  value = var.internal ? [] : [{ url = local.url }]
}

output "private_urls" {
  value = var.internal ? [{ url = local.url }] : []
}

# Empty unless server_port is set; gcp-gce-server merges these into the VM cloud-init.
output "cloud_init_stanzas" {
  description = "Cloud-init write_files and runcmd contributed to the parent gcp-gce-server module."
  value       = local.cloud_init_stanzas
}
