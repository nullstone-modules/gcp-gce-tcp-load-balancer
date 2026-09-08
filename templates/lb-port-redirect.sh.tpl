#!/usr/bin/env bash
# Managed by nullstone/gcp-gce-tcp-load-balancer. Rewritten by cloud-init on every boot and
# applied by lb-port-redirect-${service_port}.service.
set -euo pipefail

SERVICE_PORT=${service_port}
SERVER_PORT=${server_port}
METADATA_URL="http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip"

# The metadata server can lag network-online.target on first boot; retry briefly.
PRIVATE_IP=""
for ((i = 0; i < 30; i++)); do
  if PRIVATE_IP=$(curl -sf -H 'Metadata-Flavor: Google' "$METADATA_URL") && [ -n "$PRIVATE_IP" ]; then
    break
  fi
  sleep 1
done
if [ -z "$PRIVATE_IP" ]; then
  echo "lb-port-redirect-$SERVICE_PORT: could not read private IP from the metadata server" >&2
  exit 1
fi

# Packets from the target-pool load balancer arrive with the forwarding rule's IP as the
# destination (the guest agent installs a local route so the kernel accepts them). Packets from
# IAP, the VPC, or a tailnet arrive with this VM's private IP as the destination. Matching on
# "not my private IP" rewrites only load balancer traffic; source IP is untouched, so the app
# still sees the real client address.
RULE="-p tcp --dport $SERVICE_PORT ! -d $PRIVATE_IP -j REDIRECT --to-ports $SERVER_PORT"

# -C reports whether an identical rule exists; -I PREROUTING 1 puts it ahead of Docker's
# DOCKER chain jump so Docker's own port publishing never sees the original port.
# shellcheck disable=SC2086
if iptables -t nat -C PREROUTING $RULE 2>/dev/null; then
  echo "lb-port-redirect-$SERVICE_PORT: rule already present"
else
  iptables -t nat -I PREROUTING 1 $RULE
  echo "lb-port-redirect-$SERVICE_PORT: redirecting lb traffic $SERVICE_PORT -> $SERVER_PORT (private ip $PRIVATE_IP untouched)"
fi
