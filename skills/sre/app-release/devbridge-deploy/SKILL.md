---
name: devbridge-deploy
description: |
  Use when 部署项目、DevBridge 隧道部署、公网访问 URL 生成、SRE 部署、应用部署。
  DevBridge 隧道部署技能。
  在 Grape 服务器本地部署用户项目，通过 DevBridge 隧道生成公网可访问 URL。
  Grape 服务器已安装 devbridge CLI，使用系统级 API Key 认证（一次性配置）。
  替代旧版高端口部署方案，解决高端口安全组不可达问题，隧道地址公网直达。
tools:
  - git
  - curl
---

## 安全硬约束（必须遵守）

1. 调用 VCS API 只用 prompt 注入的 token，严禁从数据库/configs/日志/历史中寻找其他 token。
2. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据。
3. API 返回 403/无权限时：立即停止该操作并回复用户「该操作需要管理员/维护者权限，请在 仓库设置中手动配置后重试」，严禁尝试其他 token 或绕行手段。
4. token 不得写入任何文件/日志/评论。
5. **禁止前台运行长驻服务类命令**：`python app.py`、`flask run`、`devbridge host` 等会阻塞不退出的命令，严禁在前台直接执行。必须用 nohup 后台启动 + curl 验证 + 报告 URL。
6. **禁止占用 Grape 核心端口**：3000（Main API）、8080（Webhook）、80（nginx）、8081（Admin）、8082（Admin 前端）严禁使用。部署端口从 5100-5200 区间选择空闲端口。

# DevBridge 隧道部署

## 定位

SRE Agent 的隧道部署技能，在 Grape 服务器本地部署用户项目并通过 DevBridge 隧道暴露到公网。
Grape 服务器已安装 devbridge CLI（`~/.huawei/bin/devbridge`），使用系统级 API Key 认证。
**核心能力：git clone → 启动服务 → 创建隧道 → 输出公网 URL，用户无需配置任何凭证。**

## 前提条件

- Grape 服务器已安装 devbridge CLI（`~/.huawei/bin/devbridge`）
- 系统已配置 `HW_API_KEY` 环境变量（管理员一次性创建，见下方"管理员配置"）
- SRE Agent 执行时 `HW_API_KEY` 从环境变量自动注入

### 管理员配置（仅首次）

```bash
# 1. 安装 devbridge CLI（从 OBS 渠道，国内可达）
curl -fsSL -o /tmp/devbridge.tar.gz "https://gitcode.com/CloudDeveloperDepartment/devbrige/releases/download/latest/devbridge_linux_amd64_0.2.0-release.tar.gz"
mkdir -p ~/.huawei/bin && tar xzf /tmp/devbridge.tar.gz -C ~/.huawei/bin/
mv ~/.huawei/bin/devbridge_linux_amd64_* ~/.huawei/bin/devbridge

# 2. 创建 API Key（在 DevBridge 管理页面操作）
# 访问 https://devstation.connect.huaweicloud.com/space/devbridge/apikey
# 创建新 API Key，复制保存

# 3. 写入系统环境变量（Grape worker 会自动读取）
echo 'export HW_API_KEY="your-api-key-here"' >> ~/.bashrc
source ~/.bashrc

# 4. 首次登录（凭证持久化到 ~/.huawei/devbridge/config.yaml）
export PATH="$HOME/.huawei/bin:$PATH"
devbridge auth login --api-key "$HW_API_KEY"
devbridge auth status  # 确认 "Logged in"
```

## 入口判定

从 A2A 调用或 PR 合并事件触发。从 A2A context / payload 中获取 `issue_number`、`pr_number`（可选）。

## 部署模式判定

```bash
DEPLOY_DIR="/opt/$REPO_NAME"
if [ -d "$DEPLOY_DIR/.git" ]; then
  DEPLOY_MODE="update"    # 增量更新
else
  DEPLOY_MODE="initial"   # 首次部署
fi
echo "Deploy mode: $DEPLOY_MODE, dir=$DEPLOY_DIR"
```

## 流程

### 0. 环境检查

```bash
# 确认 devbridge 已安装
export PATH="$HOME/.huawei/bin:$PATH"
devbridge version

# 确认已登录
devbridge auth status

# 如果未登录，使用环境变量中的 API Key 登录
if ! devbridge auth status 2>&1 | grep -qi "logged in"; then
  if [ -n "$HW_API_KEY" ]; then
    devbridge auth login --api-key "$HW_API_KEY"
  else
    echo "ERROR: devbridge not authenticated and HW_API_KEY not set."
    echo "管理员请参考 SKILL.md 中的「管理员配置」步骤设置 API Key。"
    # 在 Issue 评论说明环境问题并结束
    exit 1
  fi
fi
```

### 1. 获取代码

#### 首次部署（initial）

```bash
DEPLOY_DIR="/opt/$REPO_NAME"
git clone https://gitcode.com/$REPO_OWNER/$REPO_NAME.git "$DEPLOY_DIR"
cd "$DEPLOY_DIR"
```

#### 增量更新（update）

```bash
DEPLOY_DIR="/opt/$REPO_NAME"
cd "$DEPLOY_DIR"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
git fetch origin "$CURRENT_BRANCH"
git merge "origin/$CURRENT_BRANCH" --no-edit

LATEST_COMMIT=$(git rev-parse --short HEAD)
echo "Updated to commit: $LATEST_COMMIT"
```

若 clone / pull 失败（网络/token 问题），在 Issue 评论说明并结束。

### 2. 安装依赖

```bash
cd "$DEPLOY_DIR"
if [ -f requirements.txt ]; then
  pip install -r requirements.txt --index-url https://pypi.tuna.tsinghua.edu.cn/simple 2>&1 | tail -5
fi
```

若 requirements.txt 不存在，尝试 `pip install flask` 作为最小依赖。
纯静态项目（HTML/CSS/JS 无 Python）跳过此步，直接用 `python3 -m http.server` 启动。

安装失败时在 Issue 评论说明错误并结束。

### 3. 启动 / 重启服务

#### 选择启动方式

根据项目类型选择：

```bash
# Python/Flask 项目（有 app.py）
if [ -f "$DEPLOY_DIR/app.py" ]; then
  START_CMD="python3 app.py --port $DEPLOY_PORT"

# FastAPI 项目（有 main.py 且 import fastapi）
elif [ -f "$DEPLOY_DIR/main.py" ]; then
  START_CMD="python3 -m uvicorn main:app --host 0.0.0.0 --port $DEPLOY_PORT"

# 纯静态项目（只有 HTML/CSS/JS）
else
  START_CMD="python3 -m http.server $DEPLOY_PORT --directory $DEPLOY_DIR"
fi
```

#### 选择空闲端口

```bash
for P in $(seq 5100 5200); do
  if ! ss -tlnp | grep -q ":$P "; then
    DEPLOY_PORT=$P
    break
  fi
done
echo "Selected port: $DEPLOY_PORT"
```

#### 后台启动服务

```bash
# 停止旧进程（增量更新时）
if [ -f /tmp/${REPO_NAME}.pid ]; then
  kill $(cat /tmp/${REPO_NAME}.pid) 2>/dev/null
  sleep 1
fi

# 后台启动
nohup $START_CMD > /tmp/${REPO_NAME}.log 2>&1 &
echo $! > /tmp/${REPO_NAME}.pid
sleep 3

# 确认服务存活
if ! kill -0 $(cat /tmp/${REPO_NAME}.pid) 2>/dev/null; then
  echo "Service failed to start. Logs:"
  cat /tmp/${REPO_NAME}.log
  # 在 Issue 评论附上错误日志并结束
  exit 1
fi
```

### 4. 创建 DevBridge 隧道并托管

#### 增量更新：先检查复用已有隧道

```bash
# 检查是否已有同仓库的隧道
TUNNEL_NAME="grape-${REPO_NAME}"
EXISTING_TUNNEL=$(devbridge list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')

if [ -n "$EXISTING_TUNNEL" ]; then
  TUNNEL_ID="$EXISTING_TUNNEL"
  echo "Reusing existing tunnel: $TUNNEL_ID"

  # 检查 Host 进程是否仍在运行
  if [ -f /tmp/${REPO_NAME}-tunnel.pid ] && kill -0 $(cat /tmp/${REPO_NAME}-tunnel.pid) 2>/dev/null; then
    echo "Host process still running, service restarted → traffic auto-forwarded"
  else
    # Host 进程已退出，重新启动
    nohup devbridge host "$TUNNEL_ID" > /tmp/${REPO_NAME}-tunnel.log 2>&1 &
    echo $! > /tmp/${REPO_NAME}-tunnel.pid
    sleep 3
  fi
  # 跳到步骤 5 验证
else
  # 首次部署或隧道已过期 → 创建新隧道
```

#### 首次部署：创建隧道 + 端口 + 托管

```bash
  # 创建隧道（2 小时有效期）
  devbridge create "$TUNNEL_NAME" -d "Grape deploy for $REPO_OWNER/$REPO_NAME" -e 2

  # 获取隧道 ID
  TUNNEL_ID=$(devbridge list | grep "$TUNNEL_NAME" | awk '{print $1}')
  echo "Tunnel ID: $TUNNEL_ID"

  # 创建端口（允许匿名访问，用户无需登录即可查看）
  devbridge port create "$TUNNEL_ID" -p "$DEPLOY_PORT" --protocol http -a

  # 后台启动 Host 托管端口
  nohup devbridge host "$TUNNEL_ID" > /tmp/${REPO_NAME}-tunnel.log 2>&1 &
  TUNNEL_PID=$!
  echo $TUNNEL_PID > /tmp/${REPO_NAME}-tunnel.pid
  sleep 3
fi
```

#### 提取隧道地址

```bash
# 从 Host 输出中提取隧道地址
TUNNEL_URL=$(grep -oP 'https://[a-z0-9]+\.[a-z0-9-]+\.myhuaweicloud\.com' /tmp/${REPO_NAME}-tunnel.log | head -1)

# 如果日志中没有，用 devbridge show 获取
if [ -z "$TUNNEL_URL" ]; then
  TUNNEL_URL=$(devbridge show "$TUNNEL_ID" 2>/dev/null | grep -oP 'https://[a-z0-9]+\.[a-z0-9-]+\.myhuaweicloud\.com' | head -1)
fi

if [ -z "$TUNNEL_URL" ]; then
  echo "Failed to get tunnel URL. Tunnel logs:"
  cat /tmp/${REPO_NAME}-tunnel.log
  # 在 Issue 评论附上日志并结束
  exit 1
fi

echo "Tunnel URL: $TUNNEL_URL"
```

### 5. 验证健康检查

```bash
# 验证本地服务
HTTP_LOCAL=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:${DEPLOY_PORT}/ 2>/dev/null)
echo "Local health: HTTP $HTTP_LOCAL"

# 验证隧道地址（可能需要几秒生效）
sleep 2
HTTP_TUNNEL=$(curl -s -o /dev/null -w "%{http_code}" "$TUNNEL_URL" 2>/dev/null)
echo "Tunnel health: HTTP $HTTP_TUNNEL"
```

验证失败（进程崩溃/隧道不通）时：
```bash
cat /tmp/${REPO_NAME}.log          # 服务日志
cat /tmp/${REPO_NAME}-tunnel.log   # 隧道日志
# 在 Issue 评论中附上错误日志并结束
```

### 6. 清理旧隧道（可选）

部署完成后，检查是否有同仓库的旧隧道残留：
```bash
# 列出所有 grape- 开头的隧道
devbridge list | grep "grape-" | while read -r line; do
  OLD_ID=$(echo "$line" | awk '{print $1}')
  OLD_NAME=$(echo "$line" | awk '{print $2}')
  if [ "$OLD_NAME" != "grape-${REPO_NAME}" ]; then
    echo "Cleaning up old tunnel: $OLD_ID ($OLD_NAME)"
    devbridge delete "$OLD_ID"
  fi
done
```

> **删除操作确认**：`devbridge delete` 是删除操作，执行前需确认目标隧道 ID 正确（通过 `devbridge list` 核对名称匹配），避免误删当前仓库正在使用的隧道。仅清理非当前仓库的旧隧道，当前部署隧道不在清理范围内。

## 硬规则

| 行为 | 态度 |
|------|------|
| **增量更新时必须 git pull 拉取最新代码** | ✅ **必须做** |
| **增量更新后必须重启服务使新代码生效** | ✅ **必须做** |
| **增量更新时优先复用已有隧道** | ✅ **必须做** |
| 在 result 文本中输出完整隧道公网 URL | ✅ **必须做** |
| 安装依赖使用国内镜像源 | ✅ **必须做** |
| 首次部署选择 5100-5200 区间空闲端口 | ✅ **必须做** |
| 隧道有效期设为 2 小时 | ✅ **必须做** |
| 端口允许匿名访问（`-a`）方便用户直接查看 | ✅ **必须做** |
| 健康检查通过后再报告部署成功 | ✅ **必须做** |
| 前台运行服务类命令或 devbridge host | ❌ **禁止** |
| 占用 Grape 核心端口（3000/8080/80/8081/8082） | ❌ **禁止** |
| 创建云资源（ECS/RDS/VPC 等） | ❌ **禁止** |
| 直接合并 PR | ❌ **禁止** |
| 回复 Token、密码等敏感信息 | ❌ **禁止** |
| 增量更新时跳过 git pull 直接重启 | ❌ **禁止** |
| 部署完成后不输出访问 URL | ❌ **禁止** |

## 部署失败处理

| 失败原因 | 处理方式 |
|---------|---------|
| devbridge 未安装 | 按「管理员配置」步骤安装 CLI |
| devbridge 未登录且无 HW_API_KEY | 报告环境异常，说明需要管理员配置 API Key |
| git clone / pull 失败 | 检查 token 权限，在 Issue 评论说明 |
| pip install 失败 | 在 Issue 评论附上 pip 错误输出 |
| 端口全部占用 | 在 Issue 评论说明，建议清理旧部署 |
| 服务启动后进程退出 | 查看 /tmp/<repo>.log 日志，附上错误评论 |
| devbridge host 启动失败 | 查看 /tmp/<repo>-tunnel.log，可能是配额用尽或隧道数超限 |
| 隧道 URL 无法访问 | 检查 Host 进程是否存活，等待 5 秒后重试 curl |
| devbridge create 失败（配额） | `devbridge limits` 检查配额，清理旧隧道后重试 |

## 输入参数（inputSchema）

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| repo_owner | string | 是 | 仓库所有者 |
| repo_name | string | 是 | 仓库名称 |
| issue_number | int | 是 | Issue 编号 |
| pr_number | int | 否 | PR 编号（PR 合并触发时） |

合法输入：repo_owner/repo_name 非空字符串；issue_number 为正整数。
非法输入：缺 repo_name → 不执行；issue_number 缺失 → 不执行 A2A 回复。

## 输出格式（outputSchema）

```json
{
  "actions": ["拉取最新代码", "安装依赖", "启动服务", "创建隧道", "健康检查通过"],
  "conclusion": "部署成功，隧道地址已就绪",
  "artifacts": {
    "deploy_url": "https://<tunnelId>.<clusterId>.myhuaweicloud.com",
    "tunnel_id": "<tunnelId>",
    "tunnel_expiration": "2小时",
    "local_port": "<port>"
  },
  "next_step": "用户可通过 deploy_url 访问验证功能，隧道有效期 2 小时",
  "issue_summary": "SRE 部署完成 | 访问地址: <URL> | 隧道: <tunnelId> | 有效期: 2h | 端口: <port>"
}
```

## 读写语义

| 操作类型 | 操作 | 语义 |
|----------|------|------|
| 读操作 | git clone / git pull 获取代码 | 自动执行 |
| 读操作 | devbridge version / auth status 检查环境 | 自动执行 |
| 读操作 | devbridge list 查看已有隧道 | 自动执行 |
| 读操作 | curl 健康检查 | 自动执行 |
| 写操作 | pip install 安装依赖 | 自动执行（系统环境隔离） |
| 写操作 | nohup 启动服务 | 自动执行 |
| 写操作 | devbridge create / port create 创建隧道 | 自动执行 |
| 写操作 | devbridge host 托管端口 | 自动执行 |
| 删除操作 | devbridge delete 清理旧隧道 | 需确认目标 ID 正确后再执行 |
| 删除操作 | kill 停止旧进程 | 自动执行（增量更新时重启服务） |

> 部署类写操作（clone/install/start/create tunnel）为 SRE 自动化操作，无需用户确认。删除操作（devbridge delete）执行前需通过 `devbridge list` 核对隧道名称，确认非当前部署隧道后再执行。

## 性能预算

| 指标 | 预估值 | 说明 |
|------|--------|------|
| LLM 调用次数 | 3-8 次 | 部署流程以脚本执行为主，LLM 调用少 |
| token 消耗 | 2000-6000 token | SKILL.md(~12KB) + 部署输出(可变) |
| 加载时延 | < 1s | 单文件 ~13KB |
| 执行时延 | 30s-3min | 取决于 clone/pip install/tunnel 创建时间 |

上下文压缩策略：部署日志仅保留关键输出行（tail -5），错误时附完整日志。

## 版本管理

- 当前版本：v1.0（遵循 v1.0 规范，Frontmatter 不含 version 字段）
- 向后兼容：devbridge CLI 0.2.0+ 兼容，API 向后兼容
- 灰度策略：可与旧版部署方案并存，通过 pipeline 配置切换

## 可靠性声明

| 机制 | 声明 |
|------|------|
| 断点续跑（resume） | 支持中间状态恢复：增量更新模式检查 /opt/{repo} 目录是否存在，已有则走 update 路径；隧道复用检查 devbridge list 已有隧道 |
| 重试幂等 | 部署操作幂等：重复 clone 覆盖目录；重复 start 先 kill 旧进程；隧道复用避免重复创建 |
| 资源清理 | 步骤 6 清理旧隧道；PID 文件管理进程生命周期；日志文件在 /tmp/ 下可定期清理 |
| 降级策略 | devbridge 未安装/未登录时报告环境异常；clone/pip 失败在 Issue 评论说明；隧道创建失败检查配额 |

## 依赖兼容

| 依赖 | 最低版本 | 说明 |
|------|----------|------|
| devbridge CLI | 0.2.0 | 隧道创建/host 管理 |
| VCS API | v5 | 仓库 clone 认证 |
| Python | 3.8+ | 项目运行时（pip install） |
| Grape 运行时 | - | A2A 调用支持 |

> pip install 在 Grape 服务器系统环境执行，未使用 venv。Grape 服务器为隔离的部署环境，系统级包安装不影响其他服务。如需隔离可在步骤 2 添加 `python3 -m venv .venv && source .venv/bin/activate`。

## 与旧版高端口部署方案的区别

| 维度 | 旧版高端口部署 | DevBridge 隧道部署 |
|------|-----|-----|
| 执行环境 | Grape 服务器 | Grape 服务器 |
| 公网访问 | 高端口（安全组不可达）/ nginx 代理 | `https://xxx.myhuaweicloud.com`（公网直达） |
| 认证 | 无需认证 | devbridge API Key（系统级，一次性配置） |
| 隧道有效期 | N/A | 2 小时（可配置） |
| nginx 依赖 | 需要配置代理 | 不需要 |
| 适用场景 | 内网 / 已有 nginx 代理 | 需要公网直达的轻量项目部署 |
