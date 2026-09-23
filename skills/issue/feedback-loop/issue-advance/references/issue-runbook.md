# Issue 运营执行走查表（runbook）

> 目的：把 issue-advance 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量直接使用：`$ACCOUNT`（owner）、`$REPO_NAME`（repo 名 = `${REPO_FULL_NAME#*/}`）、`$ISSUE_NUMBER`、`$PR_NUMBER`（有则填）、`$DEVOPS_EVENT_TYPE`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> **评论前缀硬规**：所有评论 body 一律以 `[issue agent]` 开头；Spec 文档评论以 `[Issue Agent] 📋 Spec Document` 开头。

---

## Step 0 · 任务上下文（必须最先，任何事件都做）

```bash
grape refresh                        # 契约刷新（前置门②）——防本地缓存过期；失败重试 ≤2 次后继续（回退内置快照）
grape tasks current --json-out
grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```

> CLI 自愈安装（仅未装/版本低时）：`timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git`（安装可能无输出——加 timeout 防误判，等待完成）。

## Step 1 · Issue 与上下文（事件 payload 缺编号时定位）

```bash
grape git-repo issues get --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape git-repo issues comments list --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape issues events --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape git-repo pulls list --owner "$ACCOUNT" --repo "$REPO_NAME" --state all --json-out
```

## Step 2 · 项目知识基线（必做；无基线才降级）

```bash
grape knowledge context --repo "$ACCOUNT/$REPO_NAME" --agent_type issue --json-out
# 需要全文时（路径取自 context 结果）：
grape knowledge content --repo "$ACCOUNT/$REPO_NAME" --file "{path}" --json-out
# 降级（仅当标注「无项目知识基线」/ [degraded]）：
grape git-repo repo --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out
grape git-repo tree --owner "$ACCOUNT" --repo "$REPO_NAME" --depth 2 --json-out
```

## Step 3 · 深度可开发性分析（每次处理必做，含评论事件）

- 读 `references/issue-developability-analysis.md`，执行四维分析（需求完整性 → 技术可行性 → 依赖就绪性 → 范围确定性）。
- 输出评级：`ready` / `almost-ready` / `needs-discussion` / `not-feasible`。

## Step 4 · 事件意图（按 SKILL.md 五·路由表选路径）

## Step 5 · 按评级执行动作 + 标签 + 分配

```bash
# 打标签：先查存在性，不存在先创建
grape git-repo labels list --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out
grape git-repo labels create --owner "$ACCOUNT" --repo "$REPO_NAME" --json '{"name":"spec-ready","color":"#0e8a16"}'
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"labels":"{原有标签},新标签"}'
# 分配（按 references/assignee-guide.md）：
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"assignee":"{用户名}"}'
# CODEOWNERS 读取（分配依据）：
grape git-repo contents --owner "$ACCOUNT" --repo "$REPO_NAME" --path CODEOWNERS --ref codeowner --json-out
# 评级动作：
#   ready          → Spec 评论（Step 5b）→ 打 spec-ready → Step 8 A2A coding
#   almost-ready   → 分配项目责任人 → 精确追问 1-2 个问题
#   needs-discussion → 分配责任人 → 逐维度列缺失 → 逐一追问 → 打 need-info
#   not-feasible   → 评论说明不可行 → 打 invalid
```

### Step 5b · Spec 发布（评级 ready 时）

```bash
# 按 references/spec-generation.md 模板写 body 到文件，再 --json @file
printf '{"body":"%s"}' "$(cat /tmp/spec-body.md)" > /tmp/spec.json
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json @/tmp/spec.json
```

## Step 6 · 评论回复（必须，除非是机器人自己的评论）

```bash
# 长文用 @file（同上方式）；短评直接内联
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[issue agent] {回复}"}'
```

## Step 7 · 任务通知（处理结束、责任人最终确定后必做；机器人接管同样要 notify）

```bash
grape tasks notify --json '{"assignee":"{责任人GitCode用户名 或 grape_bot}","repo_key":"$ACCOUNT/$REPO_NAME","issue_number":$ISSUE_NUMBER,"task_description":"Issue #$ISSUE_NUMBER 已分配给你，请处理：{简要任务描述}"}'
# 返回 {ok:false}（责任人未注册平台）→ Issue 评论说明即可。
```

## Step 8 · A2A 交办（需要时）

```bash
# ⚠️ 防悬空：$GRAPE_SCENE_ID 非空时先查场景节点——确认 coding 节点存在再交办
grape scenes detail --scene_id "$GRAPE_SCENE_ID" --json-out    # 仅 ${GRAPE_SCENE_ID:-} 非空时执行
# ⚠️ 防重复：先查 pipeline，已含目标 agent（如 coding:a2a_event）则不重复 A2A，只发评论
grape issues pipeline --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 交办（必须携带真实 issue_number；pr_number 有则填，无则不填，严禁混用）
grape a2a handoff --json '{"agent":"coding","payload":{"repository":"$ACCOUNT/$REPO_NAME","account":"{user}","issue_number":$ISSUE_NUMBER,"pr_number":$PR_NUMBER,"context":"{评级 + Spec 摘要 + Spec 评论位置}"}}'
# A2A 失败（非 2xx/超时）→ 重试 ≤3 次 → 仍失败：评论说明 + next_step 标注人工介入
```

## Step 9 · 关闭建议 / 里程碑（按需）

```bash
# 关闭前验证是否已实现：
grape git-repo commits --owner "$ACCOUNT" --repo "$REPO_NAME" --per_page 20 --json-out
grape git-repo pulls list --owner "$ACCOUNT" --repo "$REPO_NAME" --state all --json-out
# 已实现 → 关闭 + 刷新任务（必做）：
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"state":"closed"}'
grape tasks close --json '{"repo_key":"$ACCOUNT/$REPO_NAME","issue_number":$ISSUE_NUMBER}'
# 里程碑（仅 Issue 正文明确提及版本号时）：
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"milestone_id":{id}}'
```

## Step 10 · 任务收尾（必做，业务动作完成后）

```bash
grape tasks complete --json '{
  "result_text":  "Issue #'$ISSUE_NUMBER' 处理完毕（结论：{分析摘要}）",
  "actions":      ["深度可开发性分析: {评级}", "打标: {标签}", "分配: {负责人}", "Spec: {已发布/未涉及}", "A2A: {coding/qa/sre/vod/无}", "任务通知: {notify结果}"],
  "conclusion":   "{评级}，{已交办开发 / 等待用户补充 / 说明不可行}",
  "artifacts":    ["Issue 评论: {评论位置}", "Spec 文档: {评论位置（如有）}"],
  "issue_summary":"{分析摘要——需求/可行性/依赖/范围 一句话}",
  "next_step":    "a2a_coding 或 等待用户反馈"
}'
```

> ⚠️ **结束信号**：tasks complete 后立即结束任务，不要继续思考或等待输入。A2A 交办成功 ≠ 任务结束（仍需 complete）。结构化字段（actions/conclusion/artifacts/issue_summary）must 真实填充——结尾是下一节点的输入，只传 result_text 会丢结构化归档。

---

## 错误排查速查（命令返回异常时）

> ⚠️ 出错时**先看完整错误**（命令去掉 `| tail -N` 截断，`2>&1` 保留 stderr）；runbook 命令照抄仍失败，才允许 `grape commands <关键词>` / `grape <group> --help` 按 Body fields 修正。**不反复盲试同一命令**。

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名抄错，核对 runbook/reference；仍不确定再 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 里有契约不允许的字段 → `grape git-repo issues update --help` 看 Body fields，删掉多余字段 |
| `issues update` 失败（标签/分配不生效）| 核对字段格式：`labels` 用字符串逗号分隔（`"triaged,spec-ready"`）、`assignee` 用 GitCode 用户名（非显示名）|
| `labels` 创建失败 / 重复 | 先 `labels list` 确认标签存在（不存在才 `labels create`）——不重复创建 |
| `comments create` 失败（长 body 转义问题）| 改用 `--json @file`（body 先写文件，见 Step 5b）|
| `pulls list` / `commits` 返回空 | 属正常（无 PR/无提交）——按「未实现」分支处理，不报错 |
| 401 凭据失效 | 说明「凭据已失效」即可，不换 token（安全硬约束⑤）|
| 403 账户/平台管理类 | 说明需管理员配置/`grape_` 级凭据，本技能不涉及——不绕行 |
| `knowledge context` 返回空/degraded | 降级 README + git-repo 分析并标注 `[degraded]`，不阻塞 |
| 报「契约过期/命令不识别」| 先 `grape refresh` 再重试（前置门②）|