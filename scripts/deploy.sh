#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="/data/.deploy_state"
STATE_FILE="$STATE_DIR/last_deploy_hashes"

echo "==> Ensuring shared network exists"
docker network inspect shared-net >/dev/null 2>&1 || docker network create shared-net

echo "==> Ensuring log directories exist"
# Only run sudo if directories are missing
for dir in /data/logs/caddy /data/logs/postgres /data/logs/mongodb; do
    if [ ! -d "$dir" ]; then
        echo "   Creating $dir"
        sudo mkdir -p "$dir"
        sudo chmod 777 "$dir"
    fi
done

# Prepare state directory for idempotency checks
if [ ! -d "$STATE_DIR" ]; then
    sudo mkdir -p "$STATE_DIR"
    sudo chmod 777 "$STATE_DIR"
fi
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
