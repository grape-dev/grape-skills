#!/bin/bash
# DevBridge Web Project Deployment Script
# Usage: deploy_web_project.sh <repo_url> [subdir] [port] [expiration_hours]
#
# Clones a Git repo, detects project type, installs deps, starts server,
# creates a DevBridge tunnel, and returns the public URL.
#
# Prerequisites:
#   - DevBridge skill installed and devbridge_cmd.sh sourced
#   - git, curl, python3 or node available

set -euo pipefail

REPO_URL="${1:?Usage: deploy_web_project.sh <repo_url> [subdir] [port] [expiration]}"
SUBDIR="${2:-}"
PORT="${3:-}"
EXPIRATION="${4:-8}"

WORKSPACE="/root/workspace"
DEVBRIDGE_SCRIPT="${DEVBRIDGE_SCRIPT:-/root/.agents/skills/huawei-cloud-jobenv-devbridge-tunnel/scripts/devbridge_cmd.sh}"

# Extract repo name from URL
REPO_NAME=$(basename "$REPO_URL" .git)
CLONE_DIR="$WORKSPACE/$REPO_NAME"
PROJECT_DIR="$CLONE_DIR"

echo "=== DevBridge Web Project Deployment ==="
echo "Repo: $REPO_URL"
echo "Subdir: ${SUBDIR:-<root>}"
echo "Expiration: ${EXPIRATION}h"
echo ""

# Step 1: Clone
echo "[1/5] Cloning repository..."
if [ -d "$CLONE_DIR" ]; then
    echo "  Directory exists, pulling latest..."
    cd "$CLONE_DIR" && git pull --quiet
else
    git clone --quiet "$REPO_URL" "$CLONE_DIR"
fi

if [ -n "$SUBDIR" ]; then
    PROJECT_DIR="$CLONE_DIR/$SUBDIR"
fi
cd "$PROJECT_DIR"

# Step 2: Detect project type and start server
echo "[2/5] Detecting project type..."

if [ -f "requirements.txt" ] && ls *.py 1>/dev/null 2>&1; then
    TYPE="python"
    echo "  Detected: Python/Flask project"
    echo "[3/5] Installing dependencies..."
    pip install -q -r requirements.txt 2>&1 | tail -1
    
    # Find the main Python file
    APP_FILE="app.py"
    [ -f "main.py" ] && APP_FILE="main.py"
    [ -f "server.py" ] && APP_FILE="server.py"
    
    # Detect port from app file if not specified
    if [ -z "$PORT" ]; then
        PORT=$(grep -oP 'port\s*=\s*\K\d+' "$APP_FILE" 2>/dev/null | head -1 || echo "5000")
    fi
    
    echo "[4/5] Starting server on port $PORT..."
    nohup python "$APP_FILE" > "/tmp/${REPO_NAME}.log" 2>&1 &
    SERVER_PID=$!

elif [ -f "package.json" ]; then
    TYPE="node"
    echo "  Detected: Node.js project"
    echo "[3/5] Installing dependencies..."
    npm install --silent 2>&1 | tail -1
    
    if [ -z "$PORT" ]; then
        PORT=$(grep -oP '"PORT"\s*:\s*\K\d+' package.json 2>/dev/null || echo "3000")
    fi
    
    echo "[4/5] Starting server on port $PORT..."
    nohup npm start > "/tmp/${REPO_NAME}.log" 2>&1 &
    SERVER_PID=$!

elif [ -f "index.html" ]; then
    TYPE="static"
    echo "  Detected: Static HTML project"
    [ -z "$PORT" ] && PORT=8080
    
    echo "[3/5] No dependencies to install."
    echo "[4/5] Starting server on port $PORT..."
    nohup python3 -m http.server "$PORT" > "/tmp/${REPO_NAME}.log" 2>&1 &
    SERVER_PID=$!

else
    echo "ERROR: Could not detect project type."
    echo "Supported: Python/Flask (requirements.txt + *.py), Node.js (package.json), Static (index.html)"
    exit 1
fi

sleep 2

# Verify server is running
if curl -s --max-time 3 "http://localhost:$PORT/" > /dev/null 2>&1; then
    echo "  Server is running (PID: $SERVER_PID, port: $PORT)"
elif curl -s --max-time 3 "http://localhost:$PORT/health" > /dev/null 2>&1; then
    echo "  Server is running (PID: $SERVER_PID, port: $PORT)"
else
    echo "  WARNING: Server health check failed. Check /tmp/${REPO_NAME}.log"
fi

# Step 3: Create DevBridge tunnel
echo "[5/5] Creating DevBridge tunnel..."
source "$DEVBRIDGE_SCRIPT"
db_init

# --- Auth check & auto-recovery ---
# The DevBridge WebUI may have expired credentials. Check and re-login if needed.
AUTH_STATUS=$(db_auth_status 2>/dev/null || echo "")
if echo "$AUTH_STATUS" | grep -q "Not logged in"; then
    echo "  Auth expired, re-authenticating with JOB_ENV_HW_DEVBRIDGE_API_KEY..."
    curl -s -X POST "http://127.0.0.1:8090/api/v1/envs/devbridge/exec" \
        -H 'Content-Type: application/json' \
        -d '{"cmd":["bash","-c","devbridge auth login --api-key $JOB_ENV_HW_DEVBRIDGE_API_KEY 2>&1"]}' >/dev/null 2>&1
    sleep 2
    # Verify recovery
    AUTH_STATUS=$(db_auth_status 2>/dev/null || echo "")
    if echo "$AUTH_STATUS" | grep -q "Not logged in"; then
        echo "ERROR: DevBridge auth recovery failed. JOB_ENV_HW_DEVBRIDGE_API_KEY may be expired."
        echo "       Manual fix: obtain a new API key from https://devstation.connect.huaweicloud.com/space/devbridge/apikey"
        exit 1
    fi
    echo "  Auth restored."
fi

TUNNEL_NAME="${REPO_NAME}-tunnel"
# Description must NOT contain spaces — only Chinese chars, digits, letters (max 64)
TUNNEL_DESC="Web项目部署隧道"
TUNNEL_ID=$(db_create "$TUNNEL_NAME" "$TUNNEL_DESC" "$EXPIRATION")

if [ -z "$TUNNEL_ID" ]; then
    echo "ERROR: Tunnel creation failed. Check auth status and try again."
    exit 1
fi

db_port_create "$TUNNEL_ID" "$PORT" http true
HOST_RESULT=$(db_host "$TUNNEL_ID")

# Extract process ID
PROCESS_ID=$(echo "$HOST_RESULT" | grep -oP '"id":"\K[^"]+')

sleep 1

# Get tunnel URL
LOGS=$(db_process_logs "$PROCESS_ID")
TUNNEL_URL=$(echo "$LOGS" | grep -oP 'https://[a-z0-9-]+\.devbridge[a-z0-9.-]+' | head -1)

echo ""
echo "=== Deployment Complete ==="
echo "Project:     $REPO_NAME ($TYPE)"
echo "Local:       http://localhost:$PORT"
echo "Tunnel ID:   $TUNNEL_ID"
echo "Process ID:  $PROCESS_ID"
echo "Expiration:  ${EXPIRATION}h"
echo ""
echo "Public URL:  $TUNNEL_URL"
echo ""
echo "Server PID:  $SERVER_PID (local server)"
echo "Log file:    /tmp/${REPO_NAME}.log"
