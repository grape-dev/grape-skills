# 功能需求流程（feature-flow）

> 适用：「增加/支持/扩展/提供/能够/需要」+ 能力动词 的功能新增/增强需求。
> 核心原则：**先自主调查项目现状，能收敛直接收敛；仅调查后仍无法清晰化才向用户提问（≤3 轮）。**

## 0. 边界

- ✅ 自主调查现状 → 结构化收敛（评论发布）→ A2A issue。
- ❌ 不写代码 / 不建 PR / 不改标签 / 不做 spec（issue agent 职责）。

## 1. 自主调查（先做，少打扰）

```bash
# 复用 runbook Step 0/1 已取得的基线；按需深入定位：
grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --ref "$GRAPE_WORK_BRANCH" --depth single --json-out
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path {相关目录} --json-out
grape git-repo pulls list --owner "$REPO_OWNER" --repo "$REPO_NAME" --state all --per_page 10 --json-out   # 已实现/在途
```
- 判断：新增点落在哪个模块、是否已有类似实现、是否已有在途 PR。
- **调查后能收敛结构 → 直接收敛，不问用户。**

## 2. 引导（仅调查后仍不清晰时）

- 对照 `requirement-elicit-guide.md` §三 功能四要素（目标/现状/期望/验收）。
- 提问结合调查结果、具体、每次 1-3 个；≤3 轮；超限 → 评论列缺失项标「待澄清」。

```bash
# ① 发追问评论（body 以 [VOD Agent] 开头，1-3 个具体问题，长文用 @file）
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 基于项目现状，想确认：{结合调查结果的具体问题 1-3 个}"}'

# ② 显式声明待澄清（awaiting-input 置状态 + 触达用户；--issue_id 用注入 $GRAPE_ISSUE_ID，未注入用 issues detail 的 id；questions 与追问一致）
ISSUE_ID="${GRAPE_ISSUE_ID:-$(grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out | jq -r '.id')}"
grape issues awaiting-input --issue_id "$ISSUE_ID" \
  --json '{"questions":"[VOD Agent] 基于项目现状，想确认：{具体问题 1-3 个}","reason":"功能需求四要素缺失，需开发者补充"}' --json-out
```
- `awaiting-input` 提交后即触达用户（飞书卡片），无需等待/A2A；用户 `clarify` 回复后 `awaiting_input → processing` 新一轮继续。
- ⚠️ **本轮仍需回收尾**（`tasks complete`，next_step=`a2a_need_clarify`）——澄清追问也算本轮完成。

## 3. 结构化收敛（以评论发布，不改写原始 Issue）

按 `requirement-elicit-guide.md` §四 功能模板（目标/现状/期望/验收/优先级/来源）生成收敛正文，评论发布：
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 已结构化收敛需求：\n\n{§四 模板结构}"}' --json-out
```
- 拿不准但可合理推断 → 在收敛结论中注明假设，让用户确认，而非空白提问。

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
    "context": "功能需求已结构化收敛（评论发布）：<摘要>。请继续 spec 设计/打标签/排里程碑/分配责任人。"
  }
}' --json-out
```
- A2A 前查 pipeline 已含 `issue:a2a_event` → 不重复 A2A，直接回收尾（next_step=reply_comment）。

## 5. 收尾

回到 `vod-runbook.md` Step 4（tasks complete，next_step=`a2a_issue` 或 `reply_comment`）。