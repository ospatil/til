---
layout: ../layouts/GistLayout.astro
tags: [networking, homelab, proxmox, guide]
---

# Home Network Concepts

Notes on networking concepts relevant to home lab setups: virtual IPs, high availability, address types, load balancing, and network segmentation.

---

## Table of Contents

- [Home Network Concepts](#home-network-concepts)
  - [Table of Contents](#table-of-contents)
  - [1. Virtual IPs and Keepalived](#1-virtual-ips-and-keepalived)
  - [2. Gratuitous ARP](#2-gratuitous-arp)
  - [3. Choosing a Virtual IP](#3-choosing-a-virtual-ip)
  - [4. Static IP vs DHCP Reservation](#4-static-ip-vs-dhcp-reservation)
  - [5. Link-Local Addresses](#5-link-local-addresses)
    - [Manually assigning link-local addresses](#manually-assigning-link-local-addresses)
  - [6. Multicast Addresses](#6-multicast-addresses)
  - [7. Loopback Address and Binding](#7-loopback-address-and-binding)
    - [127.0.0.1 vs 0.0.0.0](#127001-vs-0000)
  - [8. Management Network](#8-management-network)
  - [9. IPVS](#9-ipvs)
  - [10. MetalLB and BGP Load Balancing](#10-metallb-and-bgp-load-balancing)
    - [The problem MetalLB solves](#the-problem-metallb-solves)
    - [BGP mode](#bgp-mode)
  - [11. Layer 2 Load Balancing](#11-layer-2-load-balancing)
    - [BGP mode vs Layer 2 mode](#bgp-mode-vs-layer-2-mode)
  - [12. Network Segmentation in a Home Lab](#12-network-segmentation-in-a-home-lab)
  - [13. pfSense](#13-pfsense)
  - [Cross-References](#cross-references)
    - [Kubernetes Network Infrastructure - L2, BGP, and On-Prem Load Balancing](#kubernetes-network-infrastructure---l2-bgp-and-on-prem-load-balancing)
    - [Kubernetes Services and DNS Guide](#kubernetes-services-and-dns-guide)
    - [Docker Networking Guide](#docker-networking-guide)
    - [Linux Networking \& Inter-Process Communication](#linux-networking--inter-process-communication)
    - [Multicasting in Rust](#multicasting-in-rust)
    - [Subnet Calculator](#subnet-calculator)

---

## 1. Virtual IPs and Keepalived

A **virtual IP (VIP)** is an IP address that can "float" between multiple physical servers. Only one server owns and responds to the VIP at any given time, but if that server fails, another takes over automatically.

**Keepalived** is a Linux daemon that implements VRRP (Virtual Router Redundancy Protocol) to manage this failover.

**VRRP roles:**
- **Master** — the active server that owns the VIP and handles traffic
- **Backup** — standby servers that monitor the master and are ready to take over

The master sends periodic VRRP advertisements. If backups stop receiving them, the highest-priority backup promotes itself to master and assumes the VIP.

**Takeover process:**
1. New master binds the VIP to its network interface
2. Sends gratuitous ARP packets to update network switches and routers
3. Begins sending VRRP advertisements as the new master

Failover typically completes within seconds.

**Requirements for the VIP:**
- Must be in the same subnet as the physical interfaces of all participating servers
- All servers must be on the same Layer 2 network segment (same broadcast domain)
- Must be a dedicated IP not used by any other service
- Network switches must support gratuitous ARP
- Firewall must allow VRRP traffic (IP protocol 112, multicast `224.0.0.18`)
- All servers need consistent VRRP group ID, priority settings, and authentication keys

---

## 2. Gratuitous ARP

**Normal ARP** asks: "Who has IP X.X.X.X?" and waits for the owner to respond with their MAC address.

**Gratuitous ARP** is a proactive, unsolicited announcement: "X.X.X.X is at MAC aa:bb:cc:dd:ee:ff" — no one asked for it.

**Why it matters for VIPs:**

When keepalived fails over a VIP from Server A to Server B, all network devices still have Server A's MAC cached for that IP. Without gratuitous ARP, traffic would continue going to the failed server until ARP caches naturally expired (several minutes).

**Failover sequence:**
1. VIP `192.168.1.100` is on Server A (MAC: `aa:bb:cc:dd:ee:ff`)
2. Server A fails — network devices still think the VIP belongs to Server A's MAC
3. Server B takes over — sends gratuitous ARP: "192.168.1.100 is now at `11:22:33:44:55:66`"
4. All network devices update their ARP tables immediately

**Gratuitous ARP packet characteristics:**
- ARP Request format where Source IP = Target IP = the virtual IP
- Broadcast to `ff:ff:ff:ff:ff:ff`
- Sent multiple times in quick succession for reliability

---

## 3. Choosing a Virtual IP

For a subnet `192.168.2.0/24`:
- **Network address**: `192.168.2.0` (cannot be used)
- **Usable range**: `192.168.2.1` to `192.168.2.254`
- **Broadcast address**: `192.168.2.255` (cannot be used)

**With a Bell Gigahub router** (DHCP range `192.168.2.10–254`):

The addresses outside the DHCP range are `192.168.2.2–9`. Using one of these (e.g., `192.168.2.5`) is ideal:
- No DHCP conflicts — the router won't assign it to another device
- Configure it as a static IP on keepalived servers, bypassing DHCP entirely

Alternatively, reserve an address inside the DHCP range with a fake MAC address to block it from assignment, but the out-of-DHCP approach is simpler and more reliable.

---

## 4. Static IP vs DHCP Reservation

| | Static IP | DHCP Reservation |
|---|---|---|
| Configured on | The device itself | The DHCP server |
| DHCP interaction | None | Device still uses DHCP, always gets same address |
| Address range | Any available IP in subnet (even outside DHCP range) | Must be within DHCP pool |

**For infrastructure like a Proxmox server, static IP is the better choice:**
- Doesn't depend on DHCP being available
- Hypervisor stays accessible even if the router reboots or DHCP fails
- Eliminates lease renewal traffic and potential delays

**Recommended layout** (adjust DHCP range to carve out a static block):
```
Router:          192.168.2.1
Static servers:  192.168.2.2  – 192.168.2.20
DHCP clients:    192.168.2.21 – 192.168.2.254
```

---

## 5. Link-Local Addresses

A **link-local address** is automatically assigned to a network interface and is only valid for communication within the local network segment. It requires no DHCP or manual configuration.

**IPv4 link-local (APIPA):**
- Range: `169.254.0.0/16` (`169.254.1.0` to `169.254.254.255`)
- Assigned automatically when DHCP is unavailable
- First and last 256 addresses (`169.254.0.x` and `169.254.255.x`) are reserved

**IPv6 link-local:**
- Range: `fe80::/10`
- Always present on every IPv6-enabled interface
- Generated from MAC address or random number

**How auto-assignment works:**
1. Interface comes up without an IP
2. Device generates a random address in the link-local range
3. ARP/NDP check confirms no other device is using it
4. Address is assigned

**Home network uses:**
- **Fallback communication** — if DHCP fails, devices get `169.254.x.x` addresses and can still communicate locally
- **Direct connections** — connect a laptop directly to a Proxmox server; both get link-local addresses automatically, no configuration needed
- **Device discovery** — Bonjour/mDNS (`224.0.0.251`), UPnP/SSDP (`239.255.255.250`), and Windows file sharing use link-local for finding devices

**Limitations:** No internet access, same subnet only, primarily for local discovery and emergency communication.

### Manually assigning link-local addresses

You can assign them statically for predictable addressing (e.g., a dedicated management network):

```bash
# Linux — add IPv4 link-local
sudo ip addr add 169.254.1.10/16 dev eth1

# Permanent via /etc/network/interfaces
auto eth1
iface eth1 inet static
    address 169.254.1.10
    netmask 255.255.0.0
```

To prevent DHCP and auto-assignment on that interface:

```
# /etc/network/interfaces — use static instead of dhcp
auto eth1
iface eth1 inet static
    address 169.254.1.10
    netmask 255.255.0.0
    post-up echo 0 > /proc/sys/net/ipv6/conf/eth1/autoconf
```

With **systemd-networkd**, create `/etc/systemd/network/eth1.network`:
```ini
[Match]
Name=eth1

[Network]
DHCP=no
LinkLocalAddressing=no

[Address]
Address=169.254.1.10/16
```

---

## 6. Multicast Addresses

A **multicast address** enables one-to-many communication — a single packet sent to a multicast address is received by all devices that have joined that multicast group.

**Unicast vs Multicast:**
- **Unicast**: One sender → one receiver (`192.168.1.10`)
- **Multicast**: One sender → multiple receivers (`224.1.1.1`)

**IPv4 multicast range:** `224.0.0.0` to `239.255.255.255` (`224.0.0.0/4`)
- `224.0.0.0/24` — reserved for local network protocols
- `239.0.0.0/8` — private/organization scope

**IPv6 multicast range:** `ff00::/8`

**Common multicast addresses:**
| Address | Protocol | Use |
|---|---|---|
| `224.0.0.251` | mDNS/Bonjour | Finding printers, AirPlay devices |
| `239.255.255.250` | SSDP/UPnP | Smart home device discovery |
| `224.0.0.18` | VRRP | Keepalived high availability |
| `224.0.0.5/6` | OSPF | Router communication |

**You cannot assign a multicast address as a device's IP** — multicast addresses are destinations, not source addresses. Devices join multicast groups to receive traffic sent to those addresses.

**Network requirements:** Router must support IGMP (Internet Group Management Protocol) for multicast forwarding. Managed switches may need IGMP snooping enabled.

---

## 7. Loopback Address and Binding

The **loopback address** (`127.0.0.1` for IPv4, `::1` for IPv6) refers to "this device itself." Packets sent to it never leave the host — the network stack routes them back internally.

The entire `127.0.0.0/8` range is reserved for loopback, though `127.0.0.1` is the conventional address.

### 127.0.0.1 vs 0.0.0.0

| Bind address | Listens on | Accessible from |
|---|---|---|
| `127.0.0.1` | Loopback interface only | Same machine only |
| `0.0.0.0` | All network interfaces | Other machines on the network |
| Specific IP (e.g., `192.168.2.201`) | That interface only | Anywhere that can reach that IP |

**Example — machine with multiple interfaces:**
```
lo:   127.0.0.1         (loopback)
eth0: 192.168.2.201     (main network)
eth1: 10.0.1.50         (management network)
```

A service bound to `0.0.0.0` accepts connections on all three. A service bound to `127.0.0.1` is only reachable from the same machine.

**Security implication:** Bind databases and internal services to `127.0.0.1` to prevent network exposure. Bind public-facing services to `0.0.0.0` or a specific interface.

---

## 8. Management Network

A **management network** is a dedicated, separate network used exclusively for administrative access to infrastructure — SSH, monitoring, backups, and configuration. It's isolated from regular user traffic.

**Why separate it:**
- Admin access works even when the main network is down or saturated
- Different, stricter firewall rules for management vs user traffic
- Easier to audit administrative access
- Servers can't "admin themselves" if the management network is restricted

**Typical layout:**
```
Main network:       192.168.2.0/24  — user traffic, services
Management network: 10.0.1.0/24    — SSH, monitoring, backups

Proxmox server:
  eth0: 192.168.2.201  (production)
  eth1: 10.0.1.10      (management)
```

**Service binding example:**
```
# /etc/ssh/sshd_config
ListenAddress 10.0.1.10   # SSH only on management interface
```

**With pfSense:**
```
Internet → pfSense
           ├── LAN:  192.168.2.0/24  (users)
           ├── DMZ:  192.168.10.0/24 (servers)
           └── MGMT: 10.0.1.0/24    (admin only)

Firewall rules:
  MGMT → anywhere     (admins need full access)
  LAN  → DMZ services (users access services)
  DMZ  → not MGMT     (servers can't reach admin network)
```

---

## 9. IPVS

**IPVS (IP Virtual Server)** is a Linux kernel module that provides high-performance Layer 4 load balancing. It operates in the kernel's netfilter framework, intercepting packets destined for a virtual IP and distributing them across backend servers.

```
Client → Virtual IP (VIP) → IPVS Director → Real Servers
                                         ├── Server 1
                                         ├── Server 2
                                         └── Server 3
```

**Forwarding methods:**
- **NAT** — IPVS rewrites the destination IP to the backend server
- **Direct Routing** — IPVS changes the MAC address; servers respond directly to clients
- **Tunneling** — IPVS encapsulates packets to reach remote servers

**Scheduling algorithms:** round robin, weighted round robin, least connections, source/destination hashing.

**Basic setup:**
```bash
apt install ipvsadm

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Create a virtual service (round robin on port 80)
ipvsadm -A -t 192.168.2.150:80 -s rr

# Add backend servers
ipvsadm -a -t 192.168.2.150:80 -r 192.168.2.201:80 -m
ipvsadm -a -t 192.168.2.150:80 -r 192.168.2.202:80 -m

ipvsadm -ln  # View configuration
```

**Integration with keepalived** — the two complement each other naturally:
- Keepalived provides VIP failover (the VIP stays available)
- IPVS provides load balancing behind that VIP

```
# keepalived.conf
virtual_server 192.168.2.100 80 {
    lb_algo rr
    lb_kind NAT

    real_server 192.168.2.201 80 {
        weight 1
        HTTP_GET { url { path / status_code 200 } }
    }
    real_server 192.168.2.202 80 {
        weight 1
        HTTP_GET { url { path / status_code 200 } }
    }
}
```

---

## 10. MetalLB and BGP Load Balancing

### The problem MetalLB solves

In cloud environments, creating a Kubernetes `LoadBalancer` service automatically provisions an external load balancer. On bare metal, there's no cloud provider to do this. MetalLB fills that gap.

### BGP mode

Each Kubernetes node runs a MetalLB speaker that establishes a BGP peering session with your router. When a `LoadBalancer` service is created:

1. MetalLB assigns an external IP from its configured pool (e.g., `192.168.2.100`)
2. Every node advertises a BGP route: "192.168.2.100/32 is reachable via me"
3. The router sees multiple equal-cost paths to the same IP
4. The router distributes traffic across all nodes (ECMP)

```
Client → Router (3 BGP routes to 192.168.2.100) → Any node → Pod
              ├── via Node1 (192.168.2.201)
              ├── via Node2 (192.168.2.202)
              └── via Node3 (192.168.2.203)
```

**Route withdrawal on failure:** If a node goes down, its BGP session drops and the router removes routes through it. Traffic automatically flows to the remaining nodes.

**Configuration:**
```yaml
apiVersion: metallb.io/v1beta1
kind: BGPPeer
metadata:
  name: router-peer
spec:
  myASN: 65001        # Cluster's AS number
  peerASN: 65000      # Router's AS number
  peerAddress: 192.168.2.1

---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
spec:
  addresses:
  - 192.168.2.100-192.168.2.110
```

**Router requirement:** BGP mode requires a BGP-capable router (pfSense/OPNsense with FRR, Mikrotik, or a Linux router VM). Most consumer routers don't support BGP.

---

## 11. Layer 2 Load Balancing

Layer 2 load balancing operates at the Data Link Layer using ARP rather than routing protocols. It's simpler but provides failover rather than true load distribution.

**How it works:**
- Multiple servers share a virtual IP
- Only one server (the "active" one) responds to ARP requests for that VIP
- All traffic flows to that server until failover occurs

**MetalLB Layer 2 mode:**
```
Client ARP: "Who has 192.168.2.100?"
  → Only Node1 responds: "192.168.2.100 is at MAC aa:bb:cc:dd:ee:ff"
  → All traffic goes to Node1
```

**Failover:** When Node1 fails, Node2 detects it, starts responding to ARP for the VIP, and sends a gratuitous ARP to update all ARP caches.

**MetalLB Layer 2 configuration:**
```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
spec:
  ipAddressPools:
  - default-pool
```

### BGP mode vs Layer 2 mode

| | Layer 2 | BGP |
|---|---|---|
| Traffic distribution | Single active node (failover only) | All nodes simultaneously |
| Router requirement | Any switch | BGP-capable router |
| Complexity | Simple | Requires BGP configuration |
| Use case | Home lab, small setups | Production, larger scale |

---

## 12. Network Segmentation in a Home Lab

You can simulate a public/private network topology in Proxmox using virtual bridges — no VLANs or extra hardware required.

**Virtual network approach (works with any consumer router):**
```
Bell Router (192.168.2.0/24) — "internet"
    ↓
Proxmox Host
    ↓
Router VM:
  WAN: 192.168.2.100 (vmbr0 — connected to real network)
  LAN: 10.0.1.1      (vmbr1 — internal only)
    ↓
Private VMs (10.0.1.0/24) — isolated network
```

**Router VM setup (iptables NAT):**
```bash
# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# NAT: private VMs can reach internet through WAN interface
iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -o eth0 -j MASQUERADE

# Allow established connections back
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Block unsolicited inbound to private network
iptables -A FORWARD -i eth0 -o eth1 -j DROP
```

---

## 13. pfSense

**pfSense** is a free, open-source firewall and router OS based on FreeBSD. It provides enterprise-grade networking features through a web interface.

**Core capabilities:**
- Stateful packet filtering firewall
- NAT/PAT
- VPN (OpenVPN, IPSec, WireGuard)
- Traffic shaping and bandwidth control
- DHCP and DNS server
- Intrusion detection/prevention (Snort, Suricata)
- High availability with CARP (similar to keepalived)
- BGP support via the FRR package

**In a home lab, pfSense is useful for:**
- Network segmentation (LAN, DMZ, IoT, Guest VLANs)
- VPN gateway for remote access
- Replacing a consumer router's routing functions (put Bell router in bridge mode)
- Learning enterprise firewall concepts
- BGP peering for MetalLB

**Compared to a consumer router:**

| | Consumer Router | pfSense |
|---|---|---|
| Firewall | Basic NAT | Stateful, thousands of rule combinations |
| VPN | Limited or none | OpenVPN, IPSec, WireGuard |
| Monitoring | Minimal | Detailed traffic analysis and logging |
| Routing protocols | None | BGP, OSPF via FRR |
| Configuration | Consumer UI | Professional web interface |

pfSense can run as a Proxmox VM, making it easy to integrate into a home lab without dedicated hardware.

---

## Cross-References

### [Kubernetes Network Infrastructure - L2, BGP, and On-Prem Load Balancing](k8s-network-infrastructure.md)

The closest related guide. Covers the same L2/ARP, Gratuitous ARP, BGP, and MetalLB concepts but from a Kubernetes cluster perspective rather than a home lab infrastructure perspective. Also includes ARP and BGP protocol deep dives, ECMP, and CNI overlay vs native networking.

### [Kubernetes Services and DNS Guide](k8s-services-dns.md)

Covers Kubernetes service types (ClusterIP, NodePort, LoadBalancer), MetalLB configuration, and how services relate to DNS inside a cluster.

### [Docker Networking Guide](docker-networking.md)

Covers `0.0.0.0` vs `127.0.0.1` binding in containers in detail, including why binding to loopback inside a container prevents external access.

### [Linux Networking & Inter-Process Communication](linux-networking-and-ipc.md)

Covers the TCP/IP stack, socket addressing, and the `0.0.0.0` vs `127.0.0.1` distinction at the Linux syscall level.

### [Multicasting in Rust](multicasting-in-rust.md)

Practical multicast socket programming — joining groups, sending and receiving multicast packets.

### [Subnet Calculator](subnet-calculator.md)

Reference for subnet math: CIDR notation, usable ranges, broadcast addresses — relevant to the VIP selection section above.
