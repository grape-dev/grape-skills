# grape CLI 命令参考（iac-sre 专用）

> 来源：cli-code-analysis-spec.md（CLI v0.3.x，契约经 `grape commands` 核对）
> 本文件只列 iac-sre 实际用到的命令子集 + 平台交互纪律。云资源操作（terraform/hcloud/obsutil）非 grape 命令，见 `references/iac-sre-runbook.md` A2-A5。

---

## 1. 安装与就绪检查

grape CLI 由 worker 包预装。使用前检查：

```bash
which grape          # 验证安装；未装/版本过低 → 按 `references/grape-cli-installation.md` 自动安装/升级
grape --version      # 确认版本（≥0.3.2）
```

> ⚠️ grape 未安装时按 `references/grape-cli-installation.md` 自动安装/升级（不 curl 直连 API）；仍装不上才报障。

## 2. 认证与配置

| 项 | 说明 |
|----|------|
| `$GRAPE_SESSION_TOKEN` | 服务端注入，任务级临时 token（`tk_` 前缀），`grape` 自动读取，不需手动 export |
| `$GRAPE_SERVER_URL` | 服务端注入，指向 API 地址 |
| Token 优先级 | `--token` > `GRAPE_SESSION_TOKEN` > `GRAPE_API_TOKEN` > config.json |
| base_url 优先级 | `--base-url` > `GRAPE_BASE_URL` > `GRAPE_SERVER_URL` > config.json > `http://localhost:8000` |
| git 克隆认证 | **`grape git` 透传**（`grape git clone/checkout/log`）——凭据由 grape 按会话 token 内部换短期凭证 |

## 3. 常用命令（iac-sre 实际用到的子集）

### 3.1 任务上下文读取（共用，执行前必做）

| 命令 | 用途 |
|------|------|
| `grape tasks current --json-out` | 获取分配给自己的任务（执行前必读） |
| `grape issues detail --owner {owner} --repo {repo} --number {n} --json-out` | Issue 全貌（资源命名/规格提取） |
| `grape commands [pattern]` | 列出可调用命令（命令发现） |

### 3.2 Issue 评论写操作

| 命令 | 用途 |
|------|------|
| `grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"[sre Agent] ..."}'` | 发 Issue 评论（部署完成摘要/STOP 恢复路径） |

### 3.3 任务完成与收尾

| 命令 | 用途 |
|------|------|
| `grape tasks complete --json '{"result_text":"...","next_step":"done",...}'` | 自报完成（收尾必做，结构见 SKILL 4.8） |

### 3.4 git 与云资源工具（git 用 grape git，云资源用本机工具）

| 工具 | 用途（命令见 iac-sre-runbook） |
|------|------|
| `grape git clone/checkout/log` | 拉取部署代码（会话 token 内部换凭据） |
| `terraform fmt/init/plan/apply/state/output` | IaC 部署与验证（1.7.5 ~ 1.10.5） |
| `hcloud <Service> <Action>` | 华为云资源查重/查询（环境变量凭证，不用 CLI profile） |
| `obsutil cp` | OBS 上传（inventory.json 归档——不用 curl 签名） |

> ⚠️ git 操作一律用 **`grape git`**（凭据内部换、不落盘）；`git-repo git credential` 契约不存在，不要手动引用。

---

## 4. 命令限制与不存在的能力

### ❌ 不存在的命令（`grape <cmd> --help` 返回 No such command，不要尝试）

| 命令 | 说明 |
|------|------|
| `tasks mine` / `tasks start` / `tasks status` / `tasks close` / `tasks clarify` | tasks 组仅 `complete` / `current` / `notify` / `wait` |
| `git-repo git credential` | 契约不存在——git 用 `grape git` 透传 |
| `grape api` | 通用兜底命令 v0.2.2 已移除——契约未覆盖端点无法 CLI 调用，**不要 curl 直连** |
| `events detail --seq {n}` | 本技能不使用（--seq 依赖平台不注入的事件序号；A2A payload 在 tasks current）|

### 本技能不用的能力（其他技能用，此处不引用）

- `git-repo pulls merge` / `pulls create` / `issues create` —— 编码/QA 链路的命令，iac-sre 不发起（sre 是流水线终点，不创建 PR/Issue、不合并、不 A2A 交办）

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
- **403/401 处理**：命令返回 403 或权限不足时，停止操作并回复「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」，不尝试其他 token 或绕行手段。
- **华为云凭证**：只用 `HUAWEI_AK/SK` 环境变量映射（A3 export）——禁用 hcloud CLI profile 里的凭据（权限不一致），不写 .tf 不 printenv。
- **token 不写入文件**：不将 token 写进日志、脚本、Issue 评论或工具调用以外的地方。