#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="/data/.deploy_state"
STATE_FILE="$STATE_DIR/last_deploy_hashes"

echo "==> Ensuring shared network exists"
docker network inspect shared-net >/dev/null 2>&1 || docker network create shared-net

# Helper to ensure directory exists with correct permissions
# It tries standard mkdir first, then falls back to Docker if permission is denied.
# This avoids sudo password prompts on self-hosted runners.
ensure_dir() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        echo "   Ensuring $dir exists..."
        if mkdir -p "$dir" 2>/dev/null; then
            chmod 777 "$dir" 2>/dev/null || true
        else
            echo "   Permission denied for mkdir, attempting via Docker fallback..."
            # Use docker to create the directory since the runner is in the docker group
            docker run --rm -v /data:/data alpine sh -c "mkdir -p $dir && chmod 777 $dir" || {
                echo "   Error: Failed to create $dir. Please ensure the runner user has write permissions to /data or configure passwordless sudo."
                exit 1
            }
        fi
    fi
}

# Validate required environment variables for the database stack
validate_secrets() {
    local missing_vars=()
    local required_vars=("POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB" "MONGO_ROOT_USER" "MONGO_ROOT_PASSWORD")
    
    for var in "${required_vars[@]}"; do
        # Robust indirect expansion to check if variable is set and non-empty
        # Using eval to support older bash and respect set -u
        local val
        val=$(eval "echo \"\${$var:-}\"")
        if [ -z "$val" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -ne 0 ]; then
        echo "❌ Error: The following required environment variables are missing or empty:"
        for var in "${missing_vars[@]}"; do
            echo "   - $var"
        done
        echo ""
        echo "💡 Troubleshooting Checklist:"
        echo "1. GitHub Secrets vs Variables: Ensure they are in the 'Secrets' tab, NOT the 'Variables' tab."
        echo "2. Scope: If you used 'Environment' secrets, you must add 'environment: <name>' to your deploy.yml job."
        echo "3. Repository Secrets: Go to Settings > Secrets and variables > Actions > Repository secrets."
        echo "4. Typo: Double check that the secret names match exactly (case-sensitive)."
        echo "5. Organization Secrets: If using Org secrets, ensure this repository is granted access."
        echo ""
        exit 1
    fi
}

echo "==> Validating secrets"
validate_secrets

echo "==> Ensuring log directories exist"
for dir in /data/logs/caddy /data/logs/postgres /data/logs/mongodb; do
    ensure_dir "$dir"
done

# Prepare state directory for idempotency checks
ensure_dir "$STATE_DIR"
touch "$STATE_FILE"

deploy_stack() {
    local name=$1
    local path=$2
    
    echo "==> Checking stack: $name"
    
    # Get the last committed hash for this directory to detect changes
    local current_hash
    current_hash=$(git log -1 --format=%H -- "$path")
    
    local last_hash
    last_hash=$(grep "^$name:" "$STATE_FILE" | cut -d: -f2 || echo "")
    
    if [ "$current_hash" != "$last_hash" ]; then
        echo "   Changes detected ($current_hash), deploying..."
        cd "$path"
        docker compose pull
        docker compose up -d
        
        # Update state file
        sed "/^$name:/d" "$STATE_FILE" > "${STATE_FILE}.tmp"
        echo "$name:$current_hash" >> "${STATE_FILE}.tmp"
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
        return 0
    else
        echo "   No changes detected, skipping pull and update."
        return 1
    fi
}

echo "==> Deploy databases"
deploy_stack "databases" "$ROOT/stacks/databases"

echo "==> Deploy web (caddy)"
if deploy_stack "web" "$ROOT/stacks/web"; then
    # Reload Caddy only if the web stack was updated and container is running
    if docker compose -f "$ROOT/stacks/web/compose.yml" ps | grep -q "caddy"; then
        echo "==> Reloading Caddy configuration"
        docker compose -f "$ROOT/stacks/web/compose.yml" exec -T caddy caddy reload --config /etc/caddy/Caddyfile
    fi
fi

echo "==> Status"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
