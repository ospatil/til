# AWS Cloud WAN - Step-by-Step Explanation

---

## What is AWS Cloud WAN and how does it work?

### Step 1: The Problem It Solves

Before Cloud WAN, connecting multiple networks was complex:

```
Traditional Approach:
┌─────────┐    ┌─────────┐    ┌─────────┐
│  VPC 1  │────│  VPC 2  │────│  VPC 3  │
└─────────┘    └─────────┘    └─────────┘
     │              │              │
     └──────────────┼──────────────┘
                    │
            Manual peering,
            route tables,
            Transit Gateways...

Problems:
• Complex routing configurations
• Manual management per region
• No centralized policy
• Difficult to scale
```

### Step 2: What is AWS Cloud WAN?

**AWS Cloud WAN** is a managed service that lets you build, manage, and monitor a **unified global network** connecting your:
- AWS resources (VPCs)
- On-premises data centers
- Branch offices

```
┌────────────────────────────────────────────┐
│           AWS Cloud WAN                    │
│  "One network to connect everything"       │
│                                            │
│  • Centralized management                  │
│  • Policy-driven                           │
│  • Global reach                            │
│  • Automated routing                       │
└────────────────────────────────────────────┘
```

### Step 3: Core Components

#### 3.1 Global Network

The top-level container for your entire network.

```
┌─────────────────────────────────────────────┐
│            GLOBAL NETWORK                   │
│  (Your entire network infrastructure)       │
└─────────────────────────────────────────────┘
```

#### 3.2 Core Network

The managed part within the global network that Cloud WAN creates and manages.

```
┌─────────────────────────────────────────────┐
│            GLOBAL NETWORK                   │
│  ┌───────────────────────────────────────┐  │
│  │         CORE NETWORK                  │  │
│  │    (AWS managed infrastructure)       │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

#### 3.3 Core Network Policy

A JSON document that defines HOW your network should behave.

```json
{
  "version": "2021.12",
  "core-network-configuration": {
    "asn-ranges": ["64512-65534"],
    "edge-locations": [
      { "location": "us-east-1" },
      { "location": "eu-west-1" }
    ]
  },
  "segments": [...],
  "attachment-policies": [...]
}
```

### Step 4: Understanding Segments

**Segments** are isolated routing domains (like virtual networks within your network).

```
┌────────────────── CORE NETWORK ──────────────────┐
│                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────┐ │
│  │ PRODUCTION  │  │ DEVELOPMENT │  │  SHARED   │ │
│  │  SEGMENT    │  │   SEGMENT   │  │  SERVICES │ │
│  │             │  │             │  │  SEGMENT  │ │
│  │  VPC-A      │  │  VPC-C      │  │  VPC-E    │ │
│  │  VPC-B      │  │  VPC-D      │  │           │ │
│  └─────────────┘  └─────────────┘  └───────────┘ │
│        ↑                ↑               ↑        │
│        └────── Isolated from each other ─────┘   │
└──────────────────────────────────────────────────┘
```

**Why Segments?**
| Purpose | Description |
|---------|-------------|
| Isolation | Production traffic never mixes with Development |
| Security | Apply different policies per segment |
| Organization | Logical grouping of resources |

### Step 5: Attachments

**Attachments** connect your resources TO the Core Network.

**Types of Attachments:**

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│   ┌─────┐     ┌─────────┐     ┌──────────────────┐  │
│   │ VPC │     │ VPN     │     │ Transit Gateway  │  │
│   │     │     │         │     │ Route Table      │  │
│   └──┬──┘     └────┬────┘     └────────┬─────────┘  │
│      │             │                   │            │
│      └─────────────┼───────────────────┘            │
│                    │                                │
│                    ▼                                │
│           ┌───────────────┐                         │
│           │ CORE NETWORK  │                         │
│           └───────────────┘                         │
└─────────────────────────────────────────────────────┘
```

### Step 6: How Routing Works

#### Attachment Policy

Automatically assigns attachments to segments based on tags.

**Example Policy Logic:**

```
┌────────────────────────────────────────────────────┐
│                                                    │
│  IF VPC has tag "environment=production"           │
│     → Attach to PRODUCTION segment                 │
│                                                    │
│  IF VPC has tag "environment=development"          │
│     → Attach to DEVELOPMENT segment                │
│                                                    │
│  ELSE                                              │
│     → Attach to DEFAULT segment                    │
│                                                    │
└────────────────────────────────────────────────────┘
```

#### Segment Sharing

You can allow segments to communicate:

```
Before Sharing:                 After Sharing:

┌──────┐    ┌──────┐           ┌──────┐ ←──→ ┌──────┐
│ PROD │ ✗  │SHARED│           │ PROD │      │SHARED│
└──────┘    └──────┘           └──────┘      └──────┘
   No communication              Routes shared!
```

### Step 7: Multi-Region Architecture

Cloud WAN automatically handles cross-region connectivity:

```
                    ┌─────────────────────┐
                    │    CORE NETWORK     │
                    │   (Global Reach)    │
                    └─────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
  ┌──────────┐          ┌──────────┐          ┌──────────┐
  │us-east-1 │◄────────►│eu-west-1 │◄────────►│ap-south-1│
  │   CNE    │          │   CNE    │          │   CNE    │
  └────┬─────┘          └────┬─────┘          └────┬─────┘
       │                     │                     │
   ┌───┴───┐             ┌───┴───┐             ┌───┴───┐
   │VPC-US │             │VPC-EU │             │VPC-AP │
   └───────┘             └───────┘             └───────┘

   All connected automatically via AWS backbone!
```

### Step 8: Complete Architecture Example

```
┌─────────────────────────────────────────────────────────────────┐
│                        GLOBAL NETWORK                           │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                     CORE NETWORK                          │  │
│  │                                                           │  │
│  │   ┌─────────────────────────────────────────────────┐     │  │
│  │   │              PRODUCTION SEGMENT                 │     │  │
│  │   │   ┌─────┐  ┌─────┐  ┌─────┐                     │     │  │
│  │   │   │VPC-A│  │VPC-B│  │VPC-C│                     │     │  │
│  │   │   └─────┘  └─────┘  └─────┘                     │     │  │
│  │   └─────────────────────────────────────────────────┘     │  │
│  │                                                           │  │
│  │   ┌─────────────────────────────────────────────────┐     │  │
│  │   │              SHARED SERVICES SEGMENT            │     │  │
│  │   │   ┌──────────┐  ┌──────────┐                    │     │  │
│  │   │   │   DNS    │  │ Logging  │                    │     │  │
│  │   │   └──────────┘  └──────────┘                    │     │  │
│  │   └─────────────────────────────────────────────────┘     │  │
│  │                                                           │  │
│  │   ┌─────────────────────────────────────────────────┐     │  │
│  │   │              ON-PREMISES CONNECTION             │     │  │
│  │   │   ┌─────────────┐                               │     │  │
│  │   │   │ VPN / DX    │ ←── Data Center               │     │  │
│  │   │   └─────────────┘                               │     │  │
│  │   └─────────────────────────────────────────────────┘     │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Step 9: Key Benefits Summary

| Benefit | Description |
|---------|-------------|
| Centralized Management | Single place to manage global network |
| Policy-Driven | Define rules once, apply everywhere |
| Automated Routing | No manual route table management |
| Segmentation | Built-in network isolation |
| Global Reach | Connect any AWS region easily |
| Visibility | Built-in monitoring and metrics |

### Step 10: When to Use Cloud WAN?

**Good fit:**
- Large organizations with multi-region presence
- Need for network segmentation (prod/dev/shared)
- Connecting multiple VPCs globally
- Hybrid cloud (AWS + on-premises)

**Maybe overkill for:**
- Single region deployments
- Simple 2-3 VPC architectures
- Cost-sensitive small projects

### Quick Comparison

| Feature | Transit Gateway | Cloud WAN |
|---------|-----------------|-----------|
| Scope | Single Region | Global |
| Management | Per-region | Centralized |
| Segmentation | Route tables | Native segments |
| Policy-based | No | Yes |
| Complexity | Manual | Automated |

---

## What is a Core Network Edge (CNE) and how does it relate to regions?

CNE (Core Network Edge) is essentially the Cloud WAN presence in a specific AWS region. It's the regional component that handles connectivity for that region.

### What is a Core Network Edge (CNE)?

**CNE** is Cloud WAN's **regional presence** - it's the actual infrastructure deployed in each AWS region where you want connectivity.

Think of it as:

```
┌─────────────────────────────────────────────────┐
│                                                 │
│   CNE = Cloud WAN's "branch office" in a region │
│                                                 │
└─────────────────────────────────────────────────┘
```

### How CNEs Work Across Regions

```
                        AWS Global Backbone
                    (Private, high-speed network)
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
        ▼                      ▼                      ▼
  ┌──────────┐           ┌──────────┐           ┌──────────┐
  │   CNE    │◄─────────►│   CNE    │◄─────────►│   CNE    │
  │us-east-1 │           │eu-west-1 │           │ap-south-1│
  └────┬─────┘           └────┬─────┘           └────┬─────┘
       │                      │                      │
   ┌───┴───┐              ┌───┴───┐              ┌───┴───┐
   │       │              │       │              │       │
┌──┴─┐  ┌──┴─┐         ┌──┴─┐  ┌──┴─┐         ┌──┴─┐  ┌──┴─┐
│VPC │  │VPN │         │VPC │  │VPC │         │VPC │  │TGW │
└────┘  └────┘         └────┘  └────┘         └────┘  └────┘
```

### Key Points

| Aspect | Description |
|--------|-------------|
| One CNE per region | Each enabled region gets one CNE |
| Automatic connectivity | CNEs connect via AWS backbone (no manual setup) |
| Attachments connect to CNE | VPCs, VPNs attach to their local region's CNE |
| You choose regions | Define which regions in your Core Network Policy |

### Defining Regions in Policy

```json
{
  "core-network-configuration": {
    "edge-locations": [
      { "location": "us-east-1" },   // ← CNE created here
      { "location": "eu-west-1" },   // ← CNE created here
      { "location": "ap-south-1" }   // ← CNE created here
    ]
  }
}
```

### Simple Analogy

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   Cloud WAN Core Network  =  Airline Network            │
│   CNE                     =  Airport Hub in each city   │
│   AWS Backbone            =  Flight routes between hubs │
│   Attachments (VPC/VPN)   =  Local roads to airport     │
│                                                         │
└─────────────────────────────────────────────────────────┘

    New York          London            Mumbai
    Airport    ✈────► Airport   ✈────►  Airport
       │                 │                 │
    Local roads      Local roads      Local roads
       │                 │                 │
    Your home        Office           Data center
```

---

## How does routing work between CNEs?

When you attach resources (VPCs, VPNs) to Cloud WAN, routes are **automatically propagated** across CNEs based on your segment configuration.

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   Routes flow automatically between CNEs via AWS backbone   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Step 1: Route Propagation Within a Segment

When a VPC attaches to a segment, its CIDR is advertised to **all CNEs in that segment**.

```
PRODUCTION Segment (same segment = routes shared automatically)

us-east-1                                      eu-west-1
  ┌────────┐                                     ┌────────┐
  │  CNE   │◄───────── AWS Backbone ────────────►│  CNE   │
  └───┬────┘                                     └───┬────┘
      │                                              │
      │  Route Table:                                │  Route Table:
      │  ┌────────────────────┐                      │  ┌────────────────────┐
      │  │ 10.1.0.0/16 →local │                      │  │ 10.1.0.0/16 →us-e1 │
      │  │ 10.2.0.0/16 →eu-w1 │ ◄── Learned          │  │ 10.2.0.0/16 →local │
      │  └────────────────────┘                      │  └────────────────────┘
      │                                              │
  ┌───┴───┐                                      ┌───┴───┐
  │ VPC-A │                                      │ VPC-B │
  │10.1.0 │                                      │10.2.0 │
  │ .0/16 │                                      │ .0/16 │
  └───────┘                                      └───────┘

     VPC-A can reach VPC-B automatically! ✓
```

### Step 2: Segment Isolation (Default Behavior)

By default, **different segments CANNOT communicate** - routes stay within their segment.

```
                          us-east-1 CNE
┌────────────────────────────────────────────────┐
│                                                │
│   PRODUCTION Segment    DEVELOPMENT Segment    │
│   ┌─────────────────┐   ┌─────────────────┐    │
│   │ Routes:         │   │ Routes:         │    │
│   │ 10.1.0.0/16     │   │ 10.3.0.0/16     │    │
│   │ 10.2.0.0/16     │   │ 10.4.0.0/16     │    │
│   └────────┬────────┘   └────────┬────────┘    │
│            │                     │             │
│            │        ✗            │             │
│            │   NO ROUTES         │             │
│            │   EXCHANGED         │             │
│            │                     │             │
└────────────┼─────────────────────┼─────────────┘
             │                     │
         ┌───┴───┐             ┌───┴───┐
         │ VPC-A │             │ VPC-C │
         │ PROD  │      ✗      │  DEV  │
         └───────┘  Can't talk └───────┘
```

### Step 3: Enabling Cross-Segment Routing (Segment Sharing)

You can allow segments to share routes using **segment actions** in your policy.

```json
{
  "segments": [
    { "name": "production", "isolate-attachments": false },
    { "name": "shared-services", "isolate-attachments": false }
  ],
  "segment-actions": [
    {
      "action": "share",
      "mode": "attachment-route",
      "segment": "shared-services",
      "share-with": ["production"]   // ← Share routes with production
    }
  ]
}
```

**Result After Sharing:**

```
                          us-east-1 CNE
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   PRODUCTION Segment       SHARED-SERVICES Segment      │
│   ┌───────────────────┐    ┌───────────────────┐        │
│   │ Routes:           │    │ Routes:           │        │
│   │ 10.1.0.0/16 (own) │    │ 10.5.0.0/16 (own) │        │
│   │ 10.5.0.0/16 ──────┼────┼─► (shared)        │        │
│   └─────────┬─────────┘    └─────────┬─────────┘        │
│             │                        │                  │
│             │    Routes shared! ✓    │                  │
│             │                        │                  │
└─────────────┼────────────────────────┼──────────────────┘
              │                        │
          ┌───┴───┐                ┌───┴───┐
          │ VPC-A │                │ VPC-E │
          │ PROD  │ ──────────────►│SHARED │
          └───────┘   Can reach!   └───────┘
                      (DNS, Auth,
                       Logging, etc.)
```

### Step 4: Complete Multi-Region Routing Example

```
                        PRODUCTION SEGMENT
─────────────────────────────────────────────────────────

us-east-1                                    eu-west-1
┌──────────────┐                            ┌──────────────┐
│     CNE      │                            │     CNE      │
│              │                            │              │
│ Route Table: │      AWS Backbone          │ Route Table: │
│┌────────────┐│◄──────────────────────────►│┌────────────┐│
││10.1.0.0/16 ││        Routes              ││10.1.0.0/16 ││
││  → local   ││      Propagate             ││  → us-e1   ││
││10.2.0.0/16 ││     Automatically          ││10.2.0.0/16 ││
││  → eu-w1   ││                            ││  → local   ││
│└────────────┘│                            │└────────────┘│
└──────┬───────┘                            └──────┬───────┘
       │                                          │
   ┌───┴───┐                                  ┌───┴───┐
   │VPC-A  │                                  │VPC-B  │
   │10.1.0 │                                  │10.2.0 │
   └───────┘                                  └───────┘


                        DEVELOPMENT SEGMENT
─────────────────────────────────────────────────────────

us-east-1                                    eu-west-1
┌──────────────┐                            ┌──────────────┐
│     CNE      │                            │     CNE      │
│              │                            │              │
│ Route Table: │      AWS Backbone          │ Route Table: │
│┌────────────┐│◄──────────────────────────►│┌────────────┐│
││10.3.0.0/16 ││        Routes              ││10.3.0.0/16 ││
││  → local   ││      Propagate             ││  → us-e1   ││
││10.4.0.0/16 ││     Automatically          ││10.4.0.0/16 ││
││  → eu-w1   ││                            ││  → local   ││
│└────────────┘│                            │└────────────┘│
└──────┬───────┘                            └──────┬───────┘
       │                                          │
   ┌───┴───┐                                  ┌───┴───┐
   │VPC-C  │                                  │VPC-D  │
   │10.3.0 │                                  │10.4.0 │
   └───────┘                                  └───────┘


PROD VPCs can talk to each other    ✓
DEV VPCs can talk to each other     ✓
PROD cannot talk to DEV             ✗ (isolated)
```

### Step 5: Traffic Flow Example

When VPC-A (us-east-1) sends traffic to VPC-B (eu-west-1):

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  Step 1: VPC-A sends packet to 10.2.0.50                        │
│                                                                 │
│  ┌───────┐                                                      │
│  │ VPC-A │ ──► Packet: src=10.1.0.10, dst=10.2.0.50             │
│  └───┬───┘                                                      │
│      │                                                          │
│      ▼                                                          │
│  Step 2: Reaches CNE, looks up route table                      │
│                                                                 │
│  ┌─────────────────┐                                            │
│  │ us-east-1 CNE   │                                            │
│  │                 │                                            │
│  │ 10.2.0.0/16     │                                            │
│  │   → eu-west-1   │ ◄── Route says: send to eu-west-1          │
│  └────────┬────────┘                                            │
│           │                                                     │
│           ▼                                                     │
│  Step 3: Travels via AWS Backbone                               │
│                                                                 │
│      ═══════════════════════════════════                        │
│           AWS Global Backbone Network                           │
│      ═══════════════════════════════════                        │
│                      │                                          │
│                      ▼                                          │
│  Step 4: Arrives at eu-west-1 CNE                               │
│                                                                 │
│  ┌─────────────────┐                                            │
│  │ eu-west-1 CNE   │                                            │
│  │                 │                                            │
│  │ 10.2.0.0/16     │                                            │
│  │   → local       │ ◄── Route says: deliver locally            │
│  └────────┬────────┘                                            │
│           │                                                     │
│           ▼                                                     │
│  Step 5: Delivered to VPC-B                                     │
│                                                                 │
│  ┌───────┐                                                      │
│  │ VPC-B │ ◄── Packet arrives at 10.2.0.50                      │
│  └───────┘                                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Summary Table

| Routing Behavior | Description |
|------------------|-------------|
| Within Segment | Routes auto-propagate across all regions |
| Between Segments | Isolated by default, need explicit sharing |
| Cross-Region | Automatic via AWS backbone |
| Route Advertisement | VPC CIDRs advertised when attached |
| No Manual Routes | Cloud WAN handles everything |

### Key Takeaways

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  1. Same segment    → Routes shared automatically           │
│  2. Diff segments   → Isolated (unless you share)           │
│  3. Cross-region    → Automatic via AWS backbone            │
│  4. You control     → Segment sharing via policy            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```
