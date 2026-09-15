# Grape CLI 参考（deploy-cli 版）

> 本技能**只使用 `grape` CLI**，统一使用系统注入的 **`$GRAPE_SESSION_TOKEN`**（任务级临时，随任务/会话失效）即可操作。
> 详细指南见 `grape-cli-guidance` 技能（命令分组 / token 作用域 / 错误排查 / 反模式），本文件是部署/资源释放实际用到的命令与要点。

## 核心原则（先读）

1. **命令是契约驱动的**：`grape <group> <verb> [--参数]` 由服务端 `/openapi.json`（或内置快照）动态生成。**不确定命令 → 先发现，别猜名字。**
2. **token 决定你能做什么**：`GRAPE_SESSION_TOKEN`（`tk_`）= 会话级，任务环境默认注入，覆盖本技能全部日常操作（workflows / Agent Context / git-repo）。账户/平台管理类（skills/auth/repos-managed…）对 `tk_` 返回 **403**，需 `GRAPE_API_TOKEN`（`grape_`）或 Web JWT——**本技能一般用不到**。
3. **读仓库用 `git-repo`，动工作流用 `tasks`/`a2a`，查 Issue/事件/上下文用 `issues`/`events`/`knowledge`。**
4. **git 与构建/部署分工**：代码 clone/checkout/pull 用 `grape git`（凭据自动注入、token 零暴露）；节点安装/构建（npm/pip/go）与华为云 hcloud/obsutil 操作照常本地执行。
5. **机器可读输出加 `--json-out`**；长 JSON 用 `--json @file.json`（不手拼内联）。

## 命令发现（拿不准命令名时必做）

```bash
grape --help                       # 全部命令 + 分类 + token 作用域提示
grape commands [pattern]           # 列出可调用命令；过滤：grape commands pulls
grape <group> --help               # 该组动词（含方法/body/Token scope/示例）
grape <group> <verb> --help        # 完整：参数 + Body fields + Examples
grape refresh                      # 重拉最新契约（或回退内置快照）
```

> ⚠️ **命令名以契约为准，不要猜测**：不许 `grape commands | grep pulls`（用 `grape commands pulls`）；不许凭印象拼写，契约里不存在会报 `No such command`。

## 常用命令（deploy 实际用到）

```bash
# 读 Issue 完整上下文（部署/释放需求 + 阶段 + 事件）
grape issues detail --owner {owner} --repo {repo} --number {n} --json-out   # 聚合视图（含阶段/状态）
grape issues pipeline --owner {owner} --repo {repo} --number {n} --json-out # 路线图
grape issues events --owner {owner} --repo {repo} --number {n} --json-out   # 事件流
grape git-repo issues get --owner {owner} --repo {repo} --number {n} --json-out

# 读 Issue 评论（补充资源信息）
grape git-repo issues comments list --owner {owner} --repo {repo} --number {n} --json-out

# Issue 评论（body 一律以 [SRE Agent] 开头）
grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} \
  --json '{"body":"[SRE Agent] 这是 SRE 的答复内容。"}'

# 列 PR / 取 PR 详情（根据入口定位 PR 分支）
grape git-repo pulls list --owner {owner} --repo {repo} --state all --per_page 10 --json-out
grape git-repo pulls get --owner {owner} --repo {repo} --number {pr} --json-out

# 分支 / 提交（入口判定 / 仓库状态）
grape git-repo branches --owner {owner} --repo {repo} --per_page 50 --json-out
grape git-repo commits --owner {owner} --repo {repo} --per_page 10 --json-out

# 仓库信息 / 文件内容（识别项目结构降级；--raw 自动 base64 解码）
grape git-repo repo --owner {owner} --repo {repo} --json-out
grape git-repo tree --owner {owner} --repo {repo} --ref main --json-out    # 目录树（先看根定位构建文件）
grape git-repo contents --owner {owner} --repo {repo} --path README.md --raw
grape git-repo contents --owner {owner} --repo {repo} --path package.json --raw

# 任务自报完成（收尾必做，见 SKILL「任务完成流程」）
grape tasks complete --json '{
  "result_text": "结论：...",
  "next_step": "done",
  "actions": ["..."],
  "conclusion": "...",
  "artifacts": ["..."],
  "issue_summary": "..."
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
grape git clone https://gitcode.com/owner/repo.git   # 从 URL 识别仓库 → 注入凭据
grape git checkout <pr_branch>                       # 切换 PR 分支
grape git pull
grape git status                                     # 本地命令（无需凭据）
```

> 部署流程中 git 的 clone/checkout/pull 一律用 `grape git`；节点安装/构建（npm/pip/go）与华为云 hcloud/obsutil 操作照常本地执行。

## 错误排查

| 现象 | 含义 | 处理 |
|------|------|------|
| `HTTP 401: ... re-inject` | token 无效/过期/缺失 | 任务级 token 短命，失效属正常：说明「凭据已失效」，不尝试换 token |
| `HTTP 403: ... 不支持会话 token / use GRAPE_API_TOKEN` | 账户/平台类（D 类）拒绝会话凭据 | 本技能一般不涉及；确需时改用 `GRAPE_API_TOKEN`（`grape_`）或 Web JWT |
| `No such command 'X'. Did you mean: A, B?` | 命令名写错 | 按建议改；或 `grape commands <关键词>` 查 |
| `unknown request field(s): ... allowed for ...` | `--json` 字段不在请求体允许集 | 看 `grape <group> <verb> --help` 的 Body fields |
| `(path not found; try --path '' to list root)` | `contents` 路径不存在 | 先 `grape git-repo tree` / `--path ""` 看根列表定位 |
| 403（无权限） | 写操作无权限 | 停止并回复「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」 |

## 退出码

`0` 成功 · `1` 通用/配置错误（缺 token/网络/超时） · `2` 用法错误 ·
`>=400` HTTP 状态透传（如 `401`） · `130` Ctrl+C。

## 反模式（禁止）

- ❌ 凭印象/经验拼命令名或 `--参数` —— 先 `--help` 或 `grape commands <pattern>`。
- ❌ `grape commands | grep ...` —— 用 `grape commands <pattern>`。
- ❌ `grape api ...` —— 该命令**已移除**（曾是逃生舱），一律走契约命令。
- ❌ 大 JSON 手拼内联 —— 用 `--json @file.json`。
- ❌ 用 `tk_` 会话 token 打账户/平台管理接口（会 403）—— 需要时切换 `grape_`/JWT。
- ❌ 在本地 worktree 用裸 `git` 绕过 `grape git`（会丢失凭据注入）—— 一律用 `grape git`。

## 安全与边界（必须遵守）

1. **只用系统注入的 `$GRAPE_SESSION_TOKEN`**：不得从数据库、配置文件、日志、历史、环境变量
   中寻找/猜测其他 token；不得读取 `BOT_GITCODE_TOKEN`/`USER_GITCODE_TOKEN`（已不注入）。
2. **禁止访问 Grape 内部数据**：不得读取 `data/sessions.db`、`user_accounts`、`managed_repos`、
   `configs/`（含 `global-bot-token.json` 等）等 Grape 内部基础设施。
3. **403/无权限**：立即停止并回复用户「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」，
   不要尝试其他 token 或绕行手段。
4. **401（token 失效）**：任务级 token 短命，失效属正常；说明凭据已失效即可，不尝试替换。
5. **接口缺失 / token 失效**：直接输出**任务无法完成的理由**，不要探索其它无关的 token。
6. **不写 token 到任何文件/日志/评论/工具调用之外的地方**。