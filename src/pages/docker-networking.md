---
layout: ../layouts/GistLayout.astro
tags: [docker, networking, guide]
---

# Docker Networking Guide

A comprehensive guide to understanding Docker networking, network modes, security configurations, and common pitfalls.

---

## Table of Contents

1. [Network Modes Overview](#1-network-modes-overview)
2. [Mixing Network Modes in Docker Compose](#2-mixing-network-modes-in-docker-compose)
3. [Network Security](#3-network-security)
4. [Accessing Internal Containers from Host](#4-accessing-internal-containers-from-host)
5. [Understanding 0.0.0.0 vs 127.0.0.1 in Containers](#5-understanding-0000-vs-127001-in-containers)
6. [Quick Reference](#6-quick-reference)

---

## 1. Network Modes Overview

### What are the different Docker network modes and when should each be used?

Docker provides several network modes for different use cases:

| Mode | Description |
|------|-------------|
| **bridge** | Default. Containers get their own IP on an isolated network |
| **host** | Container shares the host's network stack directly |
| **none** | No networking |
| **overlay** | Multi-host networking (Swarm) |
| **macvlan** | Assigns MAC address, container appears as physical device |

### When to Use Each Mode

| Use Case | Recommended Mode |
|----------|------------------|
| Most applications | bridge |
| Need maximum network performance | host |
| Container needs to access all host ports | host |
| Network isolation required | bridge |
| Multiple containers need same internal port | bridge |

### Visual Overview

```
┌─────────────────────────────────────────────────────────┐
│                        HOST                             │
│  ┌──────────────────────────────────────────────────┐   │
│  │              Host Network (eth0)                 │   │
│  │                    │                             │   │
│  │         ┌──────────┴──────────┐                  │   │
│  │         │                     │                  │   │
│  │   ┌─────▼─────┐         ┌─────▼─────┐            │   │
│  │   │ Container │         │   Host    │            │   │
│  │   │  (host    │         │  Services │            │   │
│  │   │   mode)   │         │           │            │   │
│  │   └───────────┘         └───────────┘            │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │           Bridge Network (docker0)               │   │
│  │                    │                             │   │
│  │    ┌───────────────┼───────────────┐             │   │
│  │    │               │               │             │   │
│  │ ┌──▼───┐       ┌───▼──┐       ┌───▼──┐           │   │
│  │ │ web  │       │  db  │       │ app  │           │   │
│  │ └──────┘       └──────┘       └──────┘           │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Mixing Network Modes in Docker Compose

### Can I have some containers running in bridge mode while others use host mode in the same Docker Compose file?

Yes! You can use different network modes for different services in the same compose file.

### Example Configuration

```yaml
services:
  # Service using default bridge network
  webapp:
    image: nginx
    networks:
      - my_bridge_network

  # Service using host networking
  monitoring:
    image: prometheus
    network_mode: host

  # Another service on bridge network
  database:
    image: postgres
    networks:
      - my_bridge_network

networks:
  my_bridge_network:
```

### Important Limitations with Host Mode

When using `network_mode: host`:

- **Port mapping is ignored** (container binds directly to host ports)
- **Cannot use `networks:` property** together with `network_mode: host`
- Container can access host services on `localhost` directly

### Communication Between Modes

> **Important:** A container in `host` mode and a container in `bridge` mode **cannot** communicate via Docker's internal DNS (service names).

The host-mode container would need to connect via:
- The host's IP address
- Published ports of the bridge container

---

## 3. Network Security

### 3.1 Basic Principle: Don't Publish Ports

```yaml
services:
  # ✅ SECURE - No ports exposed to outside world
  database:
    image: postgres
    networks:
      - internal_net
    # No "ports:" section = not accessible from outside

  # ❌ EXPOSED - This publishes port to host (and potentially outside)
  webapp:
    image: nginx
    ports:
      - "8080:80"  # Accessible from outside!
    networks:
      - internal_net

networks:
  internal_net:
```

### 3.2 Internal Networks

Use `internal: true` to completely block external access:

```yaml
services:
  database:
    image: postgres
    networks:
      - internal_net  # Only on internal network

  nginx:
    image: nginx
    ports:
      - "80:80"  # Only nginx exposed to outside
    networks:
      - internal_net

networks:
  internal_net:
    internal: true  # 🔒 No external connectivity AT ALL
```

```
                        │
                        ▼
┌───────────────────────────────────────────────────┐
│                     HOST                          │
│                                                   │
│   ┌─────────────────────────────────────────┐     │
│   │     Internal Network (internal: true)   │     │
│   │                                         │     │
│   │   ┌─────────┐         ┌─────────┐       │     │
│   │   │  nginx  │◄───────►│   db    │       │     │
│   │   │ :80     │         │  :5432  │       │     │
│   │   └────┬────┘         └─────────┘       │     │
│   │        │                   ✗            │     │
│   └────────│───────────────────│────────────┘     │
│            │                   │                  │
│            ▼                   ▼                  │
│     Port 80 exposed      No external access       │
└───────────────────────────────────────────────────┘
```

### 3.3 Security Comparison Table

| Configuration | Accessible From |
|--------------|-----------------|
| `ports: "8080:80"` | Internet, Host, Containers |
| `ports: "127.0.0.1:8080:80"` | Host only, Containers |
| No ports (bridge) | Other containers on same network, Host (via container IP) |
| No ports + bridge + `internal: true` | Only containers on same network |

### 3.4 Security Checklist

```yaml
services:
  secure_service:
    image: myapp
    # ✅ No "ports:" - not exposed externally
    # ✅ No "network_mode: host" - isolated from host
    networks:
      - secure_net

networks:
  secure_net:
    internal: true  # ✅ Extra isolation
```

### 3.5 Security Goals Quick Reference

| Goal | Configuration |
|------|--------------|
| Container-to-container only | Bridge + no ports + `internal: true` |
| Container + host only | Bridge + no ports (or `127.0.0.1:port:port`) |
| Expose to outside | Bridge + `ports:` |

---

## 4. Accessing Internal Containers from Host

Even without published ports, the host can still reach containers on bridge networks.

### Method 1: Using Container IP Directly

```bash
# Find the container's IP address
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' container_name

# Or for docker-compose services
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' myproject_db_1

# Now access directly from host
curl http://172.18.0.2:5432
psql -h 172.18.0.2 -U postgres
```

### Method 2: Using `docker exec`

```bash
# Interactive shell
docker exec -it myproject_db_1 bash

# Run specific command
docker exec myproject_db_1 psql -U postgres -c "SELECT 1"

# For docker-compose
docker-compose exec database psql -U postgres
```

### Method 3: List All Container IPs on a Network

```bash
# See all containers and their IPs on a specific network
docker network inspect bridge --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{println}}{{end}}'

# Output:
# myproject_web_1: 172.18.0.3/16
# myproject_db_1: 172.18.0.2/16
# myproject_redis_1: 172.18.0.4/16
```

### Method 4: Bind to Localhost Only

If you want easy host access but no external exposure:

```yaml
services:
  database:
    image: postgres
    ports:
      - "127.0.0.1:5432:5432"  # Only accessible from host localhost
```

```bash
# Works from host
psql -h 127.0.0.1 -U postgres

# Does NOT work from other machines
# (port not bound to external interfaces)
```

### Practical Complete Example

```yaml
services:
  nginx:
    image: nginx
    ports:
      - "80:80"  # Public access

  app:
    image: myapp
    ports:
      - "127.0.0.1:3000:3000"  # Host-only access for debugging
    environment:
      - DATABASE_URL=postgres://database:5432/mydb

  database:
    image: postgres
    environment:
      - POSTGRES_PASSWORD=secret
    # No ports - container access only

  redis:
    image: redis
    # No ports - container access only
```

| Service | How to Access from Host |
|---------|------------------------|
| nginx | `curl http://localhost:80` |
| app | `curl http://127.0.0.1:3000` |
| database | `psql -h 172.18.0.x -U postgres` or `docker-compose exec database psql -U postgres` |
| redis | `docker-compose exec redis redis-cli` |

### Important Note About `internal: true`

When using `internal: true`, the **host CAN still access containers** via their IP:

```bash
# This still works even with internal: true
curl http://172.18.0.2:8080
```

The `internal: true` flag only prevents:
- Containers from reaching the **outside internet**

Does NOT block host → container communication.

### Utility Script: List All Container IPs

Save this as `docker-ips.sh`:

```bash
#!/bin/bash
# List all running containers with their IPs
docker inspect -f '{{.Name}} - {{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -q)
```

```bash
$ ./docker-ips.sh
/myproject_web_1 - 172.18.0.3
/myproject_db_1 - 172.18.0.2
/myproject_redis_1 - 172.18.0.4
```

---

## 5. Understanding 0.0.0.0 vs 127.0.0.1 in Containers

### Why does binding to 127.0.0.1 inside a container prevent external access?

When creating a server in Node.js (or any technology), you need to listen on `0.0.0.0` to make it accessible from outside the container. Listening on `127.0.0.1` doesn't work.

Each container has its **own isolated network interfaces**. The container's `127.0.0.1` is NOT the host's `127.0.0.1`.

```
┌─────────────────────────────────────────────────────────────┐
│                         HOST                                │
│                                                             │
│   Network Interfaces:                                       │
│   - eth0: 192.168.1.100 (external)                          │
│   - lo: 127.0.0.1 (loopback)                                │
│   - docker0: 172.17.0.1 (bridge)                            │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │                    CONTAINER                        │   │
│   │                                                     │   │
│   │   Network Interfaces:                               │   │
│   │   - eth0: 172.17.0.2 (bridge)                       │   │
│   │   - lo: 127.0.0.1 (container's own loopback)        │   │
│   │                                                     │   │
│   └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Binding to 127.0.0.1 (Loopback Only)

```javascript
// Node.js server
app.listen(3000, '127.0.0.1');
```

```
┌─────────────────────────────────────────────────────────┐
│                      CONTAINER                          │
│                                                         │
│   ┌─────────────┐           ┌─────────────┐             │
│   │   eth0      │           │     lo      │             │
│   │ 172.17.0.2  │           │ 127.0.0.1   │             │
│   │             │           │   ▲         │             │
│   │   Traffic   │           │   │ Server  │             │
│   │   arrives   │           │   │ listens │             │
│   │   here      │           │   │ here    │             │
│   └─────────────┘           └─────────────┘             │
│         ▲                                               │
│         │                                               │
│    Port mapping                                         │
│    from host                                            │
└─────────────────────────────────────────────────────────┘

❌ External traffic arrives on eth0, but server only listens on lo. Connection refused!
```

### Binding to 0.0.0.0 (All Interfaces)

```javascript
// Node.js server
app.listen(3000, '0.0.0.0');
// Or simply
app.listen(3000);  // Defaults to 0.0.0.0 in most frameworks
```

```
┌─────────────────────────────────────────────────────────┐
│                      CONTAINER                          │
│                                                         │
│   ┌─────────────┐           ┌─────────────┐             │
│   │   eth0      │           │     lo      │             │
│   │ 172.17.0.2  │           │ 127.0.0.1   │             │
│   │      ▲      │           │      ▲      │             │
│   │      │      │           │      │      │             │
│   │      └──────┴───────────┴──────┘      │             │
│   │                  │                    │             │
│   │            Server listens             │             │
│   │            on 0.0.0.0                 │             │
└─────────────────────────────────────────────────────────┘

✅ Server listens on all interfaces, including eth0 where external traffic arrives.
```

### Code Examples

#### ❌ Won't Work From Outside Container

```javascript
// Node.js / Express
app.listen(3000, '127.0.0.1');  // Only loopback
```

```python
# Python / Flask
app.run(host='127.0.0.1', port=3000)  # Only loopback
```

```go
// Go
http.ListenAndServe("127.0.0.1:3000", nil)  // Only loopback
```

#### ✅ Works From Outside Container

```javascript
// Node.js / Express
app.listen(3000, '0.0.0.0');
// or simply
app.listen(3000);
```

```python
# Python / Flask
app.run(host='0.0.0.0', port=3000)
```

```go
// Go
http.ListenAndServe(":3000", nil)  // Empty host = all interfaces
```

### Common Gotcha in Development

Many frameworks default to `127.0.0.1` in development mode:

```bash
# These often default to localhost/127.0.0.1
npm run dev      # Vite, Next.js, etc.
flask run
rails server
```

Override the host:

```bash
vite --host 0.0.0.0
next dev -H 0.0.0.0
flask run --host=0.0.0.0
rails server -b 0.0.0.0
```

### Summary Table

| Bind Address | Listens On | Accessible From |
|-------------|-----------|-----------------|
| `127.0.0.1` | Loopback only | Inside same container only |
| `0.0.0.0` | All interfaces | Outside container (host, other containers, network) |
| `172.17.0.2` (specific IP) | That interface only | Anywhere that can reach that IP |

---

## 6. Quick Reference

### Network Mode Selection

| Need | Use |
|------|-----|
| Standard isolation | `bridge` (default) |
| Maximum performance | `host` |
| Complete isolation | `none` |
| Block outbound + isolate | `bridge` + `internal: true` |
| Multi-host communication | `overlay` |
| Direct LAN access with own IP | `macvlan` |

### Port Binding Security

| Binding | Accessibility |
|---------|--------------|
| `"8080:80"` | Public (all interfaces) |
| `"127.0.0.1:8080:80"` | Host only |
| No ports | Container network only |

### Server Binding

| Address | Result |
|---------|--------|
| `0.0.0.0` | All interfaces (accessible from outside) |
| `127.0.0.1` | Loopback only (container internal) |

### Useful Commands

```bash
# Get container IP
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' container_name

# List all containers on a network
docker network inspect network_name

# Execute command in container
docker-compose exec service_name command
```

---

## A Note on Macvlan Mode

**Macvlan** allows containers to appear as physical devices on your network with their own MAC and IP addresses. This can be useful for:

- Legacy applications that expect to be directly on the physical network
- Network monitoring tools that need to see real network traffic
- Running services like Pi-hole that work best with their own IP
- Multiple containers needing the same port (each gets its own IP)

However, macvlan has significant limitations:
- Host cannot communicate with macvlan containers without extra configuration
- Doesn't work well with WiFi interfaces
- Not supported in most cloud environments (AWS, GCP, etc.)
- Requires more network planning

For most use cases, **bridge mode with proper port configuration** is recommended.

---

## Further Reading

- [Docker Networking Documentation](https://docs.docker.com/network/)
- [Docker Compose Networking](https://docs.docker.com/compose/networking/)
- [Docker Network Drivers](https://docs.docker.com/network/drivers/)
