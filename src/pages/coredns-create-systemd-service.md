---
layout: ../layouts/GistLayout.astro
tags: [coredns,dns]
---

# Coredns - create systemd service

```toml
[Unit]
Description=CoreDNS DNS Server
After=network.target

[Service]
User=root
Group=root
ExecStart=/opt/coredns/coredns
WorkingDirectory=/opt/coredns
Restart = on-failure
RestartSec = 2

[Install]
WantedBy=multi-user.target
Alias=coredns.service
```
