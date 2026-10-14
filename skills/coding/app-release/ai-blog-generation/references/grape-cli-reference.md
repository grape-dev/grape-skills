# grape CLI 命令参考（ai-blog-generation 子集）

> 配套 `skills/coding/app-release/ai-blog-generation/SKILL.md`。只列本技能真实用到的命令；完整命令面以 `grape commands` / `grape <group> --help` 为准。

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
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out   # Issue 全貌（Spec 评论位置）
```

### 读操作

```bash
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out   # Spec/评论历史
grape git-repo pulls list --owner "$REPO_OWNER" --repo "$REPO_NAME" --state open --json-out                          # 防重复 PR 检查
grape git-repo pulls get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number {n} --json-out                            # PR 详情（优化场景）
grape git-repo pulls comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number {n} --json-out                  # PR 审查反馈（优化场景）
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out                  # 流水线（防重复 A2A）
```

### 写操作

```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"body":"[coding Agent] ..."}'   # 发评论（长 body 用 --json @file）
grape git-repo pulls create --owner "$REPO_OWNER" --repo "$REPO_NAME" --json '{"title":"docs(blog): {主题}","body":"## 概述\n\n发布博客：{主题}","head":"feat/blog-{slug}-{date}","base":"dev","related_issue_nums":["{n}"],"auto_close_issues":true}'   # 创建 PR（related_issue_nums 传 Issue 号数组）
grape git-repo pulls update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number {n} --json '{"body":"### 变更说明\n{...}"}'                          # 补 PR 描述（四段）
grape git-repo pulls comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number {n} --json '{"body":"[coding Agent] ..."}'                    # PR 评论（优化场景）
grape a2a handoff --json '{"agent":"sre","payload":{"repository":"owner/repo","account":"owner","issue_number":N,"pr_number":N,"context":"..."}}'   # A2A 交办 SRE（跳过 QA）
grape tasks complete --json '{...}'                            # 任务收尾（4.8 结构）
```

### 外部服务（合法直连——不含平台 API）

```bash
# AI 模型 API（qwen-image / Wan2.2——外部服务——url/key/model 只从 ai-models.yaml 读）：
python3 - << 'EOF'
import requests
resp = requests.post(IMAGE_URL, headers={"Authorization": f"Bearer {IMAGE_KEY}"},
                     json={"model": IMAGE_MODEL, "prompt": "...", "n": 1, "size": "1024x1024"}, timeout=60)
EOF
# 参考文章/官网页面（外部网页）：
curl -sL --max-time 20 "{URL}" -H "User-Agent: Mozilla/5.0"
# 媒体下载（外部视频/图片 URL）：
curl -sLo /tmp/out.mp4 "{video_url}"
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
| `grape git-repo pulls create` 带 `body` 字段 | create 契约无 body——描述用 pulls update 补（两步法）|

> 警示表是防误用设计：正文只写真实命令，遇到上表命令 = 写错/过期习惯，按对应真实命令执行。