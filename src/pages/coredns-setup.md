---
layout: ../layouts/GistLayout.astro
tags: [coredns]
---

# CoreDNS - setup

1. Download binary and store it in `/opt/coredns`
2. Edit `/etc/systemd/resolved.conf` and add `DNSStubListener=no`
3. Restart resolved: `sudo systemctl restart systemd-resolved`
4. Create service named `/etc/systemd/system/coredns.service` using the config in [Coredns - create systemd service](../tech-notes/Coredns%20-%20create%20systemd%20service.md)
5. Reload the daemon: `sudo systemctl daemon-reload`
    
    > If you see errors that mention ip is not available: sudo: unable to resolve host <IP>: Resource temporarily unavailable, edit the /etc/hosts file using: sudo vi /etc/hosts and add the mentioned IP : 127.0.0.1 <IP>
    > 
6. Create Corefile in `/opt/coredns/Corefile` using the config in [Coredns - hosts and forward config](../tech-notes/Coredns%20-%20hosts%20and%20forward%20config.md)
7. Start CoreDNS: `sudo systemctl start coredns`
8. If needed, tail the logs of the coredns service using: `sudo journalctl -f -u coredns.service`

Once done, we can setup the DNS server on other Ubuntu machines as per [Ubuntu - set up custom DNS server](../tech-notes/Ubuntu%20-%20set%20up%20custom%20DNS%20server.md)
