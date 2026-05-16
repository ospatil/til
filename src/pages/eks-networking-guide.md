---
layout: ../layouts/GistLayout.astro
tags: [aws, kubernetes, networking, guide]
---

# EKS Networking Guide

## AWS VPC CNI - Pod Networking

The fundamental difference from most Kubernetes CNI plugins: pods get real VPC IP addresses, not overlay network IPs.

### How It Works

Each EC2 instance (node) has Elastic Network Interfaces (ENIs). The VPC CNI:

1. Attaches secondary ENIs to the node
2. Allocates secondary IPs on each ENI from the subnet CIDR
3. Assigns those IPs directly to pods - each pod gets a routable VPC IP

A pod at `10.0.2.47` is just another IP on the VPC - no encapsulation, no overlay, no tunneling.

### Why This Matters

- **Pod-to-pod across nodes** - regular VPC routing, no overlay overhead. VPC route tables already know how to reach these IPs.
- **Pod-to-AWS services** - pods talk to RDS, S3 endpoints, etc. directly. Security groups and NACLs work natively.
- **Pod-to-on-premises** - traffic flows through VPC peering/Transit Gateway/VPN without translation, since pod IPs are part of the VPC CIDR.
- **ALB/NLB IP targets** - load balancers register pod IPs directly as targets (no node hop needed).
- **Security groups for pods** - since pods use ENIs, security groups can be attached directly to pods.

### IP Address Consumption

The main constraint is IP exhaustion. Every pod consumes a VPC IP. The number of pods per node is limited by:

```
Max pods = (number of ENIs × IPs per ENI) - node IPs
```

This varies by instance type. A `t3.medium` supports far fewer pods than an `m5.xlarge`.

Mitigations:

- **Prefix delegation** - assigns /28 prefixes instead of individual IPs to ENIs, significantly increasing pod density
- **Pod subnet isolation** - pods use different subnets than nodes, giving a larger IP pool
- **Secondary CIDRs** - add a `100.64.0.0/16` (RFC 6598) CIDR to the VPC for pod IPs

### Prefix Delegation

Without prefix delegation, each ENI slot holds one IP. With prefix delegation, each slot holds a /28 prefix - 16 IPs per slot.

#### Example (m5.large - 3 ENIs, 10 IP slots per ENI)

Without prefix delegation:

```
3 ENIs × 10 slots × 1 IP per slot = 30 IPs
Minus node/ENI primary IPs        = 27 usable pod IPs
```

With prefix delegation:

```
3 ENIs × 10 slots × 16 IPs per slot = 480 IPs
Minus node/ENI primary IPs          = 477 usable pod IPs
```

Same number of ENIs, same number of slots - but each slot carries a /28 block instead of a single address.

#### How Prefix Delegation Works

An ENI has a fixed number of address slots determined by the instance type. These slots are a VPC/hypervisor-level construct - entries in the ENI's address table that the VPC networking fabric tracks for routing.

A slot can hold either a single IP address or a /28 prefix. It's the same slot, same hypervisor resource - the difference is what you put in it.

Without prefix delegation, the VPC routing layer stores individual routes:

```
10.0.2.47 → ENI-abc (individual route)
10.0.2.48 → ENI-abc (individual route)
10.0.2.49 → ENI-abc (individual route)
```

With prefix delegation, it stores a single prefix route:

```
10.0.2.48/28 → ENI-abc (single prefix route covering 16 IPs)
```

The ENI receives the packets either way. Once the packet arrives at the node, the CNI plugin on the host decides which pod's network namespace to deliver it to. The ENI is just a pipe - it doesn't care if it's handling 1 IP or 16 IPs from a prefix.

The instance type limit on slots is about how many routing entries the VPC hypervisor tracks per ENI. A prefix entry and a single-IP entry cost the same - one slot, one routing rule. But a prefix entry covers 16 addresses instead of 1.

Subnets need to be large enough to allocate contiguous /28 blocks. If subnets are heavily fragmented or small, prefix allocation can fail even when individual IPs are available. Typically /19 or larger subnets are recommended for production.

#### Prefix Delegation in Standard EKS vs Auto Mode

In **standard EKS**, prefix delegation is off by default for IPv4 clusters and must be enabled manually:

```bash
kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true
```

You also configure warm pool settings (`WARM_PREFIX_TARGET`, `WARM_IP_TARGET`, `MINIMUM_IP_TARGET`) and set `maxPods` on node groups.

In **EKS Auto Mode**, prefix delegation is on by default. Auto Mode also:

- Maintains a predefined warm pool that scales based on scheduled pods
- Falls back to secondary IPs (/32) when subnet fragmentation is detected
- Calculates max pods per node based on ENIs and IPs per instance type (assuming worst-case fragmentation)
- Implements a cooldown pool for unused prefixes before releasing them back to the VPC

You cannot configure warm IP/prefix/ENI settings in Auto Mode - AWS manages these automatically.

#### Warm Pool

The CNI pre-allocates IP resources before pods need them. When a new pod is scheduled, it gets an IP instantly instead of waiting for a VPC API call.

Without a warm pool:

```
Pod scheduled → call VPC API to allocate IP → wait → assign IP to pod → pod starts
```

With a warm pool:

```
Pod scheduled → grab pre-allocated IP from warm pool → pod starts immediately
(background: replenish warm pool with another VPC API call)
```

In standard EKS, this is tuned with:

- `WARM_PREFIX_TARGET` - how many spare /28 prefixes to keep ready
- `WARM_IP_TARGET` - how many spare individual IPs to keep ready
- `MINIMUM_IP_TARGET` - minimum IPs to always have available

In Auto Mode, the warm pool size scales automatically based on scheduled pods.

The tradeoff: a larger warm pool means faster pod startup but more IPs reserved and unavailable to other nodes/services. Too small and pod scheduling stalls waiting for IP allocation.

#### Cooldown

When a pod terminates, its IP isn't released back to the VPC immediately. Instead, it enters a cooldown pool for a period of time.

This serves two purposes:

1. **Reuse optimization** - if a new pod is scheduled shortly after, the IP can be reused from the cooldown pool without a VPC API call. This is common during rolling deployments where pods are constantly replaced.
2. **Connection draining** - stale connections or DNS caches might still reference the old pod's IP. The cooldown period gives time for those to expire before the IP is returned to the VPC and potentially assigned to something else.

```
Pod terminates → IP moves to cooldown pool
  → New pod scheduled quickly? → reuse IP from cooldown pool
  → Cooldown expires? → release IP back to VPC
```

Together, warm pool and cooldown create a buffer on both sides - pre-allocation for fast startup, delayed release for safe cleanup.

### Pod Subnet Isolation

By default, pods and nodes share the same subnet. If the node subnet is a `/24` (256 IPs), both nodes and pods compete for those IPs. Isolating pod traffic to separate subnets avoids this.

In **standard EKS**, this is done via Custom Networking with `ENIConfig` resources that tell the CNI to attach secondary ENIs (used for pod IPs) to a different subnet:

```
Node primary ENI  → Subnet A (10.0.1.0/24) - node IPs
Pod secondary ENIs → Subnet B (10.0.2.0/20) - pod IPs only
```

In **EKS Auto Mode**, `ENIConfig` is not supported. Instead, the `NodeClass` resource provides `podSubnetSelectorTerms` and `podSecurityGroupSelectorTerms` fields. When configured, Auto Mode attaches secondary ENIs in the pod subnets and assigns pod IPs from those subnets instead of the node subnets.

```yaml
apiVersion: eks.amazonaws.com/v1
kind: NodeClass
metadata:
  name: advanced-networking
spec:
  role: MyNodeRole

  # Subnets for nodes
  subnetSelectorTerms:
    - tags:
        Name: "node-subnet"
        kubernetes.io/role/internal-elb: "1"

  securityGroupSelectorTerms:
    - tags:
        Name: "eks-cluster-sg"

  # Separate subnets for pods
  podSubnetSelectorTerms:
    - tags:
        Name: "pod-subnet"
        kubernetes.io/role/pod: "1"

  podSecurityGroupSelectorTerms:
    - tags:
        Name: "eks-pod-sg"
```

Use cases for pod subnet isolation:

- Separate infrastructure traffic (node-to-node) from application traffic (pod-to-pod)
- Apply different network ACLs or route tables to pod traffic vs node traffic
- Implement different security policies for nodes and pods

Considerations:

- **Reduced pod density** - the node's primary ENI can't be used for pods in the pod subnet
- **AZ alignment** - pod subnets must be in the same AZ as the node subnet
- **Routing** - verify route tables and NACLs allow communication between node and pod subnets

Auto Mode also exposes `advancedNetworking.ipv4PrefixSize` in the `NodeClass` to control prefix delegation behavior:

```yaml
advancedNetworking:
  ipv4PrefixSize: Auto  # default - /28 prefixes with fallback to /32 on fragmentation
  # ipv4PrefixSize: "32"  # secondary IP mode only (no prefix delegation)
```

Setting `ipv4PrefixSize` to `"32"` disables prefix delegation and uses only individual secondary IPs. This is useful when subnet fragmentation makes prefix allocation unreliable, at the cost of slower pod creation and a smaller warm pool.

### Secondary CIDRs

This solves the problem of a VPC CIDR that is too small or too fragmented for large pod subnets. AWS allows adding secondary CIDR blocks to a VPC. The common pattern is to add `100.64.0.0/16` (RFC 6598 - carrier-grade NAT range, 65,536 IPs) as a secondary CIDR, then create pod subnets from that range:

```
VPC primary CIDR:   10.0.0.0/16   → nodes, RDS, other infra
VPC secondary CIDR: 100.64.0.0/16 → pod subnets only
```

This is useful when:

- The original VPC CIDR was sized before Kubernetes was in the picture
- The VPC is peered with other VPCs and the `10.x` ranges are already allocated
- Thousands of pod IPs are needed but the primary CIDR can't be expanded

Secondary CIDRs are often combined with pod subnet isolation: add the secondary CIDR, create large subnets from it in each AZ, then configure pods to use those subnets.

One caveat with `100.64.0.0/16`: these IPs aren't routable across VPC peering or Transit Gateway by default. If pods need to be directly reachable from other VPCs or on-prem, use a routable secondary CIDR instead.

## Service Networking

### ClusterIP and Service CIDR

ClusterIP services get IPs from the service CIDR - this is the same regardless of the networking implementation. The difference is in how traffic gets routed to the backing pods.

### Cluster-Internal Traffic (Pod → Service → Pod)

In a standard EKS cluster, `kube-proxy` watches the API server for Service/Endpoints changes and programs iptables (or IPVS) rules on every node. When a pod calls `my-service.default.svc.cluster.local`:

1. CoreDNS resolves it to the ClusterIP
2. kube-proxy's iptables/IPVS rules on the node intercept the packet
3. DNAT rewrites the destination to a healthy pod IP
4. The packet routes to the pod via the CNI

In EKS Auto Mode, steps 2-3 are handled by the managed data plane instead of kube-proxy. AWS implements the equivalent service routing (ClusterIP → pod IP translation) directly in the network layer. The behavior is identical from the application's perspective.

### External Traffic (Client → Ingress → Pod)

For traffic from outside the cluster:

1. A `Service` of type `LoadBalancer` provisions an NLB/ALB. An `Ingress` resource provisions an ALB with path/host-based routing.
2. Traffic flow depends on target type:
   - **Instance target type**: LB → node → service routing → pod
   - **IP target type** (default in Auto Mode): LB → pod IP directly, bypassing node-level service routing

With IP target mode, the load balancer registers pod IPs directly as targets, so external traffic skips ClusterIP translation - it goes straight from the ALB/NLB to the pod.

### ALB Load Balancing Algorithms

ALB supports two algorithms, configurable via the target group:

1. **Round Robin** (default) - requests distributed sequentially across healthy targets. Works well when targets have similar capacity and processing times.
2. **Least Outstanding Requests (LOR)** - routes to the target with the fewest in-flight requests. Better when pods have varying processing times or uneven capacity.

Set via Ingress annotation:

```yaml
alb.ingress.kubernetes.io/target-group-attributes: load_balancing.algorithm.type=least_outstanding_requests
```

Other factors affecting distribution:

- **Slow start** - ramp-up period for new pods:
  ```yaml
  alb.ingress.kubernetes.io/target-group-attributes: slow_start.duration_seconds=30
  ```
- **Sticky sessions** - pins a client to a specific pod using cookies:
  ```yaml
  alb.ingress.kubernetes.io/target-group-attributes: stickiness.enabled=true,stickiness.type=lb_cookie
  ```
- **AZ balancing** - ALB distributes evenly across AZs first, then applies the algorithm within each AZ. Unevenly spread pods across AZs can lead to uneven traffic distribution.

### Summary

| Path | Standard EKS | EKS Auto Mode |
|------|-------------|---------------|
| **Internal (pod → service)** | kube-proxy iptables/IPVS rules | Managed data plane (built into nodes) |
| **External (client → service)** | AWS LB Controller + kube-proxy | Built-in LB management + managed data plane |
| **ClusterIP allocation** | Same (from service CIDR) | Same (from service CIDR) |
| **DNS resolution** | CoreDNS (self-managed) | CoreDNS (AWS-managed) |

## EKS Auto Mode

EKS Auto Mode replaces self-managed add-ons with AWS-managed equivalents:

- **No kube-proxy** daemonset - service networking is handled natively by the managed data plane
- **No VPC CNI daemonset** - pod networking is managed by the platform
- **No CoreDNS deployment** - CoreDNS runs as a system service directly on each node, not as pods

The networking model (Services, ClusterIPs, Endpoints, VPC-native pod IPs) remains the same - the implementation is fully managed by AWS rather than running as user-space daemonsets.

### NodeClass and NodePool Custom Resources

EKS Auto Mode uses two Custom Resources (CRDs) for node management:

- **NodePool** (`karpenter.sh/v1`) - defines *what* nodes to provision (instance types, capacity type, architecture, taints). Auto Mode uses Karpenter under the hood for node provisioning.
- **NodeClass** (`eks.amazonaws.com/v1`) - defines *how* nodes are configured (networking, storage, IAM, security). This is EKS-specific and replaces VPC CNI configuration that would normally be done via environment variables on the `aws-node` daemonset.

#### Built-in NodePools

Auto Mode creates two NodePools by default, both referencing a shared `default` NodeClass:

| | `general-purpose` | `system` |
|---|---|---|
| **Purpose** | Application workloads | Critical system add-ons |
| **Taints** | None | `CriticalAddonsOnly: NoSchedule` |
| **Architecture** | amd64 | amd64 + arm64 |
| **Instance categories** | c, m, r (gen > 4) | c, m, r (gen > 4) |
| **Capacity type** | on-demand | on-demand |
| **Node expiry** | 336h (14 days) | 336h (14 days) |
| **Disruption** | Consolidate when empty/underutilized | Same |

The `system` nodepool's taint ensures only workloads with a matching toleration are scheduled there.

#### NodeClass Key Attributes

| Attribute | Description |
|-----------|-------------|
| `subnetSelectorTerms` | Selects subnets for node placement (by tags or ID) |
| `securityGroupSelectorTerms` | Selects security groups for nodes |
| `podSubnetSelectorTerms` | Isolates pod traffic to separate subnets from nodes |
| `podSecurityGroupSelectorTerms` | Required with pod subnet selector; security groups for pods |
| `snatPolicy` | Controls source NAT for pod traffic leaving the VPC. `Random` (default) - node rewrites pod source IP to node IP with random port for outbound traffic. `Disabled` - no SNAT; use when a NAT Gateway handles translation |
| `networkPolicy` | `DefaultAllow` (default) or `DefaultDeny` for Kubernetes network policies |
| `networkPolicyEventLogs` | `Enabled` or `Disabled` for network policy event logging |
| `ephemeralStorage` | Node storage configuration (size, IOPS, throughput, KMS encryption) |
| `advancedNetworking.ipv4PrefixSize` | `Auto` (default - /28 prefixes with /32 fallback) or `"32"` (secondary IP mode only) |
| `role` | IAM role for EC2 instances |

## Pod Distribution Across Availability Zones

### Topology Spread Constraints (Recommended)

The most direct way to spread pods across AZs:

```yaml
spec:
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app: my-app
```

- `maxSkew: 1` - at most 1 pod difference between AZs
- `DoNotSchedule` - hard requirement. Use `ScheduleAnyway` for a soft preference.
- With 3 replicas across 2 AZs: 2-1 split. With 3 AZs: 1-1-1 split.

### Pod Anti-Affinity

Prevents pods from landing on the same node or AZ:

```yaml
spec:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app: my-app
            topologyKey: topology.kubernetes.io/zone
```

Use `preferredDuringScheduling` (soft) for best-effort, or `requiredDuringScheduling` (hard) to guarantee it. Hard anti-affinity can block scheduling if there aren't enough AZs for the replica count.

### Combined Pattern for Production

Spread across AZs (hard) and across nodes within each AZ (soft):

```yaml
spec:
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app: my-app
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          app: my-app
```

### Approach Comparison

| Approach | Best For |
|----------|----------|
| **Topology Spread Constraints** | Most cases - explicit, predictable AZ distribution |
| **Pod Anti-Affinity** | Avoiding co-location on the same node |
| **Both combined** | Spread across AZs and across nodes within each AZ |

In EKS Auto Mode, topology spread constraints work well because Auto Mode provisions nodes in the right AZ to satisfy the constraint.
