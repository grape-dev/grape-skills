# Issue 运营执行走查表（skill-issue runbook）

> 目的：把 skill-issue 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> **CLI 纪律**：本表已覆盖本技能全部平台交互命令（issues / pipeline / a2a / tasks）——**禁止 curl 直连平台 API**。
> 环境变量直接使用：`$ACCOUNT`、`$REPO_NAME`（= `${REPO_FULL_NAME#*/}`）、`$ISSUE_NUMBER`、`$PR_NUMBER`、`$DEVOPS_EVENT_TYPE`、`$BOT_USERNAME`。
> **评论前缀硬规**：所有评论 body 一律以 `[Issue Agent]` 开头。

---

## Step 0 · 任务上下文与就绪（必须最先，任何事件都做）

```bash
# ⚠️ CLI 前置自愈（最先）：`grape --version` ≥0.3.2；未装/版本过低 → 按 references/grape-cli-installation.md
#    自动安装/升级（timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git——安装可能无输出，加 timeout 防误判）
#    → 装好再验证一次；仍不可用 → 输出「前置检查未通过：<原因>」并结束任务（不降级直连）
grape --version
grape refresh 2>&1 && echo REFRESH_OK        # 契约保鲜；失败重试 ≤2 次后回退内置快照继续
grape tasks current --json-out               # 任务上下文（事件 payload / A2A context 在这里）
grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out 2>&1 | head -120
```

## 步骤 0 · 前置判断：危险操作确认检查（⚠️ 必须最先执行——在任何分析之前）

```bash
# 读 Issue 评论历史，找自己之前的「⚠️ 危险操作确认」标记 + 后续用户「确认」回复：
grape git-repo issues comments list --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```
- **找到标记 且 有用户「确认」** → **已确认** → 跳到步骤 7 直接 A2A coding（context 带「用户已确认危险操作」）
- **找到标记 但 无用户「确认」** → 回复「仍在等待确认，请回复'确认'继续」→ 任务结束（4.8）
- **未找到标记** → 正常流程继续步骤 1

## 步骤 1 · 确定 Issue 与上下文

- 从事件 payload 提取 issue 编号（`$ISSUE_NUMBER`）；缺失时定位：
```bash
grape git-repo issues get --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 或
grape git-repo issues list --owner "$ACCOUNT" --repo "$REPO_NAME" --state open --json-out | head -60
```
- 读取该 Issue 全部评论/标签/关联 PR（`git-repo issues comments list`——步骤 0 已拉）了解完整上下文。

## 步骤 2 · 项目知识基线（⚠️ 必须执行）

- 基线由 Grape 服务端在 prompt「项目知识基线」章节**内联注入**——直接使用；如需全文读取该章节末尾标注的副本路径。
- **不再自行生成**（服务端统一维护）。
- 无基线 / `[degraded]` → 降级分析（README + git-repo contents），不阻塞：
```bash
grape git-repo contents --owner "$ACCOUNT" --repo "$REPO_NAME" --path README.md --json-out
grape git-repo tree --owner "$ACCOUNT" --repo "$REPO_NAME" --path skills --json-out | head -60
```

## 步骤 3 · 深度可开发性分析（⚠️ 每次处理都执行）

- 读 `references/issue-developability-analysis.md` → 四维分析（需求完整性 → 技术可行性 → 依赖就绪性 → 范围确定性）→ 评级：`ready` / `almost-ready` / `needs-discussion` / `not-feasible`。

## 步骤 4 · 理解事件意图

- 按 SKILL 4.2 路由表判定本次动作（开发/下架/评论/澄清/关闭/质疑分配/修改 Spec/确认危险操作…）。核心分流：

| 场景 | 动作 |
|------|------|
| `$DEVOPS_EVENT_TYPE` = a2a_event / issue_comment + 启动开发意图 | 步骤 5（评级 → Spec → 危险识别）|
| 下架类需求（下架/撤回/unpublish，不含"删除"）| **不生成 Spec** → 直接 A2A SRE（context 带需求摘要+操作类型）|
| 危险已确认（步骤 0 命中）| 步骤 7 直接 A2A coding |
| 评论补充信息 | 重跑步骤 3 更新评级 |
| 请求关闭 Issue | 验证后回复建议（关闭 = 流程外写操作——按 4.7）|

## 步骤 5 · 按评级执行动作 + 标签 + 分配 + 危险场景识别

```bash
# 打标签 + 分配（整体替换语义——必须携带既有标签；labels 字符串逗号分隔；assignee 用 GitCode 用户名）：
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"labels":"feature,triaged,spec-ready","assignee":"<用户名 或 $BOT_USERNAME>"}' --json-out
```

| 评级 | 动作 |
|------|------|
| **ready** | 需求类型判断：下架 → A2A SRE（不 Spec）；其他 → 生成 Spec（`references/spec-generation.md`）→ 贴评论 → 打 `spec-ready` 标签 → **危险场景识别**（付费资源/删除/不可逆——见 SKILL 4.3 步骤 5 危险类型表）→ 无危险：检查华为云字段（条件性）→ A2A coding；有危险：Spec Risks 标注 + 评论「⚠️ 危险操作确认」（列出危险项 + "请回复'确认'继续"）→ 任务结束（不 A2A 不等待）|
| **almost-ready** | 分配给项目责任人 → 精确追问 1-2 个问题 |
| **needs-discussion** | 分配责任人 → 逐维度列缺失 → 逐一追问 → 标记 `need-info` |
| **not-feasible** | 评论说明不可行 → 标记 `invalid` |

华为云 Spec 字段检查（条件性）：Spec 含 Huawei Cloud Skill Details 段时——Target Service / Feature Scope / Trigger Scenarios 必须从 Issue 提取，缺失 → Spec Open Questions 标注 + 评论请求补充 → 不打 spec-ready → 任务结束；Execution Mode / CLI Operations / Skill Name / IAM Permissions 可留空标注「待 creator Step 2 验证」。

## 步骤 6 · 评论回复（⚠️ 必须，除非是机器人自己的评论）

```bash
# 前缀固定 [Issue Agent]；长 body 先写文件再 --json @file（防转义）：
printf '%s' '{"body":"[Issue Agent] <评论内容>"}' > /tmp/skill-issue-comment.json
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" \
  --number "$ISSUE_NUMBER" --json @/tmp/skill-issue-comment.json --json-out
```

## 步骤 7 · A2A 交办（需要时——危险已确认或无危险）

```bash
# 先防重复：查 pipeline 是否已含目标 agent 的 a2a 记录：
grape issues pipeline --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out | head -40
# 交办（agent 名从 prompt 底部 Agent 列表取——勿凭记忆；issue_number 必填；已确认危险时 context 带"用户已确认危险操作"）：
grape a2a handoff --json '{
  "agent": "<coding/qa/sre/vod>",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": 0,
    "context": "<需求摘要 + 已确认信息>"
  }
}'
# A2A 非 2xx/超时 → 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入
```

## 步骤 收尾 · 任务完成流程（必做——任何分支都必须执行到最后；顺序：先 notify 后 complete）

```bash
# 1. 任务通知（硬约束⑧——责任人最终确定后必做，含机器人接管；{ok:false}=责任人未注册平台→评论说明即可继续）：
grape tasks notify --json '{
  "assignee": "<责任人VCS用户名 或 grape_bot>",
  "repo_key": "'"$REPO_FULL_NAME"'",
  "issue_number": '"$ISSUE_NUMBER"',
  "task_description": "Issue #'"$ISSUE_NUMBER"' 已分配给你，请处理：<简要任务描述>"
}'
# 2. 任务收尾（tasks 组无 close 命令——收尾统一用 complete）：
grape tasks complete --json '{
  "result_text": "<处理结论>",
  "actions": ["做了什么，如 analyzed:issue / generated:spec / confirmed:dangerous-operation / a2a:coding"],
  "conclusion": "<处理结论（已 A2A coding / 等待用户确认危险操作 / 需求不清晰需 vod 澄清）>",
  "artifacts": ["产生的产物：Spec 文档评论 / 标签 / 分配 / 危险操作确认评论"],
  "next_step": "<下一步建议>"
}'
# 3. 最终答复末尾输出结构化 JSON 块（actions/conclusion/artifacts/issue_summary must 真实填充——结尾是下一节点的输入）
```

> ⚠️ **结束信号**：complete 后立即结束任务，不要继续思考或等待输入。危险操作等待确认 = 任务结束（不 A2A、不等待——用户回复"确认"会再次触发本技能，由步骤 0 处理）。

---

## 错误排查速查（命令返回异常时）

> ⚠️ 出错时**先看完整错误**（命令去掉 `| head/tail` 截断，`2>&1` 保留 stderr）；runbook 命令照抄仍失败，才允许 `grape commands <关键词>` / `grape <group> --help` 修正。**不反复盲试同一命令**。

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名抄错，核对本 runbook；仍不确定再 `grape commands <关键词>` |
| 命令 403/无权限 | 停止该操作，回复「需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」——不换 token 不绕行（硬约束④）|
| 401/凭据失效 | 说明「凭据已失效」即可（tk_ 短命属正常）——不替换不绕行（硬约束⑤）|
| `tasks notify` 返回 `{ok:false}` | 责任人未注册平台——Issue 评论说明即可，继续收尾不阻塞 |
| A2A 非 2xx/超时 | 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入 |
| 标签 create 重复/失败 | 先 `labels list` 确认存在（不存在才 create）——不重复创建 |
| 打标/分配 `issues update` 不生效 | 核对字段：`labels` 字符串逗号分隔整体替换、`assignee` 用 GitCode 用户名 |
| `comments create` 长 body 转义失败 | 改用 `--json @file`（body 先写文件）|
| 报「契约过期/命令不识别」| 先 `grape refresh` 再重试（前置门②）|
| 基线降级/`[degraded]` | README + git-repo contents 降级分析——不阻塞 |