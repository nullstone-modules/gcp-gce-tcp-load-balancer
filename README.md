# gcp-gce-tcp-load-balancer

External L4 TCP passthrough load balancer for `gcp-gce-server`.

## Attach model (`mode`)

The capability never references the MIG: `gcp-gce-server` consumes each capability as a whole
object, so a capability input derived from the MIG is a Terraform module cycle. Two modes:

| `mode` | Capability creates | Server creates | Health check |
|--------|--------------------|----------------|--------------|
| `target_pool` (default) | static IP, target pool, forwarding rule, DNS, firewall | MIG joins the pool via `target_pools` | none |
| `backend_service` | static IP, DNS, firewall | TCP health check, backend service on the MIG instance group, forwarding rule | TCP on `server_port` |

`backend_service` requires `gcp-gce-server` >= 0.1.0. Older servers ignore the `tcp` spec and
attach nothing. Switch to it to get health checks and backend membership derived from the
instance group instead of a pool that can silently lose members. Switching mode on a live
workspace recreates the forwarding rule on the same address: about 30–60 s of refused
connections on `service_port`. The address, DNS record, firewall, and port-redirect stanza are
untouched; no state moves.

`service_port` must match the Docker `host_port` unless `server_port` is set (see below).

## Inputs

| Name | Default | Description |
|------|---------|-------------|
| `service_port` | (required) | External TCP port |
| `server_port` | `null` | VM port that LB traffic is redirected to; unset = no translation |
| `mode` | `target_pool` | `target_pool` or `backend_service` (see above) |
| `scheme` | `tcp` | Scheme for `public_urls` (for example `sftp`) |
| `allowed_cidr_blocks` | `["0.0.0.0/0"]` | Client CIDRs to the service port |
| `name_overrides` | `{ ip_address = "" }` | Override generated resource names; `ip_address` renames the static IP |
| `health_check_interval_sec` | `5` | `backend_service` mode: seconds between probes |
| `health_check_timeout_sec` | `4` | Probe timeout; must not exceed the interval |
| `health_check_healthy_threshold` | `2` | Passed probes before an instance is added |
| `health_check_unhealthy_threshold` | `2` | Failed probes before an instance is removed |

Optional connection: `subdomain` for a DNS A record.

## Outputs

| Name | Description |
|------|-------------|
| `load_balancers` | One spec entry consumed by `gcp-gce-server` (shape below) |
| `public_urls` | e.g. `sftp://<ip-or-host>:<service_port>` |
| `cloud_init_stanzas` | Port-redirect script and unit for the VM; empty unless `server_port` is set |

`load_balancers` entry by mode:

```hcl
# mode = "target_pool"
{ type = "target_pool", name = "<block_ref>-<suffix>", target_pool = "<self_link>" }

# mode = "backend_service"
{
  type         = "tcp"
  name         = "<block_ref>-<suffix>"   # server uses it for resource names
  ip_address   = "203.0.113.10"           # google_compute_address.this.address
  service_port = 22                       # external port on the forwarding rule
  server_port  = 2022                     # port probed on the VM; = service_port when unset
  health_check = { interval_sec = 5, timeout_sec = 4, healthy_threshold = 2, unhealthy_threshold = 2 }
}
```

## Firewall

This capability opens `service_port` to `allowed_cidr_blocks`. In `backend_service` mode the
server adds a rule for `server_port` from Google's health-check ranges (`35.191.0.0/16`,
`130.211.0.0/22`) only. `server_port` is reachable from nothing else.

## Port translation on the VM (`server_port`)

The load balancer is passthrough and cannot translate ports. The VM can, and only for packets
that arrived through the load balancer.

Use case: customers reach an SFTP server on port 22, but port 22 on the VM belongs to
Container-Optimized OS sshd, which operators use through IAP
(`gcloud compute ssh --tunnel-through-iap`). Publishing the container on host port 22 collides
with sshd. Set `service_port = 22` and `server_port = 2022`, publish the container on host
port 2022, and the capability installs this rule on every boot:

```bash
PRIVATE_IP=$(curl -sf -H 'Metadata-Flavor: Google' \
  http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip)
iptables -t nat -I PREROUTING 1 -p tcp --dport 22 ! -d "$PRIVATE_IP" -j REDIRECT --to-ports 2022
```

Why "not my private IP": packets from a passthrough load balancer reach the VM with the
forwarding rule's IP as the destination (the guest agent installs a local route so the kernel
accepts them). Packets from IAP, the VPC, a tailnet, or the health checker arrive with the VM's
own private IP as the destination. Matching on the private IP instead of the LB address needs no
Terraform-time value, survives address recreation without an instance-template change, and lets
several LB capabilities share one server.

What is affected:

- Load balancer traffic on `service_port`: rewritten to `server_port`. Source IP is untouched,
  so the app sees the real client address.
- SSH to the private IP via IAP, the VPC, or a tailnet: unaffected. The `gcp-gce-server` IAP
  firewall rules for port 22 keep working because IAP targets the private IP.
- Health-check probes (`backend_service` mode): unaffected; they target the private IP on
  `server_port`, which is why the spec reports `server_port` as the probed port.

Delivery: the capability emits `cloud_init_stanzas` that write
`/etc/nullstone/lb-port-redirect-<service_port>.sh` and
`lb-port-redirect-<service_port>.service`, then enable the unit. A oneshot unit, not a bare
`runcmd`, so the rule is re-applied on every boot and on MIG replacement. Rule insertion is
idempotent; `server_port` equal to `service_port` is a no-op. If the metadata lookup fails the
unit exits non-zero.

Verify on the VM:

```bash
systemctl status lb-port-redirect-22
sudo iptables -t nat -L PREROUTING -n --line-numbers
```

## Example

SFTP on port 22 with sshd keeping port 22 for IAP, health-checked backend service:

```yaml
capabilities:
  app:
    module: nullstone/gcp-gce-docker-app
    vars:
      image_url: "ghcr.io/drakkan/sftpgo:v2.6"
      ports:
        - host_port: 2022
          container_port: 2022
  sftp-ingress:
    module: nullstone/gcp-gce-tcp-load-balancer
    vars:
      mode: backend_service
      scheme: sftp
      service_port: 22   # what customers connect to
      server_port: 2022  # what the container publishes; sshd keeps 22
```

Without translation, `service_port` and the Docker `host_port` must match:

```yaml
capabilities:
  tcp-lb:
    module: nullstone/gcp-gce-tcp-load-balancer
    vars:
      service_port: 2022
      scheme: sftp
```

## Tests

```bash
tofu test
bash tests/lb-port-redirect.sh
```
