# Asserts the load_balancers spec consumed by gcp-gce-server in both modes.
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

  mock_resource "google_compute_target_pool" {
    defaults = { self_link = "https://www.googleapis.com/compute/v1/projects/proj/regions/us-central1/targetPools/sftp-server-abcde" }
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
  }
  scheme       = "sftp"
  service_port = 22
  server_port  = 2022
}

run "target_pool_mode_is_default" {
  command = plan

  assert {
    condition     = length(resource.google_compute_target_pool.this) == 1 && length(resource.google_compute_forwarding_rule.this) == 1
    error_message = "default mode must create the target pool and forwarding rule"
  }

  assert {
    condition     = output.load_balancers == [{ type = "target_pool", name = "sftp-server-abcde", target_pool = "https://www.googleapis.com/compute/v1/projects/proj/regions/us-central1/targetPools/sftp-server-abcde" }]
    error_message = "target_pool entry shape mismatch"
  }

  assert {
    condition     = length(output.cloud_init_stanzas) == 1
    error_message = "port-redirect stanza expected when server_port differs from service_port"
  }
}

run "backend_service_mode" {
  command = plan

  variables {
    mode                             = "backend_service"
    health_check_interval_sec        = 10
    health_check_timeout_sec         = 5
    health_check_healthy_threshold   = 1
    health_check_unhealthy_threshold = 3
  }

  assert {
    condition     = length(resource.google_compute_target_pool.this) == 0 && length(resource.google_compute_forwarding_rule.this) == 0
    error_message = "backend_service mode must not create a target pool or forwarding rule"
  }

  assert {
    condition = output.load_balancers == [{
      type         = "tcp"
      name         = "sftp-server-abcde"
      ip_address   = "203.0.113.10"
      service_port = 22
      server_port  = 2022
      health_check = { interval_sec = 10, timeout_sec = 5, healthy_threshold = 1, unhealthy_threshold = 3 }
    }]
    error_message = "tcp entry shape mismatch"
  }

  assert {
    condition     = flatten([for a in resource.google_compute_firewall.lb.allow : a.ports]) == ["22"]
    error_message = "client firewall must open only service_port"
  }

  assert {
    condition     = output.public_urls == [{ url = "sftp://203.0.113.10:22" }]
    error_message = "public_urls unchanged by mode"
  }
}

run "backend_service_mode_without_server_port" {
  command = plan

  variables {
    mode        = "backend_service"
    server_port = null
  }

  assert {
    condition     = output.load_balancers[0].server_port == 22
    error_message = "server_port must fall back to service_port"
  }

  assert {
    condition     = length(output.cloud_init_stanzas) == 0
    error_message = "no port-redirect stanza without server_port"
  }
}

run "rejects_unknown_mode" {
  command = plan

  variables {
    mode = "proxy"
  }

  expect_failures = [var.mode]
}
