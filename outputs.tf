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
