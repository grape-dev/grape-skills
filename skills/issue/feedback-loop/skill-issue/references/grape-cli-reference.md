# grape CLI 命令参考（skill-issue 专用）

> 来源：cli-code-analysis-spec.md（CLI v0.3.x，契约经 `grape commands` 核对）
> 本文件只列 skill-issue 实际用到的命令子集 + 平台交互纪律。云资源操作（terraform/hcloud/obsutil）非本技能范围。git 操作用 `grape git` 透传（不接触平台 token）。

## §1 安装与就绪（自愈）

- 前置：`grape --version` ≥ 0.3.2；未装/过低 → 按 `references/grape-cli-installation.md` 自动安装/升级 → 再验；仍不可用 → 结束任务并说明
- 契约保鲜：`grape refresh`（失败重试 ≤2 次后回退内置快照继续）

## §2 认证（平台注入，自动读取）

- grape CLI **自动读取**服务端注入的 `$GRAPE_SESSION_TOKEN`——不需要也不允许手动传 token
- git 操作：用 **`grape git clone/log` 透传**（凭据由 grape 内部换短期凭证）
- ❌ 禁止 `curl`/`requests` 直连平台 API（含 api.gitcode.com）——平台交互一律 grape CLI

## §3 本技能使用子集（照抄执行，不 help 探索）

### 3.1 任务上下文

```bash
grape tasks current --json-out
```

### 3.2 Issue 读取

```bash
grape git-repo issues get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 全部评论（Step 0 危险操作确认检查用）：
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 可用标签（判断标签缺失/更新）：
grape git-repo labels list --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out
```

### 3.3 Issue 写操作

```bash
# 打标签 / 指派 / 更新：
grape git-repo issues update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"labels": "triaged", "assignee": "<模块负责人用户名（从 CODEOWNERS 匹配结果取）>"}'
# 关闭（含"关闭 Issue 后刷新任务"场景）：
grape git-repo issues update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"state": "closed"}'
# 里程碑（Issue 正文提及版本号时）：
grape git-repo issues update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"milestone_id": <id>}'
# 评论回复（前缀 [Issue Agent]）：
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"body": "[Issue Agent] <正文>"}'
```

### 3.4 关联 PR / 提交历史（验证外部 claim、关闭建议）

```bash
grape git-repo pulls list --owner "$REPO_OWNER" --repo "$REPO_NAME" --state all --json-out
grape git-repo commits --owner "$REPO_OWNER" --repo "$REPO_NAME" --per_page 20 --json-out
```

### 3.5 任务通知（⚠️ 处理结束必做——见 SKILL 硬约束⑧ + 4.8）

```bash
grape tasks notify --json '{"assignee": "<责任人VCS用户名 或 grape_bot>", "repo_key": "$REPO_FULL_NAME", "issue_number": $ISSUE_NUMBER, "task_description": "Issue #<N> 已分配给你，请处理：<简要任务描述>"}'
```

### 3.6 A2A 交办

```bash
grape a2a handoff --json '{"agent": "<coding/sre/vod/qa>", "payload": {"repository": "$ACCOUNT/$REPO_NAME", "account": "$ACCOUNT", "issue_number": $ISSUE_NUMBER, "pr_number": 0, "context": "<需求摘要 + 已确认信息>"}}'
# 失败 → 重试 ≤3 次 → 仍失败：评论说明 + 结束任务（人工介入）
```

### 3.7 任务收尾（所有业务动作完成后必做）

```bash
grape tasks complete --json '{"result_text": "<一句话结论>", "actions": ["<做了什么>"], "conclusion": "<处理结论>", "artifacts": ["<产物>"], "next_step": "<下一步建议>"}'
```

## §4 ❌ 不存在的命令 / 禁用能力（照着格式用，不要尝试）

| 命令/能力 | 真相 |
|-----------|------|
| `grape tasks close` / `tasks status` / `tasks mine` / `tasks start` / `tasks clarify` | tasks 组仅 `complete` / `current` / `notify` / `wait` |
| `grape api ...`（通用 API 兜底） | 已从 CLI 移除（0.2.2），且平台禁止直连 |
| `grape knowledge context/content` | 不存在——知识基线由平台 prompt 内联注入（服务端维护，Agent 不自取） |
| `grape events detail --seq {n}` | 本技能**不需要** events detail——事件 payload 在 `tasks current`/A2A context；`--seq` 参数真实但平台**不注入** `$SEQ`——不可执行死路；`--event_id` 参数**不存在**（--help 示例旧写法误导）|
| `curl`/`requests` 直连平台 API | 禁止（含 api.gitcode.com、`POST /api/a2a`、`POST /api/tasks/notify` 等旧写法） |

## §5 退出码（grape 统一）

| 码 | 含义 | 动作 |
|----|------|------|
| 0 | 成功 | 继续 |
| 1 | 通用错误（含 auth 失败 / repo 不存在 / dialect 不支持） | 看 stderr；auth 类 → 检查会话凭据（`$GRAPE_SESSION_TOKEN` 预置状态——不访问内部数据，见 SKILL 硬约束③） |
| 2 | 参数错误 | `--help` 核对字段（一次，不反复探索） |
| 3 | 命令不存在 | **不要尝试**；用 §4 正确替代 |
| 10 | 网络错误（超时 30s/连接失败） | 重试 ≤2 次；仍失败 → 回退内置快照 |

## §6 安全边界

- 只用平台注入 token（`$GRAPE_SESSION_TOKEN`）；严禁寻找/读取其他 token
- token 不得落盘（不写文件/日志/评论/脚本）
- 403/无权限 → 立即停止该操作并回复用户（不找替代 token、不绕行）
- 长命令（create/update/handoff 等）用 `--json @file.json` 避免转义出错