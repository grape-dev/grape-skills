# grape CLI 命令参考（skill-uploader 专用）

> 来源：基于 grape-cli 契约（以 `grape commands` / `grape <group> <verb> --help` 实际输出为准）
> 本文件只列 skill-uploader 实际用到的命令子集，不列全量命令。

---

## 1. 安装与就绪检查

`grape` 通常预装；**未装/版本过低可自行安装**（见 `references/grape-cli-installation.md`）。使用前检查：

```bash
grape --version    # 确认安装（应 >= 0.3.2）
grape commands     # 验证命令树可用
```

> ⚠️ grape 未安装且无法安装时，输出「任务无法完成的理由」，不 curl 直连 API。401 报错说明 token 失效。

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
| `grape tasks current --json-out` | session_only | 获取当前任务（含前序 A2A context） |
| `grape issues detail --owner {owner} --repo {repo} --number {n} --json-out` | dual | Issue 全貌 |
| `grape events detail --seq {seq} --json-out` | dual | 读取前序 A2A 交接 payload（参数是 `--seq`，不是 `--event_id`） |

### 3.3 PR 状态与变更确认

| 命令 | Scope | 用途 |
|------|-------|------|
| `grape git-repo pulls get --owner {owner} --repo {repo} --number {pr} --json-out` | session_only | PR 详情（合并状态确认，触发点 c） |
| `grape git-repo pulls files --owner {owner} --repo {repo} --number {pr} --json-out` | session_only | PR 变更文件（定位 skill 目录，来源唯一） |

### 3.4 skill 内容获取（仓库直拉，不依赖本地 worktree）

| 命令 | Scope | 用途 |
|------|-------|------|
| `grape git-repo contents --owner {owner} --repo {repo} --path {skill_dir} --json-out` | session_only | 列出 skill 目录下文件清单 |
| `grape git-repo contents --owner {owner} --repo {repo} --path {file} --raw` | session_only | 拉取单个文件原文（SKILL.md / references/{f}）到本地临时目录用于打包 |

### 3.5 GitCode Issue 评论

| 命令 | Scope | 用途 |
|------|-------|------|
| `grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"..."}'` | session_only | 发布上传结果/失败通知 |

### 3.6 任务完成与 A2A 交接

| 命令 | Scope | 用途 |
|------|-------|------|
| `grape tasks complete --json '{"result_text":"...","next_step":"done","actions":[],"conclusion":"...","artifacts":[],"issue_summary":"..."}'` | dual | 自报完成（结构化字段必填） |
| `grape a2a handoff --json '{"agent":"coding","payload":{...}}'` | dual | 内容类失败（422）时回交 Coding 排查 |

### 3.7 --json body Schema（本 skill 用到的）

| Body schema | 使用命令 | 必填 | 可选 |
|-------------|---------|------|------|
| `CommentBody` | `git-repo issues comments create` | `body` | — |
| `A2AHandoffBody` | `a2a handoff` | — | `agent`, `payload` |
| `CompleteBody` | `tasks complete` | — | `task_id`, `result_text`, `next_step`, `conclusion`, `issue_summary`, `actions`, `artifacts` |

> `skills upload` 为 multipart，无 JSON body schema，参数走 `--file`/`--scope`/`--repo`/`--agent_type`。

### 3.8 A2A payload 标准结构

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

> 经 `grape commands` + `grape <group> <verb> --help` 动态验证（CLI v0.3.2），本 skill 用到的 `git-repo pulls get/files`、`git-repo issues comments create`、`git-repo contents`、`tasks current`、`tasks complete`、`a2a handoff`、`skills list/detail/sub list/upload` 均可直接调用，不存在遮蔽。

### 无 grape api 逃生舱

`grape api` 通用兜底命令已移除。契约未覆盖的端点无法通过 CLI 调用，不要 curl 直连 Grape API。

### 不存在的能力（不要尝试）

| 能力 | 说明 |
|------|------|
| 任务删除 | 无 `tasks delete`（有 `tasks close` 但非删除） |
| 知识上传 | 无 `knowledge upload` |
| Issue/PR 删除 | 无 issues delete / pulls delete |
| 分支创建/删除 | 无 branches create / branches delete |
| Token 管理（CLI 层） | 无 CLI 子命令创建/吊销/刷新 token |
| `grape api` 逃生舱 | 已移除，契约未覆盖端点无法 CLI 调用 |
| `tasks create` | 已移除，用 `issues create` 代替 |
| `tasks start/status` | 已下架/遮蔽 |
| 流式输出 / 交互式提示 / 配置初始化 | 不支持 |

> ✅ `skills upload` / `skills list` / `skills detail` / `skills sub list` 均存在且可用（dual，`tk_` 可调），`skills convert`/`skills delete` 为 `user_only`（需 `GRAPE_API_TOKEN`）——本 skill 不用。旧文档将 `skills upload` 标注「已下架」为过时信息，以 `grape commands skills` 实际输出为准。`skills upload` 返回 HTTP 503「OBS 存储未启用」= 服务端配置阻塞，非命令/参数问题。

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

- **token 使用范围**：只用 `$GRAPE_SESSION_TOKEN`（会话级 `tk_`）；`BOT_TOKEN`/`USER_TOKEN` 已不注入。`skills` 相关命令为 dual（`tk_` 可用）；如需 `user_only` 级操作需 `GRAPE_API_TOKEN`（`grape_`）/JWT，本技能一般用不到。
- **禁止访问的内部数据路径**：`data/sessions.db`、`user_accounts` 表、`configs/` 目录。
- **403/401 处理**：403 → 停止并回复「需管理员/维护者权限」；401 → 说明凭据已失效，不换 token。
- **`git-repo issues update` 为整体覆盖语义**：本技能不修改 Issue body，结果用 `git-repo issues comments create` 发布。
- **token 不写入文件**：不将 token 写进日志、脚本、ZIP、Issue 评论或工具调用以外的地方。
