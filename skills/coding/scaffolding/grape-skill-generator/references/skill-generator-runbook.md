# grape-skill-generator 执行走查表（skill-generator-runbook）

> 目的：把「按规范生成 grape-cli skill」的**每一步要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名）、`$ISSUE_NUMBER`、`$REPO_FULL_NAME`（owner/repo）、`$GRAPE_WORK_BRANCH`（目标合入分支）、`$BOT_USERNAME`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> ⚠️ **owner 只用 `$REPO_OWNER`**；`$ACCOUNT` 是触发人 actor，**仅用于 A2A payload `account` 字段**。
> **评论前缀硬规**：所有评论 body 一律以 `[Coding Agent]` 开头。

---

## 统一流程（生成 grape-cli skill）

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
- 从上下文/评论提取 `agent_type`（chat/vod/issue/coding/qa/sre）+ 技能需求单（name/description/目标系统/验收）。
- 信息不全 → 澄清追问：`grape issues clarify --issue_id ${GRAPE_ISSUE_ID:-{issue_id}} --json '{"message":"..."}'`（issue_id 优先用注入的 `$GRAPE_ISSUE_ID`，未注入才用 `issues detail` 的 `id`）。

### Step 1 · 查重（必做）
```bash
grape skills list --repo "$REPO_FULL_NAME" --q "{name}" --json-out 2>/dev/null || true
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path ".grape/skills/{agent_type}" --json-out 2>/dev/null || true
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path "skills/{agent_type}" --json-out 2>/dev/null || true
```
- 已存在同名 → 回复「已存在——可复用/更新」，进入 Step 10 收尾（next_step=reply_comment）。
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
grape git add ".grape/skills/{agent_type}/{name}/" && grape git commit -m "feat(skills): add {name} skill"
grape git push origin "feat/issue-$ISSUE_NUMBER"

# 建 PR（base 用 $WORK_BRANCH，不硬编码 main；关联字段用 related_issue_nums/auto_close_issues；body 必带，生成的 PR 才有完整描述）
grape git-repo pulls create --owner "$REPO_OWNER" --repo "$REPO_NAME" \
  --json '{
    "title": "feat: add {name} skill",
    "head": "feat/issue-'"$ISSUE_NUMBER"'",
    "base": "'"$WORK_BRANCH"'",
    "body": "## 概述\n\n新增 {agent_type} 技能 {name}：{技能职责一句话}（按 grape-cli skill 撰写规范生成）。\n\n## 改动\n- 新增 `.grape/skills/{agent_type}/{name}/SKILL.md`\n- 新增 `.grape/skills/{agent_type}/{name}/references/`（grape-cli-reference / {业务 guide} 等）\n\n## 后续\n- 请 QA 审查技能规范合规性（skill 合规检查器验证 frontmatter/安全硬约束/runbook 等）",
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
- 未命中 qa 节点 → 评论说明「当前场景未配置 QA 审查环节」，进入 Step 10（next_step=done/reply_comment）。

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

## 错误排查速查

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook/reference；仍不确定 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 字段不在允许集，看 `grape <g> <v> --help` Body fields 删多余字段 |
| `pulls create` 字段错误 | 关联字段用 `related_issue_nums`/`auto_close_issues`；报错删掉只留 title/head/base |
| `grape skills list` 不存在/403 | 跳过，用 `git-repo contents` 查仓库 skills/ 目录 |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT，本技能一般不涉及 |
| 自检未通过 | 修复后重检；无法修复 → 评论说明，不建 PR |

## 明确禁止

- ❌ 不编造命令/参数（命令只引事实基线）。
- ❌ A2A 交办写技能名（如 `grape-skill-validator`）——交办 **agent**（`qa`）。
- ❌ 建 PR 硬编码 `base: main`——用 `$WORK_BRANCH`。
- ❌ 改生成目录以外文件 / 直接合并 PR。
- ❌ 不因"等待"跳过 Step 8（tasks complete）。