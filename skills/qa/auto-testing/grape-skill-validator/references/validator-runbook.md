# grape-skill-validator 执行走查表（validator-runbook）

> 目的：把「skill 合规检查」的**每一步要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名）、`$REPO_FULL_NAME`（owner/repo）、`$ISSUE_NUMBER`、`$PR_NUMBER`、`$GRAPE_SCENE_ID`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> ⚠️ **owner 只用 `$REPO_OWNER`**；`$ACCOUNT` 是触发人 actor，**仅用于 A2A payload `account` 字段**。
> **评论前缀硬规**：所有评论 body 一律以 `[QA Agent]` 开头。

---

## 统一流程（skill 合规检查）

### Step 0 · 前置 + 读任务上下文（必须最先）
```bash
# ① 任务上下文
grape tasks current --json-out
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape events detail --seq {seq} --json-out   # 前序 A2A payload（coding 交棒）

# ② 场景节点（A2A 分流前核验用）
echo "scene_id=${GRAPE_SCENE_ID:+set}"
SCENE_NODES="$(grape scenes detail --scene_id "$GRAPE_SCENE_ID" --json-out 2>/dev/null)"
echo "scene_agents: $(echo "$SCENE_NODES" | jq -r '[.nodes[]?.tag // .nodes[]?.skill] | unique | join(",")' 2>/dev/null)"
```
- 从 payload/context 提取 `skill_path`（被检查 skill 目录）；缺失 → `grape issues clarify --issue_id ${GRAPE_ISSUE_ID:-{issue_id}} --json '{"message":"需要 skill_path 参数"}'`（--issue_id 优先用注入的 `$GRAPE_ISSUE_ID`）。
- **提取 `flow_nodes`**（A2A context / Spec「流程设计」段的流程节点：`pending-review`/`awaiting-input`/`tasks notify`，无则 `无`）——供 Step 2 H6 需求追溯核对。
- 场景未绑定（`$GRAPE_SCENE_ID` 空）→ 跳过核验，按常见约定路由（coding/sre）。

### Step 1 · 读被检查 skill 文件（必做）
```bash
# skill_path 通常为 .grape/skills/{agent_type}/{name}/（本流水线生成地）或 skills/{agent_type}/{name}/
# 用 read 工具读：
#   {skill_path}/SKILL.md 全文
#   {skill_path}/references/ 下所有 .md
```
- 目录不存在 / SKILL.md 缺失 → 报告 ❌ 结构错误，进入 Step 6 收尾（next_step=a2a_coding）。

### Step 2 · 按质量检查清单逐项验证（必做）
- 对照 `references/checklist.md`（A-K）逐项检查：frontmatter / 安全硬约束 / Prerequisites / 环境变量表 / 处理流程（runbook 引用）/ 任务完成流程 / reference 完整性 / 命令与参数规范 / A2A-建 PR 规范 / 其他。
- 每项标注 ✅ / ❌ + 原因；记录不合规项 `文件:行号 + 问题 + 修正建议`。

### Step 3 · 交叉验证（必做，见 `references/grape-cli-reference.md`）
```bash
# 命令验证：核对被检查 skill 中出现的 grape 命令是否在事实基线存在
grape commands | grep {关键词}    # 或对照 reference §4 全量清单
```
- **命令一致性**：对照 `grape-cli-reference.md` §4 逐个核对。
- **schema 字段一致性**：--json body 字段对照 §6（注意 PRCreateBody 用 `related_issue_nums`/`auto_close_issues`，非旧字段）。
- **不存在能力一致性**：对照 §7。
- **流程节点一致性（H6）**：用 Step 0 提取的 `flow_nodes` 对照被检查 skill——声明了 `pending-review` 须有审批步骤、`awaiting-input` 须有澄清收尾步骤（且未误用 `issues awaiting-input` 状态接口）、`tasks notify` 仅任务分派语义不得作结果通知。

### Step 4 · 输出检查报告并发布评论（必做）
- 按 `references/checklist.md` 末尾「检查报告输出格式」。
- 发布评论：PR 有 `$PR_NUMBER` → PR 评论；PR 评论 405（已合并）→ 发 Issue 评论：
```bash
grape git-repo pulls comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" \
  --json '{"body":"[QA Agent] 检查报告\n\n{报告内容}"}' --json-out
# 405 时改发 Issue：
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[QA Agent] 检查报告\n\n{报告内容}"}' --json-out
```

### Step 5 · A2A 分流（必做，按检查结果）
**情况 A — 检查不通过 → A2A 交办 coding agent**：
```bash
grape a2a handoff --json '{
  "agent": "coding",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": '"${PR_NUMBER:-0}"',
    "context": "QA 检查发现 N 项不合规，请修复以下问题后更新 PR：\n{不合规项清单，含 文件:行号 + 问题 + 修正建议}"
  }
}' --json-out
```

**情况 B — 全部通过 + `pull_request_merged`（PR 已合并）→ A2A 交办 sre agent**：
```bash
grape a2a handoff --json '{
  "agent": "sre",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": '"${PR_NUMBER:-0}"',
    "context": "QA 合规检查全部通过（{总项数}/{总项数}），PR #'"${PR_NUMBER:-0}"' 已合并。请执行 skill 发布/上传流程。"
  }
}' --json-out
```

**情况 C — 全部通过 + PR 未合入 → 显式 `pending-review` 置审核点（必做，参考 qa-cli Step 6b）**
> ⚠️ **审查通过 = 交付决策点**。凡检查通过且 PR **未合入**、需用户确认是否合入的，**必须用 `pending-review` 显式置审核点**（触达用户拍板）；**禁止在评论里只写"可合入/待合并"就直接收尾**——无审核点则用户无触达、状态不一致。

```bash
# ISSUE_ID 优先用已注入环境变量 $GRAPE_ISSUE_ID；未注入才降级用 issues detail 解析
ISSUE_ID="${GRAPE_ISSUE_ID:-$(grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out | jq -r '.id')}"
# ① 置审核点（review_points=审查结论，references=PR#；changed:true=成功）
grape issues pending-review --issue_id "$ISSUE_ID" \
  --json '{"review_points":"PR #'"${PR_NUMBER:-0}"' skill 合规检查全部通过（{总项数}/{总项数}），请确认是否合入","references":"PR #'"${PR_NUMBER:-0}"'"}' --json-out
```

- **用户评论续接**（平台恢复 processing 后，下一轮 qa 事件按用户回复判定）：
  - 用户同意合入/完成 → `review-pass target=done` **并处理 PR 合入 + A2A 通知 sre**（仅最终合入决策；⚠️ **合入成功后必须 A2A 交办 sre，否则 SRE Agent 收不到后续发布/上传任务**）：
    ```bash
    # ① 标记审核通过（仅 pending_review 态有效）
    grape issues review-pass --issue_id "$ISSUE_ID" --json '{"target":"done","evidence":"用户确认合入（评论 {id}）"}' --json-out
    # ② 显式合入 PR（409 冲突/不可合并 → 评论说明原因，不强行合并）
    grape git-repo pulls merge --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out
    # ③ 合入成功 → A2A 通知 sre agent（payload 同情况 B，否则 SRE 收不到后续任务）
    grape a2a handoff --json '{
      "agent": "sre",
      "payload": {
        "repository": "'"$REPO_FULL_NAME"'",
        "account": "'"$ACCOUNT"'",
        "issue_number": '"$ISSUE_NUMBER"',
        "pr_number": '"${PR_NUMBER:-0}"',
        "context": "skill 合规检查全部通过（{总项数}/{总项数}），用户确认合入，PR #'"${PR_NUMBER:-0}"' 已合入。请执行 skill 发布/上传流程。"
      }
    }' --json-out
    ```
    - 若 `pulls merge` 失败（409/不可合并）→ 评论说明不可合入原因，**不 A2A sre**，不强行合并。
  - 用户同意继续下一环节（非最终合入）→ `review-pass target=processing`：
    ```bash
    grape issues review-pass --issue_id "$ISSUE_ID" --json '{"target":"processing","evidence":"用户确认（评论 {id}）"}' --json-out
    ```
  - 用户要求修改/打回 → `review-reject`（打回重做或转澄清）：
    ```bash
    grape issues review-reject --issue_id "$ISSUE_ID" --json '{"target":"processing","reason":"用户要求修改：{要点}"}' --json-out
    ```
- ⚠️ `pending-review` 不终态化——**本轮仍走 Step 6 `tasks complete` 收尾（next_step=reply_comment）**；`review-pass target=done` 才置 completed 并合入 PR + **A2A 通知 sre**（next_step=a2a_sre）。
- ⚠️ 需用户补充信息（非拍板）→ 用 `awaiting-input`，不混用。

> ⚠️ **A2A 交办的是 agent（coding/sre），不是技能名**；A2A 前若场景未绑定跳过核验，绑定则先 `SCENE_NODES` 确认对应 agent 节点存在，未命中 → 评论说明 + 收尾。

### Step 6 · 任务完成流程（必做，任何分支都必须执行到最后）
> ⚠️ **强约束：收尾 = `grape tasks complete`（情形一）**，最后一个动作；评论发完 ≠ 任务完成。结构化字段**必须真实填充**。

按分支选定 `next_step`：不通过已 A2A coding→`a2a_coding`；通过+merged 已 A2A sre / 用户确认合入后已完成 merge+A2A sre→`a2a_sre`；通过未合入已置 pending-review→`reply_comment`。

```bash
grape tasks complete --json '{
  "result_text": "结论：skill {skill_path} <合规检查全部通过 / 发现 N 项不合规>。",
  "next_step": "reply_comment",
  "actions": ["读取 skill 文件", "按质量检查清单逐项验证", "交叉验证命令/schema/不存在能力", "发布审查评论", "置 pending-review 审核点 / A2A 交办 coding/sre（按结果）"],
  "conclusion": "检查 {skill_path}：<全部合规 / 不合规 N 项>；<已置 pending-review 待用户确认 / 已 A2A coding 修复 / 已 A2A sre 发布>",
  "artifacts": ["检查报告", "审查评论（comment id=XXXXXX）", "pending-review 状态变更 / A2A event seq=XXXX（如交办）"],
  "issue_summary": "QA 检查 <通过/未通过> | {skill_path} | <待用户确认合入 / 已交办 coding / sre>"
}'
```
> ✅ **结构化字段必填**（actions/conclusion/artifacts/issue_summary），只传 result_text 丢归档。`already:true` 忽略。**然后结束任务**。

---

## 错误排查速查

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook/reference；仍不确定 `grape commands <关键词>` |
| `grape issues clarify` 字段错误 | 用 `--issue_id`（number）+ `--json {"message":"..."}`，删多余字段 |
| PR 评论 405（已合并） | 改发 Issue 评论（`git-repo issues comments create`） |
| `grape commands | grep` 无结果 | 被检查 skill 命令可能编造 → 记 ❌ 命令一致性不合规 |
| `pending-review` 返回 changed:false | 已终态/已退出（幂等）——忽略，按已置审核点处理收尾 |
| `pulls merge` 失败（409 冲突） | 评论说明不可合入原因，不强行合并；**不 A2A sre** |
| `pulls merge` 成功 | **必须跟随 A2A 交办 sre agent**（`a2a handoff agent=sre`），否则 SRE Agent 收不到后续发布/上传任务 |
| `a2a handoff` 非 2xx / 超时 | 重试 ≤3 次；仍失败 → 评论说明 + next_step 标注人工介入 |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT，本技能一般不涉及 |

## 明确禁止

- ❌ 修改被检查 skill 文件 / 创建/删除/修改任何文件（只读不写）。
- ❌ A2A 交办写技能名（如 `grape-skill-generator`）——用 agent 名 `coding`/`sre`。
- ❌ 编造命令或 schema（交叉验证以事实基线为准）。
- ❌ 修复 skill 不合规项 / 创建 PR（仅报告与分流）。
- ❌ **漏检需求单 `flow_nodes` 的流程节点落地**——声明了 `pending-review`/`awaiting-input`/`tasks notify` 却未在 runbook 找到对应步骤/语义时，须按 H6 记 ❌ 或保留提示。
- ❌ **检查通过 + PR 未合入时，只写"可合入/待合并"就收尾**——必须 `pending-review` 置审核点（触达用户拍板）。
- ❌ **`pulls merge` 成功后不 A2A 通知 sre**（`git-repo pulls merge` 是显式动作，完成后必须 `a2a handoff agent=sre`，否则 SRE 收不到后续任务）。
- ❌ 不因"等待"跳过 Step 6（tasks complete）。