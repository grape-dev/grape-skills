# grape CLI 命令参考（blog-issue 子集）

> 配套 `skills/issue/feedback-loop/blog-issue/SKILL.md`。只列本技能真实用到的命令；完整命令面以 `grape commands` / `grape <group> --help` 为准。

## 认证与安装

- grape 自动读服务端注入的 `$GRAPE_SESSION_TOKEN`，不用配 token。
- 安装：`pip install git+https://gitcode.com/grape-dev/grape-cli.git`（**禁止 `pip install grape`**——PyPI 同名第三方包）。
- 安装/升级流程见 `references/grape-cli-installation.md`。

## 本技能命令面

### 就绪与上下文

```bash
grape --version                                             # CLI 可用性（前置门）
grape refresh                                               # 契约刷新（失败重试 ≤2 次后继续）
grape tasks current --json-out                              # 当前任务上下文（前序 A2A payload 在这里）
grape events detail --seq {seq} --json-out             # 前序事件详情（参数是 --seq 不是 --event_id）
grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out   # Issue 全貌
```

### 读操作

```bash
grape git-repo issues comments list --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out   # 评论历史
grape git-repo issues list --owner "$ACCOUNT" --repo "$REPO_NAME" --state all --per_page 20 --json-out            # 历史 Issue
grape git-repo pulls list --owner "$ACCOUNT" --repo "$REPO_NAME" --state all --per_page 10 --json-out             # 历史 PR
grape git-repo labels list --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out                                     # 标签查重
grape git-repo contents --owner "$ACCOUNT" --repo "$REPO_NAME" --path CODEOWNERS --ref main --json-out            # CODEOWNERS（指派依据）
grape git-repo repo --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out                                             # 仓库信息（基线降级）
grape issues pipeline --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out                  # 流水线（防重复 A2A）
```

### 写操作

```bash
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"body":"[blog-issue Agent] ..."}'   # 发评论（长 body 用 --json @file）
grape git-repo labels create --owner "$ACCOUNT" --repo "$REPO_NAME" --json '{"name":"type:feature","color":"#0e8a16"}'                              # 建标签（先查重）
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"labels":"spec-ready,blog-issue"}'            # 打标（整体替换）
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"assignee":"{user}"}'                          # 指派
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"state":"closed"}'                             # 关闭 Issue（流程外——先确认）
grape a2a handoff --json '{"agent":"coding","payload":{"repository":"...","account":"...","issue_number":N,"context":"..."}}'                         # A2A 交办
grape tasks notify --json '{"assignee":"{user}","repo_key":"owner/repo","issue_number":N,"task_description":"..."}'                                  # 任务通知（assignee 最终确定后）
grape tasks complete --json '{...}'                            # 任务收尾（4.8 结构）
```

### 外部系统（合法 curl——仅限博客系统/AI 服务）

```bash
curl -s --max-time 10 "https://$BLOG_HOST/health"                 # 博客系统健康
curl -s --max-time 10 "https://$BLOG_HOST/api/lables"             # 博客标签（真实接口拼写——不带 s）
curl -s --max-time 10 "https://$BLOG_HOST/api/articles?page=1&size=2"   # 文章接口探测
```

## ❌ 不存在的命令（警示表——防误用，勿执行）

| 命令 | 说明 |
|------|------|
| `grape api` | 已移除——平台 API 直连通道取消，一律走具体命令 |
| `grape git <verb>` | 透传类命令不存在（可能落入 shell/怪异输出）——用 `grape git-repo ...` 具体命令 |
| `grape tasks close / mine / start / status / clarify` | tasks 组仅有 complete/current/notify/wait（实测 0.3.3——wait 存在，轮询终态用 `tasks wait --task_id <id>`）|
| `grape knowledge context / content` | 知识基线命令不存在——基线由服务端 prompt 内联注入 |
| `grape events detail --event_id` | `--event_id` 参数**不存在**（--help 示例文本是旧写法误导——实测 0.3.3 Options 只有 `--seq`）——正确写法 `--seq {seq}` |
| `grape issues confirm done / status` | User-only 命令——session token (tk_) 会 403——本技能不使用 |
| `grape git-repo branches delete` | 无删除接口——仅 branches list 可查，删除需人工 |

> 警示表是防误用设计：正文只写真实命令，遇到上表命令 = 写错/过期习惯，按对应真实命令执行。