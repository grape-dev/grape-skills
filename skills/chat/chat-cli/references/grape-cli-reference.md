# Grape CLI 参考（Chat-CLI 版）

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

## 常用命令（Chat 实际用到）

```bash
# Issue 详情（task 澄清读取背景；出参含 title/body/labels/assignee 等）
grape git-repo issues get --owner {owner} --repo {repo} --number {number} --json-out

# Issue 全部评论（理解讨论过程）
grape git-repo issues comments list --owner {owner} --repo {repo} --number {number} --json-out

# Issue 评论回复（task-handling 回帖 / 澄清追问，body 注明补充人和来源）
grape git-repo issues comments create --owner {owner} --repo {repo} --number {number} \
  --json '{"body":"**补充需求澄清**（由任务处理对话整理）：\n\n## 背景\n<原 Issue 核心内容>\n\n## 澄清后的需求\n- 使用场景：<用户补充>\n- 预期效果：<用户补充>\n- 验收标准：<用户补充>\n\n---\n补充人：<用户昵称>（通过 Chat 对话整理）"}'

# 创建 Issue（inquiry-handling 需求明确后；不带标签，标签由 issue skill 统一分诊）
grape git-repo issues create --owner {owner} --repo {repo} \
  --json '{"title":"<清晰的需求标题>","body":"**提交人**: @用户飞书昵称 (Feishu ID: xxx)\n**渠道**: 飞书\n**时间**: 当前时间\n**归属**: 🤖 Chat Agent 本身 / 📦 当前仓库\n\n**需求描述**:\n> 用户核心需求\n\n**使用场景**:\n> 场景说明\n\n**预期效果**:\n> 期望结果\n\n**验收标准**:\n> 可衡量的完成标准\n\n---\nauto-submitted by Chat Agent Feishu feedback"}'

# 列 Issue（implementation-start 查询待启动 feature；出参结构与 GitCode 平台一致，含 labels/assignee）
grape git-repo issues list --owner {owner} --repo {repo} --state open --per_page 100 --json-out

# 更新 Issue（implementation-start 加 PATCH 标签，触发 implementation skill）
grape git-repo issues update --owner {owner} --repo {repo} --number {number} \
  --json '{"labels":"feature,triaged,PATCH"}'

# 查询 PR / commit 状态（状态分析类问题）
grape git-repo pulls get --owner {owner} --repo {repo} --number {pr} --json-out
grape git-repo commits --owner {owner} --repo {repo} --per_page 20 --json-out

# 用户映射（Feishu open_id；grape 内部端点，无专属子命令 → 通用兜底 grape api）
grape api GET "/api/user-mapping?login={gitcode_login}&repo_key=gitcode:{owner}/{repo}" --json-out

# 任务自报完成（会话绑定任务时收尾必做，见 SKILL「任务完成流程」）
grape tasks complete --json '{"result_text":"结论：...","next_step":"done"}'

# 轮询任务至终态
grape tasks wait --task-id t_xxx --timeout 120 --interval 3 --json-out
```

- 所有命令支持 `--json-out`（机器可读单行 JSON）；`-h/--help` 查看参数；`grape commands [pattern]` 列出契约命令。
- 分页：`--per_page 20`（max 100）；出参结构 = GitCode 平台实际结构。
- 契约不可达时 CLI 自动回退**内置契约快照**（`grape refresh` 显示来源）。
- 命令形态：`grape <组> <动词> [--参数]`；组 `git-repo` 对应全部 GitCode 仓库 REST 接口（issues/pulls/contents/branches/commits/comments 等）；`tasks complete` 为专属收尾命令。

## 写入身份与 self-comment 过滤说明

- 原始版以 `$USER_GITCODE_TOKEN`（用户本人身份）回帖/建 Issue，避免被 self-comment 过滤。**CLI 版默认使用会话 token `$GRAPE_SESSION_TOKEN`**，写入身份为当前会话。
- 若 prompt 中仍注入 `$USER_GITCODE_TOKEN` 且需以用户身份写入，可用一次性参数显式指定：`grape --token "$USER_GITCODE_TOKEN" git-repo issues comments create ...`（不改写任何配置文件）。
- 若回帖后 webhook 事件因 self-comment 过滤未被 issue agent 重新分诊，在回复中如实提示用户，不假称已生效。

## 通用兜底（`grape api`）

对没有专门命令的 **grape 内部端点**（如 `/api/user-mapping`），用 `grape api <METHOD> <path> [-d '<JSON>']`：

```bash
grape api GET "/api/user-mapping?login={gitcode_login}&repo_key=gitcode:{owner}/{repo}" --json-out
grape api GET /api/scenes --json-out
# 任务自报完成有专属命令，不在此列：grape tasks complete
```

> ⚠️ 仓库操作（Issue/PR/评论/commit）**均有专属 `grape git-repo` 命令**，直接用上面的命令即可，**不要**用 `grape api` 或 curl 拼 GitCode REST 端点。

## git（本地执行，token 零暴露）

`grape git` 是 **git 原生命令透传**：**自动识别仓库**（clone 从 URL 解析，其余从当前目录 `remote.origin.url` 解析），
再用会话 token 换券成**短期平台凭据**经 `GIT_CONFIG` env 注入 git 子进程——**不进命令行、不落磁盘、agent 感知不到**。
仅 gitcode.com 宿主注入；换券失败仅告警、按本机原生行为执行。`grape git --help` 与 `git --help` 一致。

> ⚠️ Chat 只做查询与回答，**不执行 git/写操作**；此处仅说明 `grape git` 能力存在，Chat 场景下不使用。

## 退出码

`0` 成功 · `1` 通用/配置错误（缺 token/网络/超时） · `2` 用法错误 ·
`>=400` HTTP 状态透传（如 `401`） · `130` Ctrl+C。

## 安全与边界（必须遵守）

1. **只用系统注入的 `$GRAPE_SESSION_TOKEN`**：不得从数据库、配置文件、日志、历史、环境变量
   中寻找/猜测其他 token；不得读取 `BOT_GITCODE_TOKEN`/`USER_GITCODE_TOKEN`（已不注入，见上文「写入身份」例外）。
2. **禁止访问 Grape 内部数据**：不得读取 `data/sessions.db`、`user_accounts`、`managed_repos`、
   `configs/`（含 `global-bot-token.json` 等）等 Grape 内部基础设施（`data/workspaces/` 项目知识文档除外）。
3. **403/无权限**：立即停止并回复用户「该操作需要相应权限，请在 GitCode 中手动配置后重试」，
   不要尝试其他 token 或绕行手段。
4. **401（token 失效）**：任务级 token 短命，失效属正常；说明凭据已失效即可，不尝试替换。
5. **接口缺失 / token 失效**：直接输出**任务无法完成的理由**，不要探索其它无关的 token。
6. **不写 token 到任何文件/日志/评论/工具调用之外的地方**。