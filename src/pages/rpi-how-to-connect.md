---
layout: ../layouts/GistLayout.astro
tags: [linux,mac,networking,rpi,ssh]
---

# rpi - how to connect

How to connect to rpi connected to the same wifi network

1. Get the CIDR of the network. You can find it from command line using `ifconfig` command. Usually `en0` is the interface.

```bash
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	options=6460<TSO4,TSO6,CHANNEL_IO,PARTIAL_CSUM,ZEROINVERT_CSUM>
	ether f4:d4:88:87:5c:9d
	inet6 fe80::872:5e6:1a18:f21f%en0 prefixlen 64 secured scopeid 0xe
	inet 192.168.2.23 netmask 0xffffff00 broadcast 192.168.2.255
	nd6 options=201<PERFORMNUD,DAD>
	media: autoselect
	status: active
```

1. Use `nmap` to find out the hosts on the network using the CIDR from step 1

```bash
Nmap scan report for 192.168.2.30
Host is up (0.066s latency).
MAC Address: D8:3A:DD:15:72:5D (Raspberry Pi Trading)
```

1. Connect to RPI using `ssh`.
