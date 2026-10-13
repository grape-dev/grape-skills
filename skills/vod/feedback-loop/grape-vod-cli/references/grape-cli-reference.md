# grape CLI 命令参考（VOD skill 专用）

> 来源：cli-code-analysis-spec.md（CLI v0.3.2，58 paths / 68 operations）
> 本文件只列 VOD skill 实际用到的命令子集，不列全量 68 个。

---

## 1. 安装与就绪检查

grape CLI 由 worker 包预装。使用前检查：

```bash
which grape          # 验证安装，无结果直接报障，不自行安装
grape --version      # 确认版本
```

> ⚠️ grape 未安装时直接报障，不 curl 直连 API。

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
| `grape events detail --seq {seq} --json-out` | 读取前序 A2A 交接 payload |
| `grape issues clarify --issue_id ${GRAPE_ISSUE_ID:-{id}} --json '{"message":"..."}'` | 向上游提问（--issue_id 优先用注入的 `$GRAPE_ISSUE_ID`） |
| `grape commands [pattern]` | 列出可调用命令（命令发现） |

### 3.2 知识与项目上下文

| 命令 | 用途 |
|------|------|
| `grape repos project info --owner {owner} --repo {repo} --json-out` | 项目知识基线：project-graph.md + project-capabilities.md 全文 + meta（degraded/commit/branches） |
| `grape knowledge stats --repo {owner}/{repo} --json-out` | 各类知识数量，判断是否有沉淀 |
| `grape knowledge list --repo {owner}/{repo} --source agent --json-out` | Agent 沉淀知识清单（前序经验） |
| `grape knowledge list --repo {owner}/{repo} --source system --json-out` | 系统注入说明文档清单 |
| `grape knowledge detail --knowledge_id {id} --json-out` | 读取单条知识全文 |

### 3.3 Issue 操作

| 命令 | 用途 |
|------|------|
| `grape issues pipeline --owner {owner} --repo {repo} --number {n} --json-out` | Issue pipeline（防重复 A2A 检查） |
| `grape issues list --owner {owner} --repo {repo} --json-out` | Issue 列表（历史全貌/判断重复） |
| `grape issues awaiting-input --issue_id {issue_id} --json '{"questions":"...","reason":"..."}' --json-out` | 澄清时显式声明待用户补充（置 awaiting_input + 触达；vod/issue 会话可用，changed:true=成功）。`--issue_id` 用注入的 `$GRAPE_ISSUE_ID`（未注入降级 `issues detail` 的 `id`），非 ISSUE_NUMBER |

### 3.4 GitCode Issue 评论与更新

> 本技能接管 `issue_opened`（开发者提交的 Issue），不建 Issue；结构化收敛结论**以评论发布**（`issues comments create`），**不用 `issues update` 改写 body**（防覆盖原始描述）。

| 命令 | 用途 |
|------|------|
| `grape git-repo issues list --owner {owner} --repo {repo} --json-out` | 原始 Issue 列表 |
| `grape git-repo issues comments list --owner {owner} --repo {repo} --number {n} --json-out` | 读评论（理解讨论过程） |
| `grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"[VOD Agent] ..."}'` | 发评论（澄清/结构化收敛结论） |
| `grape git-repo issues update --owner {owner} --repo {repo} --number {n} --json '{"state":"close"}'` | 仅用于关闭/状态（**不传 body**，改 body 会覆盖原始描述） |

### 3.5 任务完成与 A2A 交接

| 命令 | 用途 |
|------|------|
| `grape tasks complete --json '{"result_text":"...","next_step":"a2a_issue"}'` | 自报完成 |
| `grape a2a handoff --json '{"agent":"issue","payload":{...}}'` | A2A 交棒 issue agent（非技能名） |

### 3.5.1 技能资产查询（技能创建需求引导用）

| 命令 | 用途 |
|------|------|
| `grape skills list --json-out` | 平台技能清单（命名查重 / 改造定位）；403/不存在则跳过，用仓库 `skills/` 目录查重 |
| `grape git-repo tree --owner {owner} --repo {repo} --depth single --json-out` | 仓库目录树（看是否已有 skills/ 子目录） |

### 3.6 --json body Schema（VOD 用到的）

| Body schema | 使用命令 | 必填 | 可选 |
|-------------|---------|------|------|
| `CommentBody` | `git-repo issues comments create` | `body` | — |
| `IssueUpdateBody` | `git-repo issues update` | — | `assignee`, `labels`, `milestone_id`, `state`（**不含 body**：改 body 会覆盖原始描述，收敛结论用 comments） |
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
> - `grape tasks clarify` — 不存在；向上游提问用 `grape issues clarify --issue_id {id} --json '{"message":"..."}'`
> - `grape tasks status` / `grape tasks status get` — 不存在（`grape tasks` 子命令仅 `complete/current/notify/wait`）
> - `grape issues status_get` — 不存在（下划线形式，返回 `No such command 'status_get'`；空格形式 `status get` 被遮蔽见上）
> - `grape issues pipeline_detail` — 不存在（下划线形式，返回 `No such command 'pipeline_detail'`；空格形式 `pipeline detail` 被遮蔽见上）
> - `grape issues list_attachments` — 不存在（下划线形式，返回 `No such command 'list_attachments'`；空格形式 `list attachments` 被遮蔽见上）
>
> 注：`grape commands` 列出空格分词的 click 命令名（如 `issues status`），不含下划线形式 operationId；下划线形式（如 `status_get`）不可执行（返回 `No such command`），多词空格形式（如 `status get`）被父 leaf 遮蔽——两者均不可用。

### 无 grape api 逃生舱

v0.2.2 移除 `grape api` 通用兜底命令。契约未覆盖的端点无法通过 CLI 调用，不要 curl 直连。

### 不存在的能力（不要尝试）

任务删除（有 close 非删除）· 知识上传 · Issue/PR 删除 · 分支创建/删除 · Token 管理 · 流式输出 · 交互式提示 · 配置初始化

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

- **token 使用范围**：只用 `$GRAPE_SESSION_TOKEN`（grape CLI 自动读取）。不得从数据库、配置文件、日志、历史中寻找其他 token。
- **禁止访问的内部数据路径**：`data/sessions.db`、`user_accounts` 表、`managed_repos` 表、`configs/` 目录（含 `global-bot-token.json` 等）。`data/workspaces/` 项目知识文档除外。
- **403/401 处理**：API 返回 403 或权限不足时，停止操作并回复「该操作需要管理员/维护者权限，请在 仓库设置中手动配置后重试」，不尝试其他 token 或绕行手段。
- **token 不写入文件**：不将 token 写进日志、脚本、Issue 评论或工具调用以外的地方。
