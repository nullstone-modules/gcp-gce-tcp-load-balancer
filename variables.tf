variable "app_metadata" {
  description = <<EOF
Nullstone automatically injects metadata from the app module into this module through this variable.
This variable is a reserved variable for capabilities.
EOF

  type    = map(string)
  default = {}
}

locals {
  instance_group = var.app_metadata["instance_group"]
  network        = var.app_metadata["network"]
  region         = var.app_metadata["region"]
  instance_tags  = split(",", var.app_metadata["instance_tags"])

  # Named port registered on the parent MIG via output "named_ports".
  port_name = "tcp-${var.port}"

  # GCP load balancer / health check probe ranges (required for NLB health checks).
  # https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
  health_check_cidrs = [
    "35.191.0.0/16",
    "130.211.0.0/22",
  ]
}

variable "scheme" {
  type        = string
  default     = "tcp"
  description = "URL scheme used when composing public_urls (e.g. tcp, sftp)."
}

variable "port" {
  type        = number
  description = <<EOF
External TCP port on the load balancer.
Passthrough NLB does not translate ports; the MIG host must listen on this same port
(docker host_port must match).
EOF
}

variable "health_check_interval" {
  type        = number
  default     = 5
  description = "Seconds between health checks."
}

variable "health_check_timeout" {
  type        = number
  default     = 4
  description = "Seconds before a probe is considered failed."
}

variable "health_check_unhealthy_threshold" {
  type        = number
  default     = 2
  description = "Consecutive failed probes before a backend is unhealthy."
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR ranges allowed to reach the backend port on MIG instances (passthrough preserves client source IPs)."
}
