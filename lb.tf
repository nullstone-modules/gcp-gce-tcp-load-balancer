# External passthrough Network Load Balancer (L4). TCP only; no TLS termination.

resource "google_compute_address" "this" {
  name         = local.resource_name
  region       = local.region
  network_tier = "PREMIUM"
  labels       = local.labels
}

resource "google_compute_region_health_check" "this" {
  name   = local.resource_name
  region = local.region

  timeout_sec         = var.health_check_timeout
  check_interval_sec  = var.health_check_interval
  unhealthy_threshold = var.health_check_unhealthy_threshold

  tcp_health_check {
    port = var.service_port
  }
}

resource "google_compute_region_backend_service" "this" {
  name                  = local.resource_name
  region                = local.region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.this.id]
  port_name             = local.port_name

  backend {
    group          = local.instance_group
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_forwarding_rule" "this" {
  name                  = local.resource_name
  region                = local.region
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  ports                 = [tostring(var.service_port)]
  ip_address            = google_compute_address.this.address
  backend_service       = google_compute_region_backend_service.this.id
  labels                = local.labels
}

# Passthrough preserves client IPs; health checks use Google probe ranges.
resource "google_compute_firewall" "lb" {
  name        = "${local.resource_name}-allow-lb"
  network     = local.network
  target_tags = local.instance_tags

  allow {
    protocol = "tcp"
    ports    = [tostring(var.service_port)]
  }

  source_ranges = distinct(concat(
    var.allowed_cidr_blocks,
    local.health_check_cidrs,
  ))
}

resource "google_dns_record_set" "this" {
  count = local.has_subdomain ? 1 : 0

  managed_zone = local.subdomain_zone_id
  name         = local.subdomain_fqdn
  rrdatas      = [google_compute_address.this.address]
  type         = "A"
  ttl          = 300
}
