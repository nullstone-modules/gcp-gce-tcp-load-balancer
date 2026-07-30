# External TCP passthrough. Capability owns the target pool; the app MIG joins
# it via the load_balancers output.

resource "google_compute_address" "this" {
  name         = local.resource_name
  region       = local.region
  network_tier = "PREMIUM"
  labels       = local.labels
}

resource "google_compute_target_pool" "this" {
  name   = local.resource_name
  region = local.region
}

resource "google_compute_forwarding_rule" "this" {
  name                  = local.resource_name
  region                = local.region
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = tostring(var.service_port)
  ip_address            = google_compute_address.this.address
  target                = google_compute_target_pool.this.self_link
  labels                = local.labels
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
