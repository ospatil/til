# Kubernetes Network Infrastructure — L2, BGP, and On-Prem Load Balancing

A companion to [01-k8s-services-dns.md](./01-k8s-services-dns.md). That doc covers Kubernetes service types, DNS, and traffic policies. This doc goes deeper into the network infrastructure underneath — how traffic actually enters the cluster on-prem, the protocols involved, and the load balancing options available when there's no cloud provider.

---

## 1. The On-Prem Problem

In cloud environments (EKS, GKE, AKS), creating a `LoadBalancer` Service automatically provisions a cloud load balancer. On-prem, there's no cloud API to call — the Service stays in `Pending` state unless something fulfills it.

The two main approaches to solve this:

- **L2 Announcements** — a node claims a Virtual IP (VIP) via ARP on the local network segment
- **BGP Route Advertisement** — nodes advertise VIP routes to upstream routers

Both make `LoadBalancer` Services work on bare-metal clusters by assigning external IPs and making them reachable from outside the cluster.

---

## 2. L2 Announcements

### How It Works

L2 Announcements make service VIPs reachable on the local area network by responding to ARP queries. One node at a time "owns" each VIP.

1. A `LoadBalancer` Service is created and assigned a VIP (e.g., `192.168.1.100`)
2. Via leader election, one node becomes the owner of that VIP
3. When any device on the L2 segment sends an ARP request ("Who has 192.168.1.100?"), the owning node responds with its MAC address
4. All traffic for that VIP flows to the owning node
5. The owning node uses kube-proxy/eBPF to load-balance across backend pods on any node

```
Client → ARP "Who has 192.168.1.100?" → Node2 responds with its MAC
Client → 192.168.1.100 → Node2 → kube-proxy → Pod (any node)
```

### Failover via Gratuitous ARP

When the owning node fails:

1. Another node wins leader election for the VIP
2. It sends a **gratuitous ARP** — an unsolicited broadcast announcing "192.168.1.100 is now at my MAC"
3. All devices on the segment (switches, routers, hosts) update their ARP tables
4. Traffic seamlessly redirects to the new node

### Advantages Over NodePort

- Each service gets a **unique IP** — multiple services can use port 80/443
- Clients don't need to know about individual node IPs
- Automatic failover — VIP migrates to a healthy node

### Limitations

- **Single entry point** — all traffic for a VIP enters through one node (potential bottleneck)
- **L2 scope only** — only works within a single broadcast domain (VLAN/subnet). The router/gateway for external clients must be on the same L2 segment as the cluster nodes
- **No true pre-cluster load balancing** — unlike BGP with ECMP

### Who Actually Sends the ARP?

Clients outside the cluster don't send ARP directly. The **router/gateway** on the same L2 segment does:

1. External client sends packet to VIP `192.168.1.100`
2. Internet/WAN routing delivers it to the local router
3. Router sees VIP is in its local subnet, sends ARP to resolve the MAC
4. Kubernetes node responds, router forwards the packet

This is why L2 Announcements are described as being for "office or campus networks" — the cluster's gateway must be on the same broadcast domain.

---

## 3. BGP Route Advertisement

BGP is the enterprise-grade alternative that works across routed networks (multiple subnets, data centers).

### How It Works

Instead of ARP, Kubernetes nodes establish **BGP peering sessions** (TCP port 179) with upstream routers and advertise VIP routes:

1. Each node configured as a BGP speaker connects to the upstream router
2. When a node owns a VIP, it sends a BGP UPDATE: "Route to 192.168.100.10/32 via me"
3. The router installs this route and can propagate it further
4. Traffic for the VIP is routed to the advertising node

```
Node1 → Router: BGP UPDATE "192.168.100.10/32 via 192.168.1.10"
Router installs route → forwards traffic to Node1
```

### ECMP — True Multi-Node Load Balancing

Unlike L2 (single owner), BGP supports **Equal Cost Multi-Path** — multiple nodes advertise the same route:

```
Node1 → Router: "192.168.100.10/32 via 192.168.1.10"
Node2 → Router: "192.168.100.10/32 via 192.168.1.11"
Node3 → Router: "192.168.100.10/32 via 192.168.1.12"

Router: ECMP group → load-balances across all three nodes
```

This eliminates the single-entry-point bottleneck of L2.

### Failover

When a node fails, its BGP session drops. The router receives a WITHDRAW message (or detects session timeout) and removes that route. Traffic redistributes across remaining nodes.

### Requirements

- **BGP-capable routers** (Cisco, Juniper, Arista, or open-source FRR)
- **ASN allocation** (private ASNs 64512–65535 for internal use)
- **BGP peering configuration** on both the router and Kubernetes side
- **Network engineering expertise**

### BGP Message Types

| Message | Purpose |
|---|---|
| OPEN | Establish peering session (ASN, capabilities) |
| UPDATE | Advertise new routes or withdraw old ones |
| KEEPALIVE | Maintain session (heartbeat) |
| NOTIFICATION | Signal errors or close session |

---

## 4. L2 vs BGP — When to Use Which

| | L2 Announcements | BGP |
|---|---|---|
| **Network scope** | Single broadcast domain | Multi-subnet, multi-datacenter |
| **Protocol** | ARP (Layer 2) | BGP over TCP (Layer 3) |
| **Load balancing** | Single node per VIP | ECMP across multiple nodes |
| **Failover** | Gratuitous ARP (seconds) | BGP convergence (faster, tunable) |
| **Infrastructure needed** | None (just a LAN) | BGP-capable routers |
| **Expertise needed** | Minimal | Network engineering |
| **Best for** | Office/campus, simple setups | Enterprise, multi-segment networks |

### Choose L2 when:
- Simple office/campus network, single subnet
- Limited networking expertise
- Moderate traffic, simplicity over performance

### Choose BGP when:
- Enterprise network with multiple subnets/VLANs
- Need true multi-node load balancing (ECMP)
- Multi-datacenter deployments
- Have BGP-capable infrastructure and expertise

---

## 5. On-Prem Load Balancer Solutions

Three categories of solutions fulfill `LoadBalancer` Services on bare-metal:

### MetalLB

- **What it does**: VIP advertisement only (L2 or BGP). Assigns external IPs to Services and announces them.
- **What it doesn't do**: No data plane — relies entirely on kube-proxy for packet forwarding
- **Works with**: Any CNI
- **Maturity**: Widely deployed, large community

### Cilium LB-IPAM

- **What it does**: Full load balancing integrated into the CNI — IP allocation, L2/BGP advertisement, and eBPF-based data plane
- **Advantages over MetalLB**: Better performance (eBPF, no iptables), built-in observability via Hubble, integrated network policy enforcement
- **Trade-off**: Must use Cilium as your CNI

### LoxiLB

- **What it does**: Complete eBPF-based load balancer with its own control and data plane
- **Differentiator**: Designed for telecom — strong SCTP support, active health checks per Service, built-in metrics
- **Works with**: Any CNI (standalone, like MetalLB)
- **Trade-off**: Smaller community, CNCF sandbox project

### Comparison

| | MetalLB | Cilium LB-IPAM | LoxiLB |
|---|---|---|---|
| **Data plane** | None (kube-proxy) | eBPF (integrated) | eBPF (standalone) |
| **Health checks** | None (relies on K8s) | Integrated | Active per-service |
| **Observability** | Basic metrics | Hubble (deep) | Built-in dashboards |
| **CNI requirement** | Any | Cilium only | Any |
| **Protocol support** | TCP/UDP | TCP/UDP | TCP/UDP/SCTP |
| **Community** | Large | Large (CNCF graduated) | Small (CNCF sandbox) |

### Control Plane vs Data Plane

In the context of these load balancers:

- **Control plane** — decides *where* traffic goes: service discovery, endpoint management, health checking, VIP assignment, BGP/ARP advertisement, leader election
- **Data plane** — actually *forwards* packets: NAT, load balancing to backends, connection tracking, packet filtering

MetalLB only has a control plane. Cilium and LoxiLB have both.

---

## 6. Overlay vs Native CNI

This distinction matters for load balancing because it determines whether pod IPs are routable from outside the cluster.

### Overlay CNI (Flannel, Weave)

Pods get IPs from a virtual address space. Traffic between nodes is **encapsulated** (typically VXLAN):

```
Pod on Node1 (10.244.0.5) → Pod on Node2 (10.244.1.8):

Original:  [src: 10.244.0.5 → dst: 10.244.1.8]
Encapsulated: [src: 192.168.1.10 → dst: 192.168.1.11] wrapping [10.244.0.5 → 10.244.1.8]
```

The physical network only sees host-to-host traffic. Pod IPs (`10.244.x.x`) are **not routable** from outside the cluster — external routers have no routes to them.

**Consequence**: External load balancers cannot target pod IPs directly. Traffic must enter via NodePort or a VIP on a node.

### Native/Routed CNI (AWS VPC CNI, Calico BGP mode)

Pods get real IPs from the host network (e.g., VPC subnet). No encapsulation — packets route directly.

```
Pod on Node1 (10.0.1.101) → Pod on Node2 (10.0.1.201):

Packet: [src: 10.0.1.101 → dst: 10.0.1.201]  ← routed directly, no wrapping
```

The network infrastructure knows about pod IPs. External load balancers **can target pods directly** (IP target mode).

**Consequence**: Cloud LBs (NLB/ALB) can skip NodePort entirely and route to pod IPs. See [IP Target vs Instance Target Mode](./01-k8s-services-dns.md#ip-target-vs-instance-target-mode) in the services doc.

| | Overlay (Flannel) | Native (VPC CNI) |
|---|---|---|
| **Pod IPs** | Virtual, not externally routable | Real, externally routable |
| **Encapsulation** | Yes (VXLAN/UDP) | No |
| **Performance** | Overhead from encap/decap | Native speed |
| **External LB → pod** | Not possible | Possible (IP target mode) |
| **Portability** | Works anywhere | Requires specific infra |

---

## 7. External Load Balancers (NGINX, HAProxy)

Traditional load balancers can front a Kubernetes cluster on-prem. The main challenge is **service discovery** — how does the LB know about pod/node endpoints?

### Option 1: Static NodePort Config

Point the LB at node IPs + NodePort. Simple but requires manual updates when nodes change.

```nginx
# nginx.conf
upstream backend {
    server 192.168.1.10:30080;  # node1
    server 192.168.1.11:30080;  # node2
    server 192.168.1.12:30080;  # node3
}
```

### Option 2: Dynamic Discovery via Consul

Consul's `consul-k8s` controller watches the Kubernetes API for Service/Endpoints changes and syncs them into Consul's service catalog. Then `consul-template` regenerates the LB config automatically:

```
K8s Endpoints change → consul-k8s syncs to Consul catalog →
consul-template regenerates nginx.conf → NGINX reloads
```

Template example:

```hcl
upstream backend {
{{range service "web-service"}}
  server {{.Address}}:{{.Port}};
{{end}}
}
```

Each pod backing the service is registered individually in Consul — the LB gets fine-grained endpoint awareness.

### Option 3: External Ingress Controller

Run an ingress controller (HAProxy, NGINX) **outside** the cluster, connected to the Kubernetes API. It watches Ingress/Service resources and configures itself dynamically.

### When to Use External LBs

- Need advanced L7 features (caching, rate limiting, WAF)
- Already have NGINX/HAProxy expertise and infrastructure
- Want to load-balance both K8s and non-K8s services
- Need dedicated hardware for LB performance

### Comparison with K8s-Native Solutions

| | MetalLB/Cilium/LoxiLB | External NGINX/HAProxy |
|---|---|---|
| **Service discovery** | Automatic (K8s native) | Needs Consul/static config |
| **Failover** | Built-in leader election | Separate HA setup needed |
| **L7 features** | Limited | Rich (caching, WAF, etc.) |
| **Operational model** | K8s-native | Traditional infra |

---

## 8. Protocol Deep Dives

### ARP (Address Resolution Protocol)

ARP resolves IP addresses to MAC addresses on a local network segment.

**ARP Request** — broadcast to `FF:FF:FF:FF:FF:FF` (MAC broadcast, not IP `255.255.255.255`):

```
Ethernet: dst=FF:FF:FF:FF:FF:FF  src=<requester MAC>
ARP:      op=REQUEST  sender-ip=192.168.1.50  target-ip=192.168.1.100
```

Every device on the L2 segment receives it. Only the device owning the target IP responds (unicast):

```
Ethernet: dst=<requester MAC>  src=<owner MAC>
ARP:      op=REPLY  sender-ip=192.168.1.100  sender-mac=<owner MAC>
```

**Gratuitous ARP** — unsolicited broadcast announcing an IP→MAC mapping. Used during VIP failover to force all devices to update their ARP tables immediately.

**Security note**: ARP has no authentication. Any device can claim any IP (ARP spoofing). In Kubernetes, leader election ensures only one node claims each VIP.

### BGP (Border Gateway Protocol)

BGP exchanges routing information between autonomous systems over **persistent TCP sessions** (port 179). Unlike ARP broadcasts, BGP is point-to-point and stateful.

**Session lifecycle**:

```
Idle → Connect → OpenSent → OpenConfirm → Established
                                              ↑ routes exchanged here
```

**Route advertisement** (UPDATE message):

```
NLRI:       192.168.100.10/32          (the VIP)
Next-Hop:   192.168.1.10               (the advertising node)
AS-Path:    65001                       (originating AS)
```

**Route withdrawal** — when a node stops owning a VIP or its session drops, the router removes the route and stops forwarding traffic to it.

**Path attributes** control how routes propagate: AS-Path (loop prevention), Local-Pref (prefer certain paths), MED (influence inbound traffic), Communities (tagging for policy).

### SCTP (Stream Control Transmission Protocol)

A transport protocol combining TCP reliability with UDP message boundaries:

- **Multi-streaming** — multiple independent data streams in one connection
- **Multi-homing** — single connection across multiple network paths for redundancy
- **Message-oriented** — preserves message boundaries (unlike TCP's byte stream)

Primarily used in telecom (SIP signaling, Diameter, SS7-over-IP). LoxiLB's strong SCTP support is why it's positioned for telecom environments.

---

## 9. Network Addressing Modes

Understanding how packets are addressed ties together many concepts in this doc.

### Unicast (one-to-one)

A packet sent to a single specific destination. Most network traffic is unicast.

- **BGP peering sessions** — TCP between one node and one router
- **Pod-to-pod traffic** — one source IP to one destination IP
- **kube-proxy forwarding** — after DNAT, traffic goes to one specific pod

### Broadcast (one-to-all-on-segment)

A packet sent to all devices on a local network segment.

- **ARP requests** — MAC broadcast `FF:FF:FF:FF:FF:FF`, received by all devices on the L2 segment
- **Limited broadcast** (`255.255.255.255`) — IP-level broadcast, never forwarded by routers (RFC 919). Used by DHCP discovery.
- **Directed broadcast** (e.g., `192.168.2.255`) — targets a specific subnet's broadcast address. Routers *can* forward but usually don't (security risk).

L2 Announcements rely on ARP broadcast, which is why they're confined to a single broadcast domain.

### Anycast (one-to-nearest)

The same IP address is advertised from **multiple locations**. Routers send traffic to the nearest/best one.

This is exactly what BGP ECMP does in section 3 — multiple nodes advertise the same VIP route:

```
Node1 → Router: "192.168.100.10/32 via me"
Node2 → Router: "192.168.100.10/32 via me"
Node3 → Router: "192.168.100.10/32 via me"

Router: picks nearest/best path (or load-balances across all)
```

Anycast is also used at internet scale:
- **DNS root servers** — the same IP serves DNS from hundreds of locations worldwide
- **CDNs (Cloudflare, AWS CloudFront)** — client traffic routes to the nearest edge node
- **AWS Global Accelerator** — anycast IPs route to the nearest AWS region

The key property: anycast provides **geographic load balancing and fault tolerance** without the client knowing anything about the topology. If one node goes down, traffic automatically routes to the next nearest.

In Kubernetes terms: L2 Announcements give you a VIP owned by one node (unicast with failover). BGP with ECMP gives you anycast — the same VIP served by multiple nodes simultaneously.

### Multicast (one-to-group)

A packet sent to a group of interested receivers — not all devices (broadcast), not one (unicast), but a subscribed subset.

**How it works:**
- IP range `224.0.0.0/4` (224.0.0.0 – 239.255.255.255) is reserved for multicast
- A sender transmits once to a multicast group address (e.g., `239.1.1.1`)
- The network replicates the packet only to hosts that have joined that group
- **IGMP** (Internet Group Management Protocol) handles group membership — hosts tell their local router "I want to receive group 239.1.1.1"
- **PIM** (Protocol Independent Multicast) handles routing between routers — ensures multicast traffic reaches all network segments with interested receivers
- At L2, multicast IP addresses map to special MAC addresses (`01:00:5e:xx:xx:xx`), so switches can forward selectively

**How applications use it:**
- **Video/audio streaming** — one source, many viewers. The source sends once; the network replicates. Far more efficient than sending individual unicast streams to each viewer.
- **Financial market data** — stock exchanges publish price feeds to a multicast group. Thousands of trading systems subscribe and receive simultaneously.
- **Service/cluster discovery** — protocols like mDNS (`224.0.0.251`), VRRP, and older cluster membership systems (JGroups) use multicast to find peers without a central registry.
- **Gaming** — multiplayer game state updates broadcast to all players in a session.

The key advantage: the sender transmits once regardless of how many receivers exist. The network handles replication. With unicast, the sender would need one copy per receiver.

#### Multicast Beyond the LAN

IP multicast was designed for local/campus networks. It breaks down in distributed scenarios:

- **No multicast routing across the internet** — ISPs don't enable PIM or carry multicast between autonomous systems. There's no global multicast routing table.
- **Cloud providers don't support it across regions** — AWS VPC multicast only works within a single VPC via Transit Gateway. No cross-region, no cross-cloud.
- **NAT breaks it** — IGMP group joins don't traverse NAT gateways.

In practice, distributed multicast uses one of these approaches:

**Application-level fan-out (most common):**
The application builds its own distribution tree using unicast connections. The "multicast" happens at the app layer, not the network:

```
Source → Relay A (US-East) → Subscribers 1, 2
                            → Relay B (EU-West) → Subscribers 3, 4
```

This is how Kafka, NATS, Redis pub/sub, and WebSocket fan-out work — producers write once, the middleware replicates and fans out over unicast.

**Multicast-to-unicast gateways:**
For legacy apps that speak native multicast, a gateway at each site captures multicast traffic and tunnels it (GRE/VXLAN) to remote sites, which re-inject it as local multicast. Common in financial services for bridging stock exchange feeds across data centers.

**Protocols designed for wide-area distribution:**
MQTT (IoT), AMQP — message protocols built for distributed pub/sub over unicast from the start.

The bottom line: once you cross network boundaries, everyone falls back to application-level fan-out over unicast. The sender still transmits once, but replication happens in middleware rather than network routers.

#### Multicast on Kubernetes

Not used in Kubernetes service networking, and most CNIs don't support it:

- **Overlay CNIs (Flannel, Calico VXLAN)** — encapsulate packets in unicast tunnels. Multicast semantics are lost inside the tunnel.
- **VPC CNI (AWS)** — AWS VPC doesn't support IP multicast between ENIs (except via Transit Gateway multicast domains, a separate feature).
- **Host networking (`hostNetwork: true`)** — pods share the node's network stack and *can* do multicast if the physical network supports it, but you lose pod isolation.

#### Approaches that work

**Multicast-capable CNI:**
- **Weave Net** — supports multicast natively, replicates packets across its overlay via gossip
- **Macvlan/IPVLAN CNI** — pods get interfaces directly on the physical network, so multicast works if the LAN supports it. But you lose network policy, service mesh, etc.
- **Calico in BGP mode (unencapsulated)** — if the physical network supports multicast routing (PIM), it can work since pod IPs are routable

**Application-level workaround:**
- Replace multicast with a message broker (Kafka, NATS, Redis pub/sub). Publish to a topic, subscribers receive via unicast. Most common approach — redesign the app to not need multicast.

**Multus + secondary interface:**
- Use Multus CNI to attach a second network interface to pods
- Primary interface: normal CNI (Calico/Cilium) for K8s services
- Secondary interface: Macvlan/SR-IOV on a multicast-capable network
- Common in telecom/5G workloads (which is also where SCTP from section 8 shows up)

Most teams running multicast on Kubernetes (telecom, financial services) use the Multus approach — a dedicated multicast network alongside the regular CNI, rather than trying to make the primary CNI support it.

---

## 10. Summary

| Topic | Solution | Scope |
|---|---|---|
| Expose services on-prem (simple) | L2 Announcements (MetalLB/Cilium) | Single LAN segment |
| Expose services on-prem (enterprise) | BGP (MetalLB/Cilium/Calico) | Multi-subnet, multi-DC |
| Full LB with health checks | Cilium LB-IPAM or LoxiLB | Any |
| External LB with K8s discovery | NGINX/HAProxy + Consul | Any |
| Cloud LB direct-to-pod | IP target mode (VPC CNI) | Cloud only |

The progression for on-prem:
1. **NodePort** — works but exposes cluster topology, port conflicts
2. **L2 Announcements** — unique VIPs, automatic failover, single broadcast domain
3. **BGP** — multi-node ECMP, multi-subnet, enterprise-grade
4. **External LB** — advanced L7 features, hybrid K8s + non-K8s

---

## Cross-References

### Related: Kubernetes Services & DNS Guide

See [01-k8s-services-dns.md](./01-k8s-services-dns.md) for:

- **Service types** (ClusterIP, NodePort, LoadBalancer, ExternalName, Headless) — detailed specs and traffic flows
- **IP Target vs Instance Target Mode** — how cloud LBs bypass NodePort with VPC CNI
- **MetalLB bare-metal section** — how MetalLB fulfills LoadBalancer Services
- **Ingress & Gateway API** — L7 routing that sits in front of Services
- **ExternalDNS** — bridging cluster DNS to external DNS providers
- **Traffic Policies** — `externalTrafficPolicy` and `internalTrafficPolicy` behavior
