# gcp-gce-tcp-load-balancer

External L4 TCP passthrough load balancer for `gcp-gce-server`.

## Attach model

1. Capability creates a regional target pool, static IP, and forwarding rule.
2. App MIG joins via the `load_balancers` output.
3. Capability does not depend on the MIG instance group (avoids a Terraform cycle).

`service_port` must match the Docker `host_port` unless `server_port` is set (see below).

## Inputs

| Name | Default | Description |
|------|---------|-------------|
| `service_port` | (required) | External TCP port |
| `server_port` | `null` | VM port that LB traffic is redirected to; unset = no translation |
| `scheme` | `tcp` | Scheme for `public_urls` (for example `sftp`) |
| `allowed_cidr_blocks` | `["0.0.0.0/0"]` | Client CIDRs to the service port |

Optional connection: `subdomain` for a DNS A record.

## Outputs

| Name | Description |
|------|-------------|
| `load_balancers` | Target pool and port for the app MIG |
| `public_urls` | e.g. `sftp://<ip-or-host>:<service_port>` |
| `cloud_init_stanzas` | Port-redirect script and unit for the VM; empty unless `server_port` is set |

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

Why "not my private IP": packets from a target-pool load balancer reach the VM with the
forwarding rule's IP as the destination (the guest agent installs a local route so the kernel
accepts them). Packets from IAP, the VPC, or a tailnet arrive with the VM's own private IP as
the destination. Matching on the private IP instead of the LB address needs no Terraform-time
value, survives address recreation without an instance-template change, and lets several LB
capabilities share one server.

What is affected:

- Load balancer traffic on `service_port`: rewritten to `server_port`. Source IP is untouched,
  so the app sees the real client address.
- SSH to the private IP via IAP, the VPC, or a tailnet: unaffected. The `gcp-gce-server` IAP
  firewall rules for port 22 keep working because IAP targets the private IP.

Firewall: only `service_port` is opened to `allowed_cidr_blocks`. `server_port` is
intentionally not opened and is never reachable from outside the VM.

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
bash tests/lb-port-redirect.sh
```
