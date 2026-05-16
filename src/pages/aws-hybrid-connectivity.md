---
layout: ../layouts/GistLayout.astro
tags: [aws, networking]
---

# AWS Hybrid & Multi-VPC Connectivity Guide

A comprehensive reference for AWS hybrid connectivity terms, concepts, and architecture patterns.

---

## Table of Contents

1. [Core Terms & Definitions](#core-terms--definitions)
2. [VPC-to-VPC Connectivity](#vpc-to-vpc-connectivity)
3. [On-Premises to AWS Connectivity](#on-premises-to-aws-connectivity)
4. [Remote/Client Access](#remoteclient-access)
5. [AWS Cloud WAN](#aws-cloud-wan)
6. [Direct Connect Deep Dive](#direct-connect-deep-dive)
7. [Architecture Patterns](#architecture-patterns)
8. [Decision Matrices](#decision-matrices)

---

## Core Terms & Definitions

### What are the key terms and concepts in AWS hybrid connectivity?

#### Gateways

| Term | Description |
|------|-------------|
| **VGW (Virtual Private Gateway)** | VPN/DX termination point attached to a single VPC; supports both VPN and Direct Connect via Private VIF |
| **CGW (Customer Gateway)** | Logical representation of your on-premises router/firewall device in AWS; contains public IP and ASN info |
| **TGW (Transit Gateway)** | Regional network hub that connects VPCs, VPNs, Direct Connect, and other TGWs; supports transitive routing |
| **DXGW (Direct Connect Gateway)** | Global resource that connects Direct Connect to multiple VGWs or TGWs across any AWS region |
| **IGW (Internet Gateway)** | Enables internet access for VPC resources; horizontally scaled and highly available |
| **NAT Gateway** | Allows private subnet resources to access internet while remaining unreachable from internet |

#### Connection Types

| Term | Description |
|------|-------------|
| **VPC Peering** | Direct private connection between two VPCs; non-transitive, works cross-region and cross-account |
| **Transit Gateway Peering** | Connects TGWs across regions; enables global transitive network |
| **PrivateLink (VPC Endpoint Services)** | Privately expose services to other VPCs via ENI; consumer-provider model, highly secure |
| **Gateway Endpoints** | Free endpoints for S3 and DynamoDB; route table entries, no ENI required |
| **Interface Endpoints** | ENI-based endpoints for AWS services; uses PrivateLink, costs per hour and per GB |
| **Site-to-Site VPN** | IPsec encrypted tunnel over internet to VGW or TGW; quick setup, up to 1.25 Gbps per tunnel |
| **Client VPN** | OpenVPN-based managed service for remote user access to AWS and on-premises resources |
| **Direct Connect (DX)** | Dedicated physical connection from on-premises to AWS; 1/10/100 Gbps dedicated or 50Mbps-10Gbps hosted |
| **Cloud WAN** | Global network service that uses a central policy to create and manage networks spanning multiple regions and accounts |

#### Direct Connect Components

| Term | Description |
|------|-------------|
| **DX Location** | Physical colocation facility where AWS has presence; you colocate or connect via partner |
| **DX Connection** | Physical port allocation - Dedicated (you own) or Hosted (partner owns) |
| **VIF (Virtual Interface)** | Logical 802.1Q VLAN over DX connection; carries traffic to specific destinations |
| **Private VIF** | Access VPC private resources via VGW or DXGW; uses private IP space |
| **Public VIF** | Access all AWS public services and IPs over dedicated connection (not internet) |
| **Transit VIF** | Connect to Transit Gateway via DXGW; required for TGW connectivity over DX |
| **Hosted VIF** | VIF created by DX partner and shared to your account; you don't own the connection |
| **LAG (Link Aggregation Group)** | Bundle up to 4 DX connections for increased bandwidth and redundancy |
| **MACsec** | Layer 2 encryption for DX connections; available on 10Gbps and 100Gbps dedicated connections |

#### Cloud WAN Components

| Term | Description |
|------|-------------|
| **Global Network** | Top-level container for your Cloud WAN; spans all regions |
| **Core Network** | Managed network within Global Network; defined by policy document |
| **Core Network Policy** | JSON document defining segments, attachments, and routing behavior |
| **Segment** | Routing domain within Core WAN; isolates traffic (e.g., prod, dev, shared) |
| **Attachment** | Connection to Core Network - VPC, VPN, Direct Connect, or TGW Route Table |
| **Core Network Edge (CNE)** | Regional presence of Core Network; similar to TGW but managed by Cloud WAN |

#### Routing Concepts

| Term | Description |
|------|-------------|
| **BGP (Border Gateway Protocol)** | Dynamic routing protocol; required for DX, optional for VPN |
| **ASN (Autonomous System Number)** | Unique identifier for BGP peers; AWS default is 64512, you bring your own |
| **AS_PATH** | BGP attribute showing path through autonomous systems; used for path selection |
| **MED (Multi-Exit Discriminator)** | BGP attribute to influence inbound traffic path selection |
| **LOCAL_PREF** | BGP attribute for outbound path selection; higher is preferred |
| **ECMP (Equal Cost Multi-Path)** | Load balancing across multiple equal-cost paths; TGW supports up to 50 VPN tunnels |

---

## VPC-to-VPC Connectivity

### What are the different ways to connect VPCs to each other?

### VPC Peering

```
┌────────────────────────────────────────────────────────────────────────┐
│                                                                        │
│   Account A                              Account B                     │
│   ┌─────────────────────┐                ┌─────────────────────┐       │
│   │  VPC-A (10.0.0.0/16)│                │  VPC-B (10.1.0.0/16)│       │
│   │                     │                │                     │       │
│   │  ┌───────────────┐  │                │  ┌───────────────┐  │       │
│   │  │ EC2 Instance  │  │                │  │ EC2 Instance  │  │       │
│   │  │ 10.0.1.10     │  │                │  │ 10.1.1.10     │  │       │
│   │  └───────────────┘  │                │  └───────────────┘  │       │
│   │                     │                │                     │       │
│   │  Route Table:       │                │  Route Table:       │       │
│   │  10.1.0.0/16→pcx-xx │                │  10.0.0.0/16→pcx-xx │       │
│   └──────────┬──────────┘                └──────────┬──────────┘       │
│              │                                      │                  │
│              │         VPC Peering Connection       │                  │
│              │            pcx-xxxxxxxx              │                  │
│              └──────────────────────────────────────┘                  │
│                                                                        │
│   ⚠️  Non-transitive: A↔B, B↔C does NOT mean A↔C                       |
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

**VPC Peering Characteristics:**

| Feature | Details |
|---------|---------|
| Transitivity | Non-transitive (A↔B, B↔C does NOT mean A↔C) |
| Bandwidth | No limit (uses AWS backbone) |
| Cross-Region | Supported (inter-region peering) |
| Cross-Account | Supported |
| IP Overlap | Not allowed between peered VPCs |
| Cost | Free within AZ, $0.01/GB cross-AZ, $0.02/GB cross-region |
| Max Peerings | 125 per VPC (can request increase) |

### Transit Gateway

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                    AWS CLOUD (us-east-1)                               │
│                                                                                        │
│         VPC-A (Prod)              VPC-B (Dev)               VPC-C (Shared)             │
│        10.1.0.0/16               10.2.0.0/16                10.3.0.0/16                │
│    ┌────────────────┐        ┌────────────────┐        ┌────────────────┐              │
│    │ ┌────┐ ┌────┐  │        │ ┌────┐ ┌────┐  │        │ ┌────┐ ┌────┐  │              │
│    │ │App │ │ DB │  │        │ │App │ │ DB │  │        │ │DNS │ │Mail│  │              │
│    │ └──┬─┘ └─┬──┘  │        │ └──┬─┘ └─┬──┘  │        │ └──┬─┘ └─┬──┘  │              │
│    │    └──┬──┘     │        │    └──┬──┘     │        │    └──┬──┘     │              │
│    └───────┼────────┘        └───────┼────────┘        └───────┼────────┘              │
│            │                         │                         │                       │
│    ┌───────┴────────┐        ┌───────┴────────┐        ┌───────┴────────┐              │
│    │ TGW Attachment │        │ TGW Attachment │        │ TGW Attachment │              │
│    └───────┬────────┘        └───────┬────────┘        └───────┬────────┘              │
│            │                         │                         │                       │
│            └─────────────────────────┼─────────────────────────┘                       │
│                                      │                                                 │
│    ╔═════════════════════════════════╧═════════════════════════════════════╗           │
│    ║                      TRANSIT GATEWAY (Regional Hub)                   ║           │
│    ║                           ASN: 64512                                  ║           │
│    ║                                                                       ║           │
│    ║  ┌─────────────────────────────────────────────────────────────────┐  ║           │
│    ║  │              TGW Route Tables (for segmentation)                │  ║           │
│    ║  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐            │  ║           │
│    ║  │  │  Prod-RT    │ │   Dev-RT    │ │   Shared-RT     │            │  ║           │
│    ║  │  │10.3→VPC-C   │ │10.3→VPC-C   │ │10.1→VPC-A       │            │  ║           │
│    ║  │  │192.168→VPN  │ │(no on-prem) │ │10.2→VPC-B       │            │  ║           │
│    ║  │  └─────────────┘ └─────────────┘ │192.168→VPN      │            │  ║           │
│    ║  └─────────────────────────────────────────────────────────────────┘  ║           │
│    ╚═══════════════════════════════════╤═══════════════════════════════════╝           │
│                                        │                                               │
│                           ┌────────────┴────────────┐                                  │
│                           │    VPN Attachment       │                                  │
│                           └────────────┬────────────┘                                  │
└────────────────────────────────────────┼───────────────────────────────────────────────┘
                                         │
                            ╔════════════╧════════════╗
                            ║   Site-to-Site VPN      ║
                            ╚════════════╤════════════╝
                                         │
                            ┌────────────┴────────────┐
                            │      ON-PREMISES        │
                            │    192.168.0.0/16       │
                            └─────────────────────────┘
```

**Transit Gateway Characteristics:**

| Feature | Details |
|---------|---------|
| Transitivity | Fully transitive routing |
| Bandwidth | 50 Gbps per VPC attachment per AZ |
| Scope | Regional (use TGW Peering for cross-region) |
| Attachments | VPC, VPN, Direct Connect (via DXGW), Peering, Connect |
| Route Tables | Multiple supported for network segmentation |
| Max Attachments | 5,000 per TGW |
| Cost | $0.05/hour per attachment + $0.02/GB processed |

### PrivateLink (VPC Endpoint Services)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│   Consumer VPC (10.0.0.0/16)              Provider VPC (172.16.0.0/16)   │
│   ┌─────────────────────────┐              ┌─────────────────────────┐   │
│   │                         │              │                         │   │
│   │  ┌─────────────────┐    │              │    ┌─────────────────┐  │   │
│   │  │   Application   │    │              │    │  Target Service │  │   │
│   │  └────────┬────────┘    │              │    └────────▲────────┘  │   |
│   │           │             │              │             │           │   │
│   │           ▼             │              │    ┌────────┴────────┐  │   │
│   │  ┌──────────────────┐   │              │    │      NLB        │  │   │
│   │  │Interface Endpoint│   │              │    └────────▲────────┘  │   │
│   │  │(ENI with Priv IP)│   │              │             │           │   │
│   │  └────────┬─────────┘   │              │    ┌────────┴────────┐  │   │
│   │           │             │              │    │Endpoint Service │  │   │
│   └───────────┼─────────────┘              │    └───────┬─────────┘  │   │
│               │                            └────────────┼────────────┘   │
│               │         AWS PrivateLink                 │                │
│               └─────────────────────────────────────────┘                │
│                   (Traffic stays on AWS backbone)                        │
│                                                                          │
│   ✓ IP overlap allowed (uses ENI in consumer VPC)                        │
│   ✓ Cross-account supported                                              │
│   ✗ Cross-region NOT supported                                           │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**PrivateLink Characteristics:**

| Feature | Details |
|---------|---------|
| Direction | Unidirectional (consumer → provider) |
| IP Overlap | Allowed (uses ENI in consumer VPC) |
| Cross-Account | Supported (via endpoint service permissions) |
| Cross-Region | NOT supported (same region only) |
| Load Balancer | Requires NLB or GWLB in provider VPC |
| Security | Traffic never traverses public internet |
| Cost | $0.01/hour per AZ + $0.01/GB processed |

### Gateway vs Interface Endpoints

| Feature | Gateway Endpoint | Interface Endpoint |
|---------|-----------------|-------------------|
| Services | S3, DynamoDB only | 100+ AWS services |
| Implementation | Route table entry | ENI with private IP |
| Cost | FREE | $0.01/hour/AZ + $0.01/GB |
| DNS | Uses public DNS | Private DNS optional |
| On-premises Access | Not directly | Yes (via private IP) |
| Security Groups | Not supported | Supported |

---

## On-Premises to AWS Connectivity

### How do I connect my on-premises data center to AWS?

### Site-to-Site VPN

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              AWS CLOUD                                  │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                         VPC (10.0.0.0/16)                       │    │
│  │   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │    │
│  │   │  Subnet A   │    │  Subnet B   │    │  Subnet C   │         │    │
│  │   │ 10.0.1.0/24 │    │ 10.0.2.0/24 │    │ 10.0.3.0/24 │         │    │
│  │   └─────────────┘    └─────────────┘    └─────────────┘         │    │
│  │         │                   │                  │                │    │
│  │         └───────────────────┼──────────────────┘                │    │
│  │                             │                                   │    │
│  │                    ┌────────┴────────┐                          │    │
│  │                    │ Route Table     │                          │    │
│  │                    │ 192.168.0.0/16  │                          │    │
│  │                    │    → VGW        │                          │    │
│  │                    └────────┬────────┘                          │    │
│  └─────────────────────────────┼───────────────────────────────────┘    │
│                                │                                        │
│                    ┌───────────┴───────────┐                            │
│                    │         VGW           │                            │
│                    │  (Virtual Private GW) │                            │
│                    │    ASN: 64512         │                            │
│                    └───────────┬───────────┘                            │
└────────────────────────────────┼────────────────────────────────────────┘
                                 │
                    ╔════════════╧════════════╗
                    ║   VPN Connection        ║
                    ║  (2 IPsec Tunnels)      ║
                    ║   Tunnel 1: Active      ║
                    ║   Tunnel 2: Standby     ║
                    ╚════════════╤════════════╝
                                 │
                        ═════════╧═════════
                            INTERNET
                        ═════════╤═════════
                                 │
                    ┌────────────┴────────────┐
                    │         CGW             │
                    │  (Customer Gateway)     │
                    │   Public IP: x.x.x.x    │
                    │   ASN: 65000            │
                    └────────────┬────────────┘
                                 │
┌────────────────────────────────┼────────────────────────────────────────┐
│                     ON-PREMISES DATA CENTER                             │
│                                │                                        │
│                    ┌───────────┴───────────┐                            │
│                    │   Router/Firewall     │                            │
│                    │   (Physical Device)   │                            │
│                    └───────────┬───────────┘                            │
│                                │                                        │
│         ┌──────────────────────┼──────────────────────┐                 │
│         │                      │                      │                 │
│   ┌─────┴─────┐         ┌──────┴──────┐        ┌──────┴──────┐          │
│   │  Server   │         │   Server    │        │   Server    │          │
│   │192.168.1.x│         │192.168.2.x  │        │192.168.3.x  │          │
│   └───────────┘         └─────────────┘        └─────────────┘          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Site-to-Site VPN Characteristics:**

| Feature | VPN to VGW | VPN to TGW |
|---------|-----------|-----------|
| Max Tunnels | 2 (1 VPN connection) | 100 (50 VPN connections × 2) |
| ECMP | Not supported | Supported (up to 50 tunnels) |
| Max Bandwidth | 1.25 Gbps | 50 Gbps (with ECMP) |
| Routing | Static or BGP | Static or BGP |
| Acceleration | Supported | Supported |

### Accelerated Site-to-Site VPN

Uses AWS Global Accelerator edge locations for better performance:
- Traffic enters AWS network closer to user
- More consistent latency
- Automatic failover between tunnels
- Additional cost: $0.05/hour + GA data processing fees


### Direct Connect Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                      AWS CLOUD                                          │
│                                                                                         │
│      US-EAST-1                                              EU-WEST-1                   │
│   ┌─────────────────────────────────────────┐         ┌─────────────────────────────┐   │
│   │  VPC-1        VPC-2        VPC-3        │         │  VPC-4        VPC-5         │   │
│   │  10.1/16      10.2/16      10.3/16      │         │  10.4/16      10.5/16       │   │
│   │    │            │            │          │         │    │            │           │   │
│   │    └──────────┬─┴────────────┘          │         │    └──────┬─────┘           │   │
│   │               │                         │         │           │                 │   │
│   │   ╔═══════════╧═══════════════╗         │         │   ╔═══════╧═════════╗       │   │
│   │   ║   Transit Gateway (TGW)   ║         │         │   ║      TGW        ║       │   │
│   │   ║      us-east-1            ║         │         │   ║   eu-west-1     ║       │   │
│   │   ╚═══════════╤═══════════════╝         │         │   ╚═══════╤═════════╝       │   │
│   └───────────────┼─────────────────────────┘         └───────────┼─────────────────┘   │
│                   │                                               │                     │
│                   │    ┌─────────────────────────────┐            │                     │
│                   └────┤                             ├────────────┘                     │
│                        │    Direct Connect Gateway   │     ◄── GLOBAL RESOURCE          │
│                        │          (DXGW)             │                                  │
│                        │       ASN: 64514            │                                  │
│                        └──────────────┬──────────────┘                                  │
│                                       │                                                 │
│                              Transit VIF (VLAN 200)   ◄── Must use Transit VIF          │
│                                       │                   for TGW connectivity          │
│                                       │                                                 │
│      ┌────────────────────────────────┴────────────────────────────────┐                │
│      │                      DX Location                                │                │
│      │    ┌────────────────────────────────────────────────────────┐   │                │
│      │    │   AWS          ════════════════          Customer      │   │                │
│      │    │   DX Router    Cross Connect             Router        │   │                │
│      │    │   (MMR)        (Physical Fiber)          (Your Cage)   │   │                │
│      │    └────────────────────────────────────────────────────────┘   │                │
│      └────────────────────────────────┬────────────────────────────────┘                │
└───────────────────────────────────────┼─────────────────────────────────────────────────┘
                                        │
                              ┌─────────┴─────────┐
                              │  Carrier Network  │
                              │  (MPLS/WAN)       │
                              └─────────┬─────────┘
                                        │
┌───────────────────────────────────────┼──────────────────────────────────────────────────┐
│                           ON-PREMISES DATA CENTER                                        │
│                                       │                                                  │
│                           ┌───────────┴────────────┐                                     │
│                           │   Core Router          │                                     │
│                           │   ASN: 65000           │                                     │
│                           │   192.168.0.0/16       │                                     │
│                           │                        │                                     │
│                           │   Receives via BGP:    │                                     │
│                           │   10.1.0.0/16 (VPC-1)  │                                     │
│                           │   10.2.0.0/16 (VPC-2)  │                                     │
│                           │   10.3.0.0/16 (VPC-3)  │                                     │
│                           │   10.4.0.0/16 (VPC-4)  │                                     │
│                           │   10.5.0.0/16 (VPC-5)  │                                     │
│                           └────────────────────────┘                                     │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Remote/Client Access

### How do remote users connect to AWS resources?

### Client VPN

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                         │
│   Remote Users                                                                          │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐                                                 │
│   │ 👤 User  │ │ 👤 User  │  │ 👤 User │                                                 │
│   │OpenVPN  │  │AWS App  │  │OpenVPN  │                                                 │
│   └────┬────┘  └────┬────┘  └────┬────┘                                                 │
│        │            │            │                                                      │
│        └────────────┼────────────┘                                                      │
│                     │                                                                   │
│                     │  OpenVPN/TLS (UDP/TCP 443)                                        │
│                     │                                                                   │
│                ═════╧═════                                                              │
│                 INTERNET                                                                │
│                ═════╤═════                                                              │
│                     │                                                                   │
│   ┌─────────────────┼───────────────────────────────────────────────────────────────┐   │
│   │                 │                    AWS CLOUD                                  │   │
│   │                 │                                                               │   │
│   │   ┌─────────────┴──────────────┐                                                │   │
│   │   │    Client VPN Endpoint     │                                                │   │
│   │   │ Client CIDR: 172.16.0.0/16 │                                                │   │
│   │   │  (ENIs per subnet assoc)   │                                                │   │
│   │   └─────────────┬──────────────┘                                                │   │
│   │                 │                                                               │   │
│   │   ┌─────────────┴─────────────────────────────────────────────────────────┐     │   │
│   │   │                         VPC (10.0.0.0/16)                             │     │   │
│   │   │   ┌───────────┐    ┌───────────┐    ┌───────────┐                     │     │   │
│   │   │   │ Subnet A  │    │ Subnet B  │    │  EC2/RDS  │                     │     │   │
│   │   │   └───────────┘    └───────────┘    └───────────┘                     │     │   │
│   │   └───────────────────────────────────────────────────────────────────────┘     │   │
│   │                 │                                                               │   │
│   │                 │  (Optional: via TGW)                                          │   │
│   │                 ▼                                                               │   │
│   │   ┌─────────────────────────┐                                                   │   │
│   │   │     On-Premises         │                                                   │   │
│   │   │   192.168.0.0/16        │                                                   │   │
│   │   └─────────────────────────┘                                                   │   │
│   └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

**Client VPN Features:**

| Feature | Details |
|---------|---------|
| Protocol | OpenVPN (UDP/TCP 443) |
| Authentication | Mutual TLS, AD, SAML 2.0, or combination |
| Split Tunnel | Supported (only VPC traffic through VPN) |
| Authorization | Security groups + Network-based rules |
| Logging | CloudWatch Logs integration |
| Client CIDR | Cannot overlap with VPC CIDR |
| Cost | $0.10/hour per association + $0.05/hour per connection |

### Client VPN vs Site-to-Site VPN

| Feature | Client VPN | Site-to-Site VPN |
|---------|-----------|-----------------|
| Use Case | Remote users | Site connectivity |
| Protocol | OpenVPN (TLS) | IPsec |
| Authentication | User-based (certs, AD, SAML) | Pre-shared key or certs |
| Scalability | Per-user connections | Network-to-network |
| Client Software | Required | Not required |
| Managed By | AWS | Shared (AWS + Customer) |

---

## AWS Cloud WAN

### What is AWS Cloud WAN and how does it differ from Transit Gateway?

AWS Cloud WAN is a global network service that uses a central policy to create and manage networks spanning multiple regions and accounts.

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                   AWS CLOUD WAN                                         │
│                                                                                         │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│   │                           Core Network Policy                                   │   │
│   │                           (JSON Document)                                       │   │
│   │                                                                                 │   │
│   │   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                 │   │
│   │   │   Production    │  │   Development   │  │ Shared Services │                 │   │
│   │   │    Segment      │  │    Segment      │  │    Segment      │                 │   │
│   │   └────────┬────────┘  └────────┬────────┘  └────────┬────────┘                 │   │
│   │            │                    │                    │                          │   │
│   │            │    ┌───────────────┼───────────────┐    │                          │   │
│   │            └────┤     Shared routing allowed    ├────┘                          │   │
│   │                 │   Prod ↔ Shared ↔ Dev         │                               │   │
│   │                 │   Prod ✗ Dev (isolated)       │                               │   │
│   │                 └───────────────────────────────┘                               │   │
│   └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│   US-EAST-1                          EU-WEST-1                       AP-SOUTHEAST-1     │
│   ┌─────────────────────┐            ┌─────────────────────┐        ┌───────────────┐   │
│   │ Core Network Edge   │◄══════════►│ Core Network Edge   │◄══════►│     CNE       │   │
│   │       (CNE)         │  AWS       │       (CNE)         │  AWS   │               │   │
│   └──────────┬──────────┘  Backbone  └──────────┬──────────┘Backbone└───────┬───────┘   │
│              │                                  │                           │           │
│   ┌──────────┴──────────┐            ┌──────────┴──────────┐        ┌───────┴───────┐   │
│   │ VPC-Prod  VPC-Dev   │            │ VPC-Prod  VPC-Dev   │        │   VPC-Prod    │   │
│   │ VPC-Shared          │            │                     │        │               │   │
│   └─────────────────────┘            └─────────────────────┘        └───────────────┘   │
│              │                                  │                           │           │
│              │                                  │                           │           │
│   ┌──────────┴──────────┐            ┌──────────┴──────────┐        ┌───────┴───────┐   │
│   │   DX Connection     │            │   DX Connection     │        │  VPN Conn     │   │
│   └──────────┬──────────┘            └──────────┬──────────┘        └───────┬───────┘   │
│              │                                  │                           │           │
└──────────────┼──────────────────────────────────┼───────────────────────────┼───────────┘
               │                                  │                           │
    ┌──────────┴──────────┐            ┌──────────┴──────────┐        ┌───────┴───────┐
    │    HQ - US          │            │   Branch - EU       │        │  Branch - AP  │
    │  (On-Premises)      │            │  (On-Premises)      │        │ (On-Premises) │
    └─────────────────────┘            └─────────────────────┘        └───────────────┘
```

### Cloud WAN vs Transit Gateway

| Feature | Transit Gateway | Cloud WAN |
|---------|----------------|-----------|
| Scope | Regional | Global |
| Management | Per-region configuration | Central policy |
| Cross-Region | Manual TGW Peering | Automatic |
| Segmentation | Route tables | Policy-based segments |
| Route Management | Manual/BGP | Automatic from policy |
| Best For | Single region or few regions | Global networks |
| Cost | Per attachment + data | Per attachment + data + policy |

---

## Direct Connect Deep Dive

### What are the different VIF types and when should I use each?

### VIF Types

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                          DIRECT CONNECT VIRTUAL INTERFACES                              │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  PRIVATE VIF                                                                            │
│  ══════════                                                                             │
│  Purpose: Access VPC private IP addresses                                               │
│                                                                                         │
│      On-Prem                DX              Private VIF                                 │
│     ┌───────┐           ┌───────┐           ┌───────┐          ┌───────────────────┐    │
│     │Router │═══════════│  DX   │═══════════│DXGW or│══════════│  VGW ──► VPC      │    │
│     │       │           │       │           │ VGW   │          │       (Private)   │    │
│     └───────┘           └───────┘           └───────┘          └───────────────────┘    │
│        │                                                                                │
│        └──► Access: EC2, RDS, Lambda, etc. via private IPs                              │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  PUBLIC VIF                                                                             │
│  ══════════                                                                             │
│  Purpose: Access AWS public endpoints (S3, DynamoDB, EC2 public IPs)                    │
│                                                                                         │
│      On-Prem                DX              Public VIF                                  │
│     ┌───────┐           ┌───────┐           ┌───────┐          ┌───────────────────┐    │
│     │Router │═══════════│  DX   │═══════════│ AWS   │══════════│ S3, DynamoDB,     │    │
│     │       │           │       │           │Public │          │ SQS, SNS, etc.    │    │
│     └───────┘           └───────┘           │Network│          │ (Public IPs)      │    │
│        │                                    └───────┘          └───────────────────┘    │
│        │                                                                                │
│        └──► Access: AWS public services WITHOUT traversing Internet                     │
│             Still uses AWS public IP ranges but via dedicated link                      │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  TRANSIT VIF                                                                            │
│  ═══════════                                                                            │
│  Purpose: Connect to Transit Gateway (for multi-VPC, multi-region)                      │
│                                                                                         │
│      On-Prem                DX             Transit VIF                                  │
│     ┌───────┐           ┌───────┐           ┌───────┐          ┌───────────────────┐    │
│     │Router │═══════════│  DX   │═══════════│ DXGW  │══════════│  TGW ──► VPC-1    │    │
│     │       │           │       │           │       │          │      ──► VPC-2    │    │
│     └───────┘           └───────┘           └───────┘          │      ──► VPC-3    │    │
│        │                                                       │      ──► VPN      │    │
│        │                                                       └───────────────────┘    │
│        └──► Access: Multiple VPCs via single attachment                                 │
│             Required when connecting DX to Transit Gateway                              │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

**VIF Limits & Requirements:**

| VIF Type | Connects To | BGP Required | Typical Use Case |
|----------|-------------|--------------|------------------|
| Private VIF | VGW or DXGW | Yes | Single VPC or few VPCs |
| Public VIF | AWS Public | Yes | S3, DynamoDB access |
| Transit VIF | DXGW → TGW | Yes | Many VPCs, hub-spoke |

Max VIFs per DX Connection:
- 50 Public VIFs
- 50 Private VIFs
- 1 Transit VIF (per DX connection to a DXGW)

### Dedicated vs Hosted Connections

| Feature | Dedicated Connection | Hosted Connection |
|---------|---------------------|-------------------|
| Port Ownership | You own | Partner owns |
| Bandwidth | 1/10/100 Gbps | 50 Mbps - 10 Gbps |
| Lead Time | 1-2 months | Days to weeks |
| VIFs | Up to 50 private, 50 public, 1 transit | Limited by partner |
| MACsec | Available (10G/100G) | Not available |
| Provisioning | Request via AWS (LOA) | Via DX Partner |

### High Availability Pattern: DX + VPN Backup

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                      AWS CLOUD                                          │
│                                                                                         │
│   ┌───────────────────────────────────────────────────────────────────────────────────┐ │
│   │                              VPC (10.0.0.0/16)                                    │ │
│   └─────────────────────────────────────────┬─────────────────────────────────────────┘ │
│                                             │                                           │
│                               ╔═════════════╧═════════════╗                             │
│                               ║     Transit Gateway       ║                             │
│                               ╚═══════╤═══════════╤═══════╝                             │
│                                       │           │                                     │
│                          ┌────────────┘           └────────────┐                        │
│                          │                                     │                        │
│              ┌───────────┴───────────┐             ┌───────────┴───────────┐            │
│              │   DX Attachment       │             │   VPN Attachment      │            │
│              │   (Primary)           │             │   (Backup)            │            │
│              └───────────┬───────────┘             └───────────┬───────────┘            │
│                          │                                     │                        │
│              ┌───────────┴───────────┐                         │                        │
│              │   Direct Connect GW   │                         │                        │
│              └───────────┬───────────┘                         │                        │
│                          │                                     │                        │
│                 Transit VIF                           ╔════════╧════════╗               │
│                          │                            ║  Site-to-Site   ║               │
│                          │                            ║      VPN        ║               │
│                          │                            ╚════════╤════════╝               │
└──────────────────────────┼─────────────────────────────────────┼────────────────────────┘
                           │                                     │
     ┌─────────────────────┴─────────────────────┐               │
     │            DX Location                    │               │
     │  ┌─────────────────────────────────────┐  │               │
     │  │ AWS Router ◄═══════► Your Router    │  │               │
     │  │            10 Gbps                  │  │          INTERNET
     │  └─────────────────────────────────────┘  │               │
     └─────────────────────┬─────────────────────┘               │
                           │                                     │
                           │    Private WAN                      │
                           │                                     │
┌──────────────────────────┴─────────────────────────────────────┴─────────────────────────┐
│                                  ON-PREMISES                                             │
│                                                                                          │
│    ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│    │                            Core Router (BGP)                                    │   │
│    │                              ASN: 65000                                         │   │
│    │                                                                                 │   │
│    │   DX Routes (preferred):          VPN Routes (backup):                          │   │
│    │   • LOCAL_PREF: 200               • LOCAL_PREF: 100                             │   │
│    │        ▲                                ▲                                       │   │
│    │        │                                │                                       │   │
│    │        └── PREFERRED ──────────────────►│◄── BACKUP (failover)                  │   │
│    └─────────────────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────────────────┘

                         ┌─────────────────────────────────────┐
                         │        FAILOVER BEHAVIOR            │
                         ├─────────────────────────────────────┤
                         │  Normal: Traffic via DX (low        │
                         │          latency, high bandwidth)   │
                         │                                     │
                         │  DX Fail: BGP detects failure,      │
                         │           routes shift to VPN       │
                         │           (~30-60 sec failover)     │
                         │                                     │
                         │  DX Recovery: Traffic returns       │
                         │              to DX path             │
                         └─────────────────────────────────────┘
```


---

## Architecture Patterns

### Pattern 1: Small/Medium Business (VPN Only)

**Best For:**
- Quick setup needed
- Budget-conscious
- < 1.25 Gbps bandwidth requirement
- Acceptable latency variability

```
On-Premises ──► Site-to-Site VPN ──► VGW ──► Single VPC
```

### Pattern 2: Multi-VPC with Transit Gateway

**Best For:**
- Multiple VPCs in same region
- Need network segmentation
- Transitive routing required

```
                    ┌──► VPC-Prod
On-Premises ──► TGW ├──► VPC-Dev
                    ├──► VPC-Staging
                    └──► VPC-Shared
```

### Pattern 3: Enterprise Multi-Region with Direct Connect

**Best For:**
- Consistent latency requirements
- High bandwidth needs
- Multi-region presence

```
                              ┌──► TGW (us-east-1) ──► VPCs
On-Premises ──► DX ──► DXGW ──┤
                              └──► TGW (eu-west-1) ──► VPCs
```

### Pattern 4: Global Enterprise with Cloud WAN

**Best For:**
- Global network spanning many regions
- Policy-driven management
- Automatic routing

```
                    ┌──► CNE (us-east-1) ──► VPCs
Core Network Policy ├──► CNE (eu-west-1) ──► VPCs
                    └──► CNE (ap-southeast-1) ──► VPCs
```

---

## Decision Matrices

### VPC Connectivity Decision

| Scenario | Recommended Solution |
|----------|---------------------|
| 2-3 VPCs, no transitive routing | VPC Peering |
| 4+ VPCs, same region | Transit Gateway |
| Multi-region, manual control | TGW + TGW Peering |
| Multi-region, central management | Cloud WAN |

### On-Premises Connectivity Decision

| Scenario | Recommended Solution |
|----------|---------------------|
| Quick PoC, < 1 Gbps | Site-to-Site VPN → VGW |
| Better VPN performance | Accelerated VPN |
| Higher VPN bandwidth | VPN → TGW (ECMP) |
| Consistent latency, single VPC | DX → VGW |
| Multi-VPC, single region | TGW |
| Multi-VPC, multi-region via DX | DX → DXGW → VGWs |
| Multi-VPC, transitive via DX | DX → DXGW → TGW |
| Global enterprise | Cloud WAN |

### Direct Connect Termination Decision

| Scenario | Solution |
|----------|----------|
| 1 VPC | Private VIF → VGW |
| 2-10 VPCs (no transitive) | Private VIF → DXGW → VGWs |
| Many VPCs (transitive needed) | Transit VIF → DXGW → TGW |
| Global scale, policy-driven | Transit VIF → DXGW → Cloud WAN |

### Complete Reference Table

| Requirement | Solution | Bandwidth | Setup Time | Cost Level |
|-------------|----------|-----------|------------|------------|
| Quick PoC, single VPC | VPN → VGW | 1.25 Gbps | Hours | $ |
| Better VPN performance | Accelerated VPN | 1.25 Gbps | Hours | $$ |
| Higher VPN bandwidth | VPN → TGW (ECMP) | Up to 50 Gbps | Hours | $$ |
| Consistent latency, single VPC | DX → VGW | 1-100 Gbps | Weeks/Months | $$$ |
| Multi-VPC, single region | TGW | 50 Gbps/AZ | Hours | $$ |
| Multi-VPC, multi-region via DX | DX → DXGW → VGWs | 1-100 Gbps | Weeks/Months | $$$ |
| Multi-VPC, transitive via DX | DX → DXGW → TGW | 1-100 Gbps | Weeks/Months | $$$$ |
| Global enterprise | Cloud WAN | Varies | Days | $$$$ |
| Service exposure (private) | PrivateLink | Scales with NLB | Hours | $$ |
| Remote user access | Client VPN | Varies | Hours | $$ |

### Limits Quick Reference

| Resource | Limit | Notes |
|----------|-------|-------|
| VPC Peering per VPC | 125 | Increasable |
| TGW Attachments | 5,000 | Per TGW |
| TGW per Region | 5 | Increasable |
| VGWs per DXGW | 10 | Across all regions |
| TGWs per DXGW | 3 | Across all regions |
| Private VIFs per DX | 50 | Per connection |
| Public VIFs per DX | 50 | Per connection |
| Transit VIFs per DX | 1 | Per DXGW |
| VPN Tunnels to TGW | 100 | 50 connections × 2 |
| Client VPN concurrent connections | 2,000 | Per endpoint |
| Cloud WAN segments | 16 | Per core network |

---

## Key Relationships Summary

```
    ON-PREMISES                           AWS
    ───────────                           ───

    ┌─────────┐                      ┌─────────┐
    │Physical │  ─── represents ───► │   CGW   │     (Customer Gateway - logical)
    │Router   │                      │         │
    └─────────┘                      └─────────┘
         │                                │
         │ VPN Tunnel                     │ VPN Connection
         │                                │
         ▼                                ▼
    ┌─────────┐                      ┌─────────┐
    │         │  ─── terminates ───► │   VGW   │     (1 VPC only)
    │         │         at           │   or    │
    │         │                      │   TGW   │     (Multiple VPCs)
    └─────────┘                      └─────────┘


    ┌─────────┐                      ┌─────────┐
    │Physical │  ─── connects ─────► │   DX    │     (Physical Connection)
    │Router   │     via fiber        │Location │
    └─────────┘                      └─────────┘
         │                                │
         │                                │ VIF (Virtual Interface)
         │                                │
         │                                ▼
         │                           ┌─────────┐
         │                           │ Private │───► VGW or DXGW ───► VPCs
         │                           │   VIF   │
         │                           ├─────────┤
         │                           │ Transit │───► DXGW ───► TGW ───► VPCs
         │                           │   VIF   │
         │                           ├─────────┤
         │                           │ Public  │───► AWS Public Services
         │                           │   VIF   │
         │                           └─────────┘
```

---

## Further Reading

- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)
- [AWS Direct Connect Documentation](https://docs.aws.amazon.com/directconnect/)
- [AWS Transit Gateway Documentation](https://docs.aws.amazon.com/vpc/latest/tgw/)
- [AWS Cloud WAN Documentation](https://docs.aws.amazon.com/vpc/latest/cloudwan/)
- [AWS Client VPN Documentation](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/)
