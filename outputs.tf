locals {
  host = local.has_subdomain ? trimsuffix(local.subdomain_fqdn, ".") : google_compute_address.this.address
  url  = "${var.scheme}://${local.host}:${var.port}"
}

output "public_urls" {
  value = [
    {
      url = local.url
    }
  ]
}
