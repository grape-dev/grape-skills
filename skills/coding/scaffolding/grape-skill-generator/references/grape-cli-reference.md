# grape CLI 命令参考（事实基线完整副本）

> 来源：cli-code-analysis-spec.md（CLI v0.2.8，58 paths / 68 operations）
> 用途：生成 skill 时引用 grape 命令的唯一事实来源，不编造

---

## 1. CLI 总览

| 项 | 内容 |
|----|------|
| 项目用途 | Grape Agentic DevOps 命令行客户端；契约驱动命令生成 + git 本地透传 |
| 语言/框架 | Python ≥3.10 / click ≥8.0 + httpx ≥0.24；入口 `grape` = `src/cli:main` |
| 版本 | `0.2.8`；核心机制：读 `/openapi.json` 按 `operationId` 自动生成命令树 |
| operationId 拆分 | 首段→组名（`gitrepo`→`git-repo`），其余→嵌套动词链 |
| 契约加载 | 本地缓存 > 远端 > 内置快照 `src/data/openapi.json` |
| 认证三通道 | Bearer(默认) / PRIVATE-TOKEN / access_token |
| Token 优先级 | `--token` > `GRAPE_SESSION_TOKEN`(tk_) > `GRAPE_API_TOKEN`(grape_) > config.json |
| base_url 优先级 | `--base-url` > `GRAPE_BASE_URL` > `GRAPE_SERVER_URL` > config.json > `http://localhost:8000` |
| 命令总数 | 68 契约 + 4 内置 = 72；只读 48 / 变更 19 / 异步轮询 1 / 本地透传 1 |
| 帮助分类 | 5 类：Core workflows / Code & repositories / Agent Context / Account & platform / CLI utilities |
| 错误信封 | 新 `{"detail":{"code","message"}}`，兼容旧 `{"message":"..."}` |

---

## 3. 常用命令（全量契约清单，68 操作 + 4 内置）

> 本文件为事实基线完整副本。生成具体 skill 时，从此全量清单中按 agent_type 选取实际用到的命令子集（见 `command-matrix.md`），写入生成物的 grape-cli-reference.md 常用命令章节——**只列该 skill 用到的，不列全量**。

### 3.1 内置命令（4 个）

| 命令 | 用途 | 变更性 |
|------|------|--------|
| `grape refresh` | 强制重新拉取 OpenAPI 契约并缓存，输出版本+路径数+来源 | 只读 |
| `grape commands [pattern]` | 列出全部可调用契约命令（空格分隔，可直接执行），支持 pattern 过滤 | 只读 |
| `grape tasks wait --task-id <id> [--timeout=120] [--interval=3] [--json-out]` | 轮询任务直至终态 | 只读 |
| `grape git <args>` | 本地 git 透传 + 进程内凭据注入（仅 gitcode.com） | 取决于子命令 |

> ⚠️ v0.2.2 移除了 `grape api` 通用兜底命令。契约未覆盖的端点不再有 CLI 逃生舱。

### 3.2 契约驱动命令（68 个操作，按 tag 分组）

> 参数名沿用 openapi.json 原始名称（含下划线如 `task_id`）；内置 wait 用连字符 `--task-id`。

### agents（1）
| 命令 | 方法 | 路径 | 变更性 |
|------|------|------|--------|
| `agents detail --name --owner --repo [--issue_number] [--keyword] [--page=1] [--page_size=10]` | GET | `/api/agents/{name}/{owner}/{repo}` | 只读 |

### auth（1）
| 命令 | 方法 | 路径 | 变更性 |
|------|------|------|--------|
| `auth profile get` | GET | `/api/auth/profile` | 只读 |

### chat（2）
| 命令 | 方法 | 路径 | 变更性 |
|------|------|------|--------|
| `chat conversations [--repo_key]` | GET | `/api/chat/conversations` | 只读 |
| `chat messages --conv_id [--before=0]` | GET | `/api/chat/messages/{conv_id}` | 只读 |

### events（1）
| 命令 | 方法 | 路径 | 变更性 |
|------|------|------|--------|
| `events detail --seq` | GET | `/api/events/detail/{seq}` | 只读 |

### git-repo（23）— 平台 Git 仓库 API
> v0.2.x 路径前缀 `/api/git-repo/`。`--provider` 已移除。

| 命令 | 方法 | 路径 | 变更性 |
|------|------|------|--------|
| `git-repo repo --owner --repo` | GET | `/api/git-repo/{owner}/{repo}` | 只读 |
| `git-repo branches --owner --repo [--per_page=50]` | GET | `/api/git-repo/{owner}/{repo}/branches` | 只读 |
| `git-repo commits --owner --repo [--per_page=20]` | GET | `/api/git-repo/{owner}/{repo}/commits` | 只读 |
| `git-repo contents --owner --repo --path [--ref] [--raw]` | GET | `/api/git-repo/{owner}/{repo}/contents/{path}` | 只读 |
| `git-repo contents root --owner --repo [--ref]` | GET | `/api/git-repo/{owner}/{repo}/contents` | 只读 |
| `git-repo tree --owner --repo [--ref] [--depth=single]` | GET | `/api/git-repo/{owner}/{repo}/tree` | 只读 |
| `git-repo labels list --owner --repo` | GET | `/api/git-repo/{owner}/{repo}/labels` | 只读 |
| `git-repo labels create --owner --repo --json` | POST | `/api/git-repo/{owner}/{repo}/labels` | **变更** |
| `git-repo milestones --owner --repo [--state=all]` | GET | `/api/git-repo/{owner}/{repo}/milestones` | 只读 |
| `git-repo issues list --owner --repo [--state=open] [--page=1] [--per_page=50]` | GET | `/api/git-repo/{owner}/{repo}/issues` | 只读 |
| `git-repo issues create --owner --repo --json` | POST | `/api/git-repo/{owner}/{repo}/issues` | **变更** |
| `git-repo issues get --owner --repo --number` | GET | `/api/git-repo/{owner}/{repo}/issues/{number}` | 只读 |
| `git-repo issues update --owner --repo --number --json` | PATCH | `/api/git-repo/{owner}/{repo}/issues/{number}` | **变更** |
| `git-repo issues comments list --owner --repo --number` | GET | `/api/git-repo/{owner}/{repo}/issues/{number}/comments` | 只读 |
| `git-repo issues comments create --owner --repo --number --json` | POST | `/api/git-repo/{owner}/{repo}/issues/{number}/comments` | **变更** |
| `git-repo pulls list --owner --repo [--state=open] [--page=1] [--per_page=50]` | GET | `/api/git-repo/{owner}/{repo}/pulls` | 只读 |
| `git-repo pulls create --owner --repo --json` | POST | `/api/git-repo/{owner}/{repo}/pulls` | **变更** |
| `git-repo pulls get --owner --repo --number` | GET | `/api/git-repo/{owner}/{repo}/pulls/{number}` | 只读 |
| `git-repo pulls update --owner --repo --number --json` | PATCH | `/api/git-repo/{owner}/{repo}/pulls/{number}` | **变更** |
| `git-repo pulls merge --owner --repo --number` | PUT | `/api/git-repo/{owner}/{repo}/pulls/{number}/merge` | **变更** |
| `git-repo pulls comments list --owner --repo --number` | GET | `/api/git-repo/{owner}/{repo}/pulls/{number}/comments` | 只读 |
| `git-repo pulls comments create --owner --repo --number --json` | POST | `/api/git-repo/{owner}/{repo}/pulls/{number}/comments` | **变更** |
| `git-repo pulls files --owner --repo --number` | GET | `/api/git-repo/{owner}/{repo}/pulls/{number}/files` | 只读 |

### issues（5）— Issue 对外接口
> `tasks create` 已移除，`issues create` 为唯一创建入口。

| 命令 | 方法 | 路径 | 变更性 |
|------|------|------|--------|
| `issues list --owner --repo` | GET | `/api/issues/{owner}/{repo}` | 只读 |
| `issues create --owner --repo --json` | POST | `/api/issues/{owner}/{repo}` | **变更** |
| `issues detail --owner --repo --number` | GET | `/api/issues/{owner}/{repo}/{number}` | 只读 |
| `issues events --owner --repo --number` | GET | `/api/issues/{owner}/{repo}/{number}/events` | 只读 |
| `issues pipeline --owner --repo --number` | GET | `/api/issues/{owner}/{repo}/{number}/pipeline` | 只读 |

### knowledge（5）
| 命令 | 方法 | 路径 | 变更性 |
|------|------|------|--------|
| `knowledge list [--repo] [--source] [--page=1] [--page_size=50] [--show_archived=False] [--sort] [--q]` | GET | `/api/knowledge` | 只读 |
| `knowledge detail --knowledge_id` | GET | `/api/knowledge/{knowledge_id}` | 只读 |
| `knowledge content [--repo] [--file] [--obs_key]` | GET | `/api/knowledge/content` | 只读 |
| `knowledge context [--repo] [--agent_type] [--issue_num=0] [--scene_id]` | GET | `/api/knowledge/context` | 只读 |
| `knowledge stats [--repo]` | GET | `/api/knowledge/stats` | 只读 |

### repos（5）
| 命令 | 方法 | 路径 | 变更性 |
|------|------|------|--------|
| `repos member` | GET | `/api/repos/member` | 只读 |
| `repos managed` | GET | `/api/repos/managed` | 只读 |
| `repos deploy url --owner --repo_name` | GET | `/api/repos/deploy-url/{owner}/{repo_name}` | 只读 |
| `repos git credential --owner --repo` | GET | `/api/repos/{owner}/{repo}/git-credential` | 只读 |
| `repos workspace --owner --repo` | GET | `/api/repos/{owner}/{repo}/workspace` | 只读 |

### scenes（1）
| 命令 | 方法 | 路径 | 变更性 |
|------|------|------|--------|
| `scenes list [--repo]` | GET | `/api/scenes` | 只读 |

### skills（13）
> v0.2.6 新增，含 multipart 上传（`--file`）。

| 命令 | 方法 | 路径 | 变更性 |
|------|------|------|--------|
| `skills list [--repo] [--scope] [--q] [--sort] [--page=1] [--page_size=0]` | GET | `/api/skills` | 只读 |
| `skills detail --skill_id [--repo]` | GET | `/api/skills/by-id/{skill_id}` | 只读 |
| `skills search [--q] [--repo] [--page=1] [--page_size=20]` | GET | `/api/skills/search` | 只读 |
| `skills stats [--repo]` | GET | `/api/skills/stats` | 只读 |
| `skills featured [--repo] [--page=1] [--page_size=20]` | GET | `/api/skills/featured` | 只读 |
| `skills upload --file <path> [--json]` | POST | `/api/skills/upload` | **变更** |
| `skills convert --json` | POST | `/api/skills/convert` | **变更** |
| `skills delete --skill_id` | DELETE | `/api/skills/by-id/{skill_id}` | **变更** |
| `skills download --skill_id` | GET | `/api/skills/by-id/{skill_id}/download` | 只读 |
| `skills like --skill_id --json` | POST | `/api/skills/{skill_id}/like` | **变更** |
| `skills sub list --skill_id` | GET | `/api/skills/{skill_id}/sub` | 只读 |
| `skills sub read --skill_id --sub_name` | GET | `/api/skills/{skill_id}/sub/{sub_name}` | 只读 |
| `skills sub package --skill_id --pkg_id --sub_name` | GET | `/api/skills/package-sub/{pkg_id}/{sub_name}` | 只读 |

### tasks（10 契约 + 1 内置）
> `tasks create` 已移除，用 `issues create` 代替。

| 命令 | 方法 | 路径 | 变更性 |
|------|------|------|--------|
| `tasks mine [--status] [--repo_key] [--sort_order=desc] [--mode=default] [--created_by_me] [--assignees]` | GET | `/api/tasks/mine` | 只读 |
| `tasks start --task_id` | POST | `/api/tasks/{task_id}/start` | **变更** |
| `tasks status --task_id --json` | PUT | `/api/tasks/{task_id}/status` | **变更** |
| `tasks status get --task_id` | GET | `/api/tasks/{task_id}/status` | 只读（遮蔽） |
| `tasks complete --json` | POST | `/api/tasks/complete` | **变更** |
| `tasks close --json` | POST | `/api/tasks/close` | **变更** |
| `tasks notify --json` | POST | `/api/tasks/notify` | **变更** |
| `tasks clarify --task_id --json` | POST | `/api/tasks/{task_id}/clarify` | **变更** |
| `tasks clarifications --task_id` | GET | `/api/tasks/{task_id}/clarifications` | 只读 |
| `tasks repo all --owner --repo [--status] [--sort_order=desc] [--mode=default] [--assignees]` | GET | `/api/tasks/repo/{owner}/{repo}` | 只读 |
| `tasks wait --task-id [--timeout=120] [--interval=3]` | 内置轮询 | 复用 GET status | 只读 |

> ⚠️ **命令遮蔽**：`tasks status get` 被 `tasks status`(PUT) 遮蔽，CLI **不可执行**。用 `grape tasks wait`。

### webhook/a2a（1）
| 命令 | 方法 | 路径 | 变更性 |
|------|------|------|--------|
| `a2a handoff --json` | POST | `/api/a2a` | **变更** |

---

## 4. requestBody Schema

> 完整 schema 清单见 `spec-reference.md` §5。`issues create` body 为 free-form JSON。
> 关键：`TaskSelfCompleteBody` 可选 `task_id`/`result_text`/`next_step`/`conclusion`/`issue_summary`；`A2AHandoffBody` 可选 `agent`/`payload`。

---

## 5. 参数使用规则

- **path 参数**：必填，下划线名（`--task_id` `--skill_id` `--per_page`）；integer 类型：`--number`/`--task_id`/`--seq`/`--skill_id`
- **内置 wait 参数**：连字符名（`--task-id`）
- **query 参数**：可选，空值自动丢弃；有默认值的可省略
- **requestBody**：`--json '<JSON字符串>'`
- **机器可读输出**：查询命令加 `--json-out`（省 30-50% token）
- **contents 解码**：`--raw` 直接输出解码内容
- **命令验证**：`grape commands | grep <keyword>` 或 `grape <group> <verb> --help`

---

## 6. 限制与不存在的能力

### 命令遮蔽
`grape tasks status get` **不可执行**。查询任务状态用 `grape tasks wait --task-id <id>`。

### 无 grape api 逃生舱
v0.2.2 移除 `grape api`。契约未覆盖的端点无法通过 CLI 调用，不要 curl 直连。

### 不存在的能力（不要尝试）
仓库创建/删除 · 任务删除（有 close 非删除）· 知识上传 · Issue/PR 删除 · 分支创建/删除 · Token 管理 · `tasks create`（已移除用 `issues create`）· 流式输出 · 交互式提示 · 配置初始化

---

## 7. 退出码

`0` 成功 · `1` 通用/配置错误 · `2` click 用法错误 · `≥400` HTTP 透传 · `130` Ctrl+C · git 退出码透传

---

## 8. 环境前提

| 项目 | 说明 |
|------|------|
| grape CLI | worker 包预装，`which grape` 无结果直接报障，不自行安装 |
| `$GRAPE_SESSION_TOKEN` | 服务端注入，任务级临时，`grape` 自动读取，不需手动 export |
| `$GRAPE_SERVER_URL` | 服务端注入，指向 API 地址 |
| `$GRAPE_API_TOKEN` | 用户级 `grape_` token；Account & platform 类命令需要 |
| 执行环境 | worker .venv，有 bash |
| 降级行为 | grape 未安装时直接报障，不 curl 直连 |
