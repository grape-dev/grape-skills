# grape-skill-generator 执行走查表（skill-generator-runbook）

> 目的：把「按规范生成/修复 grape-cli skill」的**每一步要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名）、`$ISSUE_NUMBER`、`$REPO_FULL_NAME`（owner/repo）、`$GRAPE_WORK_BRANCH`（目标合入分支）、`$BOT_USERNAME`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> ⚠️ **owner 只用 `$REPO_OWNER`**；`$ACCOUNT` 是触发人 actor，**仅用于 A2A payload `account` 字段**。
> **评论前缀硬规**：所有评论 body 一律以 `[Coding Agent]` 开头。
> ⚠️ **git 前缀原则**：仓库类 git 操作（branch/fetch/merge/checkout/add/commit/push/ls-remote 等）**一律走 `grape git`**（凭据经 `GIT_CONFIG` 进程内注入、token 零暴露）；**禁用裸 `git`**——否则无凭据注入、push/私有拉取必然失败。

### 防抖纪律（场景 A/B 共用，必须遵守）

1. **一条命令取到即继续**：`issues detail` 已含阶段/事件/路线图全貌，不必重复调 `git-repo issues get`；按需才取 `comments list` / `events list`。
2. **命令失败先看完整错误**：先把 `| tail -N` 截断去掉看完整 stderr，再按「错误排查速查」处理，**不重复相同命令试错**（5xx 用 `tasks wait`/`grape git ls-remote` 兜底，见错误排查表）。
3. **只核验差异点**：QA 已给出「真字段/假字段」结论时按结论改；仅与被改点直接相关才 `--help`/源码核验，不做全量二次审计。

---

## 统一流程 · 场景 A：生成 grape-cli skill

### Step 0 · 前置 + 读任务上下文（必须最先）
```bash
# ① 项目知识基线 + 技能资产
grape repos project info --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out
grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --depth single --json-out   # 看 skills/ 目录

# ② 任务上下文
grape tasks current --json-out
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape events detail --seq {seq} --json-out   # 读前序 A2A payload（vod/issue 交办摘要）
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out  # 读技能需求单
```
- 从上下文/评论提取 `agent_type`（chat/vod/issue/coding/qa/sre）+ 技能需求单（name/description/目标系统/验收）+ **`flow_nodes`（流程审批节点，A2A context / Spec「流程设计」段；无则 `无`）**。
- ⚠️ **`flow_nodes` 是「审批/澄清/通知」节点清单**（`awaiting-input`/`pending-review`/`tasks notify` 多选）——**必须在生成时落地为 runbook 步骤**（见 Step 3c），防止流程设计随实现丢失。
- 信息不全 → 澄清追问：`grape issues clarify --issue_id ${GRAPE_ISSUE_ID:-{issue_id}} --json '{"message":"..."}'`（issue_id 优先用注入的 `$GRAPE_ISSUE_ID`，未注入才用 `issues detail` 的 `id`）。

### Step 1 · 查重（必做）
```bash
grape skills list --repo "$REPO_FULL_NAME" --q "{name}" --json-out 2>/dev/null || true
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path ".grape/skills/{agent_type}" --json-out 2>/dev/null || true
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path "skills/{agent_type}" --json-out 2>/dev/null || true
```
- 已存在同名 → 回复「已存在——可复用/更新」，进入 Step 8 收尾（next_step=reply_comment）。
- 不存在 → 继续。

### Step 2 · 读取 references 三件套（必做，生成前必须先读）
```bash
# 用 read 工具读以下三件
# references/grape-cli-reference.md   —— 命令事实基线（生成 skill 引用命令的唯一来源）
# references/spec-reference.md        —— 撰写规范 8 大节要点
# references/command-matrix.md        —— agent_type → 命令映射矩阵
```

### Step 3 · 生成 SKILL.md（必做）
> ⚠️ **生成的 skill 文件放在项目根目录 `.grape/skills/${agent_type}/${name}/` 下**；若项目根目录没有该目录，应先创建它（`mkdir -p .grape/skills/{agent_type}/{name}`）。

- **目录**：`.grape/skills/{agent_type}/{name}/`（`{agent_type}` 为 vod/issue/coding/qa/sre/chat 之一，`{name}` 为 kebab-case skill 名）
- frontmatter：`name`（=目录名 kebab-case）/ `version` / `description`（一句话定位+职责枚举）/ `tools: [grape, bash]`
- 正文段落顺序（spec §2.2）：安全硬约束 → 定位 → Prerequisites → 环境变量表 → 评论规范 → 处理流程 → 领域规则 → 操作边界 → 硬约束 → 任务完成流程 → 参考
- **新规范必含**：**Prerequisites**（`grape --version` / `grape refresh` / env `${VAR:+ok}` 校验）、**环境变量表**（含 `$REPO_OWNER`/`$BOT_USERNAME`/`$GRAPE_WORK_BRANCH`）、**正文不改写**（结论用 comments 发布，`issues update` 不写 body）、A2A 交办 **agent**（如 `qa`，非技能名）
- 主体 **≤130 行**；超出拆到 references/
- 只引用 `references/grape-cli-reference.md` 中实际存在的命令；agent_type 相关命令从 `command-matrix.md` 选取
- `--json body` 字段只用 spec §5 的 schema，不编造

### Step 3b · 沉淀 skill 开发过程文档（必做，随 skill 一并提交）
> 生成过程文档放项目根 `.grape/docs/{name}/`，与 `.grape/skills/` 同一 commit/PR 提交（见 Step 6 add）。
> **spec.md 来源于 issue agent 交付的 Spec/技能需求单**：coding 负责将其落入 `.grape/docs/{name}/spec.md` 并提交，不自行编造内容；plan/task 由 coding 按需求单生成。

```bash
mkdir -p .grape/docs/{name}
# 写 .grape/docs/{name}/spec.md  —— 需求/规格（来源：issue agent 交付的 Spec/需求单，原样落盘）
# 写 .grape/docs/{name}/plan.md  —— 方案/计划（实现顺序/依赖/风险）
# 写 .grape/docs/{name}/task.md  —— 任务拆解清单（逐项验收/验证）
```
- `{name}` = skill 目录名（kebab-case）；文档只描述开发过程事实，不重复 SKILL.md/references 已固化内容。
- 说明：`.grape/` 在 .gitignore 中，add 须按文件逐一执行（同 `.grape/skills/`，见 Step 6）。

### Step 3c · 流程节点落地为运行书步骤（按需求单 `flow_nodes`，必做）
> ⚠️ **依据 Step 0 提取的 `flow_nodes`**：声明了哪个节点，runbook 就必须含对应步骤；`flow_nodes=无` 则跳过本节。产出放生成物 runbook（references/{x}-runbook.md 或 SKILL.md 处理流程段，需 ≤250/≤130 行）。

| flow_nodes | 必须落地的 runbook 步骤 | 关键命令/模式 |
|-----------|----------------------|--------------|
| `awaiting-input` 澄清 | 需用户补充输入才能继续的环节：发追问评论 + 本轮收尾 | `grape git-repo issues comments create ... --json '{"body":"[<Agent>] 请补充：{问题}"}'` + `grape tasks complete next_step=reply_comment`（大部分情况 vod/issue 阶段用 awaiting-input，其他 agent 以用户需求为准决定是否置状态） |
| `pending-review` 审批 | 交付决策点（部署前/合入前）需用户拍板：置审核点 → 用户回复 → 通过/驳回 | `grape issues pending-review --issue_id $ISSUE_ID --json '{"review_points":"{审查/审批结论}","references":"{PR/依据}"}'` → 评论续接：`grape issues review-pass --json '{"target":"done/processing",...}'` / `grape issues review-reject --json '{"reason":"..."}'`（幂等，`changed:false` 忽略） |
| `tasks notify` 通知 | 任务分派/状态通知节点 | `tasks notify`（body=assignee/issue_number/repo_key/task_description）为**通用接口，任何 agent 可用**，按用户需求/技能职责决定是否用于任务分派；若需求是「完成/结果通知」→ 落地 `git-repo issues comments create` 评论步骤（不用 tasks notify 传结果） |

- 每个节点步骤标注 `（必做）` 与 `next_step` 取值（clarify→`reply_comment`；approve→`done`/`processing`）。
- 生成后对照检验：runbook 中出现 `pending-review`/`tasks notify`/澄清收尾步骤 与 `flow_nodes` 一一对应。

### Step 4 · 生成 references/（必做，在 `.grape/skills/{agent_type}/{name}/references/`）
- `references/grape-cli-reference.md`：按 spec §3（安装/认证/常用命令/限制/退出码/安全）+ 只列该 skill 用到的命令
- `references/{domain-guide}.md`：agent_type 专属业务规则/判断标准/话术
- `references/{technical-guide}.md`：技术指南（可选，如工具操作手册）
- 每个 ≤250 行

### Step 5 · 质量自检（必做）
- 按 `references/spec-reference.md` §8 清单逐项检查（含新规范项：Prerequisites/env 表/agency 交办用 agent/正文不改写/base 用 $WORK_BRANCH）
- 失败项修复后重检；无法修复 → Issue 评论说明，不创建 PR

### Step 6 · 建分支 + 创建 PR（必做）
```bash
# 分支/工作区：基于目标合入分支 $WORK_BRANCH 开发（服务端通常已备 worktree/branch）
WORK_BRANCH="${GRAPE_WORK_BRANCH:-main}"
grape git status   # 确认在 feat/issue-{n}
# ⚠️ 生成的 skill 放在项目根 `.grape/skills/{agent_type}/{name}/`；目录不存在先创建
mkdir -p ".grape/skills/{agent_type}/{name}"
# ⚠️ 开发过程文档放在 `.grape/docs/{name}/`（见 Step 3b），随本 PR 一并提交
# ⚠️ `.grape/` 在 .gitignore 中——整目录 add 会触发 ignored 警告（rc=1），须按文件逐一 add（已跟踪文件不受 ignore 影响）
grape git add \
  .grape/skills/{agent_type}/{name}/SKILL.md \
  .grape/skills/{agent_type}/{name}/references/{reference-file}.md \
  .grape/skills/{agent_type}/{name}/references/{another-file}.md \
  .grape/docs/{name}/spec.md \
  .grape/docs/{name}/plan.md \
  .grape/docs/{name}/task.md   # 实际存在的文件清单（skill 文件 + 开发过程文档）
grape git status   # 确认 M 状态后再 commit；若仍被 ignore 拒绝，用 `grape git add -f <文件>`
grape git commit -m "feat(skills): add {name} skill"
grape git push origin "feat/issue-$ISSUE_NUMBER"

# 建 PR（base 用 $WORK_BRANCH，不硬编码 main；关联字段用 related_issue_nums/auto_close_issues；body 必带，生成的 PR 才有完整描述）
grape git-repo pulls create --owner "$REPO_OWNER" --repo "$REPO_NAME" \
  --json '{
    "title": "feat: add {name} skill",
    "head": "feat/issue-'"$ISSUE_NUMBER"'",
    "base": "'"$WORK_BRANCH"'",
    "body": "## 概述\n\n新增 {agent_type} 技能 {name}：{技能职责一句话}（按 grape-cli skill 撰写规范生成）。\n\n## 改动\n- 新增 `.grape/skills/{agent_type}/{name}/SKILL.md`\n- 新增 `.grape/skills/{agent_type}/{name}/references/`（grape-cli-reference / {业务 guide} 等）\n- 新增 `.grape/docs/{name}/`（spec.md 需求 / plan.md 方案 / task.md 任务拆解）\n\n## 后续\n- 请 QA 审查技能规范合规性（skill 合规检查器验证 frontmatter/安全硬约束/runbook 等）",
    "related_issue_nums": ["'"$REPO_FULL_NAME"'#'"$ISSUE_NUMBER"'"],
    "auto_close_issues": true
  }' --json-out
```
- ⚠️ PR 链接用 `pulls get` 的 `html_url`（不猜 `/pull/` vs `/merge_requests/`）。
- Issue 评论告知 PR（body 以 `[Coding Agent]` 开头，Markdown 链接）。

### Step 7 · A2A 交棒 QA agent（必须严格按三步）

**第 1 步：取当前场景节点**
```bash
echo "scene_id=${GRAPE_SCENE_ID:+set}"
SCENE_NODES="$(grape scenes detail --scene_id "$GRAPE_SCENE_ID" --json-out 2>/dev/null)"
echo "scene_agents: $(echo "$SCENE_NODES" | jq -r '[.nodes[]?.tag // .nodes[]?.skill] | unique | join(",")' 2>/dev/null)"
```

**第 2 步：校验 qa 节点命中**
```bash
TARGET_AGENT="qa"
if echo "$SCENE_NODES" | jq -e --arg a "$TARGET_AGENT" '[.nodes[] | ((.tag // "")|ascii_downcase) + " " + ((.skill // "")|ascii_downcase)] | any(startswith($a) or startswith(("$a-")))' >/dev/null 2>&1; then
  echo "OK: scene contains qa agent → 可 A2A"
else
  echo "BLOCK: scene 不含 qa 节点 → 不 A2A，评论说明 + next_step=reply_comment"
fi
```
- **A2A 交办的是 agent（qa）**，不是某个审查技能；qa agent 用哪个技能由它决定。
- 未命中 qa 节点 → 评论说明「当前场景未配置 QA 审查环节」，进入 Step 8（next_step=done/reply_comment）。

**第 3 步：发起 A2A**（qa agent；issue_number 必填，pr_number 填新 PR 编号）
```bash
grape a2a handoff --json '{
  "agent": "qa",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": {pr},
    "context": "skill 已生成，PR #{pr}（.grape/skills/{agent_type}/{name}/），请审查 SKILL.md 规范合规性 + references 完整性。"
  }
}' --json-out
```
- ⚠️ A2A 前查 pipeline 已含 `qa:a2a_event` → 不重复 A2A，只发评论。
- ⚠️ A2A 失败重试 ≤3 次；仍失败 → 评论说明 + 标注人工介入。

### Step 8 · 任务完成流程（必做，任何分支都必须执行到最后）
> ⚠️ **强约束：收尾 = `grape tasks complete`**，最后一个动作；评论发完 ≠ 任务完成。结构化字段**必须真实填充**。

按分支选定 `next_step`：生成+交办→`a2a_qa`；查重命中已存在→`reply_comment`；场景无 qa→`done`。

先**输出人类可读的分析摘要**（skill 名称 + PR 编号 + 自检结果），再调用自报完成：
```bash
grape tasks complete --json '{
  "result_text": "结论：skill 已生成并提交 PR。",
  "next_step": "a2a_qa",
  "actions": ["查重", "读三件套", "生成 SKILL.md+references", "自检", "创建 PR #'"${PR_NUMBER}"'", "A2A 交棒 qa"],
  "conclusion": "已按 spec 生成 {agent_type} skill {name}，PR #'"${PR_NUMBER}"' 待 QA 审查",
  "artifacts": ["PR #'"${PR_NUMBER}"'", ".grape/skills/{agent_type}/{name}/"],
  "issue_summary": "skill 已生成 | {name} | PR #'"${PR_NUMBER}"' 待 QA 审查"
}'
```
> ✅ **结构化字段必填**（actions/conclusion/artifacts/issue_summary），只传 result_text 丢归档。`already:true` 忽略。**然后结束任务**。

---

## 场景 B：修复 QA 反馈的合规问题（a2a_event，从 qa agent 触发）

> 触发判定：A2A context `/ 评论` 含「审查发现问题」「不合规」「QA 反馈」「请修复」等 → 本场景；含「生成」「创建」→ 场景 A。
> 进入前已通过 SKILL「Prerequisites」。**只定点修复，不重复场景 A 的生成步骤（不重新读三件套全量生成）。**

### Step B1 · 读任务上下文 + 定位被修复 skill（必做）
```bash
grape tasks current --json-out
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape events detail --seq {seq} --json-out                       # QA 交棒 payload
grape git-repo pulls get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out     # 确认 PR 与 head 分支
grape git-repo pulls files --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out   # 定位被修复 skill 路径
```
- 从 payload/评论提取不合规项清单（`文件:行号 + 问题 + 修正建议`）+ 被修复 skill 目录（`.grape/skills/{agent_type}/{name}/` 或 `skills/{agent_type}/{name}/`）。

### Step B2 · 同步 PR 分支到本地 worktree（必做）
> ⚠️ 一律走 `grape git`（凭据注入）；worktree 未就绪/无 skill 目录时同步：
```bash
grape git fetch origin
grape git branch -a
# 本地无 feat/issue-N → 基于 PR base 重建；已有则 fast-forward 合并 PR head
grape git checkout -b "feat/issue-$ISSUE_NUMBER" "origin/$WORK_BRANCH" 2>/dev/null || true
grape git merge "origin/feat/issue-$ISSUE_NUMBER" --quiet || grape git rebase "origin/feat/issue-$ISSUE_NUMBER"
grape git status   # 确认 skill 目录文件已就位
```
- 确认 skill 目录文件与 `pulls files` 内容一致；不一致 → 评论说明同步失败原因，进入 Step B7 收尾。

### Step B3 · 按 QA 反馈定点修复（必做）
- 逐条对照不合规项修改对应文件（SKILL.md / references/*.md），只动被修复 skill 目录内文件。
- 修复原则（决策固化为规则，不临场纠结）：
  - **保持原 runbook 结构**：仅替换/修正命令内容与字段，不重整编号、不连锁改 SKILL.md 步骤引用；
  - 命令/字段以 `references/grape-cli-reference.md` 事实基线为准，QA 已给结论的直接按结论改；
  - 版本号：内容修复 → `+0.0.x`；行为/流程变更 → `+0.x.0`（bump frontmatter `version`）。

### Step B4 · 自检（必做）
- 变更文件行数 ≤ 限制（SKILL.md ≤130、reference ≤250）。
- grep 残留旧命令/字段（如 `tasks notify`/`awaiting-input`/已删命令）→ 应只剩「禁止使用」提示语境：
  ```bash
  grep -rn "tasks notify\|awaiting-input\|<旧字段名>" ".grape/skills/{agent_type}/{name}/" || true
  ```
- 自检不过 → 修复后重检；无法修复 → 评论说明，不推送。

### Step B5 · 提交 + 推送 + 评论告知（必做）
```bash
# ⚠️ 一律走 grape git；.grape/ 被 ignore → 按文件逐一 add（同场景 A Step 6）
grape git add \
  .grape/skills/{agent_type}/{name}/SKILL.md \
  .grape/skills/{agent_type}/{name}/references/{file}.md
grape git status
grape git commit -m "fix(skills): {修复摘要}（{agent_type}/{name}）"
grape git push origin "feat/issue-$ISSUE_NUMBER"

grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Coding Agent] 已按 QA 反馈修复：{不合规项清单 + 修复摘要}，PR #'"$PR_NUMBER"' 已更新（commit {sha}）。"}'
```

### Step B6 · A2A 交棒 qa agent 复审（必做）
> 修复后**必须 A2A 回 qa 复审**（与场景 A 一致）；pipeline 已有进行中的 `qa:a2a_event` → 不重复 A2A，只发评论。
```bash
# 场景核验（同场景 A Step 7 第 1/2 步）确认 qa 节点命中后发起：
grape a2a handoff --json '{
  "agent": "qa",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": '"$PR_NUMBER"',
    "context": "QA 反馈的不合规项已修复：{清单}。PR #'"$PR_NUMBER"' 已更新（commit {sha}），请复审。"
  }
}' --json-out
```

### Step B7 · 任务完成流程（必做，任何分支都必须执行到最后）
```bash
grape tasks complete --json '{
  "result_text": "结论：QA 反馈的 {N} 项不合规已修复，PR #'"$PR_NUMBER"' 已更新。",
  "next_step": "a2a_qa",
  "actions": ["定位被修复 skill", "同步 PR 分支", "定点修复 {N} 项不合规", "自检", "commit+push 更新 PR", "Issue 评论告知", "A2A 交棒 qa 复审"],
  "conclusion": "已按 QA 反馈修复 {agent_type}/{name}（{N}/{N} 项），PR #'"$PR_NUMBER"' 待复审",
  "artifacts": ["PR #'"$PR_NUMBER"'（commit {sha}）", "Issue 评论（comment id=XXXXXX）"],
  "issue_summary": "QA 反馈修复完成 | {agent_type}/{name} | PR #'"$PR_NUMBER"' 待复审"
}'
```
> `already:true` 忽略。**然后结束任务**。

---

## 错误排查速查

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook/reference；仍不确定 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 字段不在允许集，看 `grape <g> <v> --help` Body fields 删多余字段 |
| `pulls create` 字段错误 | 关联字段用 `related_issue_nums`/`auto_close_issues`；报错删掉只留 title/head/base |
| `grape skills list` 不存在/403 | 跳过，用 `git-repo contents` 查仓库 skills/ 目录 |
| `pulls get` / API 返回 5xx | 用 `grape tasks wait --task-id` 或 `grape` 内置退避（默认 timeout 120s / interval 3s）重试，**不要 sleep 固定时长**；仍失败用 `grape git ls-remote origin` 核对远端 ref 落盘后继续 |
| `grape git add <目录>` rc=1（ignored） | `.grape/` 在 .gitignore 中——按文件逐一 `grape git add <文件>`（见 Step 6），仍拒绝用 `grape git add -f <文件>` |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT，本技能一般不涉及 |
| 自检未通过 | 修复后重检；无法修复 → 评论说明，不建 PR |

## 明确禁止

- ❌ 不编造命令/参数（命令只引事实基线）。
- ❌ 不用裸 `git`（branch/fetch/merge/checkout/add/commit/push/ls-remote 等一律走 `grape git`，保证凭据注入、token 零暴露）。
- ❌ A2A 交办写技能名（如 `grape-skill-validator`）——交办 **agent**（`qa`）。
- ❌ 建 PR 硬编码 `base: main`——用 `$WORK_BRANCH`。
- ❌ 改生成目录以外文件 / 直接合并 PR。
- ❌ 场景 B 重复场景 A 的生成步骤（不重读三件套全量生成，只定点修复）。
- ❌ 不因"等待"跳过最终 Step（tasks complete）——回复/交办后即算本轮完成，必须收尾。