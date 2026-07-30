# gcp-gce-tcp-load-balancer

Nullstone capability that exposes a `gcp-gce-server` MIG through an external
Layer 4 (TCP) **passthrough** Network Load Balancer.

Use this for non-HTTP TCP workloads (for example SFTP). The load balancer does
not terminate TLS or rewrite ports; the VM host port must match `port`.

## Requirements

- Parent app: `gcp-gce-server` (MIG + named port `app` via `app_metadata`)
- `service_port` = docker `host_port` = this capability `port`

## Inputs

| Name | Default | Description |
|------|---------|-------------|
| `port` | (required) | External and backend TCP port (passthrough) |
| `scheme` | `tcp` | Scheme for `public_urls` (`tcp`, `sftp`, ...) |
| `allowed_cidr_blocks` | `["0.0.0.0/0"]` | Client CIDRs allowed to the backend port |

Optional connection: `subdomain` (`subdomain/gcp/cloud-dns`) for a DNS A record.

## Example

```yaml
capabilities:
  tcp-lb:
    module: nullstone/gcp-gce-tcp-load-balancer
    vars:
      port: 2022
      scheme: sftp
```
