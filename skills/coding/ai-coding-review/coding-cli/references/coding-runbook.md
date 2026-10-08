# Coding 执行走查表（runbook）

> 目的：把 Coding 处理 Issue / PR 的**每一步要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名）、`$ISSUE_NUMBER`、`$REPO_FULL_NAME`（owner/repo）、`$PR_NUMBER`、`$GRAPE_WORK_BRANCH`（工作基线分支）、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。`ACCOUNT`（触发人 actor）一般不作 --owner。
> **评论前缀硬规**：所有 Coding 评论 body 一律以 `[Coding Agent]` 开头（用 `grape git-repo issues comments create` / `grape git-repo pulls comments create ... --json '{"body":"[Coding Agent] ..."}'`）。
> 命令取舍速查：读 Issue 聚合用 `issues detail`；取原始字段/评论用 `git-repo issues get` / `issues comments list`；列目录用 `contents --path ""` 或 `tree --depth single`（**`tree` 无 `--path`**）。

---

## 场景 A：新开发（`a2a_event`，从 issue skill 触发）

> 进入前已通过 SKILL「Prerequisites」。下表步骤按顺序执行，命中分支后到对应步骤，**未命中的步骤直接跳过**。

### Step 0 · 前置确认（必做）
> ⚠️ 认证只用注入的 `$GRAPE_SESSION_TOKEN`（`grape` 自动读取）：**不探测** `BOT_*`/`USER_*`/其它 token（`printenv`/`env | grep` 均无效且被禁止）；token 不落日志/评论/文件。

```bash
# ① 解析目标合入分支（工作基线）——【强制第 1 步，必须执行并回显，不得跳过】
#    优先级：$GRAPE_WORK_BRANCH（权威）> 仓库默认分支 > main 探测（不存在则 master）
WORK_BRANCH="${GRAPE_WORK_BRANCH:-$(grape git-repo repo --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out | jq -r '.default_branch // "main"')}"
echo ">>> WORK_BRANCH=$WORK_BRANCH (来源: ${GRAPE_WORK_BRANCH:+GRAPE_WORK_BRANCH 注入值}/${GRAPE_WORK_BRANCH:-仓库默认分支})"
echo "$WORK_BRANCH" > /tmp/work_branch.txt   # 落盘暂存，Step 6 建 PR 的 base 从此读取，杜绝改主意

# ①-2 基线存在性核对（在 Step 0 内闭环，避免"注入值指向不存在的分支"）
grape git-repo branches --owner "$REPO_OWNER" --repo "$REPO_NAME" --per_page 100 --json-out \
  | jq -e --arg b "$WORK_BRANCH" '[.[].name] | index($b)' >/dev/null 2>&1 \
  && echo ">>> WORK_BRANCH($WORK_BRANCH) 存在于远端" \
  || echo ">>> ⚠️ WORK_BRANCH($WORK_BRANCH) 远端未见（可能为尚未推送的基线/场景注入名），仍以此为准声明"

# ② 确认本地开发分支：应为 feat/issue-{issue_number}（服务端通常已按 $WORK_BRANCH 备好 worktree）
grape git status
```

> ⚠️ **基线决策锚定（硬性原则，必须遵守）**：
> - **PR base 一律 = `$WORK_BRANCH`**（环境变量 `$GRAPE_WORK_BRANCH` 配置值，Step 6 从 `/tmp/work_branch.txt` 读取），**禁止硬编码 `dev`/`main`/`master` 等具体值，禁止自行改为其它分支**。
> - 是否依赖其它 PR（stacked）由 Agent 基于实际需求自行判断处理，**技能不提供 base 偏离**。

- ⚠️ **`$GRAPE_WORK_BRANCH` 语义（重要，避免误判）**：它是**整个仓库/场景的开发基线分支**，可能是长期分支（`dev`/`weekly-xx`），**也可能叫 `feat/issue-N`（N 可等于或不等于当前 Issue 编号，是场景配置的基线名）**——不是"当前 Issue 的专属分支"。
  - **一律采用服务端注入值作为 `$WORK_BRANCH`**，即使它叫别的 Issue 分支名（如 `feat/issue-2`），也不要因名字含其它 Issue 号就丢弃/改写为 main。
  - 优先级：`$GRAPE_WORK_BRANCH`（权威）> 仓库默认分支 > `main` 探测（不存在则 `master`）。

- **worktree 已就绪（默认路径）**：当前已在 `feat/issue-{N}` → 直接使用，进入 ③。
- **worktree 未就绪（降级路径）**：一次做完以下固定三步，**不要** clone 到 `/tmp` 再 `cp .git`、**不要**用裸 `git` 探测、不要另造分支名：
  ```bash
  # ① 原地 clone（凭据由 grape git 自动注入；若当前目录非空已含代码，先确认无冲突再覆盖）
  test -d .git || grape git clone https://gitcode.com/"$REPO_FULL_NAME".git .
  # ② 建/切开发分支：一律基于目标合入分支 origin/$WORK_BRANCH
  grape git checkout "feat/issue-$ISSUE_NUMBER" 2>/dev/null \
    || grape git checkout -b "feat/issue-$ISSUE_NUMBER" "origin/$WORK_BRANCH"
  # ③ 配置 git 身份（本次会话有效，逐仓库即可）
  grape git config user.name  "$BOT_USERNAME"
  grape git config user.email "$BOT_USERNAME@noreply.git.com"
  ```
  > ⚠️ 降级后所有命令仍走 `grape git`（**禁止裸 `git`**：会丢失凭据注入、token 暴露）；不要手工拼 `/tmp/clone/.git`。
- **git 身份预置（必做，避免 commit 被拒）**：走到编码/推送前确保已设置（未设置时 commit 会失败）：
  ```bash
  grape git config user.name  "$BOT_USERNAME"
  grape git config user.email "$BOT_USERNAME@noreply.git.com"
  ```
- ③ 基线同步（可选，避免 base 过期）：`grape git fetch origin "$WORK_BRANCH" && grape git rebase "origin/$WORK_BRANCH"`

```bash
# ④ 项目知识基线（解题背景；⚠️ 权威源 = grape repos project info，不用 cat 本地 .project-info 文件）
grape repos project info --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out
# 仅在上述命令不可用（如 403/契约缺失）时，才 read 本地 .project-info/*.md 兜底

# ⑤ Agent/仓库沉淀知识（前序经验，按需）
grape knowledge stats --repo "$REPO_FULL_NAME" --json-out
grape knowledge list --repo "$REPO_FULL_NAME" --source agent --json-out
```
- 基线降级（`meta.degraded=true` 或 files 空）→ `grape git-repo repo` / `grape git-repo tree --depth single` / `contents README --raw`。
- 任一命令报 403 → 跳过该来源，其余正常执行。
- ⚠️ **同一 `$WORK_BRANCH` 贯穿本场景后续所有步骤**：建 PR 的 `base`、开发分支的创建/切换、基线同步必须一致，确保 PR 指向正确的目标合入分支；**禁止把分支名硬编码成 `dev`/`main` 等具体值**。

### Step 1 · 读 Issue 上下文（首次必做）
> 💡 `issues detail` 已含阶段/状态/事件/路线图等全貌，**不必再重复调** `git-repo issues get`；按需才取 `issues comments list`。一条命令取到即继续，命令失败先看完整错误，勿重复相同命令试错。

```bash
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out   # 路线图：判断已有规格
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out  # 仅需评论时才取
```

### Step 2 · 需求分析与任务类型（对照 `references/new-dev-flow.md`）
- **需求理解**：目标 / 范围 / 关键功能点；不明确 → 发评论向用户确认后继续：
  ```bash
  grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
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
> **base 硬性 = `$WORK_BRANCH`**（Step 0 ① 落盘的 `/tmp/work_branch.txt`，环境变量 `$GRAPE_WORK_BRANCH` 配置值）：禁止硬编码 `dev`/`main`/`master`，禁止自行改为其它分支（stacked 依赖由 Agent 自行判断，不偏离 base）。
> ⚠️ **字段名以契约为准**：关联 Issue 字段实际为 `related_issue_nums`（数组）+ `auto_close_issues`（bool）；`inner_issue_nums`/`close_related_issue` 为旧字段名，多数契约不识别。字段报 `unknown request field(s)` → 删掉关联字段只留 `title`/`head`/`base` 精简重试。

```bash
# （Step 0 ① 落盘）读取基线，base 一律用它
WORK_BRANCH="$(cat /tmp/work_branch.txt)"

# base = $WORK_BRANCH（字段以契约为准：related_issue_nums + auto_close_issues；body 必带，生成的 PR 才有完整描述）
grape git-repo pulls create --owner "$REPO_OWNER" --repo "$REPO_NAME" \
  --json '{
    "title": "feat: #'"$ISSUE_NUMBER"' 标题",
    "head": "feat/issue-'"$ISSUE_NUMBER"'",
    "base": "'"$WORK_BRANCH"'",
    "body": "## 概述\n\n实现 Issue #'"$ISSUE_NUMBER"'：{需求摘要}。\n\n## 改动\n- {文件/改动要点}\n\n## 测试\n- python3 -m unittest ... 通过\n- node ... 通过",
    "related_issue_nums": ["'"$ISSUE_NUMBER"'"],
    "auto_close_issues": true
  }'
```

- ⚠️ **创建失败不要反复盲试**：先看完整 stderr（去掉 `| tail` 截断），对照「错误排查速查」；字段错误删多余字段、精简 JSON 再试。
- ✅ **PR 链接以 `pulls get` 的 `html_url` 为准**（不猜 `/pull/` vs `/merge_requests/`）：`PR_NUMBER` 取 `pulls create` 返回值编号后，用 `grape git-repo pulls get --number ${PR_NUMBER} --json-out` 取 `html_url`，评论里直接填它。
- ⚠️ **误建 PR 处理**：若创建出 base 错误的 PR（如 base=main 而应依赖未合入 PR），**不要**尝试 `pulls update {"state":"closed"}`（`state` 不在更新允许集）——用 `pulls update` 只补一条 body 说明「误建/废弃」，随后用正确 base 另建新 PR，并在最终评论中说明。

# （可选）PATCH 补充/更新 body（pulls update 仅允许 title/body/labels 等，不传 state）；create 已带 body 则无需重复
grape git-repo pulls update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "${PR_NUMBER:-$PR_NUMBER_FROM_CREATE}" \
  --json '{"body":"## 概述\n\n自动实现 Issue #'"$ISSUE_NUMBER"'：{需求摘要}","labels":"auto-pr"}'

> `$PR_NUMBER` 取 `pulls create` 返回值中的 PR 编号；若该变量未注入则从返回结果取。

**⚠️ 创建 PR 后必须在 Issue 发评论告知（跳过 = 事件未完成）**；PR 链接用 Web 页面 `/pull/`（单数）markdown 格式：
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Coding Agent] ✅ 已完成实现，请审查 PR [#${PR_NUMBER}](https://gitcode.com/'"$REPO_FULL_NAME"'/pull/${PR_NUMBER})。"}'
```

### Step 7 · A2A 通知 QA Agent（必须执行，跳过 = 事件未完成）
> ⚠️ 交办前必须先取当前场景 nodes 并校验含 `qa` 节点，命中才交办；场景未注入且默认链路含 QA → 用默认 `qa`。
```bash
echo "scene_id=${GRAPE_SCENE_ID:+set} PR_NUMBER=${PR_NUMBER:+set}"
# 场景 ID 非空时：取场景 nodes → 解析可用 Agent 集合 → 校验 qa 命中
SCENE_NODES="$(grape scenes detail --scene_id "$GRAPE_SCENE_ID" --json-out 2>/dev/null)"
echo "scene_agents: $(echo "$SCENE_NODES" | jq -r '[.nodes[]?.tag // .nodes[]?.skill] | unique | join(",")' 2>/dev/null)"
if echo "$SCENE_NODES" | jq -e --arg a "qa" '[.nodes[] | ((.tag // "")|ascii_downcase) + " " + ((.skill // "")|ascii_downcase)] | any(startswith($a) or startswith("$a-"))' >/dev/null 2>&1; then
  echo "OK: scene contains qa node → 可 A2A QA"
else
  echo "BLOCK: scene (id=$GRAPE_SCENE_ID) 不含 qa 节点 → 不发起 QA A2A"
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
    "pr_number": '"${PR_NUMBER}"',
    "context": "Issue #'"$ISSUE_NUMBER"' 开发已完成，PR #'"${PR_NUMBER:-0}"' 已创建。请对该 PR 进行代码审查。原始需求：<简要摘要>"
  }
}' --json-out
```
- **字段规则（A2A 服务端强制校验）：** `issue_number` 必填（本 PR 关联的真实 Issue 编号），**无法确定则不要调用 A2A**，在最终评论中说明；`pr_number` 有则填、无则不填，**严禁把 PR 编号填入 issue_number**。
- **场景无 `qa` 节点（BLOCK）** → **不发起 QA A2A**：评论措辞温和面向用户，说明"开发已完成，但由于当前开发流水线未配置 **qa Agent**，本次未发起 QA 审查 A2A；待你确认/配置该环节后，再进行下一步动作"；`next_step` 用 `done`。**禁止用"平台返回 skipped / not_in_scene / 请人工确认节点可用性"这类疑似 bug 的硬措辞，也不要暴露 scene id / 场景内部节点信息给用户。**
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

### Step 0 · 前置确认（同场景 A Step 0，确认分支 + 预置 git 身份）
> ⚠️ 认证只用注入的 `$GRAPE_SESSION_TOKEN`，**不探测**其它 token。
```bash
grape git status                                    # 应在 PR 对应分支上
grape git config user.name  "$BOT_USERNAME"
grape git config user.email "$BOT_USERNAME@noreply.git.com"
```

### Step 1 · 读审查反馈（必做）
```bash
grape git-repo pulls comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out
grape git-repo pulls get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out     # 按需：PR 当前状态
grape git-repo pulls files --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out   # 按需：变更清单
```
对每条评论检查代码是否已修改；不明确 → PR 评论追问。

### Step 2 · 制定修改方案并实施
- 针对每个审查问题确定修改方案、评估影响范围。
- 每个问题一个原子提交，commit message 注明问题编号（git 身份已预置，见 Step 0）：
  ```bash
  grape git add -A && grape git commit -m "fix: #$ISSUE_NUMBER 根据审查意见修正"
  grape git push origin "$PR_HEAD"   # PR 的 head 分支（Step 1 pulls get 的 head.ref），不要凭印象写分支名
  ```

### Step 3 · PR 评论告知（必须执行）
```bash
grape git-repo pulls comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" \
  --json '{"body":"[Coding Agent] 已根据审查意见完成修改，请重新审查。"}'
```

### Step 3b · A2A 通知 QA 重新审查（必须执行，跳过 = 流水线断裂）
> ⚠️ **PR 评论 ≠ 收尾**：必须用 `grape a2a handoff` 显式通知 QA 重新审查，否则 QA 不会被触发、审查流水线断在 coding。
```bash
echo "scene_id=${GRAPE_SCENE_ID:+set}"
SCENE_NODES="$(grape scenes detail --scene_id "$GRAPE_SCENE_ID" --json-out 2>/dev/null)"
echo "scene_agents: $(echo "$SCENE_NODES" | jq -r '[.nodes[]?.tag // .nodes[]?.skill] | unique | join(",")' 2>/dev/null)"
if echo "$SCENE_NODES" | jq -e --arg a "qa" '[.nodes[] | ((.tag // "")|ascii_downcase) + " " + ((.skill // "")|ascii_downcase)] | any(startswith($a) or startswith("$a-"))' >/dev/null 2>&1; then
  echo "OK: scene contains qa node → 可 A2A qa"
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
else
  echo "BLOCK: scene 不含 qa 节点 → 不发起 qa A2A（评论说明场景未配置 QA Agent，next_step=done）"
fi
```
- ⚠️ `issue_number` 必填，`pr_number` 填 PR 编号，禁止混用。
- **场景无 `qa` 节点** → 不发起 qa A2A，评论温和说明"当前开发流水线未配置 QA Agent，本次未发起重新审查"，`next_step` 用 `done`。
- 用真实 `scenes detail` 结果校验，禁止硬编码伪造节点。

### Step 4 · 任务完成流程（必做，与场景 A Step 8 同结构）
```bash
grape tasks complete --json '{
  "result_text": "结论：PR #'"$PR_NUMBER"' 已按审查意见完成修改。",
  "next_step": "a2a_qa",
  "actions": ["修改代码修复审查意见", "grape git push 分支", "在 PR #'"$PR_NUMBER"' 评论告知重新审查", "A2A 通知 QA 重新审查"],
  "conclusion": "已按审查意见完成哪些修复，已 A2A 通知 QA 重新审查",
  "artifacts": ["PR #'"$PR_NUMBER"' 评论", "A2A seq=XXXX → qa"],
  "issue_summary": "已按审查意见修复 | 修改摘要 | 已 A2A 交 QA 重新审查"
}'
```
- 除 `grape tasks complete` 之外不再发出其他任务收尾信令，避免重复完成。

---

## 错误排查速查（命令返回异常时）

> ⚠️ 出错时**先看完整错误**（命令去掉 `| tail -N` 截断，`2>&1` 保留 stderr）；runbook 命令照抄仍失败，才允许 `grape commands <关键词>` / `grape <group> --help` 按 Body fields 修正。

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook / reference 抄写；仍不确定再 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 里有契约不允许的字段（如 `pulls update` 的 `state`），看 `grape <group> <verb> --help` 的 Body fields，删掉多余字段 |
| `pulls create` 返回异常 | ①去掉 `tail` 看完整错误；②核对 `base` 是否为该 PR 应有的 base（默认 `$WORK_BRANCH`，跨依赖场景为所依赖分支）；③字段错误删掉关联字段留 `title`/`head`/`base` 精简重试（关联字段用 `related_issue_nums`/`auto_close_issues`，`related_issue_nums` 传 Issue 号数组如 `[12]`）；仍失败 `grape git-repo pulls create --help` |
| `pulls create` 成功但 head/base 不对 | 误建 PR → 不尝试 `state:closed`；用 `pulls update` 补 body 标注“误建/废弃”，另建正确 PR（见 Step 6） |
| `git commit` 被拒（无 user.name/email） | 先 `grape git config user.name/user.email`（见 Step 0）再 commit |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT，本技能不涉及 |
| `contents` 路径不存在 | 用 `tree --depth single` 或 `contents --path ""` 定位 |

## 明确禁止

- ❌ 不用 `tree --path`（该参数不存在），层级用 `--depth`；`--depth` 取值统一：**`--depth single`**（各 runbook 一致，勿用 `2`/`3`）。
- ❌ 不探测其它 token（`printenv BOT_*`/`USER_*`、`env | grep TOKEN`，**含只算长度**）——只用 `$GRAPE_SESSION_TOKEN`。
- ❌ 不 clone 成子目录 / `/tmp` 再 `cp .git` 手工拼装（worktree 未就绪按 Step 0 固定三步原地 clone）。
- ❌ 不用裸 `git`（`git status`/`git clone`/`git branch` 等一律走 `grape git`，保证凭据注入、token 零暴露）。
- ❌ 不把分支名硬编码成 `dev`/`main`/`master` 等具体值——一律用解析出的 `$WORK_BRANCH`（Step 0 ① / `/tmp/work_branch.txt`）。
- ❌ base 自行改为其它分支（stacked 依赖由 Agent 自行判断，但 **PR base 一律 = `$WORK_BRANCH`**）。
- ❌ 不给 `pulls update` 传 `state`（不在允许集；误建 PR 按 Step 6 标注废弃）。
- ❌ 不因"等待用户回复/审查结果"跳过最终 Step（tasks complete）——回复/交办后即算本轮完成，必须收尾。
- ❌ 不在本地 worktree 用裸 `git` 绕过 `grape git`（丢失凭据注入，token 暴露）。
- ❌ 不直接合并 PR、不做 Issue 分类/打标签/分配（issue skill 职责）。