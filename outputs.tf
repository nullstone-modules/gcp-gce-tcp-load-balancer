locals {
  host = local.has_subdomain ? trimsuffix(local.subdomain_fqdn, ".") : google_compute_address.this.address
  url  = "${var.scheme}://${local.host}:${var.service_port}"
}

# App MIG joins these target pools.
output "load_balancers" {
  value = [
    {
      port        = tostring(var.service_port)
      target_pool = google_compute_target_pool.this.self_link
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
