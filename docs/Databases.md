# Database Infrastructure

This document describes the database setup on this server and how applications can connect to them.

## Overview

The server runs two primary database engines as part of the `databases` stack:

1.  **PostgreSQL 16**: Relational database.
2.  **MongoDB**: Document-based NoSQL database.

Both databases are configured for **persistence**, **internal networking**, and **security**.

---

## Connection Details

Applications running on the same server can connect to these databases using their container names as hostnames. **Do not use `localhost`** from inside other containers.

| Database   | Hostname  | Internal Port |
| :--------- | :-------- | :------------ |
| PostgreSQL | `postgres`| `5432`        |
| MongoDB    | `mongodb` | `27017`       |

### Internal Networking

Communication happens over the `shared-net` Docker network. This ensures:
- **Fast communication**: Traffic never leaves the internal Docker bridge.
- **Security**: Database ports are **not** exposed to the host or the public internet. Only containers on the `shared-net` network can reach them.

---

## How to Connect Your App

To allow your application to talk to the databases, you must ensure it is joined to the `shared-net` network.

### 1. Update `compose.yml`

In your application's `compose.yml` file, add the following configuration:

```yaml
services:
  my-app:
    image: my-app-image
    networks:
      - shared-net
    environment:
      # Example connection strings
      DATABASE_URL: "postgresql://user:password@postgres:5432/dbname"
      MONGO_URL: "mongodb://user:password@mongodb:27017/admin"

networks:
  shared-net:
    external: true
```

### 2. Authentication

Authentication is handled via environment variables passed during deployment from GitHub Secrets.

**PostgreSQL:**
- **User**: `${POSTGRES_USER}`
- **Password**: `${POSTGRES_PASSWORD}`
- **Default DB**: `${POSTGRES_DB}`

**MongoDB:**
- **Root User**: `${MONGO_ROOT_USER}`
- **Root Password**: `${MONGO_ROOT_PASSWORD}`

---

## Storage & Persistence

Data is stored on the server's high-capacity HDD for long-term persistence, following the [Storage Model](StorageSetup.md).

| Database   | Host Path            | Container Path             |
| :--------- | :------------------- | :------------------------- |
| PostgreSQL | `/data/db/postgres` | `/var/lib/postgresql/data` |
| MongoDB    | `/data/db/mongodb`  | `/data/db`                 |

### Backups
Since the data is bind-mounted to `/data/db`, you can back up the entire database by simply copying these directories (though it is recommended to stop the containers or use `pg_dump`/`mongodump` for consistent backups).

---

## Troubleshooting

### "Required environment variables are missing or empty"
If you see this error in GitHub Actions:
1.  **Check Secret Type**: Ensure you added them under the **Secrets** tab, NOT the **Variables** tab.
2.  **Check Scope**: If you defined them within an **Environment** (e.g., "production"), you must update `.github/workflows/deploy.yml` to include `environment: production` in the `deploy` job.
3.  **Typos**: Ensure the names match exactly (e.g., `POSTGRES_PASSWORD`).

### "Host not found" or "Connection refused"
1.  **Check Network**: Ensure your app container has `networks: [shared-net]` defined.
2.  **Check External Flag**: Ensure the network is defined as `external: true` in your `compose.yml`.
3.  **Check Container Status**: Run `docker ps` to ensure `postgres` or `mongodb` containers are healthy.
4.  **No `localhost`**: Remember that `localhost` refers to the *app container itself*, not the host or the database container. Use the hostnames `postgres` or `mongodb`.
