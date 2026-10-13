# grape CLI 命令参考（skill-issue skill）

> 事实来源：grape CLI 契约 v2.1.0。运行时以 `grape commands` 和 `grape <group> <verb> --help` 实际输出为准。
> 命令清单只列本 skill 实际用到的，不列全量命令。
> skill-issue 特有：skill 路由（下架→sre、创建/生成→coding）通过 A2A 交办，无专属 CLI 命令。

---

## 1. 安装与就绪检查

`grape` 通常由运维/部署侧预装；**未装/版本过低可自行安装**（见 `references/grape-cli-installation.md`）。使用前验证：

```bash
grape --version    # 确认安装（应 >= 0.3.2）
grape commands     # 验证命令树可用
```

- `which grape` 无结果 → 直接回复「当前执行环境未安装 grape CLI」，**不要**自行安装，也**不要**改用 curl 直连。
- 401 报错说明 `$GRAPE_SESSION_TOKEN` 已失效（任务级临时 token）。

---

## 2. 认证与配置

- `$GRAPE_SESSION_TOKEN`（`tk_` 前缀）服务端自动注入，不需手动 export。
- `$GRAPE_SERVER_URL` 服务端注入，自动回退。
- Token 优先级：`--token` > `GRAPE_SESSION_TOKEN`（tk_）> `GRAPE_API_TOKEN`（grape_）> config.json。
- Token scope 分类：
  - `session_only`：仅 `tk_` 可用（git-repo 全部、tasks current、tasks notify）
  - `dual`：`tk_` 和 `grape_` 均可（issues detail/events/list、tasks complete、a2a handoff）
  - `user_only`：仅 `grape_`/JWT（issues create/start/cancel/clarify、issues mine）

---

## 3. 常用命令

### 任务与上下文读取

```bash
grape tasks current --json-out                                          # 当前任务详情
grape issues detail --owner {owner} --repo {repo} --number {n} --json-out   # Issue 全貌（含阶段+事件+pipeline）
grape issues events --owner {owner} --repo {repo} --number {n} --json-out    # Issue 事件流
grape issues pipeline --owner {owner} --repo {repo} --number {n} --json-out  # Issue 路线图（查重复 A2A）
grape events detail --seq {seq} --json-out                              # 读取 A2A 交接 payload
grape issues clarify --issue_id ${GRAPE_ISSUE_ID:-{issue_id}} --json '{"message":"..."}'  # 向上游提问（--issue_id 优先用注入的 $GRAPE_ISSUE_ID，未注入才从 issues detail 的 id 取）
```

### GitCode Issue 操作

```bash
grape git-repo issues get --owner {owner} --repo {repo} --number {n} --json-out
grape git-repo issues list --owner {owner} --repo {repo} --json-out
grape git-repo issues comments list --owner {owner} --repo {repo} --number {n} --json-out
grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"..."}'
grape git-repo issues update --owner {owner} --repo {repo} --number {n} --json '{"labels":"bug,triaged","assignee":"{user}","state":"close"}'
grape git-repo issues create --owner {owner} --repo {repo} --json '{"title":"...","body":"...","assignee":"{user}"}'
```

### 标签操作

```bash
grape git-repo labels list --owner {owner} --repo {repo} --json-out
grape git-repo labels create --owner {owner} --repo {repo} --json '{"name":"bug","color":"#d73a4a"}'
```

### 仓库信息（检查已实现/读取文件）

```bash
grape git-repo commits --owner {owner} --repo {repo} --json-out           # 提交历史（检查是否已实现）
grape git-repo branches --owner {owner} --repo {repo} --json-out          # 分支列表
grape git-repo contents --owner {owner} --repo {repo} --path CODEOWNERS --ref codeowner --json-out  # 读取 CODEOWNERS（content 字段为 base64，需解码）
grape git-repo repo --owner {owner} --repo {repo} --json-out             # 仓库信息
```

### 任务通知与 A2A 交接

```bash
grape tasks notify --json '{"assignee":"'"$BOT_USERNAME"'","repo_key":"{owner}/{repo}","issue_number":{n},"task_description":"..."}'
grape tasks complete --json '{"result_text":"...","next_step":"a2a_coding","actions":[],"conclusion":"","artifacts":[],"issue_summary":""}'
grape a2a handoff --json '{"agent":"coding","payload":{"repository":"{owner}/{repo}","account":"{user}","issue_number":{n},"context":"..."}}'
```

> `grape a2a handoff` 交办的是 **agent**（`coding`/`sre`/`vod`），不是技能；对应 agent 使用哪个技能由该 agent 自行决定。路由：创建/改造→`coding`；下架→`sre`；需求不清→`vod`。

> `grape tasks create`（创建任务+自动开 Issue）与 `grape issues create`（仅创建 Issue）不同；issue agent 一般用 `issues create`。

### 平台 Issue 视图（阶段/状态聚合）

```bash
grape issues create --owner {owner} --repo {repo} --json '{"title":"...","description":"...","assignee":"{user}"}'  # 创建 Issue（user_only scope）
```

> `grape issues list` 可直接调用（`--owner`/`--repo`/`--json-out`），返回阶段/状态聚合视图；`grape git-repo issues list` 返回 GitCode 原始 Issue 列表。

### 知识读取

```bash
grape repos project info --owner {owner} --repo {repo} --json-out       # 项目知识基线（project-graph + project-capabilities 全文 + meta）
grape knowledge stats --repo {owner}/{repo} --json-out                  # 各类知识数量
grape knowledge list --repo {owner}/{repo} --source agent --json-out    # Agent 沉淀知识清单
grape knowledge detail --knowledge_id {id} --json-out                    # 读取单条知识全文
```

### 技能资产（技能开发需求判断用）

```bash
grape skills list --json-out 2>/dev/null          # 平台技能清单（命名查重）；403/不存在则跳过
grape git-repo tree --owner {owner} --repo {repo} --depth single --json-out   # 仓库 skills/ 目录
grape git-repo contents --owner {owner} --repo {repo} --path skills --json-out
```

### 命令发现

```bash
grape commands [pattern]    # 列出可调用命令（不要用 | grep）
grape <group> <verb> --help # 查参数/Body fields/Token scope
grape refresh               # 重拉最新契约
```

---

## 4. 命令限制与不存在的能力

### 命令遮蔽（被命令树吞掉，不可执行）

以下父命令因存在同前缀子命令，被命令树作为父组吞掉，不可直接调用（以 `grape commands` 实际可调用为准）：

> 经 `grape commands` + `grape <group> <verb> --help` 动态验证（CLI v0.3.2），`issues list`、`issues pipeline`、`issues status`、`git-repo contents` 均可直接调用，**不构成遮蔽**。声称的子命令 `issues list attachments`、`issues pipeline detail`、`issues status get`、`git-repo contents root` 均不存在。当前无被遮蔽的命令。

### 可直接调用的命令（常被误标为遮蔽）

以下命令经动态验证可直接调用，参数以 `--help` 输出为准：

| 命令 | 参数 | 说明 |
|------|------|------|
| `grape issues list` | `--owner` `--repo` `--status` `--sort_order` `--mode` `--assignees` `--json-out` | Issue 列表（阶段/状态聚合） |
| `grape issues pipeline` | `--owner` `--repo` `--number` `--json-out` | Issue 路线图（查重复 A2A） |
| `grape issues status` | `--issue_id` `--json '{\"status\":\"...\"}'` `--json-out` | 更新 Issue 状态（user_only） |
| `grape git-repo contents` | `--owner` `--repo` `--path` `--ref` `--json-out` `--raw` | 仓库文件/目录内容 |

### 无 grape api 逃生舱

`grape api` 通用兜底命令已移除（v0.2.2）。契约未覆盖端点无 CLI 逃生舱，无法通过 CLI 调用。

### 不存在能力清单

以下能力在 CLI 命令树中不存在（最终判据：`grape commands` 未列出的即不存在）：

| 能力 | 说明 |
|------|------|
| `grape api` 逃生舱 | 已移除，契约未覆盖端点无法 CLI 调用 |
| 仓库删除 | 无 CLI 子命令（`repos remove` 仅移除 hosting，不删除仓库本身；`repos create` 存在可创建仓库） |
| Issue/PR 删除 | 无 CLI 子命令 |
| 分支创建/删除 | 无 CLI 子命令 |
| Token 管理（CLI 层） | 无 CLI 子命令创建/吊销/刷新 token |
| `tasks start`（PUT） | 已下架 |
| `auth profile` | 已下架 |
| `skills search`/`skills upload` | 已下架（user_only） |
| 流式输出 | 契约有 stream 端点但非命令行流式 |
| 交互式提示 | 缺 token 直接报错，无 prompt |

> ⚠️ `skills convert` 和 `skills delete` 正常可用（user_only，需 `GRAPE_API_TOKEN`），不列为已下架。旧文档将其标注为已下架为过时信息，以 `grape commands skills` 实际输出为准。

### --json body 字段约束

只用 `grape <group> <verb> --help` 的 Body fields 列出的字段，不编造。常用 schema：

| Body schema | 使用命令 | 必填 | 可选 |
|-------------|---------|------|------|
| `CommentBody` | git-repo issues/pulls comments create | `body` | — |
| `IssueUpdateBody` | git-repo issues update | — | `labels`, `assignee`, `milestone_id`, `state` |
| `LabelCreateBody` | git-repo labels create | `name` | `color` |
| `ProgressBody` | tasks notify | — | `assignee`, `issue_number`, `repo_key`, `task_description` |
| `CompleteBody` | tasks complete | — | `result_text`, `next_step`, `task_id`, `actions`, `artifacts`, `conclusion`, `issue_summary` |
| `A2AHandoffBody` | a2a handoff | — | `agent`, `payload` |
| `ClarifyBody` | issues clarify | — | `message` |
| Free-form JSON | issues create | — | `title`, `description`, `assignee`, `scene_id`, `is_subtask_mode`（任意字段） |

### 参数命名规则

- path 参数名随 OpenAPI 契约（path 变量名）：`--number` `--seq` `--issue_id` `--task_id`
- wait 参数用连字符名：`--task-id` `--timeout` `--interval`
- integer 类型：`--number`/`--task_id`/`--seq` 传数字值
- 占位符统一花括号：`{owner}` `{repo}` `{n}`

---

## 5. 退出码

| 退出码 | 含义 |
|--------|------|
| 0 | 成功 |
| 1 | 通用错误 |
| 2 | 用法错误 |
| ≥400 | HTTP 状态码透传 |
| 130 | Ctrl+C 中断 |

---

## 6. 安全与边界

- **token 使用范围**：只用 `$GRAPE_SESSION_TOKEN`（会话级 `tk_`）。`user_only` 端点（auth/skills 等）对 `tk_` 返回 403，需 `GRAPE_API_TOKEN`（`grape_`）或 Web JWT——本技能一般用不到。
- **禁止访问的内部数据路径**：`data/sessions.db`、`configs/`、`user_accounts` 表、`managed_repos` 表——不得读取。
- **403/401 处理**：
  - 403（无权限）→ 立即停止该操作，回复用户「该操作需要管理员/维护者权限，请在 仓库设置中手动配置」。
  - 401（token 失效）→ token 已过期，说明「凭据已失效」即可，不尝试替换。
- **`git-repo issues update` 为整体覆盖语义**：只传 labels/assignee/state 会重置未传字段（可能覆盖 body）。**先 `git-repo issues get` 回填原始 body 再 update**；Spec/结论等正文一律用 `issues comments create` 发布。
- **token 不落盘**：不得将 token 写入文件、日志、评论或脚本。
