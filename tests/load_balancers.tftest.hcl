# Asserts the load_balancers spec consumed by gcp-gce-server across the variants.
# Run: tofu test

mock_provider "ns" {
  mock_data "ns_workspace" {
    defaults = {
      block_ref  = "sftp-server"
      gcp_labels = { "nullstone-env" = "dev" }
    }
  }

  mock_data "ns_connection" {
    defaults = {
      outputs = {}
    }
  }
}

mock_provider "google" {
  mock_resource "google_compute_address" {
    defaults = { address = "203.0.113.10" }
  }

  mock_resource "google_compute_global_address" {
    defaults = { address = "203.0.113.30" }
  }
}

mock_provider "random" {
  mock_resource "random_string" {
    defaults = { result = "abcde" }
  }
}

variables {
  app_metadata = {
    network       = "primary-vpc"
    region        = "us-central1"
    instance_tags = "ns-stack-primary,ns-block-sftp-server,ns-env-dev"
    lb_subnet     = "primary-public-a"
  }
  scheme       = "sftp"
  service_port = 22
  server_port  = 2022
}

run "external_passthrough" {
  command = plan

  variables {
    health_check = { interval_sec = 10, timeout_sec = 5, healthy_threshold = 1, unhealthy_threshold = 3 }
  }

  assert {
    condition = output.load_balancers == [{
      type           = "tcp"
      name           = "sftp-server-abcde"
      scheme         = "EXTERNAL"
      global         = false
      proxy_protocol = false
      ip_address     = "203.0.113.10"
      service_port   = 22
      server_port    = 2022
      port_name      = "tcp-2022"
      health_check   = { interval_sec = 10, timeout_sec = 5, healthy_threshold = 1, unhealthy_threshold = 3 }
    }]
    error_message = "tcp entry shape mismatch"
  }

  assert {
    condition     = resource.google_compute_address.this[0].address_type == "EXTERNAL" && resource.google_compute_address.this[0].network_tier == "PREMIUM" && length(resource.google_compute_global_address.this) == 0
    error_message = "default must reserve a regional external address"
  }

  assert {
    condition     = flatten([for a in resource.google_compute_firewall.lb[0].allow : a.ports]) == ["22"]
    error_message = "client firewall must open only service_port"
  }

  assert {
    condition     = [for u in output.public_urls : u.url] == ["sftp://203.0.113.10:22"] && length(output.private_urls) == 0
    error_message = "external load balancer must report a public URL"
  }

  assert {
    condition     = length(output.cloud_init_stanzas) == 1
    error_message = "port-redirect stanza expected when server_port differs from service_port"
  }
}

run "without_server_port" {
  command = plan

  variables {
    server_port = null
  }

  assert {
    condition     = output.load_balancers[0].server_port == 22 && output.load_balancers[0].port_name == "tcp-22"
    error_message = "server_port must fall back to service_port"
  }

  assert {
    condition     = output.load_balancers[0].health_check == { interval_sec = 5, timeout_sec = 4, healthy_threshold = 2, unhealthy_threshold = 2 }
    error_message = "health_check must carry the defaults"
  }

  assert {
    condition     = length(output.cloud_init_stanzas) == 0
    error_message = "no port-redirect stanza without server_port"
  }
}

run "internal_passthrough" {
  command = plan

  variables {
    internal            = true
    allowed_cidr_blocks = ["10.0.0.0/8"]
  }

  assert {
    condition     = output.load_balancers[0].scheme == "INTERNAL" && output.load_balancers[0].global == false
    error_message = "internal must set scheme INTERNAL"
  }

  assert {
    condition     = resource.google_compute_address.this[0].address_type == "INTERNAL" && resource.google_compute_address.this[0].subnetwork == "primary-public-a"
    error_message = "internal must reserve an address in the public (ingress) subnet"
  }

  assert {
    condition     = resource.google_compute_firewall.lb[0].source_ranges == toset(["10.0.0.0/8"])
    error_message = "client firewall must use allowed_cidr_blocks"
  }

  assert {
    condition     = [for u in output.private_urls : u.url] == ["sftp://203.0.113.10:22"] && length(output.public_urls) == 0
    error_message = "internal load balancer must report a private URL"
  }

  assert {
    condition     = length(output.cloud_init_stanzas) == 1
    error_message = "port redirect still applies to internal passthrough traffic"
  }
}

run "internal_requires_subnet" {
  command = plan

  variables {
    internal = true
    app_metadata = {
      network       = "primary-vpc"
      region        = "us-central1"
      instance_tags = "ns-stack-primary,ns-block-sftp-server,ns-env-dev"
    }
  }

  expect_failures = [resource.google_compute_address.this]
}

run "global" {
  command = plan

  variables {
    global         = true
    proxy_protocol = true
  }

  assert {
    condition     = output.load_balancers[0].global == true && output.load_balancers[0].proxy_protocol == true && output.load_balancers[0].scheme == "EXTERNAL" && output.load_balancers[0].ip_address == "203.0.113.30"
    error_message = "global must flag the entry and use the global address"
  }

  assert {
    condition     = length(resource.google_compute_global_address.this) == 1 && length(resource.google_compute_address.this) == 0
    error_message = "global must reserve a global address instead of a regional one"
  }

  assert {
    condition     = length(resource.google_compute_firewall.lb) == 0
    error_message = "global must not open service_port to clients; traffic arrives from Google proxies on server_port"
  }

  assert {
    condition     = length(output.cloud_init_stanzas) == 0
    error_message = "global traffic already arrives on server_port; no redirect"
  }

  assert {
    condition     = [for u in output.public_urls : u.url] == ["sftp://203.0.113.30:22"]
    error_message = "global load balancer must report the global address"
  }
}

run "global_and_internal_conflict" {
  command = plan

  variables {
    global   = true
    internal = true
  }

  expect_failures = [var.global]
}

run "proxy_protocol_requires_global" {
  command = plan

  variables {
    proxy_protocol = true
  }

  expect_failures = [var.proxy_protocol]
}

run "timeout_must_not_exceed_interval" {
  command = plan

  variables {
    health_check = { interval_sec = 3, timeout_sec = 4 }
  }

  expect_failures = [var.health_check]
}
