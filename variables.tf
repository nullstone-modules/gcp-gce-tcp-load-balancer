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
  redirect_enabled = var.server_port != null && var.server_port != var.service_port
}
