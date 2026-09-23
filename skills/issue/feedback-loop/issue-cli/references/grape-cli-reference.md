# Grape CLI 参考（Issue-CLI 版）

> 本技能**只使用 `grape` CLI**，统一使用系统注入的 **`$GRAPE_SESSION_TOKEN`**（任务级临时，随任务/会话失效）即可操作。
> 详细指南见 `grape-cli-guidance` 技能（命令分组 / token 作用域 / 错误排查 / 反模式），本文件是 Issue 运营实际用到的命令与要点。

## 核心原则（先读）

1. **命令是契约驱动的**：`grape <group> <verb> [--参数]` 由服务端 `/openapi.json`（或内置快照）动态生成。**不确定命令 → 先发现，别猜名字。**
2. **token 决定你能做什么**：`GRAPE_SESSION_TOKEN`（`tk_`）= 会话级，任务环境默认注入，覆盖本技能全部日常操作（workflows / Agent Context / git-repo）。账户/平台管理类（skills/auth/repos-managed…）对 `tk_` 返回 **403**，需 `GRAPE_API_TOKEN`（`grape_`）或 Web JWT——**本技能一般用不到**。
3. **读仓库用 `git-repo`，动工作流用 `tasks`/`a2a`，查 Issue/事件/上下文用 `issues`/`events`/`knowledge`。**
4. **结构化内容放评论，不硬改 Issue 状态**：Issue 阶段/状态属 user 层（webhook/UI）；分类/标签/分配/Spec 结论以**评论 + 允许字段的 update**（labels/assignee/state）落地。
5. **机器可读输出加 `--json-out`**；长 JSON 用 `--json @file.json`（不手拼内联）。

## 命令发现（拿不准命令名时必做）

```bash
grape --help                       # 全部命令 + 分类 + token 作用域提示
grape commands [pattern]           # 列出可调用命令；过滤：grape commands issues
grape <group> --help               # 该组动词（含方法/body/Token scope/示例）
grape <group> <verb> --help        # 完整：参数 + Body fields + Examples
grape refresh                      # 重拉最新契约（或回退内置快照）
```

> ⚠️ **命令名以契约为准，不要猜测**：不许 `grape commands | grep issues`（用 `grape commands issues`）；不许凭印象拼写，契约里不存在会报 `No such command`。

## 常用命令（Issue 运营实际用到）

```bash
# 项目历史全貌：近期 Issue / PR（判断重复、已解决、是否已有方案）
grape issues list --owner {owner} --repo {repo} --json-out              # 聚合视图（含阶段/状态）
grape git-repo issues list --owner {owner} --repo {repo} --state all --per_page 20 --json-out
grape git-repo pulls list --owner {owner} --repo {repo} --state all --per_page 10 --json-out

# 读 Issue 完整上下文（当前审视对象：详情 + 事件流 + 路线图）
grape issues detail --owner {owner} --repo {repo} --number {n} --json-out
grape issues events --owner {owner} --repo {repo} --number {n} --json-out
grape issues pipeline --owner {owner} --repo {repo} --number {n} --json-out
grape git-repo issues get --owner {owner} --repo {repo} --number {n} --json-out

# 更新 Issue（仅允许字段：labels / assignee / milestone_id / state；改状态/阶段属 user 层）
grape git-repo issues update --owner {owner} --repo {repo} --number {n} \
  --json '{"labels":"feature,triaged","assignee":"younger_eric"}'
grape git-repo issues update --owner {owner} --repo {repo} --number {n} \
  --json '{"labels":"invalid","state":"close"}'

# Issue 评论（body 一律以 [issue agent] 开头；长文用 --json @file.json）
grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} \
  --json '{"body":"[issue agent] 这是 Issue Agent 的答复内容。"}'

# 读 Issue 评论（回复前取全部讨论上下文）
grape git-repo issues comments list --owner {owner} --repo {repo} --number {n} --json-out

# 创建 Issue（引导/跨仓同步等，仅入口/用户侧创建）
grape issues create --owner {owner} --repo {repo} \
  --json '{"title":"[ACTION] 请配置仓库模块负责人","description":"..."}'
grape git-repo issues create --owner {owner} --repo {repo} \
  --json '{"title":"[ACTION] 请配置仓库模块负责人","body":"..."}'

# 标签（确保存在时创建；已有则跳过）
grape git-repo labels list --owner {owner} --repo {repo} --json-out
grape git-repo labels create --owner {owner} --repo {repo} \
  --json '{"name":"feature","color":"#a2eeef"}'

# 里程碑（仅 Issue 正文明确提及版本号时）
grape git-repo milestones --owner {owner} --repo {repo} --state all --json-out

# 仓库信息 / 文件内容（知识基线降级 / CODEOWNERS 读取；--raw 自动 base64 解码）
grape git-repo repo --owner {owner} --repo {repo} --json-out
grape git-repo tree --owner {owner} --repo {repo} --ref main --json-out    # 目录树
grape git-repo contents --owner {owner} --repo {repo} --path CODEOWNERS --ref codeowner --raw
grape git-repo contents --owner {owner} --repo {repo} --path CODEOWNERS --raw
grape git-repo contents --owner {owner} --repo {repo} --path README.md --raw

# 分支 / 提交（是否已实现 / 活跃度）
grape git-repo branches --owner {owner} --repo {repo} --per_page 50 --json-out
grape git-repo commits --owner {owner} --repo {repo} --per_page 20 --json-out

# 任务通知/分配（处理结束责任人确定后必做，接口幂等）
grape tasks notify --json '{
  "assignee": "younger_eric",
  "repo_key": "{owner}/{repo}",
  "issue_number": {n},
  "task_description": "Issue #{n} 已分配给你，请处理：<简要任务描述>"
}'

# 关闭任务（Issue 关闭后刷新任务状态，接口幂等）
grape tasks close --json '{"repo_key":"{owner}/{repo}","issue_number":{n}}'

# A2A 交办（coding / vod / sre 等，专属命令）
grape a2a handoff --json '{"agent":"coding","payload":{...}}'

# 任务自报完成（收尾必做，见 runbook Step 8；会话 token 自动定位任务，无需 --task_id；⚠️ 结构化字段必填，服务端据此组装 archive）
grape tasks complete --json '{
  "result_text": "结论：Issue #{n} 已按评级完成处理。",
  "next_step": "a2a_coding",
  "actions": ["深度可开发性分析", "打标签", "分配负责人", "回复评论", "grape tasks notify 上报任务", "A2A 交办 coding"],
  "conclusion": "Issue #{n} 评级 {评级}，已完成 {动作}，{后续动作}",
  "artifacts": ["Issue #{n} 评论", "标签 {labels}", "负责人 {assignee}", "A2A event seq=XXXX"],
  "issue_summary": "已分诊 | 评级 {评级} | 已分配 {assignee} | 后续 {动作}"
}'

# 轮询任务至终态
grape tasks wait --task-id t_xxx --timeout 120 --interval 3 --json-out
```

- 所有命令支持 `--json-out`（机器可读单行 JSON）；分页 `--per_page 20`（max 100）；出参结构 = GitCode 平台实际结构。
- 契约不可达时 CLI 自动回退**内置契约快照**（`grape refresh` 显示来源）。

## git（本地执行，token 零暴露）

`grape git` 是 **git 原生命令透传**：**自动识别仓库**（clone 从 URL 解析，其余从当前目录 `remote.origin.url` 解析），
再用会话 token 换券成**短期平台凭据**经 `GIT_CONFIG` env 注入 git 子进程——**不进命令行、不落磁盘、agent 感知不到**。
仅 gitcode.com 宿主注入；换券失败仅告警、按本机原生行为执行。`grape git --help` 与 `git --help` 一致。

```bash
grape git log --oneline -20 --all   # 关闭建议：检查目标分支（$WORK_BRANCH，runbook Step 2 ① 解析）是否已实现（baseline 裸库）
grape git status                     # 本地命令（无需凭据）
```

> Issue Agent 不写代码，git 主要用于「关闭建议」时核对实现进度与其他读操作；写操作（改代码/提交/推送）属 coding agent 职责，本技能不使用。

## 错误排查

| 现象 | 含义 | 处理 |
|------|------|------|
| `HTTP 401: ... re-inject` | token 无效/过期/缺失 | 任务级 token 短命，失效属正常：说明「凭据已失效」，不尝试换 token |
| `HTTP 403: ... 不支持会话 token / use GRAPE_API_TOKEN` | 账户/平台类（D 类）拒绝会话凭据 | 本技能一般不涉及；确需时改用 `GRAPE_API_TOKEN`（`grape_`）或 Web JWT |
| `No such command 'X'. Did you mean: A, B?` | 命令名写错 | 按建议改；或 `grape commands <关键词>` 查 |
| `unknown request field(s): ... allowed for ...` | `--json` 字段不在请求体允许集 | 看 `grape <group> <verb> --help` 的 Body fields |
| `(path not found; try --path '' to list root)` | `contents` 路径不存在 | 先 `--path ""` 看根列表定位 |
| 403（无权限） | 写操作无权限 | 停止并回复「该操作需要管理员/维护者权限，请在 仓库设置中手动配置后重试」 |

## 退出码

`0` 成功 · `1` 通用/配置错误（缺 token/网络/超时） · `2` 用法错误 ·
`>=400` HTTP 状态透传（如 `401`） · `130` Ctrl+C。

## 反模式（禁止）

- ❌ 凭印象/经验拼命令名或 `--参数` —— 先 `--help` 或 `grape commands <pattern>`。
- ❌ `grape commands | grep ...` —— 用 `grape commands <pattern>`。
- ❌ 给 `issues update`/状态类命令传不该改的字段（改状态/阶段属 user 层）—— 只传 labels/assignee/milestone_id/state。
- ❌ `grape api ...` —— 该命令**已移除**（曾是逃生舱），一律走契约命令。
- ❌ 大 JSON 手拼内联 —— 用 `--json @file.json`。
- ❌ 用 `tk_` 会话 token 打账户/平台管理接口（会 403）—— 需要时切换 `grape_`/JWT。

## 安全与边界（必须遵守）

1. **只用系统注入的 `$GRAPE_SESSION_TOKEN`**：不得从数据库、配置文件、日志、历史、环境变量
   中寻找/猜测其他 token；不得读取 `BOT_TOKEN`/`USER_TOKEN`（已不注入）。
2. **禁止访问 Grape 内部数据**：不得读取 `data/sessions.db`、`user_accounts`、`managed_repos`、
   `configs/`（含 `global-bot-token.json` 等）等 Grape 内部基础设施（`data/workspaces/` 项目知识文档除外）。
3. **403/无权限**：立即停止并回复用户「该操作需要管理员/维护者权限，请在 仓库设置中手动配置后重试」，
   不要尝试其他 token 或绕行手段。
4. **401（token 失效）**：任务级 token 短命，失效属正常；说明凭据已失效即可，不尝试替换。
5. **接口缺失 / token 失效**：直接输出**任务无法完成的理由**，不要探索其它无关的 token。
6. **不写 token 到任何文件/日志/评论/工具调用之外的地方**。