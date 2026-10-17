# Bug 需求流程（bug-flow，strict 版）

> 适用：「异常/报错/失败/不工作/崩溃/慢/坏了/XX 有问题」的缺陷类需求。
> 核心原则：**先自主调查定位（tree/pulls/commits/相关代码），能收敛直接收敛；仅调查后仍无法清晰化才向用户提问（≤3 轮）**。
> strict 语义：A2A 目标按需求类型动态路由（开发类→issue）；本技能**不做任何部署/启动/资源操作**。

## 0. 边界

- ✅ 自主调查定位 → 结构化收敛（Bug 模板，评论发布）→ A2A（strict 路由）。
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

## 3. 收敛门禁（必做，先判定「可推断 vs 必澄清」再收敛）

> ⚠️ **核心意图歧义必须澄清，不得直接收敛/A2A**。收敛前自检：Bug 的**现象是否明确**、**根因是否唯一可定位**？

**判定分档**：
- **调查可定位/单解**（代码/提交可确认根因或现象明确）→ 可直接收敛，根因推断标注「调查推断，待确认」。
- **影响定位方向的歧义**（现象描述含糊到无法确定复现路径、根因存在多个候选分支但用户意图不明、复现条件缺失且调查无法还原）→ **必须转澄清**：走近 §2「引导」的对方澄清分支（追问评论 + `awaiting-input` + `next_step=a2a_need_clarify`），**不发布收敛评论、不 A2A**；用户补充后下一轮再收敛。

> ⚠️ **自检规则**：收敛结论中若出现「可能/疑似是 A 或 B」「暂无法确定现象」「复现待确认」这类多解表述，视为**收敛门禁未通过**——立即改走澄清分支。

## 4. 结构化收敛（以评论发布，不改写原始 Issue，仅在收敛门禁通过后）

按 `requirement-elicit-guide.md` §四 Bug 模板（现象/复现步骤/期望 vs 实际/影响范围/环境/日志报错/优先级/来源）生成收敛正文，评论发布：
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 已结构化收敛 Bug 需求：\n\n{§四 Bug 模板结构}"}' --json-out
```
- 仅对**调查可定位的根因推断**（非核心意图歧义）在收敛中注明「调查推断，待确认」，不谎称已确认。

## 5. A2A 交办（strict 动态路由，必做）

按 `requirement-elicit-guide.md` §五 路由表确定目标 agent（开发类 Bug → agent=issue）：
```bash
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
- A2A 前查 pipeline 已含目标 `a2a_event` → 不重复 A2A，直接回收尾（next_step=reply_comment）。

## 6. 收尾

回到 `vod-runbook.md` Step 4（tasks complete，next_step=`a2a_issue` 或 `reply_comment`）。