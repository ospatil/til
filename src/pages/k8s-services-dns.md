---
layout: ../layouts/GistLayout.astro
tags: [kubernetes, networking]
---

# Kubernetes Services and DNS Guide

## Service Types

Kubernetes Service types build on each other — each type includes everything the previous one does.

### ClusterIP (Base)

Internal-only. Gets a virtual IP from the service CIDR.

```
Pod → my-svc.default.svc.cluster.local
    → CoreDNS returns ClusterIP (e.g., 172.20.10.5)
    → kube-proxy/eBPF intercepts traffic to 172.20.10.5
    → DNAT to a healthy pod IP (e.g., 10.0.2.47:8080)
```

- Only reachable from within the cluster
- DNS: `<service>.<namespace>.svc.cluster.local` → ClusterIP
- Load balancing: random or round-robin across endpoints via iptables/eBPF

### NodePort (ClusterIP + port on every node)

Allocates a static port (30000–32767) on every node. A ClusterIP is still created underneath.

```
External client → <any-node-ip>:31234
    → kube-proxy/eBPF on that node intercepts
    → DNAT to a healthy pod IP (same as ClusterIP routing)

Internal pod → ClusterIP still works as before
```

- Reachable externally via `<node-ip>:<node-port>`
- DNS: same internal DNS as ClusterIP; no external DNS created
- The port is opened on all nodes, even those not running the target pods — traffic gets forwarded across nodes
- Rarely used directly in production; mainly a building block

### LoadBalancer (NodePort + external LB)

Provisions a cloud load balancer (NLB or ALB on AWS) that routes to the NodePort — or directly to pod IPs in IP target mode.

**Instance target mode (traditional):**

```
Client → AWS NLB/ALB → <node-ip>:<node-port>
    → kube-proxy/eBPF → pod IP (double hop)
```

**IP target mode (default in EKS Auto Mode):**

```
Client → AWS NLB/ALB → pod IP directly (single hop)
```

- DNS: AWS assigns a load balancer DNS name (e.g., `abc123.elb.ca-central-1.amazonaws.com`). No Kubernetes DNS — you create a Route 53 alias/CNAME yourself or use external-dns.
- One LB per Service — gets expensive with many services
- NLB for TCP/UDP (Layer 4), ALB for HTTP/HTTPS (Layer 7)

#### IP Target vs Instance Target Mode

With VPC CNI, pods have real VPC IPs, so the load balancer can route directly to them.

| | IP Target Mode | Instance Target Mode |
|---|---|---|
| **Traffic path** | LB → pod directly | LB → node → kube-proxy → pod |
| **Latency** | Lower (one fewer hop) | Higher (extra node hop) |
| **Distribution** | Even across pods | Uneven (nodes may have different pod counts) |
| **Source IP** | Preserved | May require `externalTrafficPolicy: Local` |
| **Default in** | EKS Auto Mode | Standard EKS |

In standard EKS, opt in with annotations:

```yaml
# For NLB
service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
# For ALB via Ingress
alb.ingress.kubernetes.io/target-type: ip
```

#### Bare-Metal / MetalLB

> **Deep dive**: See [02-k8s-network-infrastructure.md](./02-k8s-network-infrastructure.md) for how L2 Announcements and BGP work under the hood, and how MetalLB compares to Cilium LB-IPAM and LoxiLB.

On bare-metal clusters (k3s, kubeadm, etc.) with MetalLB, there's no cloud LB that can register pod IPs. The flow is always:

```
Client → MetalLB VIP → Node → kube-proxy → Pod
```

MetalLB operates in L2 mode (ARP, single node owns VIP) or BGP mode (multiple nodes advertise VIP to upstream router). Either way, the node hop is unavoidable because pod IPs on overlay networks aren't directly routable from outside the cluster.

### ExternalName (DNS alias)

No ClusterIP, no proxying — purely a DNS CNAME redirect.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-database
spec:
  type: ExternalName
  externalName: mydb.abc123.ca-central-1.rds.amazonaws.com
```

```
Pod resolves my-database.default.svc.cluster.local
  → CoreDNS returns CNAME → mydb.abc123.rds.amazonaws.com
    → Pod resolves and connects directly
```

Use cases:

- Reference external services with in-cluster DNS names
- Migration path — switch from ExternalName to ClusterIP when bringing a service in-cluster
- Cross-namespace references

Limitations:

- `externalName` must be a DNS name, not an IP address
- No port remapping, no health checks
- TLS/SNI issues: if the client does hostname verification, the in-cluster name won't match the external certificate. For HTTPS services this can break TLS. For databases with `sslmode=verify-ca` (verify CA only, not hostname) it's fine; `sslmode=verify-full` would fail.

### Headless Service (clusterIP: None)

No ClusterIP allocated. DNS returns individual pod IPs directly instead of a single virtual IP.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-svc
spec:
  clusterIP: None
  selector:
    app: my-app
```

```
Pod resolves my-svc.default.svc.cluster.local
  → CoreDNS returns A records: 10.0.2.10, 10.0.2.11, 10.0.2.12
  → Pod connects to one of them directly (client's choice)
```

No kube-proxy/eBPF interception — DNS returns the IPs and the pod connects directly.

#### Headless Services + StatefulSets

StatefulSets need headless Services because each pod has a stable identity and clients often need to reach a specific pod.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  clusterIP: None
  selector:
    app: mysql
  ports:
    - port: 3306
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql    # links to the headless service
  replicas: 3
```

The `serviceName` field tells Kubernetes to create per-pod DNS records:

```
# Service-level — returns all pod IPs
mysql.default.svc.cluster.local → 10.0.2.10, 10.0.2.11, 10.0.2.12

# Per-pod — stable DNS name for each pod
mysql-0.mysql.default.svc.cluster.local → 10.0.2.10
mysql-1.mysql.default.svc.cluster.local → 10.0.2.11
mysql-2.mysql.default.svc.cluster.local → 10.0.2.12
```

Clients can connect to a specific pod (`mysql-0.mysql`) or any pod (`mysql`). The service-level DNS returns all IPs — which one the client picks depends on the DNS client (not true load balancing).

A common pattern for databases is two Services:

```yaml
# Headless — for per-pod addressing
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  clusterIP: None
  selector:
    app: mysql
---
# Regular ClusterIP — for load-balanced reads
apiVersion: v1
kind: Service
metadata:
  name: mysql-read
spec:
  selector:
    app: mysql
    role: replica
  ports:
    - port: 3306
```

Writes go to `mysql-0.mysql` (specific primary), reads go to `mysql-read` (ClusterIP load-balances across replicas).

##### The concept of primary

Kubernetes itself has no concept of "primary" or "replica". The statement assumes `mysql-0` is the primary, and this is a widely-used convention that must be implemented at the application level.

StatefulSets guarantee ordered, stable pod identities. The setup scripts leverage the ordinal index (the number in the pod name) to assign roles:

```yaml
# Typically done in an initContainer or entrypoint script
apiVersion: apps/v1
kind: StatefulSet
metadata:
name: mysql
spec:
serviceName: mysql
replicas: 3
template:
spec:
  initContainers:
    - name: init-mysql
      image: mysql:8.0
      command:
        - bash
        - -c
        - |
          # Extract ordinal index from hostname
          ORDINAL=$(hostname | grep -o '[0-9]*$')

          if [ "$ORDINAL" -eq 0 ]; then
            # mysql-0 → configure as PRIMARY
            echo "[mysqld]"              > /etc/mysql/conf.d/server.cnf
            echo "server-id=1"          >> /etc/mysql/conf.d/server.cnf
            echo "log-bin=mysql-bin"    >> /etc/mysql/conf.d/server.cnf
          else
            # mysql-1, mysql-2 → configure as REPLICA
            echo "[mysqld]"                      > /etc/mysql/conf.d/server.cnf
            echo "server-id=$((ORDINAL + 1))"   >> /etc/mysql/conf.d/server.cnf
            echo "read-only=1"                   >> /etc/mysql/conf.d/server.cnf
            echo "super-read-only=1"             >> /etc/mysql/conf.d/server.cnf
          fi
```

##### The Key Chain of Responsibility

```sh
Kubernetes guarantees        Application implements       Clients assume
─────────────────────       ──────────────────────       ──────────────
• mysql-0 always exists  →  • mysql-0 runs as primary →  • Writes → mysql-0.mysql
• Stable DNS names       →  • mysql-1,2 run as replicas→  • Reads  → mysql-read
• Ordered creation       →  • Replication configured
```

##### A More Robust Alternative: Label-Based Selection

Rather than hardcoding `mysql-0.mysql` as the write endpoint, production setups often use labels + a dedicated primary service:

```yaml
# Primary-only service (writes)
apiVersion: v1
kind: Service
metadata:
  name: mysql-primary
spec:
  selector:
    app: mysql
    role: primary      # ← only the primary pod has this label
  ports:
    - port: 3306
---
# Replica-only service (reads)
apiVersion: v1
kind: Service
metadata:
  name: mysql-read
spec:
  selector:
    app: mysql
    role: replica
  ports:
    - port: 3306
```

The operator or sidecar manages the labels:

```sh
Normal operation:
  mysql-0  →  labels: {app: mysql, role: primary}
  mysql-1  →  labels: {app: mysql, role: replica}
  mysql-2  →  labels: {app: mysql, role: replica}

After failover (mysql-0 dies, mysql-1 promoted):
  mysql-1  →  labels: {app: mysql, role: primary}   ← label changed
  mysql-2  →  labels: {app: mysql, role: replica}
```

This is exactly what MySQL Operator, Vitess, and similar operators do — they watch cluster state and shuffle labels so the services automatically route to the correct pod.

#### Headless Service with Manual Endpoints

For pointing at external IPs that aren't managed by Kubernetes. Create a Service with no `selector` and a matching Endpoints object:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-db
spec:
  clusterIP: None
  ports:
    - port: 5432
---
apiVersion: v1
kind: Endpoints
metadata:
  name: external-db     # must match Service name
subsets:
  - addresses:
      - ip: 10.0.5.20
      - ip: 10.0.6.21
    ports:
      - port: 5432
```

DNS returns the IPs directly. Use a regular ClusterIP Service (instead of headless) with manual Endpoints to get kube-proxy load balancing across the external IPs.

Use cases:

- External services that only have IPs (ExternalName requires a DNS name)
- Load balancing across multiple external endpoints
- Gradual migration — start with manual Endpoints, add a `selector` later when the service moves in-cluster
- Health-aware routing — update Endpoints to remove unhealthy IPs

For newer clusters, `EndpointSlice` is the preferred API:

```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: external-db-1
  labels:
    kubernetes.io/service-name: external-db
addressType: IPv4
endpoints:
  - addresses: ["10.0.5.20"]
  - addresses: ["10.0.6.21"]
ports:
  - port: 5432
```

## Ingress

Not a Service type — a separate resource that sits in front of multiple ClusterIP Services, routing by host/path through a shared ALB.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
spec:
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-svc
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-svc
                port:
                  number: 80
```

```
Client → ALB (single LB, shared)
    → /api → api-svc pods (IP target)
    → /    → frontend-svc pods (IP target)
```

- One ALB handles many services — cost-efficient vs one LoadBalancer Service per service
- Layer 7 only (HTTP/HTTPS)
- TLS termination at the ALB
- Requires an Ingress controller (built into EKS Auto Mode, or AWS Load Balancer Controller in standard EKS)

## Gateway API

The successor to Ingress. Splits concerns across multiple resources for better role separation.

```
GatewayClass → who provides the infrastructure (e.g., AWS ALB)
Gateway      → the actual LB instance (ports, TLS, listeners)
HTTPRoute    → routing rules (replaces Ingress rules)
```

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
spec:
  gatewayClassName: amazon-alb
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        certificateRefs:
          - name: my-cert
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
spec:
  parentRefs:
    - name: my-gateway
  hostnames:
    - "app.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api-svc
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: frontend-svc
          port: 80
```

Advantages over Ingress:

- **Role separation** — platform team manages GatewayClass + Gateway, app teams manage HTTPRoutes
- **Multi-protocol** — supports TCP, UDP, gRPC, TLS natively via `TCPRoute`, `GRPCRoute`, etc.
- **Cross-namespace routing** — HTTPRoutes in different namespaces can attach to a shared Gateway
- **Traffic splitting** — native weighted routing for canary deployments
- **Standardized** — features expressed in the spec, not vendor-specific annotations

## DNS in Kubernetes

### DNS Hierarchy

CoreDNS serves the `cluster.local` domain. The full DNS structure:

```
<service>.<namespace>.svc.cluster.local          → Service ClusterIP
<pod-name>.<service>.<namespace>.svc.cluster.local → Pod IP (StatefulSet + headless)
<pod-ip-dashed>.<namespace>.pod.cluster.local     → Pod IP (e.g., 10-0-2-47.default.pod.cluster.local)
```

Within the same namespace, pods can use short names:

```
my-svc                                    → works (same namespace)
my-svc.other-namespace                    → works (cross-namespace)
my-svc.other-namespace.svc.cluster.local  → fully qualified
```

### DNS Resolution by Service Type

| Service Type | DNS Response |
|---|---|
| **ClusterIP** | A record → ClusterIP |
| **Headless** | A records → individual pod IPs |
| **Headless + StatefulSet** | A records for service + per-pod A records |
| **ExternalName** | CNAME → external DNS name |
| **NodePort** | A record → ClusterIP (same as ClusterIP) |
| **LoadBalancer** | A record → ClusterIP (internal); external DNS managed separately |

### Service Discovery Methods

Kubernetes provides two ways for pods to discover services:

**DNS (recommended)** — pods resolve service names via CoreDNS. Works for all service types and updates automatically.

**Environment variables** — kubelet injects `<SERVICE_NAME>_SERVICE_HOST` and `<SERVICE_NAME>_SERVICE_PORT` into every pod. Only includes services that existed when the pod started. Doesn't update if services change. Mainly a legacy mechanism.

## Traffic Policies

Both traffic policies are fields on the Service `spec`. They are configured per-service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-svc
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local    # or Cluster (default)
  internalTrafficPolicy: Local    # or Cluster (default)
```

### externalTrafficPolicy

Applies only to `LoadBalancer` and `NodePort` service types (traffic originating from outside the cluster).

Controls how traffic from external sources (LoadBalancer, NodePort) is routed to pods.

**Cluster (default)** — traffic can be routed to pods on any node. If the pod isn't on the receiving node, there's an extra hop. Source IP is lost (SNAT'd to the node IP).

```
Client → Node A (no pod here) → SNAT → Node B (pod here)
Pod sees source IP: Node A's IP
```

**Local** — traffic is only routed to pods on the receiving node. No extra hop, source IP preserved. But if a node has no pods, traffic to that node is dropped.

```
Client → Node B (pod here) → Pod
Pod sees source IP: Client's real IP
```

| | `Cluster` | `Local` |
|---|---|---|
| **Distribution** | Even across all pods | Only to local pods |
| **Source IP** | Lost (SNAT) | Preserved |
| **Extra hops** | Possible | None |
| **Risk** | None | Dropped traffic if node has no pods |

With IP target mode in EKS, `externalTrafficPolicy` is less relevant since the LB routes directly to pods, bypassing nodes entirely.

### internalTrafficPolicy

Applies to all service types (traffic originating from within the cluster). Controls how cluster-internal traffic is routed.

**Cluster (default)** — traffic can go to any pod backing the service, on any node.

**Local** — traffic is only routed to pods on the same node as the caller. Useful for node-local caches or DaemonSet services where you want each pod to talk to the local instance.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: node-cache
spec:
  internalTrafficPolicy: Local
  selector:
    app: cache
```

## ExternalDNS

The `cluster.local` DNS is purely internal — CoreDNS only serves it to pods inside the cluster. External clients have no visibility into it. ExternalDNS bridges that gap by watching Kubernetes resources and automatically creating/updating DNS records in an external DNS provider.

### How It Works

```
You create:  Ingress with host: app.example.com → ALB provisioned
ExternalDNS: watches the Ingress, sees the ALB DNS name
           → creates DNS record: app.example.com → ALB DNS name
```

Without ExternalDNS, you'd manually create that DNS record every time you deploy a new Ingress or LoadBalancer Service.

### What It Watches

- **LoadBalancer Services** — registers the LB's external DNS name/IP
- **Ingress resources** — registers based on the `host` field
- **Gateway API HTTPRoutes** — registers based on `hostnames`
- **NodePort Services** — registers node IPs (less common)

### Typical Setup with Route 53

ExternalDNS runs as a pod in the cluster with IAM permissions to manage Route 53:

```yaml
args:
  - --source=ingress
  - --source=service
  - --provider=aws
  - --domain-filter=example.com        # only manage this domain
  - --policy=upsert-only               # safety: never delete records
  - --txt-owner-id=my-cluster          # ownership tracking
```

The `txt-owner-id` creates TXT records alongside each DNS record to track ownership, preventing multiple clusters from clobbering each other's records.

### End-to-End Flow

```
1. Deploy Ingress with host: app.example.com
2. AWS LB Controller provisions ALB → abc123.elb.amazonaws.com
3. ExternalDNS sees the Ingress, creates Route 53 record:
   app.example.com → ALIAS → abc123.elb.amazonaws.com
4. External client resolves app.example.com → ALB → pods
```

### Providers

ExternalDNS supports many providers — Route 53, CloudFlare, Google Cloud DNS, Azure DNS, and others.

It also supports CoreDNS as a provider, which is useful in on-prem or air-gapped environments without cloud DNS. In this setup, a separate CoreDNS instance runs on the network segment (outside the cluster) with a backend that supports dynamic updates (commonly etcd, though CoreDNS supports multiple backends including file-based zone files, the kubernetes API, and others). ExternalDNS writes records to the backend, and the external CoreDNS serves them to clients on the network — making Kubernetes service endpoints resolvable from outside the cluster without a cloud DNS provider.

```
Cluster:  ExternalDNS watches Services/Ingresses → writes to backend (e.g., etcd)
Network:  External CoreDNS reads from backend → serves DNS to on-prem clients
```

## Summary

| Type | Scope | DNS | Load Balancing | Cost |
|------|-------|-----|----------------|------|
| **ClusterIP** | Internal only | `svc.cluster.local` → ClusterIP | kube-proxy/eBPF | Free |
| **NodePort** | External via node IP | No external DNS | kube-proxy/eBPF | Free |
| **LoadBalancer** | External via cloud LB | LB DNS name (manual Route 53) | Cloud LB → pods | 1 LB per service |
| **ExternalName** | DNS alias to external | CNAME to external name | None | Free |
| **Headless** | Internal, direct pod IPs | A records → pod IPs | None (client chooses) | Free |
| **Ingress** | External via shared ALB | 1 ALB DNS (manual Route 53) | ALB path/host routing → pods | 1 ALB shared |
| **Gateway API** | External via shared LB | Same as Ingress | Same, with more control | 1 LB shared |

The progression: ClusterIP (internal) → NodePort (expose on nodes) → LoadBalancer (cloud LB per service) → Ingress/Gateway API (shared LB, smart routing).

---

## Cross-References

### Related: Network Infrastructure Deep Dive

See [Kubernetes Network Infrastructure — L2, BGP, and On-Prem Load Balancing](k8s-network-infrastructure.md) for:

- **L2 Announcements** — how VIPs work via ARP, failover via gratuitous ARP, broadcast domain limitations
- **BGP Route Advertisement** — peering, ECMP multi-node load balancing, route propagation
- **MetalLB vs Cilium vs LoxiLB** — on-prem load balancer comparison (control plane vs data plane)
- **Overlay vs Native CNI** — why Flannel pod IPs aren't externally routable, contrast with VPC CNI
- **External LBs (NGINX/HAProxy)** — service discovery via Consul, static config, external ingress controllers
- **Protocol deep dives** — ARP mechanics, BGP message types, SCTP
