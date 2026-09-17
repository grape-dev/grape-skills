---
name: cloud-deploy
version: 2.0.0
description: |
  华为云部署技能：自动构建项目并部署到华为云 ECS，支持 A2A 直接触发与 PR 合并触发。
  职责：项目结构识别 → 代码获取与构建 → hcloud CLI 部署 → HTTP 验证 → 资源释放。
  适用于部署/上线/更新华为云服务及释放/销毁云资源。
tools:
  - bash
---

## 安全硬约束

1. 调用 GitCode API 只用 `$BOT_GITCODE_TOKEN`，严禁从数据库/configs/日志/历史中寻找其他 token；token 不得写入文件/日志/评论。
2. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据。
3. API 返回 403/无权限时：立即停止并回复用户「需要管理员/维护者权限」，严禁尝试其他 token 或绕行。
4. AK/SK 从 Grape 控制台配置获取；未配置时停止并提示用户，严禁硬编码或从他处寻找凭证。
5. 严禁 `hcloud configure set` 改 default profile——必须用 `--cli-profile="task-$$"` 隔离，部署结束后清理。
6. **操作确认**：变更现有配置（安全组/资源配置等）与删除/释放云资源前，必须告知用户并取得确认；仅 A2A/PR 合并显式触发的部署流水线写操作可自动执行。

## 场景 / When to Use

| 触发特征 | 场景 | 执行流程 |
|---------|------|---------|
| A2A 含「部署/上线/deploy」 | 部署 | 流程 §1~§4 |
| A2A 含「释放/销毁/destroy」 | 资源释放 | `references/deploy-guide.md` §6 |
| PR 合并到 main/master | 自动部署 | 流程 §1~§4 |
| 其他事件 | 跳过 | 输出 SKIP |

Don't use for: 非 merge/非 A2A 的 PR 事件；非 main/master 分支的 push。

## 知识 / Knowledge

### 环境变量

| 变量 | 来源 | 说明 |
|------|------|------|
| `HUAWEICLOUD_SDK_AK` | Grape 控制台 | 华为云 AK |
| `HUAWEICLOUD_SDK_SK` | Grape 控制台 | 华为云 SK |
| `BOT_GITCODE_TOKEN` | 系统 prompt | GitCode API Token |

### grape CLI 命令

使用 `grape` CLI 替代 raw curl/git。完整参考见 `references/grape-cli-reference.md`。

| 命令 | 用途 |
|------|------|
| `grape git-repo issues get` | 获取 Issue 详情 |
| `grape git-repo issues comments list` | 查 Issue 评论 |
| `grape git-repo issues comments create` | 发 Issue 评论 |
| `grape git` | git 透传（clone/checkout/push） |
| `grape tasks complete` | 任务完成自报 |
| `grape a2a handoff` | A2A 交办 |

### 操作边界

| 操作 | 允许 | 说明 |
|------|------|------|
| 创建/更新云资源（ECS/EIP/安全组） | ✅ | A2A 或 PR 合并触发时自动执行 |
| 部署代码到 ECS | ✅ | 构建后自动部署 |
| 变更现有配置（安全组/资源配置等） | ⚠️ | 需用户确认 |
| 删除/释放云资源 | ⚠️ | 需用户确认（资源释放场景） |
| 修改仓库代码 | ❌ | 禁止 |
| 删除仓库分支 | ❌ | 禁止 |
| 读取 Grape 内部数据 | ❌ | 禁止 |

## 步骤 / Steps

### 1. 理解项目结构

读取仓库根目录文件，判断构建方式：

| 文件标记 | 推断 |
|----------|------|
| `package.json` | Node.js（npm/yarn） |
| `requirements.txt` / `pyproject.toml` | Python（pip/poetry） |
| `go.mod` | Go（go build） |
| `Dockerfile` | 容器化 |
| `Makefile` | 自定义构建 |

### 2. 获取代码并构建

```bash
grape git clone <repo_url> && grape git checkout <branch>
# 按项目类型构建：npm install && npm run build / pip install -r requirements.txt
```

### 3. 部署到华为云 ECS

详细步骤见 `references/deploy-guide.md`。核心流程：

1. 安装 hcloud（缺失时自动安装，架构判定 → 下载 → 隐私确认）
2. 配置认证（`--cli-profile="task-$$"` 隔离）
3. ECS 幂等检查（查已有实例 → 复用或新建，动态选规格，AZ=cn-north-4a/4b）
4. SSH 部署（scp 上传 → 单条 SSH 完成依赖安装+启动）
5. HTTP 验证（期望 200）

### 4. 验证

- 端口检查：`ss -tlnp | grep 5000`
- HTTP 检查：`curl http://$ECS_IP:5000/` 期望 200
- 公网可达：安全组已放行 22/80/5000

### 5. 资源释放（资源释放场景）

详见 `references/deploy-guide.md` §6。核心：先查再删，逐个验证。

### 6. 任务完成

完成全部业务动作后，**调用 `grape tasks complete` 自报完成（必做）**。会话 token 自动定位当前任务，无需 --task-id。

```bash
grape tasks complete --json '{
  "result_text": "结论：Issue #{n} 部署/资源释放完成。",
  "next_step": "done",
  "actions": ["构建并部署到华为云 ECS", "验证部署结果", "在 Issue 评论告知"],
  "conclusion": "部署完成，http {http_code}",
  "artifacts": ["ECS {ecs_ip}", "Issue 评论"],
  "issue_summary": "部署完成 | 访问 {url} | 验证 {http_code}"
}'
```

完成后通过 `grape a2a handoff` 交办下游或发 Issue 评论汇报结果。

## 判断标准 / Verification

- [ ] hcloud 可用且 profile 已隔离
- [ ] ECS 创建/复用成功，SSH 可达
- [ ] 部署后 HTTP 返回 200
- [ ] 资源释放后查询返回空/404
- [ ] Issue 评论已发送
- [ ] `grape tasks complete` 已执行

## 参考 / References

- `references/grape-cli-reference.md` — grape CLI 命令参考（安装/认证/命令/限制/退出码/安全）
- `references/deploy-guide.md` — 华为云部署领域指南（hcloud 安装/ECS 创建/SSH 部署/验证/资源释放）
- `references/contracts.md` — 输入/输出参数契约（inputSchema/outputSchema 与 JSON Schema）
- `references/performance-and-version.md` — 性能与版本约束说明
