locals {
  host = local.has_subdomain ? trimsuffix(local.subdomain_fqdn, ".") : google_compute_address.this.address
  url  = "${var.scheme}://${local.host}:${var.port}"
}

# Consumed by gcp-gce-server as local.capabilities.named_ports and applied on the MIG.
# Output depends only on vars so Terraform can create the MIG named ports before LB backends.
output "named_ports" {
  value = [
    {
      name = local.port_name
      port = var.port
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
