# External TCP passthrough. Two modes (var.mode):
# - target_pool: capability owns the target pool and forwarding rule; the app MIG joins the pool.
# - backend_service: capability owns only the address, DNS, and client firewall; gcp-gce-server
#   creates the health check, backend service, and forwarding rule because those must name the
#   MIG instance group, and a capability input derived from the MIG is a module cycle.

locals {
  target_pool_mode = var.mode == "target_pool"
}

resource "google_compute_address" "this" {
  name         = coalesce(var.name_overrides.ip_address, local.resource_name)
  region       = local.region
  network_tier = "PREMIUM"
  labels       = local.labels
}

resource "google_compute_target_pool" "this" {
  count = local.target_pool_mode ? 1 : 0

  name   = local.resource_name
  region = local.region
}

resource "google_compute_forwarding_rule" "this" {
  count = local.target_pool_mode ? 1 : 0

  name                  = local.resource_name
  region                = local.region
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = tostring(var.service_port)
  ip_address            = google_compute_address.this.address
  target                = google_compute_target_pool.this[0].self_link
  labels                = local.labels
}

# 0.0.x created these without count; keep state addresses stable across the upgrade.
moved {
  from = google_compute_target_pool.this
  to   = google_compute_target_pool.this[0]
}

moved {
  from = google_compute_forwarding_rule.this
  to   = google_compute_forwarding_rule.this[0]
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
