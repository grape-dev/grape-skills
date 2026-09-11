# Grape CLI 参考（Issue-CLI 版）

> 本技能**只使用 `grape` CLI**（不再直连 `api.gitcode.com`，也不用 curl 调 API）。
> `grape` 已提供完整且必要的 **grape API / gitcode API / github API / git 原始命令** 的命令行，
> 统一使用系统注入的 **`$GRAPE_SESSION_TOKEN`**（任务级临时，随任务/会话失效）即可操作。

> 前提：执行环境需已安装 `grape` CLI（已随 worker 包 / 主控服务器预装）。未就绪时请按「安装」指引处理，**不要改用 curl 直连**。

## 安装（grape CLI）

`grape` 由运维/部署侧预装，agent **一般不需也不应自行安装**：

- **worker**：重跑一键安装脚本即获得（`install-worker.sh` 自动在 worker `.venv/bin` 生成 `grape` 并注入 PATH）；手建 worker 按实际部署方式手动安装到 `.venv/bin` 并打通 PATH。
- **主控服务器**：已装于 `/opt/grape-cli`（`ln -sf /opt/grape-cli/bin/grape /usr/local/bin/grape`）。
- **自装（有权限时）**：`python3 -m pip install -e <grape-cli 源码>`（源码仓库 `gitcode.com/grape-dev/grape-cli`，自动带 click/httpx 依赖）。

> ⚠️ **禁止 `pip3 install grape`**：PyPI 上的 `grape` 是**第三方公有包**，不是本项目的 CLI，装错会误导命令执行。

agent 内若 `which grape` 无结果：说明执行环境未就绪，直接回复「当前执行环境未安装 grape CLI，请管理员在 worker 安装后重试」，**不要**自行安装，也**不要**改用 curl 直连。

## 认证与配置（无需手动设置）

- `$GRAPE_SESSION_TOKEN` **已由服务端注入环境变量**，`grape` 自动读取（优先级：`--token` 参数 > `GRAPE_SESSION_TOKEN` > `GRAPE_API_TOKEN`/`GRAPE_BASE_URL` > `~/.grape/config.json`）。
- **不需要** `export GRAPE_SESSION_TOKEN=...`，也不需要写 `~/.grape/config.json`。
- 服务端地址自动取**已注入的环境变量 `$GRAPE_SERVER_URL`**（`grape` 直接读取，无需每次 `--base-url`）；如需覆盖可用 `--base-url <url>`。
- token 是**任务级临时**的：任务结束即失效；命令报 401 说明凭据已失效，直接说明「凭据已失效」即可，不尝试换 token。
- 一次性参数：`grape --token tk_xxx --base-url https://... --timeout 120 <cmd>`（仅本次进程）。

## 常用命令（Issue 运营实际用到）

```bash
# 列 Issue（判断重复/已解决/开放中）
grape git-repo issues list --owner {owner} --repo {repo} --state all --per_page 20 --json-out

# 获取 Issue 完整内容（需求/标签/评论，A2A context 只给摘要，必须用它拉全文）
grape git-repo issues get --owner {owner} --repo {repo} --number {n} --json-out

# 更新 Issue（打标签 / 分配负责人 / 关里程碑 / 关闭）
grape git-repo issues update --owner {owner} --repo {repo} --number {n} \
  --json '{"labels":"feature,triaged","assignee":"younger_eric"}'
grape git-repo issues update --owner {owner} --repo {repo} --number {n} \
  --json '{"labels":"invalid","state":"close"}'

# Issue 评论（body 一律以 [issue agent] 开头）
grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} \
  --json '{"body":"[issue agent] 这是 Issue Agent 的答复内容。"}'

# 读 Issue 评论（回复前取全部讨论上下文）
grape git-repo issues comments list --owner {owner} --repo {repo} --number {n} --json-out

# 创建 Issue（引导/跨仓同步等）
grape git-repo issues create --owner {owner} --repo {repo} \
  --json '{"title":"[ACTION] 请配置仓库模块负责人","body":"..."}'

# 标签（确保存在时创建；已有则跳过）
grape git-repo labels list --owner {owner} --repo {repo} --json-out
grape git-repo labels create --owner {owner} --repo {repo} \
  --json '{"name":"feature","color":"#a2eeef"}'

# 里程碑（仅 Issue 正文明确提及版本号时）
grape git-repo milestones --owner {owner} --repo {repo} --state all --json-out

# 仓库信息 / 文件内容（知识基线降级 / CODEOWNERS 读取）
grape git-repo repo --owner {owner} --repo {repo} --json-out
grape git-repo contents --owner {owner} --repo {repo} --path CODEOWNERS --ref codeowner --json-out
grape git-repo contents --owner {owner} --repo {repo} --path CODEOWNERS --json-out

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

# 任务自报完成（收尾必做，见 SKILL「任务完成流程」）
grape tasks complete --json '{
  "result_text": "结论：...",
  "next_step": "done",
  "actions": ["...", "..."],
  "conclusion": "...",
  "artifacts": ["..."],
  "issue_summary": "..."
}'

# 轮询任务至终态
grape tasks wait --task-id t_xxx --timeout 120 --interval 3 --json-out
```

- 所有命令支持 `--json-out`（机器可读单行 JSON）；`-h/--help` 查看参数；`grape commands [pattern]` 列出契约命令。
- 契约不可达时 CLI 自动回退**内置契约快照**（`grape refresh` 显示来源）。
- 命令形态：`grape <组> <动词> [--参数]`；组 `git-repo` 对应全部 GitCode 仓库 REST 接口（issues/pulls/labels/milestones/contents/branches/commits/comments 等）；组 `tasks` 对应任务中心接口；`a2a handoff`、`tasks complete` 为专属收尾命令。
- `contents` 返回的 `content` 为 Base64，需解码后读取（如 CODEOWNERS）。

## git（本地执行，token 零暴露）

`grape git` 是 **git 原生命令透传**：**自动识别仓库**（clone 从 URL 解析，其余从当前目录 `remote.origin.url` 解析），
再用会话 token 换券成**短期平台凭据**经 `GIT_CONFIG` env 注入 git 子进程——**不进命令行、不落磁盘、agent 感知不到**。
仅 gitcode.com 宿主注入；换券失败仅告警、按本机原生行为执行。`grape git --help` 与 `git --help` 一致。

```bash
grape git log --oneline -20 --all   # 关闭建议：检查 master 是否已实现（baseline 裸库）
grape git status                     # 本地命令（无需凭据）
```

> Issue Agent 不写代码，git 主要用于「关闭建议」时核对实现进度与其他读操作；写操作（改代码/提交/推送）属 coding agent 职责，本技能不使用。

## 通用兜底（`grape api`）

对没有专门命令的 grape 内部端点，用 `grape api <METHOD> <path> [-d '<JSON>']`：

```bash
grape api GET /api/scenes --json-out
grape api POST /api/tasks/create -d '{"repo_key":"{owner}/{repo}","title":"...","description":"..."}'
# A2A / 任务通知/关闭/自报完成有专属命令，不在此列：grape a2a handoff / grape tasks notify|close|complete
```

## 退出码

`0` 成功 · `1` 通用/配置错误（缺 token/网络/超时） · `2` 用法错误 ·
`>=400` HTTP 状态透传（如 `401`） · `130` Ctrl+C。

## 安全与边界（必须遵守）

1. **只用系统注入的 `$GRAPE_SESSION_TOKEN`**：不得从数据库、配置文件、日志、历史、环境变量
   中寻找/猜测其他 token；不得读取 `BOT_GITCODE_TOKEN`/`USER_GITCODE_TOKEN`（已不注入）。
2. **禁止访问 Grape 内部数据**：不得读取 `data/sessions.db`、`user_accounts`、`managed_repos`、
   `configs/`（含 `global-bot-token.json` 等）等 Grape 内部基础设施（`data/workspaces/` 项目知识文档除外）。
3. **403/无权限**：立即停止并回复用户「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」，
   不要尝试其他 token 或绕行手段。
4. **401（token 失效）**：任务级 token 短命，失效属正常；说明凭据已失效即可，不尝试替换。
5. **接口缺失 / token 失效**：直接输出**任务无法完成的理由**，不要探索其它无关的 token。
6. **不写 token 到任何文件/日志/评论/工具调用之外的地方**。