
# Container, Storage, and Networking Model

This document explains how containers, storage, and networking are structured on this server, and what decisions to make when adding new services (databases, APIs, game servers, etc.).

---

## High-Level Architecture

The system is organized into **three clear layers**:

1. **Compute (Containers)** → SSD  
2. **Persistence (Data)** → HDD  
3. **Networking (Service Communication & Access Control)**

Each layer has a specific purpose and should not be mixed.

---

## 1. Compute Layer (SSD)

**What lives here**
- Docker engine
- Container images
- Container writable layers

**Location**
```text
/ssd/docker
````

**Why**

* Fast startup
* Low latency I/O
* Better performance for containers and builds

**Rule**

> Containers run from the SSD.
> Do not store large or long-lived data here.

---

## 2. Persistence Layer (HDD)

**What lives here**

* Databases
* Game worlds (e.g. Valheim)
* Backups
* Logs
* Media
* Large artifacts

**Location**

```text
/data
```

**Recommended structure**

```text
/data
├── games
│   └── valheim
├── db
│   └── app-db
├── backups
├── logs
└── media
```

**Rule**

> Any data that must survive container rebuilds belongs under `/data`.

---

## 3. Networking Model

### Container-to-Container (Internal)

* Containers communicate via **Docker networks**
* Use **service names**, not `localhost`
* No ports required

Example:

```text
http://db:5432
```

---

### External Access (Edge)

* **SSH (human access)**: Cloudflare WARP Infrastructure SSH
* **HTTP/HTTPS**: Cloudflare Tunnel → Caddy (reverse proxy)
* **CI/CD**: Cloudflare Tunnel + service tokens (not SSH)

Cloudflare is used only at the **edge**, not inside Docker networks.

---

## Adding a New Container: Decision Checklist

For every new service, answer these questions:

### 1. Is the service stateful?

* **Yes** → bind-mount to `/data`
* **No** → no persistent volume needed

---

### 2. Does it talk to another container?

* Same `docker-compose.yml` → use service name
* Different compose projects → use a shared Docker network

---

### 3. Does it need external access?

* HTTP → expose through Caddy + Cloudflare Tunnel
* Database/internal API → **do not expose ports**

---

## Common Patterns

### Database Container (Postgres/MySQL/etc.)

**Host data**

```text
/data/db/app-db
```

**Compose example**

```yaml
services:
  db:
    image: postgres:16
    volumes:
      - /data/db/app-db:/var/lib/postgresql/data
```

**Why**

* Data survives rebuilds
* Backups are easy
* Clear separation from container lifecycle

---

### App Talking to a Database (Same Compose Project)

```yaml
services:
  db:
    image: postgres:16

  api:
    image: my-api
    environment:
      DB_HOST: db
      DB_PORT: 5432
```

**Rule**

> Use the service name (`db`), never `localhost`.

---

### App + DB in Different Compose Projects

Create a shared Docker network once:

```bash
docker network create shared-net
```

Attach both projects:

```yaml
networks:
  shared-net:
    external: true
```

Containers can now communicate by name across stacks.

---

## What Not To Do

* ❌ Store databases on `/ssd`
* ❌ Use `localhost` between containers
* ❌ Expose DB ports unless absolutely required
* ❌ Use random named Docker volumes for critical data
* ❌ Route internal service traffic through Cloudflare

---

## Cloudflare’s Role (Clarified)

| Use case           | Tool                      |
| ------------------ | ------------------------- |
| SSH (human access) | WARP Infrastructure SSH   |
| Public web traffic | Cloudflare Tunnel + Caddy |
| CI/CD              | Tunnel + service token    |
| Internal APIs      | Docker networking         |

Cloudflare controls **who can reach the server**, not how containers talk internally.

---

## Reusable Mental Model

> **SSD = compute & speed**
> **HDD = persistence & growth**
> **Containers talk by name**
> **Cloudflare stays at the edge**

---

## Example: App + DB Layout

```text
/ssd
└── docker
    ├── images
    └── containers

/data
└── db
    └── app-db
```

* App connects to `db:5432`
* DB data persists on HDD
* Containers can be rebuilt freely
* Backups are trivial

---

## Summary

* Docker runs from SSD
* Persistent data lives on HDD
* Use bind mounts for state
* Use Docker DNS for service discovery
* Use Cloudflare only for edge access

This model scales cleanly from a homelab to enterprise-style infrastructure.
