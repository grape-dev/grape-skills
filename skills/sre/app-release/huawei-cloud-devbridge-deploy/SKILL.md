---
name: huawei-cloud-devbridge-deploy
description: '通过华为云 DevBridge 隧道将 web 项目部署到公网 URL，自动按环境路由两条路线：Route A（jobenv 环境）— agent 运行环境内已预装 DevBridge tunnel skill 时，直接在本机部署，走 WebUI API 认证；Route B（本地环境）— 否则走华为云沙箱 MCP 工具，仅用 AK/SK STS 凭据，无需 API Key。全流程：clone 仓库、识别项目类型（Flask/Node.js/静态）、装依赖、起服务、建隧道、返回公网 URL。Triggers: devbridge deploy, 部署web项目, 用devbridge部署, 部署到本地并通过 devbridge 访问, expose local web app, tunnel deploy, 通过隧道部署, deploy with tunnel.'
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
| `ROUTE_B` | [Route B: Local Sandbox Deployment](#route-b-local-sandbox-deployment-aksk-only) | Agent runs outside such an environment (local machine, Windows, etc.). Deploy via Huawei Cloud sandbox MCP tools, AK/SK only. |

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

Source the DevBridge wrapper and execute the full flow:

```bash
source <devbridge_skill_dir>/scripts/devbridge_cmd.sh
db_init

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

> **CRITICAL — Read this before attempting any auth fix.** When the WebUI API returns `"API key expired, please login again"` or `db_auth_status` shows `"Not logged in"`, follow this procedure EXACTLY. Do NOT improvise.

### The Wrong Way (do NOT do any of these)

- ❌ Running `devbridge auth login --access-key <AK> --secret-key <SK>` — the CLI does NOT support `--access-key`/`--secret-key` flags (v0.2.2 only has `--api-key`).
- ❌ Passing Huawei Cloud AK as `--api-key` — AK is for IAM auth, NOT a DevBridge API key. It will return `"api key is invalid or disabled"`.
- ❌ Opening a browser to the DevStation console (`https://devstation.connect.huaweicloud.com/space/devbridge/apikey`) — headless environments have no browser.
- ❌ Using `webfetch` on the DevStation API key page — it requires login session, returns empty.
- ❌ Calling DevStation REST API directly to create an API key — auth signing format doesn't match.
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

## How It Works (verified 2026-10-10)

DevBridge 0.2.2 release builds removed AK/SK login flags — only `--api-key` works. BUT Huawei Cloud sandbox images ship a preinstalled devbridge that **retains AK/SK flags** (`--access-key`/`--secret-key`). The huaweicloud-devkit sandbox flow provides STS temp credentials via AK/SK validation, so the whole chain works with **only AK/SK, no manual API Key**.

Verified end-to-end: sandbox connect → STS credentials inject → `devbridge auth login --access-key --secret-key --security-token` → "Logged in (Huawei Cloud IAM)" → `devbridge host -p 8080` → "Created tunnel" → public URL returns 200 with expected content.

## Prerequisites (Route B)

### 1. HuaweiCloud DevKit installed (MCP tools)

Check with `huaweicloud_auth_status` MCP tool. If not configured:
```bash
export HW_ACCESS_KEY=<ak> HW_SECRET_KEY=<sk>
npx huaweicloud-devkit auth init
npx huaweicloud-devkit install --target hermes
npx huaweicloud-devkit install-hcloud   # KooCLI
hcloud IAM KeystoneListProjects --cli-region=cn-north-4   # set project_id
```

### 2. AK/SK configured

AK/SK stored in `/root/.config/huaweicloud/credentials.json` after `huaweicloud_auth_init`. Verify:
```python
# Call huaweicloud_auth_status MCP tool
# credentialsConfigured: true, kooCliInstalled: true
```

### 3. Real-name verified + agreements signed

Check with `huaweicloud_sandbox_check_user` MCP tool:
- `realnameVerified: true`
- `agreementSigned: true`

If `agreementSigned: false`, call `huaweicloud_sandbox_sign_agreement` (only after user explicitly consents).

## Deployment Flow (Route B)

### Step 1: Connect to a sandbox

Call `huaweicloud_sandbox_connect` MCP tool (no params needed).

Returns:
```json
{
  "sessionId": "c1f255f62ae246e193bcd2e1643713a4",
  "devStageId": "c1f255f62ae246e193bcd2e1643713a4",
  "status": "connected",
  "expiresAt": "2026-10-11T13:18:32.593000Z"
}
```

Save `devStageId` for all subsequent calls.

### Step 2: Inject STS credentials

Call `huaweicloud_sandbox_credentials` MCP tool:
```json
{
  "dev_stage_id": "<devStageId from Step 1>",
  "enable_sts": true,
  "region": "cn-north-4"
}
```

Returns:
```json
{
  "credentialValidation": "passed",
  "apiKeyInjected": false,
  "projectId": "019fa11c478e7880ad43037a6f62a0ad"
}
```

`apiKeyInjected: false` is expected — we don't need an API Key. The STS credentials are written to `/tmp/hw_creds.sh` inside the sandbox.

### Step 3: Start the local service

Call `huaweicloud_sandbox_exec_one_shot` MCP tool:
```json
{
  "dev_stage_id": "<devStageId>",
  "command": "mkdir -p /tmp/app && echo '<h1>Hello</h1>' > /tmp/app/index.html && nohup python3 -m http.server 8080 --directory /tmp/app > /tmp/app.log 2>&1 & sleep 2 && curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/"
}
```

Expected output: `200`

For real projects, upload project files first with `huaweicloud_sandbox_upload_project`, then start the appropriate server:
- Static site: `python3 -m http.server <port> --directory <dir>`
- Node.js: `npm install && npm start`
- Python: `pip install -r requirements.txt && python3 app.py`
- Docker: `docker run -p <port>:<port> <image>`

For Git repos, clone inside the sandbox instead of uploading:
```json
{
  "dev_stage_id": "<devStageId>",
  "command": "git clone <repo_url> /root/workspace/<repo_name> && cd /root/workspace/<repo_name>[/<subdir>] && npm install && nohup npm start > /tmp/<repo_name>.log 2>&1 & sleep 3 && curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:<port>/"
}
```

Use the same project-type detection table as Route A Step 2 to pick install/start commands and the default port.

### Step 4: Login to DevBridge with AK/SK

Call `huaweicloud_sandbox_exec_one_shot`:
```json
{
  "dev_stage_id": "<devStageId>",
  "command": "source /tmp/hw_creds.sh && devbridge auth login --access-key \"$HW_ACCESS_KEY\" --secret-key \"$HW_SECRET_KEY\" --security-token \"$HW_SECURITY_TOKEN\" 2>&1 && devbridge auth status"
}
```

Expected output:
```
Login successful
Logged in (Huawei Cloud IAM)
```

⚠️ The sandbox's devbridge is an image build that retains `--access-key`/`--secret-key` flags. Release builds (installed via `install.sh`) do NOT have these flags — always use the sandbox's preinstalled devbridge.

### Step 5: Start the tunnel

Call `huaweicloud_sandbox_exec_one_shot`:
```json
{
  "dev_stage_id": "<devStageId>",
  "command": "nohup devbridge host -p 8080 -e 2 > /tmp/devbridge-host.log 2>&1 & sleep 10 && cat /tmp/devbridge-host.log"
}
```

Expected output:
```
Created tunnel: 7ztbosh7
Hosting port: 8080
Tunnel URL: https://7ztbosh7-8080.devbridge-s2.hwtunnel.com
Ready to accept connections
Auto reconnect: enabled
```

- `-p <port>`: local port (repeat for multi-port: `-p 8080 -p 3000`)
- `-e <hours>`: tunnel duration (1-720)
- Public URL format: `https://<tunnelId>-<port>.devbridge-s2.hwtunnel.com`

### Step 6: Verify the tunnel

Call `huaweicloud_sandbox_exec_one_shot`:
```json
{
  "dev_stage_id": "<devStageId>",
  "command": "curl -s -o /dev/null -w '%{http_code}' https://<tunnelId>-<port>.devbridge-s2.hwtunnel.com && echo ' OK' && curl -s https://<tunnelId>-<port>.devbridge-s2.hwtunnel.com | head -5"
}
```

Expected: `200 OK` + your page content.

### Step 7: Report to user

Tell the user:
- The service is deployed and running
- The public access URL is: `https://<tunnelId>-<port>.devbridge-s2.hwtunnel.com`
- Tunnel duration: `<hours>` hours
- To stop: say "stop the tunnel" and the agent will clean up

Do NOT mention "DevBridge", "tunnel", "sandbox", or "STS" to the user — say "访问地址已生成" and hand over only the URL.

## Cleanup (Route B)

Call `huaweicloud_sandbox_exec_one_shot`:
```json
{
  "dev_stage_id": "<devStageId>",
  "command": "devbridge delete-all 2>&1; pkill -f 'http.server' 2>/dev/null; echo 'cleanup done'"
}
```

Then call `huaweicloud_sandbox_close_session` to release the sandbox:
```json
{
  "dev_stage_id": "<devStageId>"
}
```

## Deployment Check (Route B)

Call `huaweicloud_sandbox_deploy_check` for a one-shot completeness check:
```json
{
  "dev_stage_id": "<devStageId>"
}
```

Returns a score, nextStep, and remediation command if the DevBridge tunnel is missing.

## MCP Tool Call Summary (Route B)

| Step | MCP Tool | Key Params |
|------|----------|------------|
| 0. Check auth | `huaweicloud_auth_status` | (none) |
| 0. Check user | `huaweicloud_sandbox_check_user` | (none) |
| 1. Connect sandbox | `huaweicloud_sandbox_connect` | (none) |
| 2. Inject STS | `huaweicloud_sandbox_credentials` | `dev_stage_id`, `enable_sts=true`, `region` |
| 3. Start service | `huaweicloud_sandbox_exec_one_shot` | `dev_stage_id`, `command` |
| 4. Login devbridge | `huaweicloud_sandbox_exec_one_shot` | `dev_stage_id`, `command` |
| 5. Start tunnel | `huaweicloud_sandbox_exec_one_shot` | `dev_stage_id`, `command` |
| 6. Verify | `huaweicloud_sandbox_exec_one_shot` | `dev_stage_id`, `command` |
| Cleanup | `huaweicloud_sandbox_exec_one_shot` | `dev_stage_id`, `command` |
| Close sandbox | `huaweicloud_sandbox_close_session` | `dev_stage_id` |

---

# Troubleshooting

## Route A (jobenv)

| Symptom | Cause | Fix |
|---------|-------|-----|
| `db_auth_status` → `Not logged in` | Cached credentials expired | Run [Authentication Failure Recovery](#authentication-failure-recovery-route-a) — re-login with `JOB_ENV_HW_DEVBRIDGE_API_KEY` |
| `api key is invalid or disabled` | Huawei Cloud AK passed as `--api-key` | Use `JOB_ENV_HW_DEVBRIDGE_API_KEY`, never `JOB_ENV_HW_ACCESS_KEY` |
| Tunnel creation rejected | Description contains spaces | Use only Chinese chars, digits, letters (max 64), e.g. `Web项目部署隧道` |
| Max 10 active tunnels | Workspace tunnel quota reached | `db_list` then `db_delete` unused tunnels |
| Local server not reachable | Server died or wrong port | `curl http://localhost:<port>/`; check `/tmp/<project>.log` |

## Route B (local sandbox)

| Symptom | Cause | Fix |
|---------|-------|-----|
| `huaweicloud_sandbox_credentials` returns `credentialValidation: failed` | AK/SK invalid or expired | Re-run `huaweicloud_auth_init` with correct AK/SK |
| `devbridge auth login` → `unknown flag: --access-key` | Release build (not image build) | This should not happen in sandbox — the preinstalled devbridge is an image build. If it happens, the sandbox image was updated. Fall back to API Key path: ask user to create one at https://devstation.connect.huaweicloud.com/space/devbridge/apikey |
| `Connection failed, retrying...` loop | Old devbridge in sandbox | Run `curl -fsSL https://tools-artifact.developer.huaweicloud.com/sharedata/devbridge/install.sh \| bash` inside sandbox to upgrade |
| Public URL `Connection refused` | Local server not listening | Verify: `curl http://127.0.0.1:<port>/` inside sandbox first |
| `/tmp/hw_creds.sh` not found in sandbox | DevKit MCP older than v1.1.7 | Upgrade: `npx huaweicloud-devkit install --target hermes`, restart agent session |
| `huaweicloud_sandbox_connect` fails with agreement error | User hasn't signed agreements | Call `huaweicloud_sandbox_sign_agreement` (after user consent) |

# Key Notes

- **Route A auth**: use `JOB_ENV_HW_DEVBRIDGE_API_KEY` (DevBridge API Key) — never confuse it with IAM AK/SK (`JOB_ENV_HW_ACCESS_KEY`/`JOB_ENV_HW_SECRET_KEY`).
- **Route B auth — AK/SK only, no API Key needed**: the sandbox's preinstalled devbridge retains AK/SK login flags. STS temp credentials are injected via `huaweicloud_sandbox_credentials` into `/tmp/hw_creds.sh`.
- **Two devbridge builds**: release builds (public download, `--api-key` only) vs image builds (preinstalled in sandbox, `--access-key`/`--secret-key` retained). Route B must always use the sandbox's image build for AK/SK login.
- **Sandbox lifecycle (Route B)**: sandbox session expires (check `expiresAt`). Long-running tunnels need the sandbox to stay alive. Use `-e <hours>` to set tunnel duration.
- **Never echo credentials**: AK/SK/STS/API keys are sourced from env files or env vars — never print them.
- **Security**: anonymous tunnel access means anyone with the URL can access the service — only enable for non-sensitive content. DevBridge tunnels are for development/debugging/temporary sharing, NOT production. Always clean up tunnels when no longer needed.
- **User-facing language (Route B)**: the tunnel mechanism is an internal detail. Never mention "DevBridge", "tunnel", "sandbox", or "STS" — say "访问地址已生成" and deliver only the URL.
- **Limitations**: max 10 active tunnels per workspace; tunnel expiration 1–720 hours (default 8); port range 1–65535, no duplicate ports within the same tunnel; local server must be running for the tunnel to serve content; tunnel description only Chinese characters/digits/letters (no spaces), max 64 chars.

# References

- Jobenv DevBridge skill (Route A): `/root/.agents/skills/huawei-cloud-jobenv-devbridge-tunnel`
- DevBridge tunnel reference: `/root/huawei-devbridge-tunnel.md`
- DevBridge API Key page (Route B fallback only): https://devstation.connect.huaweicloud.com/space/devbridge/apikey
- Official docs: https://huaweicloud.github.io/devspace-devbridge/
