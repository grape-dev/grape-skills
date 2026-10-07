# 代码优化流程（Coding-CLI）

从 PR skill 通过 A2A 触发的代码优化任务，根据审查意见修改已有 PR 的代码。**全部操作走 `grape` CLI**（命令见 `references/grape-cli-reference.md`）。

## 分析（按顺序执行，上一步未完成不得进入下一步）

### 1. 理解审查反馈

读取 A2A context 中的审查意见，明确需要修改的问题点。

通过 `grape git-repo pulls comments list` 获取 PR 上的行内评论，确认具体问题和代码位置：

```bash
grape git-repo pulls comments list --owner {owner} --repo {repo} --number {number} --json-out
```

> 如需命令侧核对实际的审查意见与变更文件，可用 `grape git-repo pulls get` / `grape git-repo pulls files` 取 PR 当前状态与变更文件清单。

对每条评论检查代码是否已修改、问题是否已解决。如有不明确之处，在 PR 中评论追问。

### 2. 制定修改方案

针对审查反馈的每个问题确定修改方案，评估修改影响范围。

**不需要**输出需求文档和方案设计文档（已有 PR，只需修改问题点）。

### 3. 实施修改并推送

在现有 PR 分支上修改代码：
- 每个问题一个原子提交
- 提交后推送到 PR 分支
- 修改完成后，在 PR 中评论告知已根据审查意见完成修改

### 分析结论示例

```
分析结论：
- 场景：代码优化（从 PR skill 触发）
- 审查问题数：3（2 个 Critical，1 个 Required）
- 必须执行：修改代码 → 推送分支 → PR 评论告知
- 不需要：需求文档、方案设计、创建 PR
```

## 执行能力

### 能力一：代码实现

```bash
grape git add -A && grape git commit -m "fix: #{number} 根据审查意见修正"
grape git push origin {pr_branch}
```

每个问题一个原子提交，commit message 注明修复的问题编号。

### 能力二：PR 评论告知

修改完成后，在 PR 中评论告知：

```bash
grape git-repo pulls comments create --owner {owner} --repo {repo} --number {number} \
  --json '{"body": "[Coding Agent] 已根据审查意见完成修改，请重新审查。"}'
```

> 注：评论 body 前缀固定为 `[Coding Agent]`。

### 能力三：A2A 通知 QA 重新审查（必做，跳过 = 流水线断裂）

> ⚠️ **修改完成 + PR 评论 ≠ 任务结束**：必须用 `grape a2a handoff` 显式通知 QA Agent 重新审查，否则 QA 不会被触发、审查流水线断在 coding。

**先取当前场景并校验含 `qa` 节点**（同新开发流程；场景未注入且默认链路含 QA → 用默认 `qa`）：

```bash
echo "scene_id=${GRAPE_SCENE_ID:+set}"
SCENE_NODES="$(grape scenes detail --scene_id "$GRAPE_SCENE_ID" --json-out 2>/dev/null)"
echo "scene_agents: $(echo "$SCENE_NODES" | jq -r '[.nodes[]?.tag // .nodes[]?.skill] | unique | join(",")' 2>/dev/null)"
if echo "$SCENE_NODES" | jq -e --arg a "qa" '[.nodes[] | ((.tag // "")|ascii_downcase) + " " + ((.skill // "")|ascii_downcase)] | any(startswith($a) or startswith("$a-"))' >/dev/null 2>&1; then
  echo "OK: scene contains qa node → 可 A2A qa"
else
  echo "BLOCK: scene 不含 qa 节点 → 不发起 qa A2A（评论说明，场景未配置 QA）"
fi
```
- **命中 qa 节点 / 场景未注入** → 发起 A2A：
```bash
grape a2a handoff --json '{
  "agent": "qa",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": '"$PR_NUMBER"',
    "context": "PR #'"$PR_NUMBER"' 已按审查意见完成修改（commit {sha}），请重新审查。修改摘要：{review_summary}"
  }
}' --json-out
```
- ⚠️ `issue_number` 必填，`pr_number` 填 PR 编号，禁止混用。
- **场景无 `qa` 节点（BLOCK）** → 不发起 qa A2A，评论说明"当前开发流水线未配置 QA Agent，本次未发起重新审查"；`next_step` 用 `done`。
- 用真实 `scenes detail` 结果校验，禁止硬编码伪造节点。

### 能力四：任务完成流程（必做）

完成所有业务动作（提交修改、push、PR 评论告知、A2A 通知 QA）后，**调用 `grape tasks complete` 自报完成（必做）**——服务端据此将任务+事件置为成功（会话 token 自动定位当前任务，无需 --task-id）。

**结构化字段直接传入 `--json`**（接口见 `docs/openapi/01-tasks.md`），服务端据此组装结构化 `result_text`，供事件对话与结构化解析识别：

```bash
grape tasks complete --json '{
  "result_text": "结论：PR #N 已按审查意见完成修改。\n\n动作：\n• fixed：修复 Critical/Required 审查意见\n• pushed：grape git push 分支 {pr_branch}\n• commented：已在 PR #N 评论告知重新审查\n• a2a：已交办 QA 重新审查（seq=XXXX）\n\n产出：\n- PR #N 评论（comment id=XXXXXX）\n- A2A seq=XXXX → qa\n- commit xxxxxx\n\n摘要：一句话概括本次处理结果。",
  "next_step": "a2a_coding",
  "actions": ["修改代码修复审查意见", "grape git push 分支", "在 PR #N 评论告知重新审查", "A2A 通知 QA 重新审查"],
  "conclusion": "已按审查意见完成哪些修复，测试结果，已 A2A 通知 QA 重新审查",
  "artifacts": ["PR #N 评论", "A2A seq=XXXX → qa", "commit xxxxxx"],
  "issue_summary": "已按审查意见修复 | 修改摘要 | 已 A2A 交 QA 重新审查"
}'
```

- **字段规则**（`TaskSelfCompleteBody`）：`result_text`（结论/动作/产出摘要，可选）、`actions[]`、`conclusion`、`artifacts[]`、`issue_summary` 为结构化产出，服务端组装为结构化 `result_text`；`next_step` 取 `a2a_issue` / `reply_comment` / `a2a_need_clarify` / `done`（优化场景 A2A 后可用 `a2a_qa`，执行环境允许）。
- 传入结构化字段后，**无需再在答复末尾单独输出 JSON 块**。
- 即使本轮只是评论回复，也必须调用一次。
- 若返回 `already:true`（任务已终态），属正常，忽略即可。
- 除 `grape tasks complete` 之外不再发出其他任务收尾信令，避免重复完成。