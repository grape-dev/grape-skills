# Grape CLI 参考（VOD 试点版）

> 本技能**只使用 `grape` CLI**（不再直连 `api.gitcode.com`，也不用 curl 调 API）。
> 平台 token 不再注入/使用（`BOT_GITCODE_TOKEN` 已弃用）；认证一律用系统已注入的
> **`$GRAPE_SESSION_TOKEN`**（任务级临时，随任务/会话失效）。

> 前提：执行环境需已安装 `grape` CLI（已随 worker 包 / 主控服务器预装；安装方式见下）。未就绪时请按「安装」指引处理，**不要改用 curl 直连**。

## 安装（grape CLI）

`grape` 由运维/部署侧预装，agent **一般不需也不应自行安装**：

- **worker**：重跑一键安装脚本即获得（`install-worker.sh` 会自动在 worker `.venv/bin` 生成 `grape` 并注入 PATH）；手建 worker 按 `DEPLOYMENT-WORKER.md §5.5` 手动安装。
- **主控服务器**：已装于 `/opt/grape-cli`（`ln -sf /opt/grape-cli/bin/grape /usr/local/bin/grape`）。
- **自装（有权限时）**：`python3 -m pip install <grape 源码 cli/ 目录>`（自动带 click/httpx 依赖）。

> ⚠️ **禁止 `pip3 install grape`**：PyPI 上的 `grape` 是**第三方公有包**，不是本项目的 CLI，装错会误导命令执行。

agent 内若 `which grape` 无结果：说明执行环境未就绪，直接回复「当前执行环境未安装 grape CLI，请管理员在 worker 安装后重试」，**不要**自行安装，也**不要**改用 curl 直连。

## 认证（无需手动设置）

- `$GRAPE_SESSION_TOKEN` **已由服务端注入环境变量**，`grape` 自动读取（优先级：`--token` 参数 > 该环境变量 > 配置文件）。
- **不需要** `export GRAPE_SESSION_TOKEN=...`，也不需要写 `~/.grape/config.json`。
- 服务端地址自动取**已注入的环境变量 `$GRAPE_SERVER_URL`**（`grape` 直接读取，无需每次 `--base-url`）；如需覆盖可用 `--base-url <url>`。
- token 是**任务级临时**的：任务结束即失效；命令报 401 说明凭据已失效，直接说明「凭据已失效」即可，不尝试换 token。

## 常用命令（VOD 实际用到）

```bash
# 列最近 Issue（判断重复/已解决）
grape git-repo issues list --owner {owner} --repo {repo} --state all --per_page 20 --json-out

# 建 Issue（VOD 引导产出）
grape git-repo issues create --owner {owner} --repo {repo} \
  --json '{"title":"...","body":"...","assignee":""}'

# 更新/结构化 Issue body
grape git-repo issues update --owner {owner} --repo {repo} --number {n} \
  --json '{"body":"结构化后的 body"}'

# Issue 评论（body 一律以 [VOD Agent] 开头）
grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} \
  --json '{"body":"[VOD Agent] 这是 VOD 的答复内容。"}'

# 列 PR（是否已有方案）
grape git-repo pulls list --owner {owner} --repo {repo} --state all --per_page 10 --json-out

# 分支 / 提交（知识基线增量判断）
grape git-repo branches --owner {owner} --repo {repo} --per_page 50 --json-out
grape git-repo commits --owner {owner} --repo {repo} --per_page 1 --json-out

# git 本地传输（clone/push 等，token 进程内注入，agent 不接触平台 token）：
# 用 --repo 指定仓库 + 透传任意 git 原生命令
grape git --repo {owner}/{repo} status
```

- 所有命令都支持 `--json-out`（机器可读单行 JSON，供自身解析）。
- 分页：`--per_page 20`（max 100）；出参结构 = GitCode 平台实际结构。

## 命令与 URL 对应（仅供排查，勿改用 curl）

| 命令 | 对应接口 |
|------|----------|
| `grape git-repo issues list` | `GET {{SERVER_URL}}/api/repos/{owner}/{repo}/issues` |
| `grape git-repo issues create` | `POST …/issues` |
| `grape git-repo issues update` | `PATCH …/issues/{number}` |
| `grape git-repo issues comments create` | `POST …/issues/{number}/comments` |
| `grape git-repo pulls list` | `GET …/pulls` |
| `grape git-repo branches` | `GET …/branches` |
| `grape git-repo commits` | `GET …/commits` |
| `grape git --repo o/r <cmd>` | 本地 git 协议（token 经 CLI 进程内注入） |

> A2A 交办（`POST /api/a2a`）已有专属命令 **`grape a2a handoff`**（token/base_url 自动注入）：
> `grape a2a handoff --json '{"agent":"issue","payload":{...}}'`——见 `requirement-elicit-guide.md` §五。

## 通用兜底（`grape api`）

对没有专门命令的 grape 内部端点，用 `grape api <METHOD> <path> [-d '<JSON>']`：

```bash
grape api GET /api/scenes --json-out
grape api POST /api/tasks/create -d '{"repo_key":"{owner}/{repo}","title":"...","description":"..."}'
# A2A 有专属命令，不在此列：grape a2a handoff
```

## 安全与边界（必须遵守）

1. **只用系统注入的 `$GRAPE_SESSION_TOKEN`**：不得从数据库、配置文件、日志、历史、环境变量
   中寻找/猜测其他 token；不得读取 `BOT_GITCODE_TOKEN`/`USER_GITCODE_TOKEN`（已不注入）。
2. **禁止访问 Grape 内部数据**：不得读取 `data/sessions.db`、`user_accounts`、`managed_repos`、
   `configs/`（含 `global-bot-token.json` 等）等 Grape 内部基础设施。
3. **403/无权限**：立即停止并回复用户「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」，
   不要尝试其他 token 或绕行手段。
4. **401（token 失效）**：任务级 token 短命，失效属正常；说明凭据已失效即可，不尝试替换。
5. **不写 token 到任何文件/日志/评论/工具调用之外的地方**。