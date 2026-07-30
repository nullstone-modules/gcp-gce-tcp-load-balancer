# gcp-gce-tcp-load-balancer

External L4 TCP passthrough load balancer for `gcp-gce-server`.

## Attach pattern

1. This capability creates a **target pool** and forwarding rule.
2. The app MIG joins the pool via the `load_balancers` output.
3. This capability does not depend on the MIG instance group.

## Inputs

| Name | Default | Description |
|------|---------|-------------|
| `service_port` | (required) | TCP port (must match docker `host_port`) |
| `scheme` | `tcp` | Scheme for `public_urls` |
| `allowed_cidr_blocks` | `["0.0.0.0/0"]` | Client CIDRs to the service port |

Optional connection: `subdomain` for a DNS A record.

## Example

```yaml
capabilities:
  tcp-lb:
    module: nullstone/gcp-gce-tcp-load-balancer
    vars:
      service_port: 2022
      scheme: sftp
```
