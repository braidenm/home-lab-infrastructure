# Logging Infrastructure

This document describes how logs are managed across the home lab services.

## Overview

Following the [Storage Model](StorageSetup.md), all logs are stored on the persistent HDD to avoid SSD wear and ensure they are preserved across container restarts.

**Log Location:** `/data/logs`

## Log Organization

Logs are separated by service:

| Service    | Host Path                | Log File(s)                     |
| :--------- | :----------------------- | :------------------------------ |
| Caddy      | `/data/logs/caddy`       | `access.log`                    |
| PostgreSQL | `/data/logs/postgres`    | `postgresql-Day.log` (7 days)   |
| MongoDB    | `/data/logs/mongodb`     | `mongod.log`                    |

## Rotation and Retention

To prevent the HDD from filling up, all services are configured with log rotation.

### Caddy
- **Mechanism**: Built-in Caddy logging.
- **Retention**: Kept for **7 days** (`168h`).
- **Rotation**: Automatic when reaching size limits or time.

### PostgreSQL
- **Mechanism**: PostgreSQL `logging_collector`.
- **Retention**: Kept for **7 days**.
- **Rotation**: Daily rotation using a 7-file cycle (`postgresql-Mon.log`, etc.). The file for the current day is overwritten each week.

### MongoDB
- **Mechanism**: Internal file logging.
- **Note**: Currently logs to a single file. For advanced rotation, it is recommended to use `logrotate` on the host or periodically signal the container.

### Docker (Standard Output)
As a safety measure, all containers have a Docker-level `json-file` rotation policy:
- **Max Size**: 10MB
- **Max Files**: 3

## Accessing Logs

You can view logs directly from the host machine:

```bash
# View Caddy access logs
tail -f /data/logs/caddy/access.log

# View Postgres logs (for the current day)
tail -f /data/logs/postgres/postgresql-$(date +%a).log
```

Or via Docker (note: some services are configured to log primarily to files, so `docker logs` might be sparse):

```bash
docker logs -f caddy
```

---

## Guidelines for New Services

To ensure your new application follows the infrastructure logging standards:

### 1. Docker Stdout/Stderr (Standard)
All services **must** include the following logging configuration in their `compose.yml`. This captures standard output, prevents SSD bloat, and allows for basic log inspection via `docker logs`.

```yaml
services:
  my-app:
    # ...
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### 2. Persistent File Logging (Recommended)
If you want logs to be stored on the high-capacity HDD (`/data`) and persist for a longer duration (e.g., a week), follow these steps:

**A. Map the volume in `compose.yml`**
Mount a subdirectory under `/data/logs/` to your container's log path.

```yaml
services:
  my-app:
    # ...
    volumes:
      - /data/logs/my-app:/var/log/my-app
```

**B. Update `scripts/deploy.sh`**
Add your new log directory to the `mkdir` command in the deployment script to ensure it is created with the correct permissions on the host.

```bash
sudo mkdir -p /data/logs/caddy /data/logs/postgres /data/logs/mongodb /data/logs/my-app
```

**C. Configure App Rotation**
Ensure your application is configured to rotate its logs (e.g., daily) to prevent filling up the HDD.
