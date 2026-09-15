# 0.1.0 (Unreleased)
* Fix: the port-redirect unit now also accepts `server_port` in the filter `INPUT` chain. `REDIRECT` bypasses Docker's DNAT and delivers to the host `docker-proxy` via `INPUT`, whose policy on Container-Optimized OS is `DROP`, so every redirected client connection was silently dropped.
* Initial release
