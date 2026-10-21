# VOD-MattPocock 执行走查表（runbook）

> 目的：把「Grilling 澄清 → 无歧义收敛 → 交棒」的**步骤 + 确切命令**固化，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量：`$REPO_OWNER`/`$REPO_NAME`/`$ISSUE_NUMBER`/`$REPO_FULL_NAME`/`$GRAPE_SESSION_TOKEN`。owner 只用 `$REPO_OWNER`。
> 评论前缀硬规：`[VOD Agent]`。

### 防抖纪律
1. owner 只用 `$REPO_OWNER`，不猜 `Jason7602` 等；命令错误先核对注入，不换 owner 重复试错。
2. 一条命令取到即继续；`tree --depth single` 一次看结构，不重复折腾。
3. 命令失败先看完整错误，再按错误排查处理，不盲试。

---

## 统一流程

### Step 0 · 项目知识基线 + 领域词汇（必须最先）
```bash
grape repos project info --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out
grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --depth single --json-out
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path GLOSSARY.md --raw 2>/dev/null   # 领域词汇（存在则用）
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path README.md --raw
```
- 基线可用 → 基于它分析；`degraded`/no files → 降级 README/tree，标注 `[degraded]`。

### Step 1 · 读 Issue 上下文（必做）
```bash
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```

### Step 2 · Grilling 澄清（核心，无歧义前不交棒）
- 对照 `references/grilling-guide.md`：每轮产出「**已确认 / 未确认 / 新问题**」三段；新问题 1-3 个、具体、结合项目。
- **判定**：若收敛仍可在 A/B 之间摇摆（并列歧义）→ 继续澄清；无歧义 → Step 3。
- 澄清交互（评论 + awaiting-input 触达）：
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 已确认：{..}\n仍未确认：{..}\n请补充：1).. 2).."}'
ISSUE_ID="${GRAPE_ISSUE_ID:-$(grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out | jq -r '.id')}"
grape issues awaiting-input --issue_id "$ISSUE_ID" \
  --json '{"questions":"[VOD Agent] 请补充：{具体问题 1-3 个}","reason":"需求尚存歧义，需开发者确认"}' --json-out
```
- ⚠️ 本轮仍回收尾（tasks complete，next_step=`a2a_need_clarify`）；用户 `clarify` 回复后下一轮继续。
- **≤3 轮**；超限 → 评论列「已确认/缺失项」标「待澄清」→ 收尾。

### Step 3 · 收敛输出结构需求单（无歧义后，必做）
按 `grilling-guide.md` §三 模板生成需求单（目标 / 用户故事列表 / 验收 / Out of Scope），评论发布：
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 需求单（已收敛）：\n\n{§三 模板}"}' --json-out
```

### Step 4 · A2A 交办 issue-mattpocock（必做）
```bash
grape a2a handoff --json '{
  "agent": "issue",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": 0,
    "context": "需求已经 Grilling 澄清收敛（评论发布）：{结构需求单摘要}。请按 mattpocock 流程生成 Spec 与切片 tickets。"
  }
}' --json-out
```
- A2A 前查 pipeline 已含 `issue:a2a_event` → 不重复 A2A，直接收尾（next_step=reply_comment）。

### Step 5 · 任务完成流程（必做）
按 SKILL「任务完成流程」调用 `grape tasks complete`（next_step=`a2a_issue` 或 `reply_comment` / `a2a_need_clarify`）。`already:true` 忽略，结束任务。

---

## 错误排查速查

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook/reference；仍不确定 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 字段不在允许集，看 `grape <g> <v> --help` Body fields 删多余字段 |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT，本技能不涉及 |
| `awaiting-input` 幂等 false | 已终态/已等待，忽略（changed:false=幂等）|
| A2A 交办失败 | 重试 ≤3 次；仍失败 → 评论说明 + next_step 标注人工介入 |

## 明确禁止

- ❌ 收敛结论含并列歧义（可能 A 或 B）仍 A2A——必须继续澄清。
- ❌ 修改 Issue 标签/里程碑/分配 / 写代码 / 建 PR / 部署。
- ❌ 裸 `git`（一律 `grape git`）。
- ❌ 不因"等待用户回复"跳过 Step 收尾（tasks complete）。