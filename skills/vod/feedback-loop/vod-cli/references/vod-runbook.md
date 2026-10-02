# VOD 执行走查表（runbook）

> 目的：把 VOD 处理 Issue 的**每一步要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名）、`$ISSUE_NUMBER`、`$REPO_FULL_NAME`（owner/repo）、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> ⚠️ **owner 只用 `$REPO_OWNER`**（从 `$REPO_FULL_NAME` 解析、与仓库路径一致）；`$ACCOUNT` 是触发人 actor 的真实账号，**仅用于 A2A payload `account` 字段，一律不用作 `--owner`**。
> **评论前缀硬规**：所有 VOD 评论 body 一律以 `[VOD Agent]` 开头（用 `grape git-repo issues comments create ... --json '{"body":"[VOD Agent] ..."}'`）。
> 命令取舍速查：读 Issue 聚合用 `issues detail`；取原始字段/评论用 `git-repo issues get` / `issues comments list`；列目录用 `contents --path ""` 或 `tree --depth single`（**`tree` 无 `--path`**）。

---

## 场景 B：已有 Issue 审视（`issue_opened`，最常用）

> 收到事件时先按此走查表执行；下表步骤按顺序，命中分支后到对应步骤，**未命中的步骤直接跳过**。

### Step 0 · 项目知识基线 + Agent 专属知识（必须最先，任何分支都要做）
用 grape CLI 获取两部分知识（均支持会话 token，仓库作用域匹配即可；命令名若因契约版本不同可按 `grape <组> --help` 确认）：

```bash
# ① 项目知识基线：project-graph.md + project-capabilities.md 全文 + meta（degraded/commit/branches）
grape repos project info --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out

# ② Agent/仓库沉淀知识（前序经验、系统注入说明）
grape knowledge stats --repo "$REPO_FULL_NAME" --json-out          # 各类知识数量，判断是否有沉淀
grape knowledge list --repo "$REPO_FULL_NAME" --source agent --json-out   # Agent 沉淀知识清单
grape knowledge list --repo "$REPO_FULL_NAME" --source system --json-out  # 系统注入说明文档
```

- `meta.degraded=false` 且 `files` 非空 → 项目基线可用，基于它做分析，**不再**用 `grape git-repo` 逐文件探索。
- `knowledge list` 命中的知识 → 按需 `grape knowledge detail --knowledge_id {id} --json-out` 读全文，作为分析/答复依据。
- `meta.degraded=true` 或 `files` 空（无基线）→ 降级（**目标分支 = 优先 `$GRAPE_WORK_BRANCH`，否则仓库默认分支，兜底探测 main/master**）：
  ```bash
  # 目标分支：$GRAPE_WORK_BRANCH → repos project info 的 branches_analyzed 首个 → main/master 探测
  TARGET_BRANCH="${GRAPE_WORK_BRANCH:-}"
  grape git-repo repo --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out   # 取 default_branch（若有）
  grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --ref "${TARGET_BRANCH:-main}" --depth single --json-out
  grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path README.md --raw
  # 若 main 不存在（404）→ 用 master 重试：--ref master
  ```
  （相关结论标注 `[degraded]`）。
- 若上述任一命令报 403（会话 token 作用域不匹配等）→ 跳过该来源，其余正常执行；都不可用时降级 + 评论说明。

### Step 1 · 读 Issue 上下文（必做）
```bash
# 聚合视图（含阶段/状态/事件/路线图），首选
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 需要评论/讨论细节时再取评论（按需，不必每次都调）
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```

### Step 2 · 项目历史全貌（判断重复/已解决/已有方案）
```bash
grape issues list --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out
grape git-repo pulls list --owner "$REPO_OWNER" --repo "$REPO_NAME" --state all --per_page 10 --json-out
```
- ⚠️ **重复判断命令注解**：用上面的 `issues list --state all`（含 open/closed）即可；**不要用 `issues mine` / `tasks mine`**（那是"我的任务"视图，不是历史全貌，命令也不属 issues 组）。
- 已处理/已解决/重复 → 发一条说明评论（Step 4c 模板）→ **进入 Step 6，`next_step=reply_comment`**。
- 否则继续 Step 3。

### Step 3 · 清晰度判断
对照 `requirement-elicit-guide.md` §一 四要素（目标/现状/期望/验收）判断；追问漏斗细则见 §二（结合知识基线、每次 1-3 个问题、不重复已确认项、≤3 轮）：
- **清晰** → Step 4a
- **不清晰**（需澄清，≤3 轮）→ Step 4b
- **纯咨询 / 无新需求**（如"介绍一下项目""这是做什么的"）→ Step 4c

### Step 4a · 需求清晰 → 结构化收敛（以评论发布，不改原始 Issue）
> ⚠️ **原则：不修改开发者原始 Issue 提交记录**——VOD 的审视/结构化结论以**评论**形式发布（`issues comments create`），**不使用 `issues update` 改写原始 `body`**。

按 §四 模板写结构化收敛正文到文件，以评论发布：
```bash
# 先写 /tmp/vod-body-N.md（模板见 requirement-elicit-guide.md §四），body 以 [VOD Agent] 开头，再转 JSON 发评论
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json "{\"body\":\"[VOD Agent] 已结构化收敛需求：\n\n$(cat /tmp/vod-body-N.md)\"}" --json-out
# 或长文用 @file：先转成 {"body":"[VOD Agent] ..."} 的 json 文件再 --json @file
```
> 更稳：`printf '{"body":"[VOD Agent] 已结构化收敛需求：%s"}' "$(cat /tmp/vod-body-N.md)" > /tmp/body.json` 再 `--json @/tmp/body.json`。

> ⚠️ **成功判定与不重试（强制）**：`--json-out` 返回含评论对象 `id` = **发布成功，立即停止**——
> - **不要再去查 `comments create --help`**、**不要重建/重新校验 json**、**不要重复发布同一条评论**（重复会刷屏、污染 Issue 讨论）；
> - 一次发布成功后就继续下一步（A2A 等）；只有在 `--json-out` 明确报错（如 `unknown request field` / 404）时才排查字段或命令，修后重试一次，仍失败则评论说明。
> ⚠️ 仅当需要给 Issue 打标签/改分配等结构化元数据时，才用 `issues update` 传相应字段（`labels`/`assignee`/`milestone_id`/`state`）——**不涉及 body 收敛**。
- 收敛后 **进入 Step 5**（如 pipeline 已有 `issue:a2a_event` 则跳过 A2A，直接 Step 6 + `next_step=reply_comment`）。

### Step 4b · 需求不清晰 → 澄清追问（显式 awaiting-input + 收尾）
> 需要用户补充输入才能继续——**同时**做三件事：发追问评论（落 Issue 讨论）、`tasks awaiting-input` 显式声明待澄清（置 `awaiting_input` + 飞书卡片触达用户）、`tasks complete` 结束本轮。

```bash
# ① 发追问评论（body 以 [VOD Agent] 开头，1-3 个具体问题；长文用 @file）
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 您指的是……？请补充：1) … 2) …"}'

# ② 显式声明进入待澄清（关键：请求体 questions 必填，与追问一致；成功返回 changed:true）
grape tasks awaiting-input --json '{
  "questions": "[VOD Agent] 您指的是……？请补充：1) … 2) …",
  "reason": "需求四要素缺失，需开发者补充"
}' --json-out

# ③ 本轮任务结束（awaiting 非终态，但仍 self-complete 表示本轮处理完毕，等 clarify 回 processing 后走下一轮）
grape tasks complete --json '{
  "result_text": "结论：Issue #'"$ISSUE_NUMBER"' 需求不清晰，已发澄清追问并置 awaiting_input，等待用户补充。",
  "next_step": "a2a_need_clarify",
  "actions": ["澄清追问评论", "显式 awaiting-input（questions）", "本轮 tasks complete"],
  "conclusion": "已请求用户补充四要素缺失项，Issue 状态置 awaiting_input，待开发者回复后重新分析",
  "artifacts": ["Issue #'"$ISSUE_NUMBER"' 追问评论", "awaiting-input 状态变更"],
  "issue_summary": "待澄清 | 已追问并 awaiting-input | 等待用户补充 | next=redo"
}'
```
- ⚠️ **不要等待用户回复，也不要 A2A**（awaiting 提交后由服务端飞书卡片触达用户；用户 `clarify` 回复后 `awaiting_input → processing`，新一轮 vod 事件再进来重新分析）。
- `awaiting-input` 仅 vod/issue 会话 token 可用（`--json-out` 返回 `changed:true`=成功；`false`=已终态/已等待，幂等忽略）。

### Step 4c · 纯咨询 / 已解决 / 无需动作 → 回复说明
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] <项目介绍 / 已解决说明 / 无需动作说明>"}'
```
- **直接进入 Step 6，`next_step=reply_comment`**。
- ⚠️ **发出评论后必须继续 Step 6**：没有调用 `grape tasks complete` 就是任务未完成，即使评论已发、即使没有 A2A/标签/Spec 等结构化产物——**不要因"纯咨询只是回条评论"就提前结束**。

### Step 5 · A2A 交办（仅 Step 4a 收敛后，必须严格按以下三步）

> ⚠️ **本步为强制流程，不得跳过**：交办前**必须执行下方第 1 步的 `grape scenes detail`**（即使 `$GRAPE_SCENE_ID` 为空也先调用一次，空结果按第 2 步"场景未绑定"处理），据结果确定目标节点，再发起 A2A；**禁止不执行场景核验就直接 A2A 默认 `issue`**——跳过一次即视为违规，可能交办给场景中不存在的 Agent。
> ⚠️ **禁止硬编码伪造场景节点**：校验必须基于真实 `grape scenes detail` 返回结果（`$SCENE_NODES`）；**禁止自己 `echo '{"nodes":[...]}'` 捏造节点 JSON 来"通过"校验**——那是假通过，会向不存在的 Agent 交办。

**第 1 步：取当前场景节点，并显式解析出"可用 Agent 集合"**
```bash
echo "scene_id=${GRAPE_SCENE_ID:+set} GRAPE_SCENE_ID=<$GRAPE_SCENE_ID>"
# 场景 ID 未注入（空串）→ 跳到第 2 步（标注"场景未绑定，沿用默认交办 issue"）
SCENE_NODES="$(grape scenes detail --scene_id "$GRAPE_SCENE_ID" --json-out 2>/dev/null)"
echo "$SCENE_NODES"
# 输出本场景可用 Agent 集合（nodes[].tag 或 skill 名 → agent 值）
echo "scene_agents: $(echo "$SCENE_NODES" | jq -r '[.nodes[]?.tag // .nodes[]?.skill] | unique | join(",")' 2>/dev/null)"
```

**第 2 步：按"场景 Agent 集合 × 任务类型"确定 A2A 目标（先校验命中，再交办）**
| 场景节点 skill 含 | agent 值 | 用途 |
|------------------|---------|------|
| `issue` / `issue-*` | `issue` | 默认目标：spec 设计/打标签/排里程碑/分配责任人 |
| `coding` / `coding-*` | `coding` | 代码实现（VOD 一般交 issue 后再流转） |
| `qa` / `qa-*` | `qa` | PR 审查（由 coding 触发，VOD 不直接交） |
| `sre` / `deploy-*` / `cloud-*` | `sre` | 部署/构建/运维 |

```bash
# ⚠️ 校验：默认目标 issue 是否在当前场景节点集合中
TARGET_AGENT="issue"
if echo "$SCENE_NODES" | jq -e --arg a "$TARGET_AGENT" '[.nodes[] | ((.tag // "")|ascii_downcase) + " " + ((.skill // "")|ascii_downcase)] | any(startswith($a) or startswith(("$a-")))' >/dev/null 2>&1; then
  echo "OK: scene contains $TARGET_AGENT node → 可 A2A"
else
  echo "BLOCK: scene (id=$GRAPE_SCENE_ID) 不含 $TARGET_AGENT 节点 → 不发起 A2A"
  # ⚠️ 发评论说明 + next_step=a2a_need_clarify + 人工确认，不 A2A
fi
```
- **命中** → 进入第 3 步发起 A2A。
- **未命中**（如场景只有部分节点、无 issue）→ **不发起 A2A**，评论措辞温和面向用户，说明"当前任务已完成，但由于当前开发流水线未配置 **xx Agent**（如 issue），本次未发起 A2A；待你确认/配置该环节后，再进行下一步动作"；`next_step=a2a_need_clarify`。**禁止用"平台返回 skipped / not_in_scene / 请人工确认节点可用性"这类疑似 bug 的硬措辞，也不要暴露 scene id / 场景内部节点信息给用户。**
- 场景未绑定（`$GRAPE_SCENE_ID` 空）→ 沿用默认 `issue` 交办，在评论注明"场景未绑定，按默认路由交办"。

**第 3 步：发起 A2A**
```bash
# agent 值取第 2 步结果（未注入场景/仅 issue 节点时用默认 issue）；issue_number 必填
grape a2a handoff --json '{
  "agent": "issue",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": 0,
    "context": "VOD 已完成需求收敛与结构化：<摘要>。请继续 spec 设计/打标签/排里程碑/分配责任人。"
  }
}' --json-out
```
- ⚠️ A2A 前检查 pipeline：已含 `issue:a2a_event` → **不要重复 A2A**，直接进入 Step 6（`next_step=reply_comment`）。
- ⚠️ A2A 失败重试 ≤3 次；仍失败 → 评论说明，`next_step` 标注需人工介入。

### Step 6 · 任务完成流程（必做，任何分支都必须执行到最后）
> ⚠️ **强约束：本技能收尾 = 调 `grape tasks complete`（情形一）**。这是**最后一个动作**，任何分支（4a/4b/4c/5、以及"已处理/无需动作"）都必须执行，**评论发完 ≠ 任务完成**。若先回读 prompt 的「处理记录输出要求」，应识别本技能属于情形一（提供 `tasks complete` 结构化收尾）——**只调 complete，不再输出 JSON 块**；不要因"读过情形二"而输出 JSON 块替代 complete。

按分支选定 `next_step`：
| 分支 | next_step |
|------|-----------|
| Step 4a 收敛并交办 | `a2a_issue` |
| Step 4b 澄清追问/待澄清 | `a2a_need_clarify` |
| Step 4c 纯咨询/已解决/无需动作 | `reply_comment` |
| 目标已完成、无后续 | `done` |

先**输出人类可读的分析摘要**（分析数量、发现的问题、已创建/已审视 Issue 及交办情况；可选：如需系统采纳场景推荐，可在末尾附 JSON 块含 `recommended_scene`/`scene_reason`），再调用自报完成：

```bash
grape tasks complete --json '{
  "result_text": "结论：Issue #'$ISSUE_NUMBER' <按分支写结论>。",
  "next_step": "a2a_need_clarify",
  "actions": ["<动作 1>", "<动作 2>", "…"],
  "conclusion": "<处理结论/分析结果（简要）>",
  "artifacts": ["<产出：评论 id / A2A seq / Issue #N>", "…"],
  "issue_summary": "<Issue 最新聚合结论，紧凑文本，用 | 分隔>"
}'
```
> ✅ **结构化字段必填**：`actions[]`/`conclusion`/`artifacts[]`/`issue_summary` 服务端据此组装结构化 `_sd` 写入 archive（详情页结构化框、events.result）——**只传 result_text 会丢结构化归档**。`result_text` 可选（未结构化时服务端用兜底处理），但仍建议给一句结论。
> `result_text` 按「结论 / 动作 / 产出（含可追溯 id）/ 摘要」组织，动作逐条 `•`，产出带 Issue #N / comment id / A2A `seq` 等标识。
> 若返回 `already:true`（任务已终态），属正常，忽略即可。**然后结束任务**，不要继续思考或等待输入。

---

## 错误排查速查（命令返回异常时）

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook / reference 抄写；仍不确定再 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 里有契约不允许的字段，看确认的 Body fields，删掉多余字段 |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT，本技能不涉及 |
| `contents` 路径不存在 | 用 `tree --depth single` 或 `contents --path ""` 定位 |

## 明确禁止

- ❌ 不用 `tree --path`（该参数不存在），层级用 `--depth`。
- ❌ 不因"等待用户回复"跳过 Step 6（tasks complete）——澄清追问也算本轮完成，必须收尾。