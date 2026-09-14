# External TCP passthrough. This capability owns the address, DNS, and client firewall and emits
# a load_balancers spec; gcp-gce-server creates the health check, backend service, and
# forwarding rule because those must name the MIG instance group, and a capability input
# derived from the MIG is a module cycle.

resource "google_compute_address" "this" {
  name         = coalesce(var.name_overrides.ip_address, local.resource_name)
  region       = local.region
  network_tier = "PREMIUM"
  labels       = local.labels
}

resource "google_compute_firewall" "lb" {
  name        = "${local.resource_name}-allow-lb"
  network     = local.network
  target_tags = local.instance_tags

  allow {
    protocol = "tcp"
    ports    = [tostring(var.service_port)]
  }

  source_ranges = var.allowed_cidr_blocks
}

resource "google_dns_record_set" "this" {
  count = local.has_subdomain ? 1 : 0

  managed_zone = local.subdomain_zone_id
  name         = local.subdomain_fqdn
  rrdatas      = [google_compute_address.this.address]
  type         = "A"
  ttl          = 300
}
