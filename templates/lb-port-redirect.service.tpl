[Unit]
Description=Redirect load balancer traffic on port ${service_port} to ${server_port} (nullstone/gcp-gce-tcp-load-balancer)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${script_path}

[Install]
WantedBy=multi-user.target
