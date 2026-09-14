variable "app_metadata" {
  description = <<EOF
Nullstone automatically injects metadata from the app module into this module through this variable.
This variable is a reserved variable for capabilities.
EOF

  type    = map(string)
  default = {}
}

locals {
  network       = var.app_metadata["network"]
  region        = var.app_metadata["region"]
  instance_tags = split(",", var.app_metadata["instance_tags"])
}

variable "scheme" {
  type        = string
  default     = "tcp"
  description = "URL scheme used when composing public_urls (e.g. tcp, sftp)."
}

variable "service_port" {
  type        = number
  description = <<EOF
External TCP service port on the load balancer.
Passthrough does not translate ports; docker host_port must match unless server_port is set.
See server_port for on-VM port translation.
EOF
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR ranges allowed to reach the service port on MIG instances."
}

variable "server_port" {
  type        = number
  default     = null
  description = <<EOF
Port on the VM that load balancer traffic is redirected to.

Leave unset (default) and the load balancer delivers traffic to `service_port` on the VM
unchanged; the Docker app must publish `host_port = service_port`.

Set this when the app cannot own `service_port` on the VM. Primary use case: an SFTP server
that customers reach on port 22 while Container-Optimized OS sshd keeps port 22 for IAP/OS Login
SSH. With `service_port = 22` and `server_port = 2022`, the Docker app publishes
`host_port = 2022`, and this capability installs an iptables NAT rule on the VM that rewrites
the destination port from 22 to 2022 for packets whose destination is the load balancer IP
(not the VM's private IP). SSH to the VM's private IP is unaffected.

This is a passthrough load balancer: translation happens on the VM, not at the load balancer.
The firewall opens only `service_port`; `server_port` is never reachable from outside the VM.

Setting `server_port` equal to `service_port` is a no-op.
EOF

  validation {
    condition     = var.server_port == null || (var.server_port >= 1 && var.server_port <= 65535)
    error_message = "server_port must be between 1 and 65535."
  }
}

locals {
  # server_port == service_port needs no rule; treat it as unset.
  # Global (proxied) traffic already arrives on server_port at the private IP, so no rule is needed.
  redirect_enabled = var.server_port != null && var.server_port != var.service_port && !var.global
}

variable "name_overrides" {
  type = object({
    ip_address = optional(string)
  })
  default     = { ip_address = "" }
  description = <<EOF
Override generated GCP resource names. Empty or unset fields keep the default name.
- `ip_address`: name of the reserved static IP (google_compute_address).
Changing a name after creation replaces the resource (a new IP address is allocated).
EOF
}

locals {
  # Port probed by the health check and redirected to on the VM.
  server_port = coalesce(var.server_port, var.service_port)
}

variable "health_check" {
  type = object({
    interval_sec        = optional(number, 5)
    timeout_sec         = optional(number, 4)
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 2)
  })
  default = {
    interval_sec        = 5
    timeout_sec         = 4
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  description = <<EOF
TCP health check that gcp-gce-server runs against server_port. Omitted fields keep their defaults.
- `interval_sec`: seconds between probes.
- `timeout_sec`: seconds to wait for a probe response; must not exceed interval_sec.
- `healthy_threshold`: consecutive successful probes before an instance receives traffic.
- `unhealthy_threshold`: consecutive failed probes before an instance stops receiving traffic.
EOF

  validation {
    condition     = var.health_check.timeout_sec <= var.health_check.interval_sec
    error_message = "health_check.timeout_sec must be less than or equal to health_check.interval_sec."
  }
}

variable "internal" {
  type        = bool
  default     = false
  description = <<EOF
Create an internal passthrough load balancer on an address in the server's private subnet instead
of an external one. Reachable only from the VPC, peered networks, VPNs, and tailnets; the URL is
reported in private_urls. Set allowed_cidr_blocks to the client ranges. Requires gcp-gce-server >= 0.1.0.
EOF
}

variable "global" {
  type        = bool
  default     = false
  description = <<EOF
Serve from a global anycast address (global external proxy load balancer) instead of a regional one.
This is not passthrough: Google terminates TCP and opens a new connection to server_port on the VM, so the
app sees a Google proxy address as the client unless proxy_protocol is set. allowed_cidr_blocks and
server_port redirection do not apply. Cannot be combined with internal.
EOF

  validation {
    condition     = !(var.global && var.internal)
    error_message = "global and internal cannot both be true; internal proxy load balancers are not supported."
  }
}

variable "proxy_protocol" {
  type        = bool
  default     = false
  description = "global only: send PROXY protocol v1 headers so the app can read the client IP. The app must expect them."

  validation {
    condition     = !var.proxy_protocol || var.global
    error_message = "proxy_protocol requires global = true."
  }
}

locals {
  # Public (ingress) subnet for internal load balancer addresses; absent on gcp-gce-server < 0.1.0.
  subnet = lookup(var.app_metadata, "lb_subnet", null)
}
