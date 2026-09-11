# Grape CLI 参考（Coding-CLI 版）

> 本技能**只使用 `grape` CLI**（不再直连 `api.gitcode.com`，也不用 curl 调 API）。
> `grape` 已提供完整且必要的 **grape API / gitcode API / github API / git 原始命令** 的命令行，
> 统一使用系统注入的 **`$GRAPE_SESSION_TOKEN`**（任务级临时，随任务/会话失效）即可操作。

> 前提：执行环境需已安装 `grape` CLI（已随 worker 包 / 主控服务器预装；安装方式见下）。未就绪时请按「安装」指引处理，**不要改用 curl 直连**。

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

## 常用命令（Coding 实际用到）

```bash
# 获取 Issue 完整内容（需求/评论，A2A context 只给摘要，必须用它拉全文）
grape git-repo issues get --owner {owner} --repo {repo} --number {n} --json-out

# 列 Issue（判断重复/已解决）
grape git-repo issues list --owner {owner} --repo {repo} --state all --per_page 20 --json-out

# Issue 评论（body 一律以 [Coding Agent] 开头）
grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} \
  --json '{"body":"[Coding Agent] 这是 Coding 的答复内容。"}'

# 列 PR（是否已有方案 / 查自建 PR 编号）
grape git-repo pulls list --owner {owner} --repo {repo} --state all --per_page 10 --json-out

# 创建 PR（新开发场景；关联 Issue 可让合并后自动关闭）
grape git-repo pulls create --owner {owner} --repo {repo} \
  --json '{"title":"feat: #{n} 标题","head":"feat/issue-{n}","base":"main","inner_issue_nums":"{owner}/{repo}#{n}","close_related_issue":true}'

# 补充/更新 PR body 或标签（PATCH）
grape git-repo pulls update --owner {owner} --repo {repo} --number {pr} \
  --json '{"body":"## 概述\n\n自动实现 Issue #{n}","labels":"auto-pr"}'

# 取 PR 行内评论（优化流程核实审查意见）
grape git-repo pulls comments list --owner {owner} --repo {repo} --number {pr} --json-out

# PR 评论（body 以 [Coding Agent] 开头）
grape git-repo pulls comments create --owner {owner} --repo {repo} --number {pr} \
  --json '{"body":"[Coding Agent] 已根据审查意见完成修改，请重新审查。"}'

# 取 PR 变更文件清单（diff 摘要）
grape git-repo pulls files --owner {owner} --repo {repo} --number {pr} --json-out

# 分支 / 提交
grape git-repo branches --owner {owner} --repo {repo} --per_page 50 --json-out
grape git-repo commits --owner {owner} --repo {repo} --per_page 10 --json-out

# 仓库信息 / 文件内容（降级：本地无 worktree 或代码基线缺失时）
grape git-repo repo --owner {owner} --repo {repo} --json-out
grape git-repo contents --owner {owner} --repo {repo} --path README.md --json-out

# A2A 交办 QA Agent（新开发/优化后通知 QA 审查或重新审查）
grape a2a handoff --json '{"agent":"qa","payload":{...}}'

# 任务自报完成（收尾必做，见 SKILL「任务完成流程」；结构化字段直接传入，服务端组装 result_text，接口见 docs/openapi/01-tasks.md）
grape tasks complete --json '{
  "result_text": "结论：...",
  "next_step": "done",
  "actions": ["动作1", "动作2"],
  "conclusion": "完成情况总结",
  "artifacts": ["PR #N", "commit xxxxxx"],
  "issue_summary": "实现完成 | 改动摘要 | PR 状态"
}'

# 轮询任务至终态
grape tasks wait --task-id t_xxx --timeout 120 --interval 3 --json-out
```

- 所有命令支持 `--json-out`（机器可读单行 JSON）；`-h/--help` 查看参数；`grape commands [pattern]` 列出契约命令。
- 契约不可达时 CLI 自动回退**内置契约快照**（`grape refresh` 显示来源）。
- 命令形态：`grape <组> <动词> [--参数]`；组 `git-repo` 对应全部 GitCode 仓库 REST 接口（issues/pulls/contents/branches/commits/comments 等）。

## git（本地执行，token 零暴露）

`grape git` 是 **git 原生命令透传**：**自动识别仓库**（clone 从 URL 解析，其余从当前目录 `remote.origin.url` 解析），
再用会话 token 换券成**短期平台凭据**经 `GIT_CONFIG` env 注入 git 子进程——**不进命令行、不落磁盘、agent 感知不到**。
仅 gitcode.com 宿主注入；换券失败仅告警、按本机原生行为执行。`grape git --help` 与 `git --help` 一致。

```bash
grape git status                                   # 本地命令（无需凭据）
grape git checkout -b feat/issue-7                # 切换/创建开发分支
grape git clone https://gitcode.com/owner/repo.git # 从 URL 识别仓库 → 注入凭据
grape git pull
grape git add -A
grape git commit -m "feat: #7 描述"
grape git push origin feat/issue-7
```

> 本地代码基线已就绪（coding 工作模型）：Grape 服务端已在当前工作目录准备好该 Issue 的 **git worktree**（分支 `feat/issue-{issue_number}`）。
> 直接以 `grape git` 执行 checkout/add/commit/push 即可；若目录非 git 仓库（降级），改用 `grape git-repo contents` 读写文件。

## 通用兜底（`grape api`）

对没有专门命令的 grape 内部端点，用 `grape api <METHOD> <path> [-d '<JSON>']`：

```bash
grape api GET /api/scenes --json-out
grape api POST /api/tasks/create -d '{"repo_key":"{owner}/{repo}","title":"...","description":"..."}'
# A2A / 自报完成有专属命令，不在此列：grape a2a handoff / grape tasks complete
```

## 退出码

`0` 成功 · `1` 通用/配置错误（缺 token/网络/超时） · `2` 用法错误 ·
`>=400` HTTP 状态透传（如 `401`） · `130` Ctrl+C。

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