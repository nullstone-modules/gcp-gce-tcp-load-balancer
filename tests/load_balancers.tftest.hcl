# Asserts the load_balancers spec consumed by gcp-gce-server.
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

run "with_server_port" {
  command = plan

  variables {
    health_check = { interval_sec = 10, timeout_sec = 5, healthy_threshold = 1, unhealthy_threshold = 3 }
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
    error_message = "public_urls must use scheme, address, and service_port"
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
    condition     = output.load_balancers[0].server_port == 22
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

run "timeout_must_not_exceed_interval" {
  command = plan

  variables {
    health_check = { interval_sec = 3, timeout_sec = 4 }
  }

  expect_failures = [var.health_check]
}
