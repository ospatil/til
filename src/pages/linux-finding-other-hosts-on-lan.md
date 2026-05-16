---
layout: ../layouts/GistLayout.astro
tags: [linux,mac,networking]
---

# Linux - finding other hosts on LAN

Finding machines on the LAN

### Linux

1. Getting list of hosts: `arp` or `ip neigh`
2. Finding hostname using IP: `host <IP>`

### Mac and Linux

`nmap` can be used to find hosts on the LAN and details of those.

- On Mac, install it using `brew install nmap`
    
    

Find hosts on the LAN: `nmap -sn <CIDR>` for example: `nmap -sn 10.0.0.0/24`

Get details of a host: `sudo nmap -O <IP>`
