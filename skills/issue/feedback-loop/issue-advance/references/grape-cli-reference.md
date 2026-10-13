# grape CLI 命令参考（issue-advance skill 专用）

> 来源：cli-code-analysis-spec.md（CLI v0.3.x，216 条契约经 `grape commands` 核对）
> 本文件只列 issue-advance skill 实际用到的命令子集，不列全量。

---

## 1. 安装与就绪检查

grape CLI 由 worker 包预装。使用前检查：

```bash
which grape          # 验证安装
grape --version      # 确认版本
```

> ⚠️ grape 未安装/版本 < 0.3.2 → 按 `references/grape-cli-installation.md` **自动安装/升级**（pip 直装），装好再验证一次；仍不可用 → 输出「前置检查未通过：<原因>」并结束任务（不 curl 直连 API）。

---

## 2. 认证与配置

| 项 | 说明 |
|----|------|
| `$GRAPE_SESSION_TOKEN` | 服务端注入，任务级临时 token（`tk_` 前缀），`grape` 自动读取，不需手动 export |
| `$GRAPE_SERVER_URL` | 服务端注入，指向 API 地址 |
| Token 优先级 | `--token` > `GRAPE_SESSION_TOKEN` > `GRAPE_API_TOKEN` > config.json |
| base_url 优先级 | `--base-url` > `GRAPE_BASE_URL` > `GRAPE_SERVER_URL` > config.json > `http://localhost:8000` |

---

## 3. 常用命令（issue-advance 实际用到的子集）

### 3.1 任务上下文读取（共用，执行前必做）

| 命令 | 用途 |
|------|------|
| `grape tasks current --json-out` | 获取分配给自己的任务（执行前必读） |
| `grape issues detail --owner {owner} --repo {repo} --number {n} --json-out` | Issue 全貌（含 stage/事件/pipeline，执行前必读） |
| `grape issues events --owner {owner} --repo {repo} --number {n} --json-out` | Issue 事件历史（读 Session 历史，防重复分析） |
| `grape issues pipeline --owner {owner} --repo {repo} --number {n} --json-out` | Issue pipeline（防重复 A2A 检查） |
| `grape commands [pattern]` | 列出可调用命令（命令发现） |

### 3.2 知识与项目上下文

| 命令 | 用途 |
|------|------|
| `grape knowledge context --repo {owner}/{repo} --agent_type issue --json-out` | 合并注入上下文（项目知识基线等） |
| `grape knowledge content --repo {owner}/{repo} --file {path} --json-out` | 读取知识文件全文 |

### 3.3 GitCode Issue 读取

| 命令 | 用途 |
|------|------|
| `grape git-repo issues get --owner {owner} --repo {repo} --number {n} --json-out` | 单 Issue 原始信息（标签/负责人/状态/里程碑） |
| `grape git-repo issues list --owner {owner} --repo {repo} --state open --json-out` | Issue 列表（重复检查） |
| `grape git-repo issues comments list --owner {owner} --repo {repo} --number {n} --json-out` | Issue 全部评论 |

### 3.4 GitCode Issue 写操作

| 命令 | 用途 |
|------|------|
| `grape git-repo issues update --owner {owner} --repo {repo} --number {n} --json '{"labels":"...","assignee":"...","state":"...","milestone_id":...}'` | 更新 Issue（标签/分配/状态/里程碑/body） |
| `grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"[issue agent] ..."}'` | 发评论（答复/Spec 发布） |
| `grape git-repo labels list --owner {owner} --repo {repo} --json-out` | 仓库标签列表 |
| `grape git-repo labels create --owner {owner} --repo {repo} --json '{"name":"...","color":"..."}'` | 创建标签（不存在时先创建） |

### 3.5 仓库信息读取（知识/分析/关闭建议）

| 命令 | 用途 |
|------|------|
| `grape git-repo contents --owner {owner} --repo {repo} --path CODEOWNERS --ref codeowner --json-out` | 读取 CODEOWNERS（分配依据；base64 需解码） |
| `grape git-repo commits --owner {owner} --repo {repo} --per_page 20 --json-out` | 提交历史（关闭建议：是否已实现） |
| `grape git-repo pulls list --owner {owner} --repo {repo} --state all --json-out` | PR 列表（外部 claim 核对） |
| `grape git-repo branches --owner {owner} --repo {repo} --json-out` | 分支列表（降级分析用） |

### 3.6 任务通知与关闭（分配/关闭后必做）

| 命令 | 用途 |
|------|------|
| `grape tasks notify --json '{"assignee":"...","repo_key":"{owner}/{repo}","issue_number":{n},"task_description":"..."}'` | 任务上报/重派（处理结束、责任人确定后必做；接口幂等） |
| `grape tasks close --json '{"repo_key":"{owner}/{repo}","issue_number":{n}}'` | 关闭 Issue 的任务（关闭 Issue 后必做） |

### 3.7 任务完成与 A2A 交接

| 命令 | 用途 |
|------|------|
| `grape tasks complete --json '{"result_text":"...","next_step":"..."}'` | 自报完成（收尾必做） |
| `grape a2a handoff --json '{"agent":"coding","payload":{...}}'` | A2A 交棒 coding/qa/sre/vod Agent |

### 3.8 --json body Schema（issue-advance 用到的）

| Body schema | 使用命令 | 必填 | 可选 |
|-------------|---------|------|------|
| `IssueUpdateBody` | `git-repo issues update` | — | `assignee`, `body`, `labels`, `milestone_id`, `state` |
| `CommentBody` | `git-repo issues comments create` | `body` | — |
| `LabelCreateBody` | `git-repo labels create` | — | `name`, `color` |
| `NotifyBody` | `tasks notify` | — | `assignee`, `issue_number`, `repo_key`, `task_description` |
| `CloseBody` | `tasks close` | — | `issue_number`, `repo_key` |
| `A2AHandoffBody` | `a2a handoff` | — | `agent`, `payload` |
| `CompleteBody` | `tasks complete` | — | `actions`, `artifacts`, `conclusion`, `issue_summary`, `next_step`, `result_text`, `task_id` |

### 3.9 A2A payload 标准结构

```json
{
  "agent": "coding",
  "payload": {
    "repository": "{owner}/{repo}",
    "account": "{user}",
    "issue_number": {n},
    "pr_number": {pn},
    "context": "{交接说明}"
  }
}
```

- `issue_number` 必填；无法确定则不调用 A2A，评论说明。`pr_number` 有则必填、无则不填，严禁混用。

---

## 4. 命令限制与不存在的能力

### 命令遮蔽

issue-advance 引用的命令子集（§3.1-§3.7）均为可执行 leaf 命令，**无遮蔽**。经 `grape commands`（216 条契约）+ `grape <cmd> --help` 动态验证可执行。

> ⚠️ **空格多词形式被父级 leaf 命令遮蔽**：如 `grape issues status get` 被 `grape issues status`（PUT leaf）吞掉多余参数；使用本文件 §3 列出的带参形式即可。

### 无 grape api 逃生舱

CLI 移除 `grape api` 通用兜底命令。契约未覆盖的端点无法通过 CLI 调用，不要 curl 直连。

### 不存在的能力（不要尝试）

任务删除（有 close 非删除）· 知识上传 · Issue/PR 删除 · 分支创建/删除 · Token 管理 · `tasks create`（已移除，用 `issues create`）· 流式输出 · 交互式提示 · 配置初始化

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
- **403/401 处理**：API 返回 403 或权限不足时，停止操作并回复「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」，不尝试其他 token 或绕行手段。
- **token 不写入文件**：不将 token 写进日志、脚本、Issue 评论或工具调用以外的地方。