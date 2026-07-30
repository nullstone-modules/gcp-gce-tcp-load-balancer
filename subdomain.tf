data "ns_connection" "subdomain" {
  name     = "subdomain"
  contract = "subdomain/gcp/cloud-dns"
  optional = true
}

locals {
  subdomain_fqdn    = try(data.ns_connection.subdomain.outputs.fqdn, "")
  subdomain_zone_id = try(data.ns_connection.subdomain.outputs.zone_id, "")
  has_subdomain     = local.subdomain_fqdn != "" && local.subdomain_zone_id != ""
}
