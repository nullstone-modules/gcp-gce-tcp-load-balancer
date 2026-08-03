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
Passthrough does not translate ports; docker host_port must match.
Named service_port so a future L4 proxy capability can add server_port.
EOF
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR ranges allowed to reach the service port on MIG instances."
}
