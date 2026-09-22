# grape CLI 命令参考（skill-uploader 专用）

> 来源：基于 grape-cli 契约（以 `grape commands` / `grape <group> <verb> --help` 实际输出为准）
> 本文件只列 skill-uploader 实际用到的命令子集，不列全量命令。

---

## 1. 安装与就绪检查

grape CLI 由 worker 预装。使用前检查：

```bash
which grape          # 验证安装，无结果直接报障，不自行安装
grape --version      # 确认版本
grape commands       # 验证命令树可用
```

> ⚠️ grape 未安装时直接报障，不 curl 直连 API。401 报错说明 token 失效。

---

## 2. 认证与配置

| 项 | 说明 |
|----|------|
| `$GRAPE_SESSION_TOKEN` | 服务端注入，任务级临时 token（`tk_` 前缀），grape 自动读取 |
| `$GRAPE_API_TOKEN` | **用户级 API Key（`grape_` 前缀）** |
| Token 优先级 | `--token` > `GRAPE_SESSION_TOKEN` > `GRAPE_API_TOKEN` > config.json |
| base_url 优先级 | `--base-url` > `GRAPE_BASE_URL` > `GRAPE_SERVER_URL` > config.json > `http://localhost:8000` |
| Token scope | session_only（仅 tk_）/ dual（tk_ 和 grape_ 均可）/ user_only（仅 grape_/JWT） |
| GRAPE_CLI_MODE | WORKER/USER/ALL |

---

## 3. 常用命令（skill-uploader 实际用到的子集）

### 3.1 skill 上传与验证

| 命令 | 方法 | Scope | 用途 |
|------|------|-------|------|
| `grape skills upload --file {zip} --scope repo --repo {owner}/{repo} --agent_type {agent_type}` | POST | dual | 上传 skill ZIP 为仓库级 skill |
| `grape skills list --scope repo --repo {owner}/{repo} --json-out` | GET | dual | 列出仓库级 skill，验证是否注册 |
| `grape skills detail --skill_id {id} --json-out` | GET | dual | skill 详情（含 SKILL.md），验证内容 |
| `grape skills sub list --skill_id {id} --json-out` | GET | dual | 列出 references/ 子文件，验证完整性 |

**skills upload 参数**（multipart/form-data，不走 --json）：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `--file` | string | ✅ | skill ZIP 文件路径 |
| `--scope` | string | — | `repo`（仓库级）/ `user`（个人级，默认）；本 skill 固定 `repo` |
| `--repo` | string | — | `{owner}/{repo}`，scope=repo 时必填 |
| `--agent_type` | string | — | vod/issue/coding/qa/sre |

> `--json-out` 不可用于 multipart upload（上传响应直接输出 JSON）。

### 3.2 任务上下文读取

| 命令 | Scope | 用途 |
|------|-------|------|
| `grape tasks current --json-out` | session_only | 获取当前任务 |
| `grape issues detail --owner {owner} --repo {repo} --number {n} --json-out` | dual | Issue 全貌 |
| `grape events detail --event_id {seq} --json-out` | dual | 读取前序 A2A 交接 payload |

### 3.3 PR 状态与变更确认

| 命令 | Scope | 用途 |
|------|-------|------|
| `grape git-repo pulls get --owner {owner} --repo {repo} --number {pr} --json-out` | session_only | PR 详情（合并状态确认，触发点 c） |
| `grape git-repo pulls files --owner {owner} --repo {repo} --number {pr} --json-out` | session_only | PR 变更文件（定位 skills/ 目录） |

### 3.4 GitCode Issue 评论

| 命令 | Scope | 用途 |
|------|-------|------|
| `grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"..."}'` | session_only | 发布上传结果/失败通知 |

### 3.5 任务完成与 A2A 交接

| 命令 | Scope | 用途 |
|------|-------|------|
| `grape tasks complete --json '{"result_text":"...","next_step":"done"}'` | dual | 自报完成 |
| `grape a2a handoff --json '{"agent":"coding","payload":{...}}'` | dual | 失败时回交 Coding 排查 |

### 3.6 --json body Schema（本 skill 用到的）

| Body schema | 使用命令 | 必填 | 可选 |
|-------------|---------|------|------|
| `CommentBody` | `git-repo issues comments create` | `body` | — |
| `A2AHandoffBody` | `a2a handoff` | — | `agent`, `payload` |
| `CompleteBody` | `tasks complete` | — | `task_id`, `result_text`, `next_step`, `conclusion`, `issue_summary`, `actions`, `artifacts` |

> `skills upload` 为 multipart，无 JSON body schema，参数走 `--file`/`--scope`/`--repo`/`--agent_type`。

### 3.7 A2A payload 标准结构

```json
{
  "agent": "coding",
  "payload": {
    "repository": "{owner}/{repo}",
    "account": "{user}",
    "issue_number": {n},
    "pr_number": {pr},
    "context": "skill {name} 上传失败：{摘要}"
  }
}
```

- `issue_number` 必填；`pr_number` 有则必填；`repository` 与 `account` 必填。

---

## 4. 命令限制与不存在的能力

### 命令遮蔽（不可执行）

- `issues list`（遮蔽）→ 用 `git-repo issues list`
- `issues pipeline`（遮蔽）→ 用 `issues pipeline detail`
- `issues status`（遮蔽）→ 用 `issues status get`
- `tasks status`（遮蔽）→ 用 `tasks status get`

### 无 grape api 逃生舱

`grape api` 通用兜底命令已移除。契约未覆盖的端点无法通过 CLI 调用，不要 curl 直连 Grape API。

### 不存在的能力（不要尝试）

任务删除（有 close 非删除）· 知识上传 · Issue/PR 删除 · 分支创建/删除 · Token 管理（CLI 层）· `tasks create`（已移除，用 `issues create`）· `tasks start/status`（已下架/遮蔽）· `tasks mine`（已下架，用 `tasks current`）· `auth profile`（已下架）· 流式输出 · 交互式提示 · 配置初始化。

> ✅ `skills upload`/`skills search`/`skills list`/`skills detail`/`skills convert`/`skills delete` 等均存在且可用。旧文档将其标注为「已下架」为过时信息，以 `grape commands skills` 实际输出为准。

---

## 5. 退出码

| 码 | 含义 |
|----|------|
| 0 | 成功 |
| 1 | 通用/配置错误 |
| 2 | click 用法错误 |
| ≥400 | HTTP 透传（403 = token 作用域不足；422 = 请求体/ZIP 格式错误） |
| 130 | Ctrl+C |

---

## 6. 安全与边界

- **token 使用范围**：上传/验证、上下文读取用 `$GRAPE_SESSION_TOKEN`；GitCode Issue 评论用 prompt 注入的 `$BOT_TOKEN`。不得从数据库/配置文件/日志/历史寻找其他 token。
- **禁止访问的内部数据路径**：`data/sessions.db`、`user_accounts` 表、`configs/` 目录。
- **token 不写入文件**：不将 token 写进日志、脚本、ZIP、Issue 评论或工具调用以外的地方。
