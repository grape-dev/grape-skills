# Bug 需求流程（bug-flow）

> 适用：「异常/报错/失败/不工作/崩溃/慢/坏了/XX 有问题」的缺陷类需求。
> 核心原则：**先自主调查定位（tree/pulls/commits/相关代码），能收敛直接收敛；仅调查后仍无法清晰化才向用户提问（≤3 轮）。**

## 0. 边界

- ✅ 自主调查定位 → 结构化收敛（Bug 模板，评论发布）→ A2A issue。
- ❌ 不验证/修复代码、不跑环境、不建 PR、不做 spec。

## 1. 自主调查定位（先做，少打扰）

```bash
# 基于 Step 0/1 基线；按线索定位相关代码/提交/Issue：
grape git-repo commits --owner "$REPO_OWNER" --repo "$REPO_NAME" --per_page 20 --json-out          # 近期变更，判断引入点
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path {疑似模块} --raw
grape git-repo pulls list --owner "$REPO_OWNER" --repo "$REPO_NAME" --state all --per_page 10 --json-out   # 相关修复/在途
grape issues list --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out                             # 历史同类 Issue
```
- 目标：判断是否可复现、可能根因模块、影响面、是否已有在途/历史修复。
- **调查后能收敛结构 → 直接收敛，不问用户。**

## 2. 引导（仅调查后仍不清晰时）

- 对照 `requirement-elicit-guide.md` §三 Bug 六要素（现象 / 复现步骤 / 期望 vs 实际 / 影响范围 / 环境 / 日志报错），**作为兜底提问项而非默认第一轮**。
- 提问结合调查线索、具体、每次 1-3 个；≤3 轮；超限 → 评论列缺失项标「待澄清」。

```bash
# ① 发追问评论（body 以 [VOD Agent] 开头，结合调查线索 1-3 个具体问题）
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 结合代码情况，需要补充确认：{结合调查线索的具体问题 1-3 个}"}'

# ② 显式声明待澄清（awaiting-input 置状态 + 触达用户；--issue_id 用注入 $GRAPE_ISSUE_ID，未注入用 issues detail 的 id；questions 与追问一致）
ISSUE_ID="${GRAPE_ISSUE_ID:-$(grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out | jq -r '.id')}"
grape issues awaiting-input --issue_id "$ISSUE_ID" \
  --json '{"questions":"[VOD Agent] 结合代码情况，需要补充确认：{具体问题 1-3 个}","reason":"Bug 六要素缺失，需开发者补充"}' --json-out
```
- `awaiting-input` 提交后即触达用户（飞书卡片），无需等待/A2A；用户 `clarify` 回复后 `awaiting_input → processing` 新一轮继续。
- ⚠️ **本轮仍需回收尾**（`tasks complete`，next_step=`a2a_need_clarify`）——澄清追问也算本轮完成。

## 3. 结构化收敛（以评论发布，不改写原始 Issue）

按 `requirement-elicit-guide.md` §四 Bug 模板（现象/复现步骤/期望 vs 实际/影响范围/环境/日志报错/优先级/来源）生成收敛正文，评论发布：
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 已结构化收敛 Bug 需求：\n\n{§四 Bug 模板结构}"}' --json-out
```
- 调查所得的疑似根因/影响面在收敛中注明（标注「调查推断，待确认」），不谎称已确认。

## 4. A2A 交办 issue agent（必做）

```bash
# ≤3 次重试；交办后回 runbook Step 4 收尾（next_step=a2a_issue）
grape a2a handoff --json '{
  "agent": "issue",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": 0,
    "context": "Bug 需求已结构化收敛（评论发布）：<现象/根因推断摘要>。请继续分诊/spec/分配。"
  }
}' --json-out
```
- A2A 前查 pipeline 已含 `issue:a2a_event` → 不重复 A2A，直接回收尾（next_step=reply_comment）。

## 5. 收尾

回到 `vod-runbook.md` Step 4（tasks complete，next_step=`a2a_issue` 或 `reply_comment`）。