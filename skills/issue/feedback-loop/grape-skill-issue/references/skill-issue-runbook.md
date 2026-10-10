# grape-skill-issue 执行走查表（skill-issue-runbook）

> 目的：把 grape-skill-issue 处理「技能创建/改造需求」的**每一步要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名）、`$ISSUE_NUMBER`、`$REPO_FULL_NAME`（owner/repo）、`$GRAPE_SCENE_ID`（当前场景）、`$BOT_USERNAME`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> ⚠️ **owner 只用 `$REPO_OWNER`**（从 `$REPO_FULL_NAME` 解析、与仓库路径一致）；`$ACCOUNT` 是触发人 actor 的真实账号，**仅用于 A2A payload `account` 字段，一律不用作 `--owner`**。
> **评论前缀硬规**：所有评论 body 一律以 `[issue agent]` 开头；收敛结论以评论发布，不改写原始 Issue。

---

## 统一流程（技能创建/改造需求）

> 入口：grape-vod-cli 交办的「技能创建/改造」需求（`issue` 阶段）。所有事件共用此流程。

### Step 0 · 项目/技能知识基线 + 危险操作确认前置检查（必须最先）
```bash
# ① 项目知识基线：project-graph.md + project-capabilities.md 全文 + meta
grape repos project info --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out

# ② 技能资产：判断是新建还是改造现有技能
grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --depth single --json-out   # 看 skills/ 目录
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path skills --json-out 2>/dev/null

# ③ 仓库沉淀知识（前序经验）
grape knowledge stats --repo "$REPO_FULL_NAME" --json-out
grape knowledge list --repo "$REPO_FULL_NAME" --source agent --json-out
```
- **危险操作确认前置检查**：查评论历史中是否有「⚠️ 危险操作确认」评论 + 用户「确认」回复：
  - 已确认 → 跳过门控，进入 Step 6 A2A（context 注明「用户已确认危险操作」）
  - 等待中 → 回复「等待确认」→ **进入 Step 7 收尾**（next_step=reply_comment）
  - 未找到 → 正常流程进入 Step 1

### Step 1 · 读需求上下文（必做）
```bash
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out   # 防重复 A2A
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out  # 读技能需求单（vod 发布）
```
- 从评论中提取 grape-vod-cli 发布的「技能需求单」：agent_type / name / description / 目标系统 / 验收。
- 若缺需求单（vod 未收敛）→ 评论说明并 A2A 交回 vod 澄清，或标「待澄清」。

### Step 2 · 技能可开发性分析（必做，每次处理都执行）
- 对照 `references/issue-developability-analysis.md` 四维：需求完整性 → 技术可行性 → 依赖就绪性 → 范围确定性。
- 结合技能需求单（agent_type 决定命令子集/下游；name/description 是否合规；目标系统是否可行）。
- 输出评级：`ready` / `almost-ready` / `needs-discussion` / `not-feasible`。

### Step 3 · 需求类型路由（必做）
| 技能需求类型 | 处理 |
|------------|------|
| 下架/移除现有技能 | **不生成 Spec**，直接 Step 6 A2A 交办 **sre agent** |
| 创建/生成新技能 | Step 4 → Step 5 → Step 6 A2A **coding agent** |
| 改造/增强现有技能 | 定位目标 skill → Step 4 → Step 5 → Step 6 A2A **coding agent** |
| 需求不清晰 | 评论追问 / A2A 交回 **vod agent** 澄清 |

### Step 4 · 危险场景识别 + 用户确认门控（必做）
- 对照 `references/spec-generation.md`「危险场景识别」扫描匹配：
  - **付费资源**：Create/Purchase/Buy + ECS/OBS/RDS/BSS/VPC/EIP/SLB
  - **删除**：Delete/Remove/Drop
  - **不可逆**：Hard Delete/Force/Terminate/Purge
- **无危险** → 进入 Step 5。
- **有危险** → 评论发布门控（body 以 `[issue agent]` 开头）：

```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[issue agent] ⚠️ 危险操作确认：本技能涉及 {付费资源/删除/不可逆操作}（{具体操作}）。是否确认继续？回复「确认」后将继续开发。"}'
```
- **任务结束，不 A2A** → Step 7 收尾（next_step=reply_comment），等待用户确认。

### Step 5 · 生成 Spec（评级 ready + 无危险 时）
读取 `references/spec-generation.md` 生成 Spec，**以评论发布**（不改写原始 Issue body）：
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[issue agent] 📋 Spec Document\n\n{spec 完整内容}"}'   # 长文用 --json @file
```
- 同时打标签：⚠️ `issues update` 为整体覆盖，**先 get 回填原始 body**：
```bash
ISSUE_BODY="$(grape git-repo issues get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out | jq -r '.body')"
CUR_LABELS="$(grape git-repo issues get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out | jq -r '[.labels[]?.name] | join(",")')"
grape git-repo issues update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"'"$ISSUE_BODY"'","labels":"'"${CUR_LABELS:+$CUR_LABELS,}"'spec-ready","assignee":"'"$BOT_USERNAME"'"}'
```
- 分类/分配见 `references/labeling-guide.md` / `references/assignee-guide.md`。

### Step 6 · A2A 交办（必须严格按三步）

> ⚠️ **不得跳过场景核验**：交办前必须先用 `$GRAPE_SCENE_ID` 取当前场景，据此确定目标节点，再发起 A2A。

**第 1 步：取当前场景节点**
```bash
echo "scene_id=${GRAPE_SCENE_ID:+set} GRAPE_SCENE_ID=<$GRAPE_SCENE_ID>"
grape scenes detail --scene_id "$GRAPE_SCENE_ID" --json-out   # nodes[].skill 标识各环节 Agent
```

**第 2 步：按需求类型 × 场景节点确定 A2A 目标（agent，非技能）**
> ⚠️ A2A 交办的是 **agent**（`coding`/`sre`/`vod`），不是某个技能；对应 agent 使用哪个技能由该 agent 自行决定。

| 需求类型 | 目标 agent | 场景须含节点 |
|---------|-----------|-------------|
| 创建/生成 skill | `coding` | coding |
| 改造 skill | `coding` | coding |
| 下架 skill | `sre` | sre |
| 需求不清晰 | `vod` | vod |

- 场景无对应 agent 节点 → 评论说明「当前场景未包含该环节」，`next_step=a2a_need_clarify`，不发起 A2A。

**第 3 步：发起 A2A**（agent 取第 2 步命中结果；issue_number 必填；危险已确认时 context 注明）
```bash
# TARGET_AGENT 按第 2 步取值（coding / sre / vod）；先校验场景命中，再 handoff
TARGET_AGENT="coding"   # 按需求类型取第 2 步表值
if echo "$SCENE_NODES" | jq -e --arg a "$TARGET_AGENT" '[.nodes[] | ((.tag // "")|ascii_downcase) + " " + ((.skill // "")|ascii_downcase)] | any(startswith($a) or startswith(("$a-")))' >/dev/null 2>&1; then
  echo "OK: scene contains $TARGET_AGENT agent → 可 A2A"
else
  echo "BLOCK: scene 不含 $TARGET_AGENT agent → 不 A2A，评论说明 + next_step=a2a_need_clarify"
fi
grape a2a handoff --json '{
  "agent": "'"$TARGET_AGENT"'",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": 0,
    "context": "技能需求已收敛并生成 Spec（评论发布）：agent_type={X} name={Y}。<Spec 摘要>{；用户已确认危险操作}。请处理本技能创建/改造开发。"
  }
}' --json-out
```
- ⚠️ A2A 前检查 pipeline：已含目标 agent 的 `a2a_event` → **不要重复 A2A**，只发评论（next_step=reply_comment）。
- ⚠️ A2A 失败重试 ≤3 次；仍失败 → 评论说明 + `next_step` 标注人工介入。

### Step 7 · 任务完成流程（必做，任何分支都必须执行到最后）
> ⚠️ **强约束：本技能收尾 = 调 `grape tasks complete`（情形一）**，是**最后一个动作**；评论发完 ≠ 任务完成。结构化字段**必须真实填充**。

按分支选定 `next_step`：
| 分支 | next_step |
|------|-----------|
| ready → Spec → A2A 交办 generator | `a2a_coding` |
| 危险操作等待用户确认 | `reply_comment` |
| 澄清追问 / 需求不清晰 | `a2a_need_clarify` |
| 已处理 / 无需动作 | `reply_comment` |

先**输出人类可读的分析摘要**（评级、Spec 位置、危险操作确认情况、交办情况），再调用自报完成：

```bash
grape tasks complete --json '{
  "result_text": "结论：Issue #'"$ISSUE_NUMBER"' 技能需求<已交办/待确认/已处理>。",
  "next_step": "a2a_coding",
  "actions": ["技能可开发性分析", "生成 Spec 评论", "危险场景识别", "打 spec-ready + 分配", "A2A 交办 coding agent"],
  "conclusion": "技能 agent_type={X} name={Y} 评级 {评级}；危险操作 {有/无}；已 A2A 交办 coding",
  "artifacts": ["Issue #'"$ISSUE_NUMBER"' Spec 评论（comment id=XXXXXX）", "标签 spec-ready", "A2A event seq=XXXX"],
  "issue_summary": "技能需求已分诊 | agent_type={X} | 评级 {评级} | 危险 {有/无} | 交办 coding"
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
| Issue 原始描述被冲掉 / update 后 body 变空 | `issues update` 为整体覆盖——先 get 回填原始 body 再 update（见 Step 5）；正文/结论走 comments |
| `labels create` 返回 400 | 平台行为，不排查——用 `issues update` 的 `labels` 落地（自动补建标签） |
| `grape skills list` 不存在/403 | 跳过，用 `git-repo tree`/`contents` 查仓库 skills/ 目录 |
| `a2a handoff` 非 2xx / 未命中 | **不探索 `--help`**：回看 Step 6 场景节点核验；缺失 → 说明 + `next_step=a2a_need_clarify` 收尾 |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类（user_only） | 说明需 `grape_`/JWT，本技能一般不涉及 |

## 明确禁止

- ❌ 不用 `tree --path`（该参数不存在），层级用 `--depth single`。
- ❌ **用 `issues update` 改写 Issue body/描述**（覆盖原始描述）——Spec/门控结论一律 `issues comments create` 发布。
- ❌ 不探测其它 token（`printenv BOT_*`/`USER_*`、`env | grep TOKEN`）——只用 `$GRAPE_SESSION_TOKEN`。
- ❌ 危险操作未用户确认就 A2A。
- ❌ 直接生成/修改技能文件（coding 节点职责）、提交/合并 PR。
- ❌ 不因"等待用户回复"跳过 Step 7（tasks complete）。