# Coding 执行走查表（runbook）

> 目的：把 Coding 处理 Issue / PR 的**每一步要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$ACCOUNT`（owner）、`$REPO_NAME`（repo 名）、`$ISSUE_NUMBER`、`$REPO_FULL_NAME`（owner/repo）、`$PR_NUMBER`、`$GRAPE_WORK_BRANCH`（工作基线分支）、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> **评论前缀硬规**：所有 Coding 评论 body 一律以 `[Coding Agent]` 开头（用 `grape git-repo issues comments create` / `grape git-repo pulls comments create ... --json '{"body":"[Coding Agent] ..."}'`）。
> 命令取舍速查：读 Issue 聚合用 `issues detail`；取原始字段/评论用 `git-repo issues get` / `issues comments list`；列目录用 `contents --path ""` 或 `tree --depth 2`（**`tree` 无 `--path`**）。

---

## 场景 A：新开发（`a2a_event`，从 issue skill 触发）

> 进入前已通过 SKILL「Prerequisites」。下表步骤按顺序执行，命中分支后到对应步骤，**未命中的步骤直接跳过**。

### Step 0 · 前置确认（必做）
```bash
# ① 解析目标合入分支（工作基线）：优先 $GRAPE_WORK_BRANCH；未注入则取仓库默认分支（不要写死 main/master）
WORK_BRANCH="${GRAPE_WORK_BRANCH:-$(grape git-repo repo --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out | jq -r '.default_branch // "main"')}"
echo "work_branch=$WORK_BRANCH"   # 后续建 PR 的 base、分支创建/切换、基线同步一律用这个值

# ② 确认本地开发分支：应为 feat/issue-{issue_number}（服务端已按 $WORK_BRANCH 建好 worktree）
grape git status
# 分支不符/缺失才执行（勿另造分支名）：
# grape git checkout "feat/issue-$ISSUE_NUMBER" \
#   || grape git checkout -b "feat/issue-$ISSUE_NUMBER" "origin/$WORK_BRANCH"
# ③ 基线同步（可选，避免 base 过期）：grape git fetch origin "$WORK_BRANCH" && grape git rebase "origin/$WORK_BRANCH"

# ④ 项目知识基线（解题背景；meta.degraded=false 且 files 非空 → 基于它分析，不再逐文件探索）
grape repos project info --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out

# ⑤ Agent/仓库沉淀知识（前序经验，按需）
grape knowledge stats --repo "$REPO_FULL_NAME" --json-out
grape knowledge list --repo "$REPO_FULL_NAME" --source agent --json-out
```
- 基线降级（`meta.degraded=true` 或 files 空）→ `grape git-repo repo` / `grape git-repo tree --depth 2` / `contents README --raw`。
- 任一命令报 403 → 跳过该来源，其余正常执行。
- ⚠️ **同一 `$WORK_BRANCH` 贯穿本场景后续所有步骤**：建 PR 的 `base`、开发分支的创建/切换、基线同步必须一致，确保 PR 指向正确的目标合入分支。

### Step 1 · 读 Issue 上下文（首次必做）
```bash
grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape issues pipeline --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out   # 路线图：判断已有规格
grape git-repo issues comments list --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out  # 按需
```

### Step 2 · 需求分析与任务类型（对照 `references/new-dev-flow.md`）
- **需求理解**：目标 / 范围 / 关键功能点；不明确 → 发评论向用户确认后继续：
  ```bash
  grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
    --json '{"body":"[Coding Agent] <澄清问题，1-3 个>"}'
  ```
- **技术可行性**：需外部 API / 第三方服务 → 先取 API 文档；文档缺失 → **评论说明暂缓，等待补充**。
- **任务类型 / 复杂度评估**：见 `new-dev-flow.md` §3/§4。⚠️ 涉及架构变更或新增外部服务集成的必归「大型」，不得低估。

### Step 3 · 文档 + 方案（所有 feature 开发必做）
```bash
# 分别读取 references/spec-driven-development.md、planning-and-task-breakdown.md 后编写
# 产出 docs/spec.md、tasks/plan.md、tasks/todo.md，并在 Issue 评论告知（body 以 [Coding Agent] 开头）
```

### Step 4 · 编码 + 测试（所有开发任务必做）
- 测试先行：`references/test-driven-development.md`（RED→GREEN→REFACTOR）
- 增量实现：`references/incremental-implementation.md`
- 原子提交：
  ```bash
  grape git add -A && grape git commit -m "feat: #$ISSUE_NUMBER 描述"
  grape git push origin "feat/issue-$ISSUE_NUMBER"
  ```

### Step 5 · 自审查（创建 PR 前必须，不可跳过）
读取 `references/code-review-and-quality.md` 按 5 轴审查，修复发现的问题；审查通过才进入 Step 6。

### Step 6 · 创建 PR + Issue 评论告知
```bash
# base 用目标合入分支 $WORK_BRANCH（＝$GRAPE_WORK_BRANCH 或仓库默认分支，见 Step 0 ①），不要写死 main
grape git-repo pulls create --owner "$ACCOUNT" --repo "$REPO_NAME" \
  --json '{
    "title": "feat: #'"$ISSUE_NUMBER"' 标题",
    "head": "feat/issue-'"$ISSUE_NUMBER"'",
    "base": "'"$WORK_BRANCH"'",
    "inner_issue_nums": "'"$REPO_FULL_NAME"'#'"$ISSUE_NUMBER"'",
    "close_related_issue": true
  }'

# PATCH 补充 body
grape git-repo pulls update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "${PR_NUMBER:-$PR_NUMBER_FROM_CREATE}" \
  --json '{"body":"## 概述\n\n自动实现 Issue #'"$ISSUE_NUMBER"'","labels":"auto-pr"}'
```
> `$PR_NUMBER` 取 `pulls create` 返回值中的 PR 编号；若该变量未注入则从返回结果取。

**⚠️ 创建 PR 后必须在 Issue 发评论告知（跳过 = 事件未完成）**；PR 链接用 Web 页面 `/pull/`（单数）markdown 格式：
```bash
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Coding Agent] ✅ 已完成实现，请审查 PR [#${PR_NUMBER}](https://gitcode.com/'"$REPO_FULL_NAME"'/pull/${PR_NUMBER})。"}'
```

### Step 7 · A2A 通知 QA Agent（必须执行，跳过 = 事件未完成）
> ⚠️ 交办前先用 `$GRAPE_SCENE_ID` 取当前场景，确认存在 `qa` 节点再交办；场景未注入且默认链路包含 QA → 用默认 `qa`。
```bash
echo "scene_id=${GRAPE_SCENE_ID:+set} PR_NUMBER=${PR_NUMBER:+set}"
grape scenes detail --scene_id "$GRAPE_SCENE_ID" --json-out   # 仅 ${GRAPE_SCENE_ID:-} 非空时执行；nodes[].skill 判断

grape a2a handoff --json '{
  "agent": "qa",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": '"${PR_NUMBER}"',
    "context": "Issue #'"$ISSUE_NUMBER"' 开发已完成，PR #'"${PR_NUMBER:-0}"' 已创建。请对该 PR 进行代码审查。原始需求：<简要摘要>"
  }
}' --json-out
```
- **字段规则（A2A 服务端强制校验）：** `issue_number` 必填（本 PR 关联的真实 Issue 编号），**无法确定则不要调用 A2A**，在最终评论中说明；`pr_number` 有则填、无则不填，**严禁把 PR 编号填入 issue_number**。
- 场景无 `qa` 节点 → 在评论说明「当前场景未配置 QA 审查环节」，`next_step` 用 `done`。
- A2A 失败重试 ≤3 次；仍失败 → 评论说明，`next_step` 标注需人工介入。

### Step 8 · 任务完成流程（必做，任何分支都必须执行到最后）
> ⚠️ **强约束：本技能收尾 = 调 `grape tasks complete`（情形一）**，是**最后一个动作**；评论发完 ≠ 任务完成。结构化字段**必须真实填充**。

```bash
grape tasks complete --json '{
  "result_text": "结论：Issue #'"$ISSUE_NUMBER"' 开发实现完成，PR #'"${PR_NUMBER:-}"' 已创建并通知 QA。",
  "next_step": "a2a_qa",
  "actions": ["提交代码并推送分支 feat/issue-'"$ISSUE_NUMBER"'", "创建 PR #'"${PR_NUMBER:-}"'", "在 Issue #'"$ISSUE_NUMBER"' 发评论告知", "A2A 通知 QA 审查"],
  "conclusion": "已实现需求，测试通过，PR #'"${PR_NUMBER:-}"' 待 QA 审查",
  "artifacts": ["PR #'"${PR_NUMBER:-}"'", "分支 feat/issue-'"$ISSUE_NUMBER"'"],
  "issue_summary": "实现完成 | 改动摘要 | PR #'"${PR_NUMBER:-}"' 待审查"
}'
```
- 若 PR 创建失败或某动作未完成，`actions`/`conclusion` 如实说明（如 `"PR 创建失败：grape git-repo pulls create 返回 xxx"`），不伪造。
- 若返回 `already:true`（任务已终态），属正常，忽略即可。**然后结束任务**，不要继续思考或等待输入。

---

## 场景 B：代码优化（`a2a_event`，从 PR skill 触发）

> 按审查意见修改已有 PR，**不需要**需求文档/方案设计/建 PR。进入前已通过 SKILL「Prerequisites」。

### Step 0 · 前置确认（同场景 A Step 0，仅确认分支即可）
```bash
grape git status   # 应在 PR 对应分支上
```

### Step 1 · 读审查反馈（必做）
```bash
grape git-repo pulls comments list --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out
grape git-repo pulls get --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out     # 按需：PR 当前状态
grape git-repo pulls files --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out   # 按需：变更清单
```
对每条评论检查代码是否已修改；不明确 → PR 评论追问。

### Step 2 · 制定修改方案并实施
- 针对每个审查问题确定修改方案、评估影响范围。
- 每个问题一个原子提交，commit message 注明问题编号：
  ```bash
  grape git add -A && grape git commit -m "fix: #$ISSUE_NUMBER 根据审查意见修正"
  grape git push origin "{pr_branch}"
  ```

### Step 3 · PR 评论告知（必须执行）
```bash
grape git-repo pulls comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$PR_NUMBER" \
  --json '{"body":"[Coding Agent] 已根据审查意见完成修改，请重新审查。"}'
```

### Step 4 · 任务完成流程（必做，与场景 A Step 8 同结构）
```bash
grape tasks complete --json '{
  "result_text": "结论：PR #'"$PR_NUMBER"' 已按审查意见完成修改。",
  "next_step": "wait_qa",
  "actions": ["修改代码修复审查意见", "grape git push 分支", "在 PR #'"$PR_NUMBER"' 评论告知重新审查"],
  "conclusion": "已按审查意见完成哪些修复，待 QA 重新审查",
  "artifacts": ["PR #'"$PR_NUMBER"' 评论"],
  "issue_summary": "已按审查意见修复 | 修改摘要 | 待重新审查"
}'
```
- 除 `grape tasks complete` 之外不再发出其他任务收尾信令，避免重复完成。

---

## 错误排查速查（命令返回异常时）

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook / reference 抄写；仍不确定再 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 里有契约不允许的字段，看确认的 Body fields，删掉多余字段 |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT，本技能不涉及 |
| `contents` 路径不存在 | 用 `tree --depth 2` 或 `contents --path ""` 定位 |
| `pulls create` 返回异常 | 核对 base 是否为 `$GRAPE_WORK_BRANCH`（缺省 main）、head 是否与分支一致 |

## 明确禁止

- ❌ 不用 `tree --path`（该参数不存在），层级用 `--depth`。
- ❌ 不因"等待用户回复/审查结果"跳过最终 Step（tasks complete）——回复/交办后即算本轮完成，必须收尾。
- ❌ 不在本地 worktree 用裸 `git` 绕过 `grape git`（丢失凭据注入，token 暴露）。
- ❌ 不直接合并 PR、不做 Issue 分类/打标签/分配（issue skill 职责）。