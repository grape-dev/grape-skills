# Grape CLI 参考（Chat）

> 本技能**只使用 `grape` CLI**，统一使用系统注入的 **`$GRAPE_SESSION_TOKEN`**（任务级临时，随任务/会话失效）即可操作。
> 详细指南见 `grape-cli-guidance` 技能（命令分组 / token 作用域 / 错误排查 / 反模式），本文件是 Chat 对话实际用到的命令与要点。

## 核心原则（先读）

1. **命令是契约驱动的**：`grape <group> <verb> [--参数]` 由服务端 `/openapi.json`（或内置快照）动态生成。**不确定命令 → 先发现，别猜名字。**
2. **token 决定你能做什么**：`GRAPE_SESSION_TOKEN`（`tk_`）= 会话级，任务环境默认注入，覆盖本技能全部日常操作（workflows / Agent Context / git-repo）。账户/平台管理类（skills/auth/repos-managed…）对 `tk_` 返回 **403**，需 `GRAPE_API_TOKEN`（`grape_`）或 Web JWT——**本技能一般用不到**。
3. **读仓库用 `git-repo`，动工作流用 `tasks`/`a2a`，查 Issue/事件/上下文用 `issues`/`events`/`knowledge`。**
4. **Chat 只查询与回答，不执行 git/写操作**：`grape git` 能力存在但本场景不使用。
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

## 常用命令（Chat 实际用到）

```bash
# Issue 详情（task 澄清读取背景；出参含 title/body/labels/assignee 等）
grape issues detail --owner {owner} --repo {repo} --number {number} --json-out   # 聚合视图（含阶段/状态）
grape issues pipeline --owner {owner} --repo {repo} --number {number} --json-out # 路线图
grape git-repo issues get --owner {owner} --repo {repo} --number {number} --json-out

# Issue 全部评论（理解讨论过程）
grape git-repo issues comments list --owner {owner} --repo {repo} --number {number} --json-out

# Issue 评论回复（task-clarify 回帖 / 澄清追问，body 注明补充人和来源）
grape git-repo issues comments create --owner {owner} --repo {repo} --number {number} \
  --json '{"body":"**补充需求澄清**（由任务处理对话整理）：\n\n## 背景\n<原 Issue 核心内容>\n\n## 澄清后的需求\n- 使用场景：<用户补充>\n- 预期效果：<用户补充>\n- 验收标准：<用户补充>\n\n---\n补充人：<用户昵称>（通过 Chat 对话整理）"}'

# 创建 Issue（task-feedback 需求明确后；不带标签，标签由 issue skill 统一分诊）
grape issues create --owner {owner} --repo {repo} \
  --json '{"title":"<清晰的需求标题>","description":"<需求描述，含提交人/渠道>"}'

# 列 Issue（task-review 查询待启动 feature；出参结构与 GitCode 平台一致，含 labels/assignee）
grape issues list --owner {owner} --repo {repo} --json-out
grape git-repo issues list --owner {owner} --repo {repo} --state open --per_page 100 --json-out

# 更新 Issue（task-review 加 PATCH 标签，触发 implementation skill；仅允许字段 labels/assignee/state）
grape git-repo issues update --owner {owner} --repo {repo} --number {number} \
  --json '{"labels":"feature,triaged,PATCH"}'

# 查询 PR / commit 状态（状态分析类问题）
grape git-repo pulls get --owner {owner} --repo {repo} --number {pr} --json-out
grape git-repo commits --owner {owner} --repo {repo} --per_page 20 --json-out

# 任务自报完成（会话绑定任务时收尾必做，见 SKILL「任务完成流程」）
grape tasks complete --json '{"result_text":"结论：...","next_step":"done"}'

# 轮询任务至终态
grape tasks wait --task-id t_xxx --timeout 120 --interval 3 --json-out
```

- 所有命令支持 `--json-out`（机器可读单行 JSON）；分页 `--per_page 20`（max 100）；出参结构 = GitCode 平台实际结构。
- 契约不可达时 CLI 自动回退**内置契约快照**（`grape refresh` 显示来源）。
- **open_id 解析不走 CLI**：Feishu @mention 的 open_id 按 SKILL.md「在回复中 @ 用户」节从 prompt 内联的 Known Mappings / Collaborators / Group Members 解析，无需（也不存在）对应命令。

## 写入身份与 self-comment 过滤说明

- 写入一律使用会话 token `$GRAPE_SESSION_TOKEN`（`grape` 自动读取），写入身份为当前会话。
- 若回帖/建 Issue 后 webhook 事件因 self-comment 过滤未被 issue agent 重新分诊，在回复中如实提示用户，不假称已生效。

## git（本地执行，token 零暴露）

`grape git` 是 **git 原生命令透传**：**自动识别仓库**（clone 从 URL 解析，其余从当前目录 `remote.origin.url` 解析），
再用会话 token 换券成**短期平台凭据**经 `GIT_CONFIG` env 注入 git 子进程——**不进命令行、不落磁盘、agent 感知不到**。
仅 gitcode.com 宿主注入；换券失败仅告警、按本机原生行为执行。`grape git --help` 与 `git --help` 一致。

> ⚠️ Chat 只做查询与回答，**不执行 git/写操作**；此处仅说明 `grape git` 能力存在，Chat 场景下不使用。

## 错误排查

| 现象 | 含义 | 处理 |
|------|------|------|
| `HTTP 401: ... re-inject` | token 无效/过期/缺失 | 任务级 token 短命，失效属正常：说明「凭据已失效」，不尝试换 token |
| `HTTP 403: ... 不支持会话 token / use GRAPE_API_TOKEN` | 账户/平台类（D 类）拒绝会话凭据 | 本技能一般不涉及；确需时改用 `GRAPE_API_TOKEN`（`grape_`）或 Web JWT |
| `No such command 'X'. Did you mean: A, B?` | 命令名写错 | 按建议改；或 `grape commands <关键词>` 查 |
| `unknown request field(s): ... allowed for ...` | `--json` 字段不在请求体允许集 | 看 `grape <group> <verb> --help` 的 Body fields |
| `(path not found; try --path '' to list root)` | `contents` 路径不存在 | 先 `grape git-repo tree` / `--path ""` 看根列表定位 |
| 403（无权限） | 写操作无权限 | 停止并回复用户「该操作需要相应权限，请在 GitCode 中手动配置后重试」 |

## 退出码

`0` 成功 · `1` 通用/配置错误（缺 token/网络/超时） · `2` 用法错误 ·
`>=400` HTTP 状态透传（如 `401`） · `130` Ctrl+C。

## 反模式（禁止）

- ❌ 凭印象/经验拼命令名或 `--参数` —— 先 `--help` 或 `grape commands <pattern>`。
- ❌ `grape commands | grep ...` —— 用 `grape commands <pattern>`。
- ❌ `grape api ...` —— 该命令**已移除**（曾是逃生舱），一律走契约命令。
- ❌ 大 JSON 手拼内联 —— 用 `--json @file.json`。
- ❌ 用 `tk_` 会话 token 打账户/平台管理接口（会 403）—— 需要时切换 `grape_`/JWT。
- ❌ 在 Chat 里做 git/写操作（clone/部署/起服务/改文件）—— 只澄清+回帖，执行交 pipeline 的 coding/sre。

## 安全与边界（必须遵守）

1. **只用系统注入的 `$GRAPE_SESSION_TOKEN`**：不得从数据库、配置文件、日志、历史、环境变量
   中寻找/猜测其他 token。
2. **禁止访问 Grape 内部数据**：不得读取 `data/sessions.db`、`user_accounts`、`managed_repos`、
   `configs/`（含 `global-bot-token.json` 等）等 Grape 内部基础设施（`data/workspaces/` 项目知识文档除外）。
3. **403/无权限**：立即停止并回复用户「该操作需要相应权限，请在 GitCode 中手动配置后重试」，
   不要尝试其他 token 或绕行手段。
4. **401（token 失效）**：任务级 token 短命，失效属正常；说明凭据已失效即可，不尝试替换。
5. **接口缺失 / token 失效**：直接输出**任务无法完成的理由**，不要探索其它无关的 token。
6. **不写 token 到任何文件/日志/评论/工具调用之外的地方**。