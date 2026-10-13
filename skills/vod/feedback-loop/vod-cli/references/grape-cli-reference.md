# Grape CLI 参考（VOD 版）

> 本技能**只使用 `grape` CLI**，统一使用系统注入的 **`$GRAPE_SESSION_TOKEN`**（任务级临时，随任务/会话失效）即可操作。
> 详细指南见 `grape-cli-guidance` 技能（命令分组 / token 作用域 / 错误排查 / 反模式），本文件是 VOD 实际用到的命令与要点。

## 安装与版本校验（Prerequisites 用）

```bash
grape --version            # 版本号必须 >= 0.3.2
grape refresh              # 契约过期时重拉最新契约（或回退内置快照）
```

> 未装或版本 < 0.3.2 → 见 `references/grape-cli-installation.md` **自行安装/升级**（公开仓库 gitcode.com/grape-dev/grape-cli）；安装后仍失败再输出任务无法完成的理由，**不要**改用 curl 直连。对应 SKILL「Prerequisites」环节。

## 核心原则（先读）

1. **命令是契约驱动的**：`grape <group> <verb> [--参数]` 由服务端 `/openapi.json`（或内置快照）动态生成。**不确定命令 → 先发现，别猜名字。**
2. **token 决定你能做什么**：`GRAPE_SESSION_TOKEN`（`tk_`）= 会话级，任务环境默认注入，覆盖 VOD 全部日常操作（workflows / 仓库 / Issue 等）。账户/平台管理类（skills/auth/repos-managed）对 `tk_` 返回 403，需 `GRAPE_API_TOKEN`（`grape_`）或 Web JWT——**VOD 一般用不到**。
3. **读仓库用 `git-repo`，动工作流用 `tasks`/`a2a`，查 Issue/事件/上下文用 `issues`/`events`/`knowledge`。**
4. **结构化内容放评论，不硬改 Issue 状态**：Issue 阶段/状态属 user 层（webhook/UI），agent 不要改；VOD 的审视结论/结构化收敛以**评论**落地。
5. **机器可读输出加 `--json-out`**；长 JSON 用 `--json @file.json`（不手拼内联）。

## 命令发现（拿不准命令名时必做）

```bash
grape --help                       # 全部命令 + 分类 + token 作用域提示
grape commands [pattern]           # 列出可调用命令；过滤：grape commands issues
grape <group> --help               # 该组动词（含方法/body/Token scope/示例）
grape <group> <verb> --help        # 完整：参数 + Body fields + Examples
grape refresh                      # 重拉最新契约（或回退内置快照）
```

> ⚠️ **命令名以契约为准，不要猜测**：不许 `grape commands | grep issues`（用 `grape commands issues`）；不许凭印象拼写（如缺失动词的命令，契约里不存在会报 `No such command`）。

## 常用命令（VOD 实际用到）

```bash
# 项目历史全貌：近期 Issue / PR（判断重复、已解决、是否已有方案）
grape issues list --owner {owner} --repo {repo} --json-out              # 聚合视图（含阶段/状态）
grape git-repo issues list --owner {owner} --repo {repo} --state all --per_page 20 --json-out
grape git-repo pulls list --owner {owner} --repo {repo} --state all --per_page 10 --json-out

# 读 Issue 完整上下文（当前审视对象：详情 + 事件流 + 路线图）
grape issues detail --owner {owner} --repo {repo} --number {n} --json-out
grape issues events --owner {owner} --repo {repo} --number {n} --json-out
grape issues pipeline --owner {owner} --repo {repo} --number {n} --json-out
grape git-repo issues comments list --owner {owner} --repo {repo} --number {n} --json-out

# 建 Issue（VOD 引导产出，仅入口/用户侧创建；body 字段明确用 git-repo 组命令）
grape git-repo issues create --owner {owner} --repo {repo} \
  --json '{"title":"...","body":"..."}'

# 结构化收敛需求：以评论发布，不改写原始 Issue body（VOD 原则）
grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} \
  --json '{"body":"[VOD Agent] 已结构化收敛需求：\n\n## 目标\n…\n## 现状\n…\n## 期望行为\n…\n## 验收标准\n…\n## 优先级\n…"}'   # 长文用 --json @file.json

# 仅当需改标签/分配/关闭等元数据时用 issues update（不涉及 body 收敛）
grape git-repo issues update --owner {owner} --repo {repo} --number {n} \
  --json '{"labels":"feature","assignee":"<user>"}'

# 评论（澄清追问等反馈；body 以 [VOD Agent] 开头）
grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} \
  --json '{"body":"[VOD Agent] 这是 VOD 的答复内容。"}'                    # 长文用 --json @file.json

# 项目知识基线（Step 0 首选；支持会话 token，仓库作用域匹配即可；命令名因契约版本可能为 repos project info）
grape repos project info --owner {owner} --repo {repo} --json-out   # project-graph.md + project-capabilities.md 全文 + meta(degraded/commit/branches)

# Agent/仓库沉淀知识（Step 0；dual，会话 token 可用）
grape knowledge stats --repo {repo} --json-out                      # 各类知识数量（system/agent/manual）
grape knowledge list --repo {repo} --source agent --json-out        # Agent 沉淀知识清单（前序经验）
grape knowledge list --repo {repo} --source system --json-out       # 系统注入说明文档清单
grape knowledge detail --knowledge_id {id} --json-out               # 读单条知识全文

# 分支 / 提交 / 文件（知识基线降级、增量判断）
grape git-repo branches --owner {owner} --repo {repo} --per_page 50 --json-out
grape git-repo commits --owner {owner} --repo {repo} --per_page 10 --json-out
grape git-repo tree --owner {owner} --repo {repo} --ref main --depth single --json-out   # 目录树（--depth single=单层默认/recursive 仅 GitHub，无 --path）
grape git-repo contents --owner {owner} --repo {repo} --path README.md --raw   # 文件原文（自动 base64 解码）
grape git-repo contents --owner {owner} --repo {repo} --path "" --json-out     # 列根目录文件列表

# A2A 交办 Issue Agent（专属命令）
grape a2a handoff --json '{"agent":"issue","payload":{...}}'

# 显式声明进入待澄清（需求不清晰需用户补充时；仅 vod/issue 会话 token；--issue_id=需求卡片内部 id，优先 $GRAPE_ISSUE_ID 未注入降级 issues detail 的 id；出参 changed:true 成功 / false 幂等）
grape issues awaiting-input --issue_id ${GRAPE_ISSUE_ID:-{issue_id}} \
  --json '{"questions":"[VOD Agent] 请问：…","reason":"需求四要素缺失"}'

# 任务自报完成（收尾必做，见 SKILL「任务完成流程」；会话 token 自动定位任务，无需 --task_id；结构化字段必传，服务端据此组装 archive）
grape tasks complete --json '{
  "result_text": "结论：…",
  "next_step": "a2a_issue",
  "actions": ["…"],
  "conclusion": "…",
  "artifacts": ["…"],
  "issue_summary": "…"
}'
```

**命令取舍速查（避免重复调用 / 试错）：**
- **读 Issue 上下文**：首选聚合视图 `grape issues detail`（含阶段/状态/事件/路线图）；`grape git-repo issues get`（原始字段）仅在 detail 缺字段时再用；评论用 `grape git-repo issues comments list`。**不要 three 者都调**。
- **列目录**：`grape git-repo tree --depth single`（目录树，**无 `--path`**）；`contents --path ""` 列根目录文件列表；读单个文件用 `contents --path <file> --raw`。一次 `tree --depth single` 看清结构，再按需读 2-3 个关键文件，**不要逐目录 contents**。
- **owner/repo**：用环境变量 `$ACCOUNT` / `$REPO_NAME`（如命令模板所示），不要硬编码。

- 所有命令支持 `--json-out`（机器可读单行 JSON）；分页 `--per_page 20`（max 100）；出参结构 = GitCode 平台实际结构。
- 契约不可达时 CLI 自动回退**内置契约快照**（`grape refresh` 显示来源）。

## git（本地执行，token 零暴露）

`grape git` 是 **git 原生命令透传**：**自动识别仓库**（clone 从 URL 解析，其余从当前目录 `remote.origin.url` 解析），
再用会话 token 换券成**短期平台凭据**经 `GIT_CONFIG` env 注入 git 子进程——**不进命令行、不落磁盘、agent 感知不到**。
仅 gitcode.com 宿主注入；换券失败仅告警、按本机原生行为执行。`grape git --help` 与 `git --help` 一致。

```bash
grape git status                                   # 本地命令（无需凭据）
grape git clone https://gitcode.com/owner/repo.git # 从 URL 识别仓库 → 注入凭据
grape git pull
grape git log --oneline -20
```

> VOD 不写代码，git 主要用于本地只读核对与工作区检视；写操作（commit/push）属 coding agent 职责。

## 错误排查

| 现象 | 含义 | 处理 |
|------|------|------|
| `HTTP 401: ... re-inject` | token 无效/过期/缺失 | 任务级 token 短命，失效属正常：说明「凭据已失效」，不尝试换 token |
| `HTTP 403: ... 不支持会话 token / use GRAPE_API_TOKEN` | 账户/平台类（D 类）拒绝会话凭据 | VOD 一般不涉及；确需时改用 `GRAPE_API_TOKEN`（`grape_`）或 Web JWT |
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
- ❌ 给 `issues update`/状态类命令传不该改的字段（改状态/阶段属 user 层）—— 结构化内容用评论。
- ❌ `grape api ...` —— 该命令**已移除**（曾是逃生舱），一律走契约命令。
- ❌ 大 JSON 手拼内联 —— 用 `--json @file.json`。
- ❌ 用 `tk_` 会话 token 打账户/平台管理接口（会 403）—— 需要时切换 `grape_`/JWT。

## 安全与边界（必须遵守）

1. **只用系统注入的 `$GRAPE_SESSION_TOKEN`**：不得从数据库、配置文件、日志、历史、环境变量
   中寻找/猜测其他 token。
2. **禁止访问 Grape 内部数据**：不得读取 `data/sessions.db`、`user_accounts`、`managed_repos`、
   `configs/`（含 `global-bot-token.json` 等）等 Grape 内部基础设施（`data/workspaces/` 项目知识文档除外）。
3. **403/无权限**：立即停止并回复用户「该操作需要管理员/维护者权限，请在 仓库设置中手动配置后重试」，
   不要尝试其他 token 或绕行手段。
4. **401（token 失效）**：任务级 token 短命，失效属正常；说明凭据已失效即可，不尝试替换。
5. **接口缺失 / token 失效**：直接输出**任务无法完成的理由**，不要探索其它无关的 token。
6. **不写 token 到任何文件/日志/评论/工具调用之外的地方**。