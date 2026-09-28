# grape CLI 命令参考（VOD skill 专用）

> 来源：cli-code-analysis-spec.md（CLI v0.3.2，58 paths / 68 operations）
> 本文件只列 VOD skill 实际用到的命令子集，不列全量 68 个。

---

## 1. 安装与就绪检查

grape CLI 由 worker 包预装。使用前检查：

```bash
which grape          # 验证安装；未装/版本过低 → 按 references/grape-cli-installation.md 自动安装/升级
grape --version      # 确认版本（≥0.3.2）
```

> ⚠️ grape 未安装时按 references/grape-cli-installation.md 自动安装/升级（不 curl 直连 API）；仍装不上才报障。

---

## 2. 认证与配置

| 项 | 说明 |
|----|------|
| `$GRAPE_SESSION_TOKEN` | 服务端注入，任务级临时 token（`tk_` 前缀），`grape` 自动读取，不需手动 export |
| `$GRAPE_SERVER_URL` | 服务端注入，指向 API 地址 |
| Token 优先级 | `--token` > `GRAPE_SESSION_TOKEN` > `GRAPE_API_TOKEN` > config.json |
| base_url 优先级 | `--base-url` > `GRAPE_BASE_URL` > `GRAPE_SERVER_URL` > config.json > `http://localhost:8000` |

---

## 3. 常用命令（VOD 实际用到的子集）

### 3.1 任务上下文读取（共用）

| 命令 | 用途 |
|------|------|
| `grape tasks current --json-out` | 获取分配给自己的任务 |
| `grape issues detail --owner {owner} --repo {repo} --number {n} --json-out` | Issue 全貌（含阶段/事件/pipeline） |
| `grape issues clarify --issue_id {id} --json '{"message":"..."}'` | 向上游提问（回复 Issue 澄清） |
| `grape commands [pattern]` | 列出可调用命令（命令发现） |

### 3.2 知识与项目上下文

| 项目 | 说明 |
|------|------|
| 项目知识基线 | **由 prompt 内联注入**（平台服务端维护，Agent 不自取/不自行生成）——需全文读 prompt 标注的 project-info/ 路径 |
| ❌ 不存在的命令 | `knowledge context` / `knowledge content` 契约不存在（`grape knowledge --help` 无此子命令）——不要尝试 |

### 3.3 Issue 操作

| 命令 | 用途 |
|------|------|
| `grape issues mine --json-out` | 我的 Issue 列表（判断重复/已解决） |
| `grape issues create --owner {owner} --repo {repo} --json '{"title":"...","description":"..."}'` | 创建 Issue（反馈转 Issue） |
| `grape issues pipeline --owner {owner} --repo {repo} --number {n} --json-out` | Issue pipeline（防重复 A2A 检查） |

### 3.4 GitCode Issue 评论与更新

> VOD 建 Issue 使用统一入口 `grape issues create`（§3.3），该命令同时创建 GitCode Issue 并触发 pipeline；`grape git-repo issues create` 仅创建 GitCode Issue 不触发 pipeline，VOD 不使用，列出供完整性参考。

| 命令 | 用途 |
|------|------|
| `grape git-repo issues list --owner {owner} --repo {repo} --json-out` | 原始 Issue 列表 |
| `grape git-repo issues create --owner {owner} --repo {repo} --json '{"title":"...","body":"..."}'` | 仅创建 GitCode Issue（不触发 pipeline；VOD 用 `issues create` 统一入口代替） |
| `grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"[VOD Agent] ..."}'` | 发评论（澄清/结构化结论） |
| `grape git-repo issues update --owner {owner} --repo {repo} --number {n} --json '{"state":"open"}'` | 更新 Issue（收敛 body/state；标签/分配属 Issue Agent 职责） |

### 3.5 任务完成与 A2A 交接

| 命令 | 用途 |
|------|------|
| `grape tasks complete --json '{"result_text":"...","next_step":"a2a_issue"}'` | 自报完成 |
| `grape a2a handoff --json '{"agent":"issue","payload":{...}}'` | A2A 交棒 Issue Agent |

### 3.6 --json body Schema（VOD 用到的）

| Body schema | 使用命令 | 必填 | 可选 |
|-------------|---------|------|------|
| Free-form JSON | `issues create` | — | `title`, `description`, `assignee`, `scene_id`, `is_subtask_mode`（任意字段） |
| `IssueUpdateBody` | `git-repo issues update` | — | `assignee`, `body`, `labels`, `milestone_id`, `state` |
| `CommentBody` | `git-repo issues comments create` | `body` | — |
| `A2AHandoffBody` | `a2a handoff` | — | `agent`, `payload` |
| `CompleteBody` | `tasks complete` | — | `actions`, `artifacts`, `conclusion`, `issue_summary`, `next_step`, `result_text`, `task_id` |

### 3.7 A2A payload 标准结构

```json
{
  "agent": "issue",
  "payload": {
    "repository": "{owner}/{repo}",
    "account": "{user}",
    "issue_number": {n},
    "context": "{交接说明}"
  }
}
```

- `issue_number` 必填；`pr_number` 有则必填（VOD 通常不涉及 PR）；`repository` 与 `account` 必填。

---

## 4. 命令限制与不存在的能力

### 命令遮蔽

VOD skill 引用的命令子集（§3.1-§3.5）均为可执行 leaf 命令，**无遮蔽**。以下命令经 `grape commands` + `grape <cmd> --help` 动态验证可执行：

| 命令 | 类型 | 验证结果 |
|------|------|---------|
| `grape issues list` | GET | ✅ 可执行（`--owner/--repo/--json-out`） |
| `grape issues pipeline` | GET | ✅ 可执行（`--owner/--repo/--number/--json-out`） |
| `grape issues status` | PUT | ✅ 可执行（`--issue_id/--json`，变更命令） |
| `grape issues clarify` | POST | ✅ 可执行（`--issue_id/--json`） |
| `grape issues mine` | GET | ✅ 可执行（`--json-out`） |
| `grape tasks complete` | POST | ✅ 可执行 |
| `grape tasks current` | GET | ✅ 可执行 |

> ⚠️ **被父级 leaf 命令遮蔽**（空格形式 `grape issues <leaf> <word>` 不返回 `No such command`，而是被父级 leaf 命令吞掉多余参数、显示父命令 help，exit 0）：
> - `grape issues status get` — 被 `grape issues status`（PUT leaf 命令）遮蔽；`--help` 显示 status 帮助而非报错
> - `grape issues pipeline detail` — 被 `grape issues pipeline`（GET leaf 命令）遮蔽；`--help` 显示 pipeline 帮助而非报错
> - `grape issues list attachments` — 被 `grape issues list`（GET leaf 命令）遮蔽；`--help` 显示 list 帮助而非报错

> ⚠️ **不存在的命令**（`grape <cmd> --help` 返回 `No such command`，exit 2，不要引用）：
> - `grape tasks status get` / `grape tasks status` — tasks 组**无** status 子命令（仅 complete/current/notify/wait，实测 No such command）——不要尝试
> - `grape issues status_get` — 不存在（下划线形式，返回 `No such command 'status_get'`；空格形式 `status get` 被遮蔽见上）
> - `grape issues pipeline_detail` — 不存在（下划线形式，返回 `No such command 'pipeline_detail'`；空格形式 `pipeline detail` 被遮蔽见上）
> - `grape issues list_attachments` — 不存在（下划线形式，返回 `No such command 'list_attachments'`；空格形式 `list attachments` 被遮蔽见上）
>
> 注：`grape commands` 列出空格分词的 click 命令名（如 `issues status`），不含下划线形式 operationId；下划线形式（如 `status_get`）不可执行（返回 `No such command`），多词空格形式（如 `status get`）被父 leaf 遮蔽——两者均不可用。

### 无 grape api 逃生舱

v0.2.2 移除 `grape api` 通用兜底命令。契约未覆盖的端点无法通过 CLI 调用，不要 curl 直连。

### 不存在的能力（不要尝试）

任务删除（tasks 组仅 complete/current/notify/wait——无删除命令）· 知识上传 · Issue/PR 删除 · 分支创建/删除 · Token 管理 · `tasks create`（已移除，用 `issues create`）· 流式输出 · 交互式提示 · 配置初始化

> 注：`repos create`/`repos remove`（仓库创建/删除）**已存在**（v0.2.6+），不列为不存在。`skills upload`/`skills delete`/`skills convert` **已存在**，不列为不存在。

---

## 5. 退出码

| 码 | 含义 |
|----|------|
| 0 | 成功 |
| 1 | 通用/配置错误 |
| 2 | click 用法错误 |
| ≥400 | HTTP 透传 |
| 130 | Ctrl+C |

---

## 6. 安全与边界

- **token 使用范围**：只用 `$GRAPE_SESSION_TOKEN`（grape CLI 自动读取）和 prompt 注入的 `$BOT_GITCODE_TOKEN`。不得从数据库、配置文件、日志、历史中寻找其他 token。
- **禁止访问的内部数据路径**：`data/sessions.db`、`user_accounts` 表、`managed_repos` 表、`configs/` 目录（含 `global-bot-token.json` 等）。`data/workspaces/` 项目知识文档除外。
- **403/401 处理**：API 返回 403 或权限不足时，停止操作并回复「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」，不尝试其他 token 或绕行手段。
- **token 不写入文件**：不将 token 写进日志、脚本、Issue 评论或工具调用以外的地方。
