# Grape 技能创建需求引导 执行走查表（skill-dev-runbook）

> 目的：把 grape-vod-cli 处理「技能创建/改造」意图的**每一步要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名）、`$ISSUE_NUMBER`、`$REPO_FULL_NAME`（owner/repo）、`$GRAPE_SCENE_ID`（当前场景）、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> ⚠️ **owner 只用 `$REPO_OWNER`**（从 `$REPO_FULL_NAME` 解析、与仓库路径一致）；`$ACCOUNT` 是触发人 actor 的真实账号，**仅用于 A2A payload `account` 字段，一律不用作 `--owner`**。
> **评论前缀硬规**：所有评论 body 一律以 `[VOD Agent]` 开头；收敛结论以评论发布，不改写原始 Issue。

---

## 统一流程（技能创建/改造需求）

> 入口：用户提交「想建一个 grape 技能 / 改造现有技能」的需求（README/文档托管或 grape-skill-dev 场景）。所有事件共用此流程。

### Step 0 · 项目/技能知识基线 + Agent 知识（必须最先）
```bash
# ① 项目知识基线：project-graph.md + project-capabilities.md 全文 + meta
grape repos project info --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out

# ② 现有技能查重 + 平台技能清单（判断命名是否冲突 / 是否改造现有技能）
grape skills list --json-out 2>/dev/null
grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --depth single --json-out   # 看仓库是否已有 skills/

# ③ 仓库沉淀知识（前序经验、系统注入说明）
grape knowledge stats --repo "$REPO_FULL_NAME" --json-out
grape knowledge list --repo "$REPO_FULL_NAME" --source agent --json-out
grape knowledge list --repo "$REPO_FULL_NAME" --source system --json-out
```
- `meta.degraded=false` 且 `files` 非空 → 项目基线可用，基于它分析。
- 任一命令报 403 → 跳过该来源，其余正常执行。

### Step 1 · 读需求上下文（必做）
```bash
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out   # 防重复 A2A
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out  # 按需
```
- 自建排除：Issue 含 `auto-submitted by [VOD Agent]` 且本需求已完成收敛 → 防自我循环，直接判断是否需要重复处理。

### Step 2 · 意图判定（必做）
判断该需求是：
- **新建技能**：用户要做一个新 grape skill → 进入 Step 3 引导
- **改造现有技能**：对已有 skill 增强/修复 → 需先定位目标 skill（`grape skills list` 或仓库 `skills/` 目录），进入 Step 3 引导改造点
- **非技能需求 / 纯咨询 / 无关** → Step 4c（说明 / 转对应流程）

### Step 3 · 技能需求引导（≤3 轮，一次 1-3 个问题）
对照 `references/skill-requirement-guide.md` §二 要素引导（agent_type / name / description / 目标系统 / 验收风险）。**服务项目 = 当前项目（环境变量/prompt 已注入），无需引导；触发场景固定（工作流自动调用本技能），无需引导**。追问用评论：

```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 为了给您生成合适的技能，请补充：\n1) 这个技能承担哪类职责（chat/vod/issue/coding/qa/sre）？\n2) 技能叫什么名字（小写连字符，如 blog-manager）？\n3) 它会操作什么系统/服务？"}'
```

判定要点见 `skill-requirement-guide.md` §四（agent_type 速查）+ §七（常见口径）。

### Step 4 · 收敛
**4a · 需求清晰 → 以评论发布「技能需求单」**
> ⚠️ **不改写原始 Issue body**：需求单以评论发布；**禁止 `issues update` 改 body**。
```bash
# 长文用 --json @file：printf '{"body":"..."}' > /tmp/skill-req.json
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 📋 技能需求单（已收敛）：\n<skill-requirement-guide.md §三 模板>"}'
```
- 收敛后 **进入 Step 5**（如 pipeline 已有目标 a2a_event 则跳过 A2A，直接 Step 6 + `next_step=reply_comment`）。

**4b · 需求不清晰 → 澄清追问后进入收尾**
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 请补充：…（1-3 个问题）"}'
```
- 直接进入 Step 6，`next_step=a2a_need_clarify`。

**4c · 非技能需求/纯咨询/已处理 → 回复说明**
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] <说明：这属于 X 类需求 / 已处理 / 无需动作>"}'
```
- 直接进入 Step 6，`next_step=reply_comment`。

### Step 5 · A2A 交办 grape-skill-issue（仅 Step 4a 收敛后，必须严格按以下三步）

> ⚠️ **不得跳过场景核验**：交办前必须先用 `$GRAPE_SCENE_ID` 取当前场景，据此确定目标节点，再发起 A2A。

**第 1 步：取当前场景节点**
```bash
echo "scene_id=${GRAPE_SCENE_ID:+set} GRAPE_SCENE_ID=<$GRAPE_SCENE_ID>"
# 场景 ID 未注入（空串）→ 跳过本步，按常见约定路由（见第 2 步）
grape scenes detail --scene_id "$GRAPE_SCENE_ID" --json-out   # nodes[].skill 标识各环节 Agent
```

**第 2 步：按场景节点确定 A2A 目标**
- **首选目标 `grape-skill-issue`**（grape-skill-dev 场景的 issue 节点：做可开发性分析/Spec/门控）。
- 仅当场景节点含 `issue`/`issue-*`/`grape-skill-issue` 才交办；若场景无该节点 → 评论说明「当前场景未包含该环节」，`next_step=a2a_need_clarify` 标注需人工确认，不发起 A2A。

**第 3 步：发起 A2A**（issue_number 必填）
```bash
grape a2a handoff --json '{
  "agent": "grape-skill-issue",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": 0,
    "context": "用户要创建/改造一个 grape 技能，需求已收敛为技能需求单（以评论发布）：<agent_type/name/description 等摘要>。请做技能可开发性分析、Spec 生成与门控。"
  }
}' --json-out
```
- ⚠️ A2A 前检查 pipeline：已含目标 agent 的 `a2a_event` → **不要重复 A2A**，直接进入 Step 6（`next_step=reply_comment`）。
- ⚠️ A2A 失败重试 ≤3 次；仍失败 → 评论说明，`next_step` 标注需人工介入。

### Step 6 · 任务完成流程（必做，任何分支都必须执行到最后）
> ⚠️ **强约束：本技能收尾 = 调 `grape tasks complete`（情形一）**，是**最后一个动作**；评论发完 ≠ 任务完成。结构化字段**必须真实填充**。

按分支选定 `next_step`：
| 分支 | next_step |
|------|-----------|
| Step 4a 收敛并交办 | `a2a_issue` |
| Step 4b 澄清追问/待澄清 | `a2a_need_clarify` |
| Step 4c 已处理/无需动作 | `reply_comment` |
| 目标已完成、无后续 | `done` |

先**输出人类可读的分析摘要**（需求要素收敛情况、发现的问题、交办情况），再调用自报完成：

```bash
grape tasks complete --json '{
  "result_text": "结论：技能需求 <已收敛/待澄清/无需动作>。",
  "next_step": "a2a_issue",
  "actions": ["项目/技能知识基线", "agent_type 判定", "技能需求引导", "发布技能需求单评论", "A2A 交办 grape-skill-issue"],
  "conclusion": "已收敛技能需求单：agent_type={X} name={Y} 服务项目={owner/repo}；交办 grape-skill-issue",
  "artifacts": ["Issue #'"$ISSUE_NUMBER"' 需求单评论（comment id=XXXXXX）", "A2A event seq=XXXX"],
  "issue_summary": "技能需求已收敛 | agent_type={X} | name={Y} | 交办 grape-skill-issue"
}'
```
> ✅ **结构化字段必填**：`actions[]`/`conclusion`/`artifacts[]`/`issue_summary` 服务端据此组装结构化 `_sd` 写入 archive——**只传 result_text 会丢结构化归档**。
> 若返回 `already:true`（任务已终态），属正常，忽略即可。**然后结束任务**，不要继续思考或等待输入。

---

## 错误排查速查（命令返回异常时）

> ⚠️ 出错时**先看完整错误**（命令去掉 `| tail -N` 截断，`2>&1` 保留 stderr）；runbook 命令照抄仍失败，才允许 `grape commands <关键词>` / `grape <group> --help` 按 Body fields 修正。

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook / reference 抄写；仍不确定再 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 里有契约不允许的字段，看 `grape <group> <verb> --help` 的 Body fields，删掉多余字段 |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT，本技能不涉及 |
| `grape skills list` 不存在/403 | 跳过（用 `git-repo tree`/`contents` 看仓库 skills/ 目录查重） |
| `a2a handoff` 非 2xx / 未命中 | **不探索 `--help`**：回看 Step 5 场景节点核验；缺失 → 按 Step 5 未命中分支说明 + `next_step=a2a_need_clarify` 收尾 |

## 明确禁止

- ❌ 不用 `tree --path`（该参数不存在），层级用 `--depth single`。
- ❌ **用 `issues update` 改写 Issue body/描述**（覆盖原始描述）——收敛结论一律 `issues comments create` 发布。
- ❌ 不探测其它 token（`printenv BOT_*`/`USER_*`、`env | grep TOKEN`）——只用 `$GRAPE_SESSION_TOKEN`。
- ❌ 直接创建/修改技能文件、生成 SKILL.md（coding 节点职责）。
- ❌ agent_type 判定不清时硬猜（澄清 ≤3 轮或标「待澄清」）。
- ❌ 不因"等待用户回复"跳过 Step 6（tasks complete）——澄清追问也算本轮完成，必须收尾。