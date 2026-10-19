---
name: huawei-cloud-devbridge-deploy
description: '通过华为云 DevBridge 隧道将 web 项目部署到公网 URL，自动按环境路由两条路线：Route A（jobenv 环境）— agent 运行环境内已预装 DevBridge tunnel skill 时，直接在本机部署，走 WebUI API 认证；Route B（本地环境）— 否则通过 huaweicloud-devkit 插件连接华为云沙箱，仅用 AK/SK，无需 API Key。全流程：clone 仓库、识别项目类型（Flask/Node.js/静态）、装依赖、起服务、建隧道、返回公网 URL。Triggers: devbridge deploy, 部署web项目, 用devbridge部署, 部署到本地并通过 devbridge 访问, expose local web app, tunnel deploy, 通过隧道部署, deploy with tunnel.'
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
      - deploy
      - devbridge
      - tunnel
      - huaweicloud
      - sandbox
      - jobenv
      - web
    related_skills:
      - grape-release-and-deploy
      - huawei-cloud-jobenv-devbridge-tunnel
---

# DevBridge Unified Deployment (Auto-Routing)

Deploy a web project and expose it to a public URL via Huawei Cloud DevBridge tunnels. This skill automatically routes between two deployment paths based on the agent's own environment.

## Step 0: Environment Routing (ALWAYS run first)

Check whether the jobenv DevBridge skill is accessible **in the agent's own execution environment** (NOT inside any MCP sandbox):

Linux / macOS:
```bash
test -f /root/.agents/skills/huawei-cloud-jobenv-devbridge-tunnel/scripts/devbridge_cmd.sh && echo "ROUTE_A" || echo "ROUTE_B"
```

Windows PowerShell:
```powershell
if (Test-Path -LiteralPath "/root/.agents/skills/huawei-cloud-jobenv-devbridge-tunnel/scripts/devbridge_cmd.sh") { "ROUTE_A" } else { "ROUTE_B" }
```

| Result | Route | Meaning |
|--------|-------|---------|
| `ROUTE_A` | [Route A: Jobenv Direct Deployment](#route-a-jobenv-direct-deployment) | Agent runs inside a Huawei Cloud jobenv where `/root/.agents/skills/huawei-cloud-jobenv-devbridge-tunnel` is installed. Deploy directly on this machine. |
| `ROUTE_B` | [Route B: Local Sandbox Deployment](#route-b-local-sandbox-deployment-aksk-only) | Agent runs outside such an environment (local machine, Windows, etc.). Deploy via huaweicloud-devkit plugin sandbox, AK/SK only. |

Routing rules:
- Run this check BEFORE connecting to any MCP sandbox — it targets the agent's own shell.
- Pick ONE route and follow it end-to-end. Do not mix steps from the two routes.
- Only fall back from ROUTE_A to ROUTE_B if the jobenv environment is fundamentally broken (skill dir incomplete, WebUI API at `127.0.0.1:8090` unreachable after the auth recovery procedure). Auth expiry is NOT a reason to switch — use Route A's [Authentication Failure Recovery](#authentication-failure-recovery-route-a) first.

---

# Route A: Jobenv Direct Deployment

Use this route when the agent can access `/root/.agents/skills/huawei-cloud-jobenv-devbridge-tunnel`. Deploys a web project from a Git repository to a public URL via DevBridge tunnels, directly on the current machine.

## Workflow Overview

```
Git Repo → Clone → Detect Type → Install Deps → Start Server → Create Tunnel → Expose Port → Public URL
```

## Prerequisites

- DevBridge skill installed: `huawei-cloud-jobenv-devbridge-tunnel` (verified in Step 0)
- DevBridge wrapper script: `source <devbridge_skill_dir>/scripts/devbridge_cmd.sh`
- Bash, curl, git available
- Python/Node.js available depending on project type
- `JOB_ENV_HW_DEVBRIDGE_API_KEY` available **inside the sandbox** (injected by jobenv). Note: auth is **NOT always automatic** — the sandbox may not have `HW_ACCESS_KEY`/`HW_SECRET_KEY`/`HW_SECURITY_TOKEN` set. Step 3 includes an automated auth check and recovery using this API key. If the API key itself is missing (empty), recovery requires first running `POST /api/v1/debug/env-sync`; see [Authentication Failure Recovery](#authentication-failure-recovery-route-a) for details.

## Step 1: Clone the Repository

```bash
git clone <repo_url> /root/workspace/<repo_name>
```

If the user provides a subdirectory URL (e.g. `.../tree/main/snake-game`), clone the whole repo then `cd` into the subdirectory.

## Step 2: Detect Project Type and Start Server

Inspect files in the project root to determine type:

| Files Present | Project Type | Install Command | Start Command | Default Port |
|---|---|---|---|---|
| `requirements.txt` + `app.py` / `*.py` | Flask/Python | `pip install -r requirements.txt` | `python app.py` | 5000 |
| `package.json` | Node.js | `npm install` | `npm start` or `node server.js` | 3000 |
| `index.html` only | Static HTML | none | `python -m http.server 8080` | 8080 |
| `pom.xml` | Java/Maven | `mvn compile` | `mvn spring-boot:run` | 8080 |
| `go.mod` | Go | `go build` | `./<binary>` | 8080 |

### Start Server in Background

```bash
cd <project_dir>
nohup <start_command> > /tmp/<project_name>.log 2>&1 &
sleep 2
curl -s http://localhost:<port>/  # verify server is up
```

If the project has a `/health` endpoint, verify with that instead.

## Step 3: Create DevBridge Tunnel

Source the DevBridge wrapper, ensure auth, then execute the full flow:

```bash
source <devbridge_skill_dir>/scripts/devbridge_cmd.sh
db_init

# --- Auth check & auto-recovery ---
# The DevBridge WebUI may have expired credentials ("Not logged in").
# The sandbox has JOB_ENV_HW_DEVBRIDGE_API_KEY injected by jobenv.
# Re-login inside the sandbox if auth has expired.
AUTH_STATUS=$(db_auth_status 2>/dev/null || echo "")
if echo "$AUTH_STATUS" | grep -q "Not logged in"; then
    echo "Auth expired, re-authenticating with JOB_ENV_HW_DEVBRIDGE_API_KEY..."

    # First: is the API key even present in the sandbox?
    KEY_CHECK=$(curl -s -X POST "http://127.0.0.1:8090/api/v1/envs/devbridge/exec" \
        -H 'Content-Type: application/json' \
        -d '{"cmd":["bash","-c","echo API=${JOB_ENV_HW_DEVBRIDGE_API_KEY:+set}"]}')
    if echo "$KEY_CHECK" | grep -q 'API=set'; then
        echo "  API key present in sandbox."
    else
        # Key was never injected — ask jobenv to sync HW credentials first.
        # Do NOT self-sign IAM tokens or probe DevStation here.
        echo "  API key missing; triggering jobenv credential sync..."
        curl -s -X POST "http://127.0.0.1:8090/api/v1/debug/env-sync" \
            -H 'Content-Type: application/json' >/dev/null 2>&1
    fi

    curl -s -X POST "http://127.0.0.1:8090/api/v1/envs/devbridge/exec" \
        -H 'Content-Type: application/json' \
        -d '{"cmd":["bash","-c","devbridge auth login --api-key $JOB_ENV_HW_DEVBRIDGE_API_KEY 2>&1"]}' >/dev/null 2>&1
    sleep 2
    # Verify recovery
    AUTH_STATUS=$(db_auth_status 2>/dev/null || echo "")
    if echo "$AUTH_STATUS" | grep -q "Not logged in"; then
        echo "ERROR: DevBridge auth recovery failed."
        echo "       Tried POST /api/v1/debug/env-sync; JOB_ENV_HW_DEVBRIDGE_API_KEY still not usable."
        exit 1
    fi
    echo "Auth restored."
fi

# Create tunnel (name, description, expiration in hours; max 720)
TUNNEL_ID=$(db_create "<name>" "<description>" <expiration>)

# Create port mapping (tunnel_id, local_port, protocol, allow_anonymous)
db_port_create "$TUNNEL_ID" <port> http true

# Start hosting
db_host "$TUNNEL_ID"
```

### Default Parameters

| Parameter | Default | Notes |
|-----------|---------|-------|
| Tunnel name | `<project>-tunnel` | Descriptive name |
| Description | `Web项目部署隧道` | **No spaces** — only Chinese chars, digits, letters (0-64) |
| Expiration | `8` hours | User can request up to 720 |
| Port | Detected from project | 5000/3000/8080 |
| Protocol | `http` | |
| Anonymous access | `true` | Public access enabled |

> **CRITICAL — Tunnel description constraint:** The DevBridge API rejects descriptions containing spaces. Use only Chinese characters, digits, and letters (max 64 chars). For example, use `Web项目部署隧道` NOT `Web project deployment tunnel`.

## Step 4: Get Tunnel URL

```bash
db_processes  # find the host process ID
db_process_logs <process_id>  # extract tunnelUrls from response
```

The tunnel URL format is:
```
https://<tunnelId>-<port>.<region>-bridge.myhuaweicloud.com
```

## One-Shot Script

This skill ships `scripts/deploy_web_project.sh`, which performs Steps 1–4 in one command:

```bash
bash <this_skill_dir>/scripts/deploy_web_project.sh <repo_url> [subdir] [port] [expiration_hours]
```

## Step 5: Redeploy or Update

To change tunnel expiration or redeploy:

```bash
# Stop existing host process
db_process_stop <process_id>

# Delete old tunnel
db_delete <tunnel_id>

# Create new tunnel with updated parameters
TUNNEL_ID=$(db_create "<name>" "<description>" <new_expiration>)
db_port_create "$TUNNEL_ID" <port> http true
db_host "$TUNNEL_ID"
```

## Step 6: Cleanup (Route A)

```bash
db_process_stop <process_id>   # stop hosting
db_delete <tunnel_id>          # delete tunnel
# kill local server process
kill <server_pid>
```

## Authentication Failure Recovery (Route A)

> **Note: Step 3 already inlines this auth check and recovery logic.** This section is kept as a detailed reference for troubleshooting and manual recovery.

> **CRITICAL — Read this before attempting any manual auth fix.** When the WebUI API returns `"API key expired, please login again"` or `db_auth_status` shows `"Not logged in"`, follow this procedure EXACTLY. Do NOT improvise.

### The Wrong Way (do NOT do any of these)

- ❌ Running `devbridge auth login --access-key <AK> --secret-key <SK>` — the CLI does NOT support `--access-key`/`--secret-key` flags (v0.2.2 only has `--api-key`).
- ❌ Passing Huawei Cloud AK as `--api-key` — AK is for IAM auth, NOT a DevBridge API key. It will return `"api key is invalid or disabled"`.
- ❌ Opening a browser to the DevStation console (`https://devstation.connect.huaweicloud.com/space/devbridge/apikey`) — headless environments have no browser.
- ❌ Using `webfetch` on the DevStation API key page — it requires login session, returns empty.
- ❌ Calling DevStation REST API directly to create an API key — auth signing format doesn't match.
- ❌ Trying to synthesize the DevBridge API key yourself when it is missing — hand-signing IAM AK/SK requests, fetching an IAM token, or probing/binary-diving DevStation endpoints. These CANNOT yield a DevBridge API key. Use `POST /api/v1/debug/env-sync` (see [If the API key is MISSING](#if-the-api-key-is-missing-trigger-a-jobenv-credential-sync-first)).
- ❌ Manually `undeploy`/`deploy` the sandbox — undeploy fails when sandbox is in `running` state.
- ❌ Switching to Route B — Route A auth expiry is fixed by the procedure below, not by re-routing.

### The Correct Way

The DevBridge sandbox injects a service-specific API key via the environment variable `JOB_ENV_HW_DEVBRIDGE_API_KEY`. This is **distinct from** the Huawei Cloud IAM AK/SK (`JOB_ENV_HW_ACCESS_KEY` / `JOB_ENV_HW_SECRET_KEY`). When the cached credentials in `~/.huawei/devbridge/config.yaml` expire, re-login with this env var:

```bash
# 1. Re-login inside the sandbox using the DevBridge API key env var
source <devbridge_skill_dir>/scripts/devbridge_cmd.sh
db_init

curl -s -X POST "http://127.0.0.1:8090/api/v1/envs/devbridge/exec" \
    -H 'Content-Type: application/json' \
    -d '{"cmd":["bash","-c","devbridge auth login --api-key $JOB_ENV_HW_DEVBRIDGE_API_KEY 2>&1"]}'

# 2. Verify auth is restored
db_auth_status
# Expected: {"success":true,"data":{"status":"Logged in (Huawei Cloud IAM)"}}

# 3. Resume normal tunnel operations via WebUI API
TUNNEL_ID=$(db_create "<name>" "<description>" <expiration>)
```

### Precondition: the API key must ALREADY be in the sandbox

The recovery above **only works if `JOB_ENV_HW_DEVBRIDGE_API_KEY` is already present inside the sandbox**. Confirm this BEFORE running `devbridge auth login`:

```bash
curl -s -X POST "http://127.0.0.1:8090/api/v1/envs/devbridge/exec" \
    -H 'Content-Type: application/json' \
    -d '{"cmd":["bash","-c","echo API=${JOB_ENV_HW_DEVBRIDGE_API_KEY:+set}"]}'
# Expected: {"stdout":"API=set\n", ...}
```

- If the output is `API=set` → the key is present; just re-login as shown in "The Correct Way".
- If the output is `API=` (empty) → **the key was never injected**; the jobenv deploy log will show `WARN: keyring 中未找到 HW_DEVBRIDGE_API_KEY，跳过 auth login`. The sandbox has no usable kernel keyring (`keyctl` is not installed), so waiting for the keyring-rotate daemon will NOT help. Go to the next section.

### If the API key is MISSING: trigger a jobenv credential sync first

When the key is absent, **do NOT** try to synthesize it yourself. Specifically, do NOT:

- ❌ hand-sign Huawei Cloud IAM AK/SK requests trying to mint a token,
- ❌ fetch an IAM token or call `KeystoneCreateToken`-style APIs,
- ❌ probe / scrape / binary-dive the DevStation or devbridge endpoints (`/open-api-inner/...`, `devstation.connect.huaweicloud.com`, etc.).

None of these can produce a **DevBridge API key** — it is a separate credential issued by DevStation/DevSpace, distinct from IAM AK/SK. The correct fix is to ask jobenv to inject it:

```bash
# 1. Force one round of HW credential sync. This writes the DevBridge API key
#    into the sandbox environment (env vars) and the kernel keyring.
curl -s -X POST "http://127.0.0.1:8090/api/v1/debug/env-sync" \
    -H 'Content-Type: application/json'

# 2. Re-check that the key is now visible inside the sandbox.
curl -s -X POST "http://127.0.0.1:8090/api/v1/envs/devbridge/exec" \
    -H 'Content-Type: application/json' \
    -d '{"cmd":["bash","-c","echo API=${JOB_ENV_HW_DEVBRIDGE_API_KEY:+set}"]}'
# Expected: {"stdout":"API=set\n", ...}

# 3. Now re-run the standard recovery from "The Correct Way" above.
curl -s -X POST "http://127.0.0.1:8090/api/v1/envs/devbridge/exec" \
    -H 'Content-Type: application/json' \
    -d '{"cmd":["bash","-c","devbridge auth login --api-key $JOB_ENV_HW_DEVBRIDGE_API_KEY 2>&1"]}'
db_auth_status   # Expected: {"success":true,"data":{"status":"Logged in (Huawei Cloud IAM)"}}
```

`POST /api/v1/debug/env-sync` is documented in the `job-environment` skill. It returns `{keyring, cached, envs}` with redacted values and re-syncs every running env; after it, `JOB_ENV_HW_DEVBRIDGE_API_KEY` is available in the sandbox env.

> **Decide in one step:**
> - `Not logged in` **and** `JOB_ENV_HW_DEVBRIDGE_API_KEY` is set → just re-login ("The Correct Way").
> - `Not logged in` **and** the key is missing/empty → run `POST /api/v1/debug/env-sync` first, then re-login. This is the ONLY supported way to recover a missing key inside the jobenv — never improvise an IAM/DevStation workaround.

### Key Distinction: Three Different Credential Types

| Env Var | Type | Purpose | Works as `--api-key`? |
|---------|------|---------|----------------------|
| `JOB_ENV_HW_ACCESS_KEY` | Huawei Cloud AK | IAM API authentication | ❌ No |
| `JOB_ENV_HW_SECRET_KEY` | Huawei Cloud SK | IAM API authentication | ❌ No |
| `JOB_ENV_HW_DEVBRIDGE_API_KEY` | DevBridge API Key | DevBridge service authentication | ✅ **Yes** |

### Automated Auth Check

Before creating a tunnel, always verify auth status first. If not logged in, run the recovery procedure above automatically:

```bash
source <devbridge_skill_dir>/scripts/devbridge_cmd.sh
db_init

# Check auth, auto-recover if needed
AUTH_STATUS=$(db_auth_status 2>/dev/null)
if echo "$AUTH_STATUS" | grep -q "Not logged in"; then
    echo "Auth expired, re-authenticating with JOB_ENV_HW_DEVBRIDGE_API_KEY..."

    # If the key is not injected yet, sync it first (never self-sign IAM/DevStation).
    KEY_CHECK=$(curl -s -X POST "http://127.0.0.1:8090/api/v1/envs/devbridge/exec" \
        -H 'Content-Type: application/json' \
        -d '{"cmd":["bash","-c","echo API=${JOB_ENV_HW_DEVBRIDGE_API_KEY:+set}"]}')
    echo "$KEY_CHECK" | grep -q 'API=set' || \
        curl -s -X POST "http://127.0.0.1:8090/api/v1/debug/env-sync" -H 'Content-Type: application/json' >/dev/null

    curl -s -X POST "http://127.0.0.1:8090/api/v1/envs/devbridge/exec" \
        -H 'Content-Type: application/json' \
        -d '{"cmd":["bash","-c","devbridge auth login --api-key $JOB_ENV_HW_DEVBRIDGE_API_KEY 2>&1"]}' >/dev/null
    sleep 2
fi

# Now safe to create tunnel
TUNNEL_ID=$(db_create "<name>" "<description>" <expiration>)
```

---

# Route B: Local Sandbox Deployment (AK/SK only)

Use this route when `/root/.agents/skills/huawei-cloud-jobenv-devbridge-tunnel` is NOT accessible — the agent runs on a local machine. Deploy the project to a Huawei Cloud sandbox and expose it to a public URL via DevBridge tunnel — using only AK/SK, no DevBridge API Key required.

## When to Use (Route B)

- User asks to deploy a project locally and get a public access URL
- User asks to quickly expose a running web app via devbridge
- User asks to "部署到本地并通过 devbridge 访问"
- User asks to create a tunnel for a local service

## How It Works (verified 2026-10-16)

Route B uses **huaweicloud-devkit** as the sole prerequisite. devkit provides sandbox tools that can connect to a Huawei Cloud sandbox and execute commands inside it. The sandbox comes with `devbridge` CLI preinstalled, which supports AK/SK login (`--access-key`/`--secret-key`).

The flow: configure AK/SK → connect sandbox → start web service inside sandbox → `devbridge auth login` with AK/SK → `devbridge host` to create tunnel → verify public URL.

Verified end-to-end: `devbridge auth login --access-key <AK> --secret-key <SK>` → "Logged in (Huawei Cloud IAM)" → `devbridge host -p 8080` → "Created tunnel" → public URL returns 200 with expected content.

## Prerequisites (Route B)

### 1. huaweicloud-devkit installed

devkit provides sandbox access and unified auth management. Install and configure:
```bash
npx huaweicloud-devkit install
npx huaweicloud-devkit install-hcloud   # KooCLI
```

Verify with `npx huaweicloud-devkit doctor` — all checks should pass.

### 2. AK/SK configured

AK/SK can be obtained from environment variables or entered interactively:

```bash
# Option A: from environment variables (already set in CI/jobenv)
export HW_ACCESS_KEY=<ak> HW_SECRET_KEY=<sk>

# Option B: interactive prompt
npx huaweicloud-devkit auth init
```

After `auth init`, AK/SK is stored in `/root/.config/huaweicloud/credentials.json`. Verify:
```bash
npx huaweicloud-devkit auth status
# Expected: Credentials vault: configured
```

### 3. Real-name verified + agreements signed

Use devkit's sandbox user check tool. If `agreementSigned: false`, call the agreement signing tool (only after user explicitly consents).

## Deployment Flow (Route B)

> **Key principle:** Use huaweicloud-devkit's sandbox tools to connect to a sandbox and execute commands inside it. The specific tool names and parameters may vary by devkit version — let devkit guide the execution. The commands below are what you run **inside the sandbox**; they are stable devbridge CLI commands.

### Step 1: Connect to a sandbox

Use devkit's sandbox connect tool. This creates (or reuses) a Huawei Cloud sandbox and returns a session/dev stage ID. Save this ID — you'll need it for all subsequent commands.

Expected return includes a session ID and connection status. The sandbox comes with `devbridge` CLI preinstalled.

### Step 2: Start the web service inside the sandbox

Use devkit's sandbox exec tool to run commands inside the sandbox. For a quick test:

```bash
mkdir -p /tmp/app && echo '<h1>Hello</h1>' > /tmp/app/index.html && \
nohup python3 -m http.server 8080 --directory /tmp/app > /tmp/app.log 2>&1 & \
sleep 2 && curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/
```

Expected output: `200`

For real projects, clone the repo inside the sandbox and start the appropriate server:

| Project Type | Install Command | Start Command | Default Port |
|---|---|---|---|
| Flask/Python | `pip install -r requirements.txt` | `python app.py` | 5000 |
| Node.js | `npm install` | `npm start` or `node server.js` | 3000 |
| Static HTML | none | `python3 -m http.server 8080` | 8080 |

```bash
git clone <repo_url> /root/workspace/<repo_name> && \
cd /root/workspace/<repo_name>[/<subdir>] && \
npm install && \
nohup npm start > /tmp/<repo_name>.log 2>&1 & \
sleep 3 && curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:<port>/
```

Use the same project-type detection table as Route A Step 2 to pick install/start commands and the default port.

### Step 3: Login to DevBridge with AK/SK

Run this command inside the sandbox, passing the AK/SK directly (not from env vars — the sandbox may not have them set):

```bash
devbridge auth login --access-key "<AK>" --secret-key "<SK>" 2>&1 && devbridge auth status
```

Expected output:
```
Login successful
Logged in (Huawei Cloud IAM)
```

> **Note:** The sandbox's preinstalled devbridge supports `--access-key`/`--secret-key` flags. Do NOT use `--security-token` — it is not supported. Do NOT use `--api-key` — we don't have one and don't need one.

### Step 4: Start the tunnel

Run inside the sandbox:

```bash
nohup devbridge host -p <port> -e <hours> > /tmp/devbridge-host.log 2>&1 & \
sleep 10 && cat /tmp/devbridge-host.log
```

Expected output:
```
Created tunnel: <tunnelId>
Hosting port: <port>
Tunnel URL: https://<tunnelId>-<port>.devbridge-s2.hwtunnel.com
Ready to accept connections
Auto reconnect: enabled
```

- `-p <port>`: local port (repeat for multi-port: `-p 8080 -p 3000`)
- `-e <hours>`: tunnel duration (1-720, default 8)
- Public URL format: `https://<tunnelId>-<port>.devbridge-s2.hwtunnel.com`

### Step 5: Verify the tunnel

From outside the sandbox (on the agent's own machine), curl the public URL:

```bash
curl -s -o /dev/null -w '%{http_code}' https://<tunnelId>-<port>.devbridge-s2.hwtunnel.com
```

Expected: `200` + your page content.

### Step 6: Report to user

Tell the user:
- The service is deployed and running
- The public access URL is: `https://<tunnelId>-<port>.devbridge-s2.hwtunnel.com`
- Tunnel duration: `<hours>` hours
- To stop: say "stop the tunnel" and the agent will clean up

Do NOT mention "DevBridge", "tunnel", "sandbox", or "STS" to the user — say "访问地址已生成" and hand over only the URL.

## Cleanup (Route B)

Run inside the sandbox:
```bash
devbridge delete-all 2>&1; pkill -f 'http.server' 2>/dev/null; echo 'cleanup done'
```

Then close the sandbox session using devkit's sandbox close tool.

---

# Troubleshooting

## Route A (jobenv)

| Symptom | Cause | Fix |
|---------|-------|-----|
| `db_auth_status` → `Not logged in` | Cached credentials expired | Run [Authentication Failure Recovery](#authentication-failure-recovery-route-a) — re-login with `JOB_ENV_HW_DEVBRIDGE_API_KEY` |
| `api key is invalid or disabled` | Huawei Cloud AK passed as `--api-key` | Use `JOB_ENV_HW_DEVBRIDGE_API_KEY`, never `JOB_ENV_HW_ACCESS_KEY` |
| `JOB_ENV_HW_DEVBRIDGE_API_KEY` empty in sandbox (`API=`), deploy log shows `keyring 中未找到 HW_DEVBRIDGE_API_KEY` | jobenv did not inject the DevBridge API key at sandbox startup | Run `POST /api/v1/debug/env-sync`, then re-login with `--api-key $JOB_ENV_HW_DEVBRIDGE_API_KEY`. Do NOT self-sign IAM tokens or probe DevStation — see [If the API key is MISSING](#if-the-api-key-is-missing-trigger-a-jobenv-credential-sync-first) |
| Tunnel creation rejected | Description contains spaces | Use only Chinese chars, digits, letters (max 64), e.g. `Web项目部署隧道` |
| Max 10 active tunnels | Workspace tunnel quota reached | `db_list` then `db_delete` unused tunnels |
| Local server not reachable | Server died or wrong port | `curl http://localhost:<port>/`; check `/tmp/<project>.log` |

## Route B (local sandbox)

| Symptom | Cause | Fix |
|---------|-------|-----|
| `npx huaweicloud-devkit doctor` fails | devkit not installed or misconfigured | Run `npx huaweicloud-devkit install` and `npx huaweicloud-devkit auth init` |
| Sandbox connect fails with "No available node pool" | Cloud-side capacity issue | Retry after a few minutes; this is transient, not a config problem |
| Sandbox connect fails with agreement error | User hasn't signed agreements | Use devkit's agreement signing tool (after user consent), then retry |
| `devbridge auth login` → "No browser available" | No AK/SK passed, fell back to browser | Pass `--access-key` and `--secret-key` explicitly |
| `devbridge auth login` → "unknown flag: --access-key" | Release build (not sandbox preinstalled) | Use the sandbox's preinstalled devbridge, not a manually installed one |
| `Failed to create tunnel: API key expired` | Not logged in or login expired | Re-run Step 3 (`devbridge auth login --access-key --secret-key`) |
| `Connection failed, retrying...` loop | Old devbridge in sandbox | Run `curl -fsSL https://tools-artifact.developer.huaweicloud.com/sharedata/devbridge/install.sh \| bash` inside sandbox to upgrade |
| Public URL `Connection refused` | Local server not listening | Verify: `curl http://127.0.0.1:<port>/` inside sandbox first |

# Key Notes

- **Route A auth**: use `JOB_ENV_HW_DEVBRIDGE_API_KEY` (DevBridge API Key) — never confuse it with IAM AK/SK (`JOB_ENV_HW_ACCESS_KEY`/`JOB_ENV_HW_SECRET_KEY`). If it is missing in the sandbox, run `POST /api/v1/debug/env-sync` to inject it, then re-login — do NOT self-sign IAM requests or probe DevStation.
- **Route B auth — AK/SK only, no API Key needed**: pass AK/SK directly to `devbridge auth login --access-key <AK> --secret-key <SK>` inside the sandbox. The sandbox's preinstalled devbridge supports these flags. Do NOT use `--security-token` (not supported).
- **Route B prerequisite**: huaweicloud-devkit provides the sandbox tools. Specific tool names/parameters may vary by devkit version — let devkit guide execution. The stable parts are the devbridge CLI commands run inside the sandbox.
- **Sandbox lifecycle (Route B)**: sandbox session expires (check `expiresAt`). Long-running tunnels need the sandbox to stay alive. Use `-e <hours>` to set tunnel duration.
- **Never echo credentials**: AK/SK/STS/API keys are sourced from env files or env vars — never print them.
- **Security**: anonymous tunnel access means anyone with the URL can access the service — only enable for non-sensitive content. DevBridge tunnels are for development/debugging/temporary sharing, NOT production. Always clean up tunnels when no longer needed.
- **User-facing language (Route B)**: the tunnel mechanism is an internal detail. Never mention "DevBridge", "tunnel", "sandbox", or "STS" — say "访问地址已生成" and deliver only the URL.
- **Limitations**: max 10 active tunnels per workspace; tunnel expiration 1–720 hours (default 8); port range 1–65535, no duplicate ports within the same tunnel; local server must be running for the tunnel to serve content; tunnel description only Chinese characters/digits/letters (no spaces), max 64 chars.

# References

- Jobenv DevBridge skill (Route A): `/root/.agents/skills/huawei-cloud-jobenv-devbridge-tunnel`
- huaweicloud-devkit (Route B prerequisite): `npx huaweicloud-devkit --help`
- DevBridge tunnel reference: `/root/huawei-devbridge-tunnel.md`
- DevBridge API Key page (Route B fallback only): https://devstation.connect.huaweicloud.com/space/devbridge/apikey
- Official docs: https://huaweicloud.github.io/devspace-devbridge/
