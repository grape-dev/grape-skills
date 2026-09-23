# VOD 执行走查表（runbook）

> 目的：把 VOD 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量直接使用：`$ACCOUNT`、`$REPO_NAME`（= `${REPO_FULL_NAME#*/}`）、`$ISSUE_NUMBER`、`$DEVOPS_EVENT_TYPE`。
> **评论前缀硬规**：所有评论 body 一律以 `[VOD Agent]` 开头。

---

## Step 0 · 任务上下文与就绪（必须最先，任何事件都做）

```bash
grape refresh                        # 契约刷新（前置门②）——失败重试 ≤2 次后继续（回退内置快照）
grape tasks current --json-out
# 事件带 seq 时读前序 A2A payload（场景 A 必做）：
grape events detail --seq {seq} --json-out
# 场景 B：读 Issue 全貌
grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```

> CLI 自愈安装（仅未装/版本低时）：`timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git`（安装可能无输出——加 timeout 防误判，等待完成）。

---

## 场景 A · 开发者声音引导建 Issue（vod_signal / 飞书消息）

### A1 · 项目知识基线（必须最先）
- 知识基线由服务端在 prompt「项目知识基线」章节内联注入（或 `grape knowledge context --repo "$ACCOUNT/$REPO_NAME" --agent_type vod --json-out`）
- 标注「无基线」/`[degraded]` → 降级：README + `grape git-repo` 命令

### A2 · 项目历史全貌（必做——防重复/重复反馈聚类）

```bash
grape issues mine --json-out
grape git-repo issues list --owner "$ACCOUNT" --repo "$REPO_NAME" --state all --json-out
grape git-repo pulls list --owner "$ACCOUNT" --repo "$REPO_NAME" --state all --json-out
# 历史反馈画像：聚类此前 auto-submitted by VOD Agent 的 Issue，识别高频主题
```

### A3 · 需求引导漏斗
- 判断消息需求是否清晰（`references/requirement-elicit-guide.md` 四要素）
- 已清晰（一轮）→ 直接 A4；不清晰 → 飞书群多轮引导（每次 1-3 个澄清问题，结合知识基线，≤3 轮）
- 超限仍不清晰 → 建「待澄清」Issue（body 列出已获取/缺失信息）

### A4 · 结构化建 Issue

```bash
# body 按 requirement-elicit-guide §四 模板（目标/现状/期望/验收/优先级/来源）写文件，再 @file
grape issues create --owner "$ACCOUNT" --repo "$REPO_NAME" \
  --json '{"title":"{标题}","description":"{模板结构化 body，标注 auto-submitted by VOD Agent（Feishu）}"}'
```

### A5 · A2A 交办 Issue Agent（含防重复检查）

```bash
# ⚠️ 防重复：先查 pipeline，已含 issue:a2a_event 则不重复 A2A，只发评论
grape issues pipeline --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 交办（必须携带真实 issue_number）
grape a2a handoff --json '{"agent":"issue","payload":{"repository":"$ACCOUNT/$REPO_NAME","account":"{user}","issue_number":$ISSUE_NUMBER,"context":"VOD 已完成需求收敛与结构化，请继续 spec 设计/打标签/分配"}}'
# A2A 失败 → 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入
```

---

## 场景 B · Issue 审视（接管 issue_opened）

### B1 · 项目知识基线（同 A1，若已存在则复用）

### B2 · 自建排除
- Issue 含 `auto-submitted by VOD Agent` → **跳过审视**，直接 B6 交办

### B3 · 清晰度审视
- 读取 Issue 完整内容（title/body/标签/评论——`grape issues detail` + `comments list`），对照四要素
- 结合知识基线判断：可执行性 / 是否重复 / 是否有歧义

```bash
grape git-repo issues comments list --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```

### B4 · 与开发者沟通澄清（不清晰时，≤3 轮）

```bash
# 引原文 + 1-3 个具体澄清问题，结合知识基线提问
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] > {用户原文}\n\n{澄清问题}"}'
# 超限 → 评论列出已获取/缺失信息，标记「待澄清」
```

### B5 · 结构化总结

```bash
# 收敛 body 为模板结构（来源标注「VOD 审视结构化」；不修改标签/分配——Issue Agent 职责）
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"state":"open","body":"{按模板结构化的 body}"}'
```

### B6 · A2A 交办 Issue Agent（同 A5，含防重复检查）

```bash
grape issues pipeline --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape a2a handoff --json '{"agent":"issue","payload":{"repository":"$ACCOUNT/$REPO_NAME","account":"{user}","issue_number":$ISSUE_NUMBER,"context":"VOD 已完成审视与结构化，请继续 spec 设计/打标签/分配"}}'
```

---

## Step 收尾 · 任务完成流程（必做，业务动作完成后）

```bash
grape tasks complete --json '{
  "result_text":  "VOD 处理完毕（结论：{分析摘要}）",
  "actions":      ["知识基线: {已读/降级}", "历史全貌: 分析 {n} 条", "引导: {轮数} 轮/无需", "建/审 Issue: {#n}", "A2A: issue"],
  "conclusion":   "{已建 Issue #n 并交办 / 已审视并结构化 / 待澄清}",
  "artifacts":    ["Issue #{n}（新建/结构化）", "评论: {评论位置}"],
  "issue_summary":"{分析摘要——声音主题/清晰度/去向 一句话}",
  "next_step":    "a2a_issue 或 等待开发者补充"
}'
```

> ⚠️ **结束信号**：tasks complete 后立即结束任务。A2A 交办成功 ≠ 任务结束（仍需 complete）。结构化字段 must 真实填充（结尾 = 下一节点输入）。

---

## 错误排查速查（命令返回异常时）

> ⚠️ 出错时**先看完整错误**（命令去掉 `| tail -N` 截断，`2>&1` 保留 stderr）；runbook 命令照抄仍失败，才允许 `grape commands <关键词>` / `grape <group> --help` 按 Body fields 修正。**不反复盲试同一命令**。

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名抄错，核对 runbook/reference；仍不确定再 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 有契约不允许字段 → `grape <group> <verb> --help` 看 Body fields 删多余 |
| `issues create` 失败 | 核对 title/description 字段（description 用模板结构）；长 body 用 `--json @file` |
| `issues update` 失败 | `body` 字段收敛用 `{"state":"open","body":...}`——不传 `labels`（Issue Agent 职责）|
| `events detail --seq` 返回空 | seq 缺失/前序事件不存在 → 用 `grape events list`（如有）定位或按无前序处理 |
| `comments create` 失败（长 body 转义）| 改用 `--json @file`（body 先写文件）|
| 401 凭据失效 | 说明「凭据已失效」即可，不换 token（安全硬约束⑤）|
| 403 账户/平台管理类 | 说明需管理员配置/`grape_` 级凭据，本技能不涉及——不绕行 |
| `knowledge context` 返回空/degraded | 降级 README + git-repo 分析并标注 `[degraded]`，不阻塞 |
| 报「契约过期/命令不识别」| 先 `grape refresh` 再重试（前置门②）|