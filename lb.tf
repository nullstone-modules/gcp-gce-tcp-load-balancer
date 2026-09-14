# External or internal TCP load balancer. This capability owns the address, DNS, and client
# firewall and emits a load_balancers spec; gcp-gce-server creates the health check, backend
# service, and forwarding rule (and the TCP proxy when proxied) because those must name the MIG
# instance group, and a capability input derived from the MIG is a module cycle.
#
# Variants (see README):
#   default            regional external passthrough NLB, client IP preserved
#   internal = true    regional internal passthrough NLB on a private-subnet address
#   global   = true    global external proxy NLB on an anycast address; no passthrough, client IP only via PROXY protocol

locals {
  address_name = coalesce(var.name_overrides.ip_address, local.resource_name)
}

resource "google_compute_address" "this" {
  count = var.global ? 0 : 1

  name         = local.address_name
  region       = local.region
  address_type = var.internal ? "INTERNAL" : "EXTERNAL"
  subnetwork   = var.internal ? local.subnet : null
  network_tier = var.internal ? null : "PREMIUM"
  labels       = local.labels

  lifecycle {
    precondition {
      condition     = !var.internal || local.subnet != null
      error_message = "internal = true needs app_metadata.lb_subnet, provided by gcp-gce-server >= 0.1.0."
    }
  }
}

resource "google_compute_global_address" "this" {
  count = var.global ? 1 : 0

  name   = local.address_name
  labels = local.labels
}

# 0.0.x created these without count; keep state addresses stable across the upgrade.
moved {
  from = google_compute_address.this
  to   = google_compute_address.this[0]
}

moved {
  from = google_compute_firewall.lb
  to   = google_compute_firewall.lb[0]
}

locals {
  ip_address = coalesce(one(google_compute_address.this[*].address), one(google_compute_global_address.this[*].address))
}

# Client traffic to service_port. Not created when global: traffic then arrives from Google's
# proxy ranges on server_port, which gcp-gce-server opens.
resource "google_compute_firewall" "lb" {
  count = var.global ? 0 : 1

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
  rrdatas      = [local.ip_address]
  type         = "A"
  ttl          = 300
}
