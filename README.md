# gcp-gce-tcp-load-balancer

External L4 TCP passthrough load balancer for `gcp-gce-server`.

## Attach model

1. Capability creates a regional target pool, static IP, and forwarding rule.
2. App MIG joins via the `load_balancers` output.
3. Capability does not depend on the MIG instance group (avoids a Terraform cycle).

`service_port` must match the Docker `host_port` (no port translation).

## Inputs

| Name | Default | Description |
|------|---------|-------------|
| `service_port` | (required) | External TCP port |
| `scheme` | `tcp` | Scheme for `public_urls` (for example `sftp`) |
| `allowed_cidr_blocks` | `["0.0.0.0/0"]` | Client CIDRs to the service port |

Optional connection: `subdomain` for a DNS A record.

## Outputs

| Name | Description |
|------|-------------|
| `load_balancers` | Target pool and port for the app MIG |
| `public_urls` | e.g. `sftp://<ip-or-host>:<service_port>` |

## Example

```yaml
capabilities:
  tcp-lb:
    module: nullstone/gcp-gce-tcp-load-balancer
    vars:
      service_port: 2022
      scheme: sftp
```
