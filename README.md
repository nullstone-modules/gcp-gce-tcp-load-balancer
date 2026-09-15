# gcp-gce-tcp-load-balancer

L4 TCP load balancer for `gcp-gce-server`. External passthrough by default; `internal` and
`global` select the other variants.

## Attach model

The capability never references the MIG: `gcp-gce-server` consumes each capability as a whole
object, so a capability input derived from the MIG is a Terraform module cycle. Ownership is
split instead:

| Owner | Resources |
|-------|-----------|
| This capability | address, DNS A record, client firewall on `service_port`, port-redirect cloud-init, `load_balancers` spec, `public_urls` or `private_urls` |
| `gcp-gce-server` >= 0.1.0 | health check on `server_port`, backend service on the MIG instance group, forwarding rule on the capability's address (plus the TCP proxy when global), firewall for Google's health-check ranges to `server_port` |

Backend membership is derived from the instance group, so it cannot drift, and the health check
removes an instance that stops answering on `server_port`. Older servers ignore the spec and
attach nothing.

## Variants

| Flags | Load balancer | Address | Client IP | Reach |
|-------|---------------|---------|-----------|-------|
| (default) | regional external passthrough NLB | regional external | preserved | internet, `allowed_cidr_blocks` |
| `internal = true` | regional internal passthrough NLB | public (ingress) subnet, internal IP | preserved | VPC, peering, VPN, tailnet; `allowed_cidr_blocks` |
| `global = true` | global external proxy NLB (not passthrough) | global anycast | Google proxy, or real IP via `proxy_protocol` | internet; `allowed_cidr_blocks` does not apply |

`global` and `internal` cannot be combined (internal proxy load balancers need a proxy-only
subnet, which gcp-network does not create). Changing a flag on a live workspace replaces the
address and forwarding rule.

`service_port` must match the Docker `host_port` unless `server_port` is set (see below).
When global, the VM always receives traffic on `server_port` at its private IP; no redirect is
installed.

## Inputs

| Name | Default | Description |
|------|---------|-------------|
| `service_port` | (required) | Port clients connect to |
| `server_port` | `null` | VM port that LB traffic is redirected to; unset = no translation |
| `internal` | `false` | Internal passthrough on an internal address in the public (ingress) subnet |
| `global` | `false` | Global anycast address; disables passthrough (Google proxies to the VM) |
| `proxy_protocol` | `false` | Global only: PROXY protocol v1 headers so the app sees the client IP |
| `scheme` | `tcp` | Scheme for the reported URL (for example `sftp`) |
| `allowed_cidr_blocks` | `["0.0.0.0/0"]` | Client CIDRs to the service port (passthrough variants) |
| `name_overrides` | `{ ip_address = "" }` | Override generated resource names; `ip_address` renames the address |
| `health_check` | `{ interval_sec = 5, timeout_sec = 4, healthy_threshold = 2, unhealthy_threshold = 2 }` | TCP probe on `server_port`; set only the fields to change. `timeout_sec` must not exceed `interval_sec` |

Optional connection: `subdomain` for a DNS A record.

## Outputs

| Name | Description |
|------|-------------|
| `load_balancers` | One `type = "tcp"` spec entry consumed by `gcp-gce-server` |
| `public_urls` | `<scheme>://<ip-or-host>:<service_port>`; empty when internal |
| `private_urls` | Same URL when internal; empty otherwise |
| `cloud_init_stanzas` | Port-redirect script and unit; empty unless `server_port` is set and not global |

```hcl
{
  type           = "tcp"
  name           = "<block_ref>-<suffix>"   # server uses it for resource names
  scheme         = "EXTERNAL"               # INTERNAL when internal = true
  global         = false                    # not passthrough when true
  proxy_protocol = false
  ip_address     = "203.0.113.10"
  service_port   = 22                       # port on the forwarding rule
  server_port    = 2022                     # port probed on the VM; = service_port when unset
  port_name      = "tcp-2022"               # MIG named port, used only when global
  health_check   = { interval_sec = 5, timeout_sec = 4, healthy_threshold = 2, unhealthy_threshold = 2 }
}
```

## Firewall

Passthrough variants: this capability opens `service_port` to `allowed_cidr_blocks`. Global:
no client rule; traffic reaches the VM from Google's proxy ranges. In every variant the server
opens `server_port` to `35.191.0.0/16` and `130.211.0.0/22` (health checks, and global client
traffic). `server_port` is reachable from nothing else.

## Port translation on the VM (`server_port`)

Passthrough load balancers cannot translate ports. The VM can, and only for packets that arrived
through the load balancer.

Use case: customers reach an SFTP server on port 22, but port 22 on the VM belongs to
Container-Optimized OS sshd, which operators use through IAP
(`gcloud compute ssh --tunnel-through-iap`). Publishing the container on host port 22 collides
with sshd. Set `service_port = 22` and `server_port = 2022`, publish the container on host
port 2022, and the capability installs this rule on every boot:

```bash
PRIVATE_IP=$(curl -sf -H 'Metadata-Flavor: Google' \
  http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip)
iptables -t nat -I PREROUTING 1 -p tcp --dport 22 ! -d "$PRIVATE_IP" -j REDIRECT --to-ports 2022
iptables -I INPUT 1 -p tcp --dport 2022 -j ACCEPT
```

Why "not my private IP": packets from a passthrough load balancer (external or internal) reach
the VM with the forwarding rule's IP as the destination (the guest agent installs a local route
so the kernel accepts them). Packets from IAP, the VPC, or a tailnet arrive with the VM's own
private IP as the destination. Matching on the private IP instead of the LB address needs no
Terraform-time value, survives address recreation without an instance-template change, and lets
several LB capabilities share one server.

Why the INPUT rule: `REDIRECT` ends nat PREROUTING, so the packet skips Docker's `DOCKER` chain
and is delivered to the host's `docker-proxy` listener on `server_port` through the filter
`INPUT` chain. Container-Optimized OS ships `INPUT` with policy `DROP` and only port 22 accepted,
so without this rule every redirected packet is dropped and clients hang. The GCE firewall still
limits who can reach `server_port` from outside the VM.

What is affected:

- Load balancer traffic on `service_port`: rewritten to `server_port`. Source IP is untouched,
  so the app sees the real client address.
- SSH to the private IP via IAP, the VPC, or a tailnet: unaffected. The `gcp-gce-server` IAP
  firewall rules for port 22 keep working because IAP targets the private IP.
- Health-check probes: unaffected. Passthrough probes are addressed to the load balancer IP on
  `server_port` (not `service_port`), so they miss the redirect and reach the container through
  Docker's published port; that is why the spec reports `server_port` as the probed port.
- Global: not installed. Google's proxies connect to the private IP on `server_port` directly.

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
sudo iptables -L INPUT -n --line-numbers | grep 2022
```

## Examples

SFTP on port 22 with sshd keeping port 22 for IAP:

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
      scheme: sftp
      service_port: 22   # what customers connect to
      server_port: 2022  # what the container publishes; sshd keeps 22
```

Same service reachable only from the VPC and a tailnet:

```yaml
  sftp-internal:
    module: nullstone/gcp-gce-tcp-load-balancer
    vars:
      scheme: sftp
      internal: true
      allowed_cidr_blocks: ["10.0.0.0/8", "100.64.0.0/10"]
      service_port: 22
      server_port: 2022
```

Global anycast address with client IPs delivered by PROXY protocol (the app must expect it):

```yaml
  sftp-global:
    module: nullstone/gcp-gce-tcp-load-balancer
    vars:
      scheme: sftp
      global: true
      proxy_protocol: true
      service_port: 22
      server_port: 2022
```

## Upgrading from 0.0.x

0.0.x created a target pool and forwarding rule here and the server set `target_pools` on the
MIG. Target pools have no health check and silently lost their members when recreated.

- Upgrade `gcp-gce-server` to >= 0.1.0 in the same change. Servers before 0.1.0 ignore the
  spec; this version no longer outputs `target_pool`.
- The apply destroys the target pool and forwarding rule and creates a backend service and a new
  forwarding rule on the same address. Expect 30–60 s of refused connections on `service_port`.
- If the apply fails with "IP address ... is already in use", the new forwarding rule was created
  before the old one finished deleting. Apply again.
- The static address, DNS record, client firewall, and port-redirect stanza are untouched. `moved`
  blocks keep their state addresses.

## Tests

```bash
tofu test
bash tests/lb-port-redirect.sh
```
