# grape CLI 命令参考（blog-publish 子集）

> 配套 `skills/sre/app-release/blog-publish/SKILL.md`。只列本技能真实用到的平台命令；完整命令面以 `grape commands` / `grape <group> --help` 为准。**博客系统 API 不在此表**（外部 BLOG_HOST——curl 直连合法——见 runbook P1-P6）。

## 认证与安装

- grape 自动读服务端注入的 `$GRAPE_SESSION_TOKEN`，不用配 token。
- 安装：`pip install git+https://gitcode.com/grape-dev/grape-cli.git`（**禁止 `pip install grape`**——PyPI 同名第三方包）。
- 安装/升级流程见 `references/grape-cli-installation.md`。

## 本技能命令面

### 就绪与上下文

```bash
grape --version                                             # CLI 可用性（前置门）
grape refresh                                               # 契约刷新（失败重试 ≤2 次后继续）
grape tasks current --json-out                              # 当前任务上下文（A2A payload 在这里）
```

### 平台写操作

```bash
grape git-repo pulls merge --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$PR_NUMBER"   # 合并 PR（A2A 链路第一步）
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"body":"[blog-publish Agent] ..."}'   # 发布结果反馈（长 body 用 --json @file）
grape tasks complete --json '{...}'                            # 任务收尾（4.8 结构）
```

### 平台读操作

```bash
grape git-repo pulls get --owner "$ACCOUNT" --repo "$REPO_NAME" --number {n} --json-out   # PR 状态核查（P3 前可选——确认未合并）
grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out   # Issue 全貌（上下文兜底）
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
| `curl {BLOG_HOST}/api/...` 带平台 token | 博客系统**无鉴权**——外部系统——不要臆造凭据（也不要把平台 token 发给外部系统）|

> 警示表是防误用设计：正文只写真实命令，遇到上表命令 = 写错/过期习惯，按对应真实命令执行。
> 本技能真实命令面小（3 写 2 读）——平台操作薄、外部博客操作为主。