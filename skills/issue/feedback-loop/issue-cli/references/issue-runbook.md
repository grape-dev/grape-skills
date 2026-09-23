# Issue-CLI 执行走查表（runbook）

> 目的：把 Issue Agent 处理 Issue 的**每一步要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$ACCOUNT`（owner）、`$REPO_NAME`（repo 名）、`$ISSUE_NUMBER`、`$REPO_FULL_NAME`（owner/repo）、`$GRAPE_SCENE_ID`（当前场景）、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> **评论前缀硬规**：所有 Issue 评论 body 一律以 `[issue agent]` 开头。
> 命令取舍速查：读 Issue 聚合用 `issues detail`；原始字段/评论用 `git-repo issues get` / `issues comments list`；列目录用 `contents --path ""` 或 `tree --depth single`（`tree` 无 `--path`）。

---

## 统一流程（任何 issue 事件：issue_updated / issue_comment / issue_labeled）

> 从 VOD 交办后进入 `issue` 阶段开始处理；`issue_opened` 由 VOD 接管。所有事件共用此流程，**不区分"新 Issue"与"评论"**。

### Step 1 · 读 Issue 上下文（首次必做）
```bash
# 聚合视图（含阶段/状态/事件/路线图）+ 评论
grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape issues pipeline --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape git-repo issues comments list --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```

### Step 2 · 项目知识基线 + Agent 知识 + 目标分支（首次必做，后续按需——由 agent 自判是否需要）
```bash
# ① 解析目标分支（目标合入分支/工作基线）：优先 $GRAPE_WORK_BRANCH；未注入则取仓库默认分支（不要写死 main/master）
WORK_BRANCH="${GRAPE_WORK_BRANCH:-$(grape git-repo repo --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out | jq -r '.default_branch // "main"')}"
echo "work_branch=$WORK_BRANCH"   # 后续「是否已实现」判断、范围预估、Spec 基准、A2A 交接都以它为准
grape git-repo branches --owner "$ACCOUNT" --repo "$REPO_NAME" --per_page 50 --json-out   # 确认 $WORK_BRANCH 存在

# ② 项目知识基线（project-graph.md + project-capabilities.md 全文 + meta）
grape repos project info --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out

# ③ 仓库沉淀知识（前序经验）
grape knowledge stats --repo "$REPO_FULL_NAME" --json-out
grape knowledge list --repo "$REPO_FULL_NAME" --source agent --json-out
grape knowledge list --repo "$REPO_FULL_NAME" --source system --json-out
```
- ⚠️ **`$GRAPE_WORK_BRANCH` 语义（重要，避免误判）**：它是**整个仓库/场景的开发基线分支**，可能是长期分支（`dev`/`weekly-xx`），**也可能叫 `feat/issue-N`（N 不一定等于当前 Issue 编号）**——它是场景配置的基线名，**不是"当前 Issue 的专属分支"**。
  - **即使它叫其它 Issue 分支名（如 `feat/issue-2`），也默认采用服务端注入值作为目标开发分支，不要因名字含别的 Issue 号就丢弃/改写成 main**。
  - 仅在有明确证据（场景/基线明确指向 main，且该分支与当前需求无关）时才改，并评论/Spec 说明原因。
  - 优先级：`$GRAPE_WORK_BRANCH`（权威）> 仓库默认分支 > `main` 探测（不存在则 `master`）。
- `meta.degraded=false` 且 `files` 非空 → 基线可用，基于它分析，不再逐文件探索。
- 无基线/`[degraded]` → 降级：`grape git-repo repo` / `grape git-repo tree --depth single` / `contents README --raw`。
- ⚠️ **首次必做**（建立分析基础）；后续事件按需——若已掌握足够项目上下文、且本次是简单追问/澄清，可由 agent 自行判断是否需要重新拉取（如项目可能更新或评论需基于新信息时再取）。

### Step 3 · 深度可开发性分析（⚠️ 每次处理都执行）
- 执行四维分析（需求完整性 → 技术可行性 → 依赖就绪性 → 范围确定性），输出评级：
  `ready` / `almost-ready` / `needs-discussion` / `not-feasible`。
- **技术可行性·是否已实现**：先核对**目标分支 `$WORK_BRANCH`**（Step 2 ① 解析，缺省仓库默认分支）commit 是否已实现本需求（标题/正文关键字匹配 feature/fix 等）：
  ```bash
  grape git-repo commits --owner "$ACCOUNT" --repo "$REPO_NAME" --per_page 20 --json-out   # 结合 $WORK_BRANCH 的 commit 核对
  ```
  已实现 → 回复建议关闭（引用 commit sha），不进入评级。
- 细则见 `references/issue-developability-analysis.md`；评论事件同样重新分析（用户补充信息会改变评级）。

### Step 4 · 按评级执行动作 + 标签 + 分配
```bash
# ready → 生成 Spec（→ Step 5）；贴 Issue 评论；打 spec-ready；A2A 交办 coding
#   ⚠️ Spec 中注明目标分支（开发基准 = $WORK_BRANCH，Step 2 ① 解析），供 coding 在正确分支开发
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"labels":"{原有标签},spec-ready","assignee":"{BOT_USERNAME}"}'
# almost-ready → 分配责任人（CODEOWNERS）→ 精确追问 1-2 个问题
# needs-discussion → 分配责任人 → 逐维度追问 → 标记 need-info
# not-feasible → 评论说明不可行 → 标记 invalid

# 打标签（先确保标签存在再设置）
grape git-repo labels create --owner "$ACCOUNT" --repo "$REPO_NAME" --json '{"name":"feature","color":"#a2eeef"}'
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"labels":"feature,triaged"}'
```

### Step 5 · A2A 交办（仅 ready 且已生成 Spec；必须严格按以下三步）

> ⚠️ **不得跳过场景核验**：交办目标是"当前场景实际存在的 Agent 节点 ∩ 任务类型"，**必须先取场景 nodes 清单并校验目标 agent 存在，命中才 A2A；禁止不查场景直接照抄 coding**。

**第 1 步：取当前场景节点，并显式解析出"可用 Agent 集合"**
```bash
echo "scene_id=${GRAPE_SCENE_ID:+set} GRAPE_SCENE_ID=<$GRAPE_SCENE_ID>"
# 场景 ID 未注入（空串）→ 跳到第 2 步（标注"场景未绑定，按常见约定路由"）
SCENE_NODES="$(grape scenes detail --scene_id "$GRAPE_SCENE_ID" --json-out 2>/dev/null)"
echo "$SCENE_NODES"
# 输出本场景可用 Agent 集合（nodes[].tag 或 skill 名 → agent 值）
echo "scene_agents: $(echo "$SCENE_NODES" | jq -r '[.nodes[]?.tag // .nodes[]?.skill] | unique | join(",")' 2>/dev/null)"
```

**第 2 步：按"场景 Agent 集合 × 任务类型"确定 A2A 目标（先校验命中，再交办）**
| 任务类型 | 需命中的 agent | 说明 |
|---------|------------|------|
| 开发类（feature/bug 实现，评级 ready） | `coding` | 生成 Spec 后交办开发；**场景必须含 coding 节点** |
| 需求不清晰 / 需引导澄清 | `vod` | 场景须含 vod 节点 |
| 部署 / 构建 / 运维 / 发布类 | `sre` | 场景须含 sre 节点 |
| PR 审查 / 质量检查 | `qa` | 场景须含 qa 节点 |

```bash
# ⚠️ 校验：目标 agent 是否在当前场景节点集合中
TARGET_AGENT="coding"   # 按任务类型取上表值
if echo "$SCENE_NODES" | jq -e --arg a "$TARGET_AGENT" '[.nodes[] | ((.tag // "")|ascii_downcase) + " " + ((.skill // "")|ascii_downcase)] | any(startswith($a) or startswith(("$a-")))' >/dev/null 2>&1; then
  echo "OK: scene contains $TARGET_AGENT node → 可 A2A"
else
  echo "BLOCK: scene (id=$GRAPE_SCENE_ID) 不含 $TARGET_AGENT 节点 → 不发起 A2A"
  # ⚠️ 发评论说明 + next_step=a2a_need_clarify + 人工确认，不 A2A
fi
```
- **命中** → 进入第 3 步发起 A2A。
- **未命中**（如开发类但场景只有 issue 无 coding）→ **不发起 A2A**：发评论"当前场景未包含该开发环节（scene=`$GRAPE_SCENE_ID`，可选 agents=`$scene_agents`）"，`next_step=a2a_need_clarify` 并标注需人工确认。
- 场景未绑定（`$GRAPE_SCENE_ID` 空）→ 按常见约定路由（开发→coding 等），在评论注明"场景未绑定，按默认路由交办"。

**第 3 步：发起 A2A**（agent 值取第 2 步命中结果）
```bash
grape a2a handoff --json '{
  "agent": "coding",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": 0,
    "context": "Issue #'$ISSUE_NUMBER' 已通过深度可开发性分析（评级 ready），Spec 已发布。请基于 Spec 在目标分支（$WORK_BRANCH）启动开发实现。<Spec 摘要>"
  }
}' --json-out
```
- ⚠️ `issue_number` 必填；`pr_number` 有则填、无则不填，严禁混用。
- ⚠️ **重复 A2A 检查**：pipeline 已含目标 agent 的 `a2a_event` → 不要重复交办，只发评论回复。

### Step 6 · 任务通知（处理结束责任人确定后必做，幂等）
```bash
grape tasks notify --json '{
  "assignee": "<责任人VCS用户名 或 grape_bot>",
  "repo_key": "'"$REPO_FULL_NAME"'",
  "issue_number": '"$ISSUE_NUMBER"',
  "task_description": "Issue #'$ISSUE_NUMBER' 已分配给你，请处理：<简要任务描述>"
}'
```

### Step 7 · 判断"是否已实现" + 评论回复（必做，除非是机器人自己的评论）
**① 核对需求是否已实现（目标分支 `$WORK_BRANCH`，Step 2 ① 解析）——避免重复开发/误判**：
```bash
grape git log --oneline -20 --all                                     # 本地裸库核对合并历史
grape git-repo commits --owner "$ACCOUNT" --repo "$REPO_NAME" --per_page 20 --json-out   # 平台 commit
```
- 已实现 → 回复说明已实现（引用 commit sha）并建议关闭；用户是请求关闭 → 关 + `grape tasks close`。
- 未实现 → 继续分析/动作。

**② 发评论**：按 `references/comment-guide.md` 格式，body 以 `[issue agent]` 开头，基于知识基线与分析结论。

### Step 8 · 任务完成流程（必做，任何分支都必须执行到最后）
> ⚠️ **强约束：本技能收尾 = 调 `grape tasks complete`（情形一）**。任何分支最后一步都必须调用，**评论发完 ≠ 任务完成**；只调 complete，不再输出 JSON 块。

按分支选定 `next_step`：
| 分支 | next_step |
|------|-----------|
| ready → A2A 交办 coding | `a2a_coding` |
| 澄清追问 / 待澄清 | `a2a_need_clarify` |
| 回复评论 / 无需交办 | `reply_comment` |
| 目标已完成、无后续 | `done` |

```bash
grape tasks complete --json '{
  "result_text": "结论：Issue #'$ISSUE_NUMBER' 已按评级完成处理。",
  "next_step": "a2a_coding",
  "actions": ["深度可开发性分析", "打标签", "分配负责人", "回复评论", "grape tasks notify 上报任务", "A2A 交办 coding"],
  "conclusion": "Issue #'$ISSUE_NUMBER' 评级 {评级}，已完成 {动作}，{后续动作}",
  "artifacts": ["Issue #'$ISSUE_NUMBER' 评论", "标签 {labels}", "负责人 {assignee}", "A2A event seq=XXXX"],
  "issue_summary": "已分诊 | 评级 {评级} | 已分配 {assignee} | 后续 {动作}"
}'
```
> `next_step` 取 `a2a_issue` / `reply_comment` / `a2a_need_clarify` / `done`。`already:true` 忽略。**然后结束任务**

---

## 错误排查速查

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook / reference；仍不确定才 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 字段不在允许集，看 `--help` 的 Body fields 删除多余字段 |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT，本技能一般不涉及 |
| `contents` 路径不存在 | 用 `tree --depth single` 或 `contents --path ""` 定位 |

## 明确禁止

- ❌ `tree --path`（参数不存在），层级用 `--depth`。
- ❌ 不因"等待用户回复"跳过 Step 8（tasks complete）。
- ❌ 直接写代码 / 提交 PR / 合并 PR（交给 coding/对应环节）。