# HomeLab-Infrastructure

A lightweight, GitOps-driven home lab infrastructure designed for hosting personal portfolio projects and APIs. This setup emphasizes automation, security, and developer productivity with a minimal footprint.

## 🎯 Project Goals
- **Automation**: Fully automated CI/CD pipeline from commit to production.
- **Simplicity**: Minimalistic Docker-based orchestration.
- **Security**: Zero-trust access via Cloudflare Tunnels and WARP (no open ports).
- **Scalability**: Easy-to-add services via Infrastructure-as-Code (IaC) patterns.

## 🏗 Architecture & Hardware

- **Host**: Resource-efficient Ubuntu Server (Intel/ARM) optimized for low-power consumption.
- **Network Topology**: 
  - **VLAN Isolation**: Server resides in a dedicated DMZ, isolated from the primary home network via a managed smart switch.
  - **Edge Security**: 
    - **Cloudflare Tunnel (Argo)**: Inbound HTTPS traffic is routed through an encrypted tunnel, eliminating the need for open firewall ports.
    - **Cloudflare WARP**: Zero-trust SSH access secured by identity-based policies.
- **Service Orchestration**: **Caddy** (Dockerized) provides automatic TLS management, reverse proxying, and internal service discovery.

## 🚀 GitOps Deployment Pipeline

The infrastructure follows a GitOps philosophy: the state of this repository defines the desired state of the server. 

### Core Workflow
1. **Independent CI/CD**: Each application (e.g., the Portfolio React app, Backend APIs) maintains its own repository and CI/CD pipeline. They build and push versioned Docker images to a registry.
2. **Infrastructure Trigger**: When a service's image is updated or a configuration change is merged into the `main` branch of *this* repo, the deployment is triggered.
3. **Execution**: GitHub Actions triggers a **self-hosted runner** operating directly on the Ubuntu host.
4. **Deployment**: The runner executes `scripts/deploy.sh`, which leverages:
   - `docker compose pull`: Fetches the latest service images.
   - `docker compose up -d`: Idempotent update (only restarts changed services).
   - `caddy reload`: Zero-downtime configuration hot-swap.
5. **Verification**: Post-deployment health checks ensure all containers are running and the web gateway is responding with HTTP 200.

## 🛡️ Automated Quality Assurance

To ensure infrastructure stability, every change undergoes two levels of verification:

### 1. Pre-Merge Validation (PRs)
When a Pull Request is opened, GitHub Actions automatically validates:
- **Docker Compose Syntax**: Checks all `compose.yml` files for structural errors.
- **Caddyfile Validation**: Uses the official Caddy binary to verify reverse proxy configurations.
- **Script Linting**: Checks `deploy.sh` for bash syntax errors.

### 2. Post-Deployment Verification
After deployment to the server, the system performs real-time checks with automatic retries:
- **Container Health**: Verifies that `caddy`, `postgres`, and `mongodb` are in a `running` state.
- **Connectivity**: Performs a local HTTP probe to ensure the site is being served correctly.

## 📈 Roadmap & Future Evolution

This system is designed to evolve from a lightweight setup into a robust, enterprise-grade home infrastructure.

### Planned Enhancements
- **Observability**: Integration of Prometheus and Grafana for real-time resource monitoring and Caddy traffic metrics.
- **Secret Management**: Transitioning from environment variables to a dedicated secret manager (like HashiCorp Vault or Bitnami Sealed Secrets).
- **Advanced Deployment Patterns**: Moving toward Blue-Green or Canary deployments to further minimize risk during updates.
- **Centralized Logging**: Aggregating logs from all containers using the ELK stack or Loki for easier debugging.

## 📂 Project Structure

- `stacks/`: Docker Compose configurations grouped by concern.
  - `web/`: Edge routing (Caddy) and core web services.
  - `databases/`: Persistent PostgreSQL and MongoDB services.
- `docs/`: Infrastructure documentation.
  - [Storage Model](docs/StorageSetup.md): How persistence and hardware layers are organized.
  - [Database Guide](docs/Databases.md): How to connect to and manage databases.
  - [Logging Guide](docs/Logging.md): How logs are stored, rotated, and accessed.
- `scripts/`: Operational scripts (Deployment, Maintenance).
- `.github/workflows/`: Automated CI/CD definitions.

## 🌐 Current Services

### Personal Portfolio
A high-performance static site served directly by Caddy.
- **Location**: `stacks/web/site/PersonalSite`
- **Roadmap**: Transitioning to a containerized React application for dynamic project showcases.

### Databases
Persistent storage engines for applications.
- **Engines**: PostgreSQL 16, MongoDB
- **Internal Hostnames**: `postgres`, `mongodb`
- **Documentation**: [Database Guide](docs/Databases.md)

## 🛠 Developer Guide: Adding Services

This setup is optimized for backend developers to deploy new APIs in minutes.

### 1. Define the Service (IaC)
Add your service to `stacks/web/compose.yml`. Caddy uses the service name for internal DNS.

```yaml
services:
  my-api:
    image: my-api-image:latest
    restart: unless-stopped
    # Environment-driven config, no host ports exposed
```

### 2. Configure Routing
Update `stacks/web/Caddyfile`. Choose between subdomains or sub-paths based on your API's needs.

```caddy
# Example: Subdomain routing (api.braidenmiller.com)
api.braidenmiller.com {
    reverse_proxy my-api:8080
}

# Example: Sub-path routing (braidenmiller.com/api)
braidenmiller.com {
    handle_path /api/* {
        reverse_proxy my-api:8080
    }
}
```

### 3. Configure Logging (Best Practice)
To ensure your app's logs are persisted on the HDD and rotated properly, add a bind mount to `/data/logs` and include the Docker logging driver config. See the [Logging Guide](docs/Logging.md) for full details.

```yaml
services:
  my-api:
    # ...
    volumes:
      - /data/logs/my-api:/var/log/my-api
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### 4. Deploy
Push to `main`. The automation handles the rest.

```bash
git commit -am "feat: deploy analytics-api" && git push
```
