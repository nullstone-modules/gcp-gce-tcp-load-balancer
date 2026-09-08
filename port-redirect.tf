# On-VM port translation for load balancer traffic (see README "Port translation on the VM").
#
# A target-pool LB is passthrough: packets reach the VM with the forwarding rule's IP as the
# destination, while IAP/VPC/tailnet packets carry the VM's private IP. One iptables NAT rule
# keyed on "not my private IP" rewrites only LB traffic from service_port to server_port.
# It is keyed on the private IP (read from the metadata server at boot) rather than the LB
# address so no Terraform-time value is baked into the instance template, address recreation
# does not churn the template, and several LB capabilities can coexist on one server.
#
# Delivered to gcp-gce-server as cloud-init stanzas; a systemd unit (not a bare runcmd)
# re-applies the rule on every boot regardless of cloud-init per-boot semantics on COS.

locals {
  redirect_name        = "lb-port-redirect-${var.service_port}"
  redirect_script_path = "/etc/nullstone/${local.redirect_name}.sh"
  redirect_unit_name   = "${local.redirect_name}.service"
  redirect_unit_path   = "/etc/systemd/system/${local.redirect_unit_name}"

  # coalesce keeps templatefile() renderable when server_port is null (stanza is dropped anyway).
  redirect_server_port = coalesce(var.server_port, var.service_port)

  redirect_script = templatefile("${path.module}/templates/lb-port-redirect.sh.tpl", {
    service_port = var.service_port
    server_port  = local.redirect_server_port
  })

  redirect_unit = templatefile("${path.module}/templates/lb-port-redirect.service.tpl", {
    service_port = var.service_port
    server_port  = local.redirect_server_port
    script_path  = local.redirect_script_path
  })

  redirect_stanza = {
    write_files = [
      {
        path        = local.redirect_script_path
        permissions = "0755"
        owner       = "root:root"
        content     = local.redirect_script
      },
      {
        path        = local.redirect_unit_path
        permissions = "0644"
        owner       = "root:root"
        content     = local.redirect_unit
      },
    ]
    runcmd = [
      "systemctl daemon-reload",
      "systemctl enable --now ${local.redirect_unit_name}",
    ]
  }

  cloud_init_stanzas = local.redirect_enabled ? [local.redirect_stanza] : []
}
