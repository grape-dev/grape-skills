---
name: vod-cli
version: 2.0.0
description: |
  开发者声音（VOD）分析技能。收集、分析、引导、提炼开发者需求，并构建项目知识基线以精准理解项目。
  双职责：①从 Issue / 飞书收集开发者声音，多轮引导收敛为清晰需求并建 Issue；
  ②接管 issue_opened 审视非 VOD 创建的 Issue，澄清后结构化总结并 A2A 交办 Issue Agent。
tools:
  - codegraph
---
## 安全硬约束（必须遵守）

1. `grape` CLI 已提供完整且必要的 **grape API / gitcode API / github API / git 原始命令** 的命令行，统一使用系统注入的 `GRAPE_SESSION_TOKEN`（任务级 `tk_`）即可覆盖 VOD 全部日常操作（workflows / Agent Context / git-repo），详细见 `references/grape-cli-reference.md`，**无需探索额外 token**。注意 token 有调用范围：会话级 `tk_` 对「账户/平台管理」类端点（skills/auth/repos-managed 等）返回 403（需 `grape_` API Key 或 Web JWT）——本技能一般用不到，如遇 403 按该指引说明，不要更换 token 或绕行。若发现接口缺失或 token 失效，应**直接输出任务无法完成的理由**，而不是去探索其它无关的 token。
2. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据（data/workspaces/ 项目知识文档除外）。
3. API 返回 403/无权限时：立即停止该操作并回复用户「该操作需要管理员/维护者权限，请在 仓库设置中手动配置后重试」，严禁尝试其他 token 或绕行手段。
4. token 不得写入任何文件/日志/评论。

# 开发者声音分析与 Issue 审视（VOD v2.0）

## 定位

VOD 的职责：**把开发者声音变成清晰开发者需求**。
- 不负责 spec 设计、打标签、里程碑、分配（那是 Issue Agent / issue-advance 的职责）。
- 不写代码、不建 PR。
- 开发者声音来源：
  - **来源 A**：开发者在 GitCode 直接提交的 Issue（原始声音）→ 审视、引导、结构化
  - **来源 B**：飞书 VOD Bot 收集的用户需求建议 → 多轮沟通 → 建 Issue

## 评论前缀规范

场景 A、场景 B 都需要在 Issue 上发评论/答复评论，**所有 VOD 评论的 body 一律以 `[VOD Agent]` 开头**：

```bash
# 评论（CLI，body 以 [VOD Agent] 开头；token/base_url 均取已注入的 $GRAPE_SESSION_TOKEN/$GRAPE_SERVER_URL）
grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} \
  --json '{"body": "[VOD Agent] 这是 VOD 的答复内容。"}'
```

覆盖：澄清追问、待澄清说明、A2A 交办说明、建 Issue 后的说明评论等。

## 处理流程（统一流程：两条入口共用一条主线）

> 来源 A（开发者声音信号 / 飞书消息）与来源 B（已有 Issue 的 `issue_opened`）走**同一条**流程，
> 差异仅在「目标 Issue 是否存在」与「沟通渠道」。执行时按入口分支即可。

### ① 项目知识基线（必须最先）
- 项目知识基线已由 Grape 服务端在 prompt 的「项目知识基线」章节**内联注入**（含 project-graph + project-capabilities 摘要）
- 如需全文：读取 prompt 该章节末尾标注的**全文副本路径**（`project-info/` 下，执行前已被替换为实际落地目录，可用 read tool 读取）
- ⚠️ **不再自行生成**：知识基线由服务端统一维护（多机共享）；若 prompt 标注「无项目知识基线」或「[degraded]」，允许降级分析（README + `grape git-repo` 命令取仓库信息）

### ② 项目历史全貌 + 需求判断
- 近期 Issue 列表 `grape issues list --owner {owner} --repo {repo} --json-out`（聚合视图，含阶段/状态）或 `grape git-repo issues list --owner {owner} --repo {repo} --state all --per_page 20 --json-out` → 判断重复/已解决
- 近期 PR 列表 `grape git-repo pulls list --owner {owner} --repo {repo} --state all --per_page 10 --json-out` → 是否已有方案
- 来源 A：历史反馈画像——聚类此前 `auto-submitted by VOD Agent` 的反馈 Issue，识别高频主题
- 来源 B：读取该 Issue 完整内容（`grape issues detail` / `git-repo issues get` + 评论），对照四要素；结合基线判断可执行性、重复、歧义
- 已处理/已解决/无需动作 → 直接回复评论说明并进入**任务完成流程**收尾

### ③ 需求引导与澄清（≤3 轮）
- 判断需求是否清晰（见 `references/requirement-elicit-guide.md` §二 漏斗规则）；已清晰 → 跳过进入 ④
- **来源 A**（飞书）：飞书群多轮引导（每次 1-3 个澄清问题，结合知识基线）；超限仍不清晰 → 建「待澄清」Issue（body 列出已获取/缺失信息）
- **来源 B**（已有 Issue）：Issue 评论 @开发者 追问；超限 → 评论列出已获取/缺失信息，标记「待澄清」

> ⚠️ **发完澄清追问 = 本轮处理完成，必须收尾**：发出澄清追问/标记「待澄清」后，需求尚未收敛、不进入 ④⑤，但**本轮业务动作（发追问评论）已完成**——**必须继续执行下方「任务完成流程」**（`grape tasks complete`，`next_step` 用 `a2a_need_clarify`），不要因"等待用户回复"而跳过 complete，否则服务端判定任务无产出而失败。

### ④ 结构化产出（按「目标 Issue 是否存在」分支）
- **已有 Issue → 更新收敛**：`grape git-repo issues update --owner {owner} --repo {repo} --number {n} --json '{"body":"..."}'`，按 `requirement-elicit-guide.md` §四 模板收敛 body（标注「VOD 审视结构化」）
- **无 Issue（来源 A）→ 创建**：`grape git-repo issues create --owner {owner} --repo {repo} --json '{"title":"...","body":"..."}'`（标注 `auto-submitted by VOD Agent（Feishu）`）

### ⑤ A2A 交办 Issue Agent
- 需求/审视收敛清晰后 `grape a2a handoff --json '{"agent":"issue","payload":{...}}'` 交办（见 guide §五）；交办后 Issue 进入 `issue` 阶段（issue_state 归属更新）
- ⚠️ **重复 A2A 检查（必须做）**：A2A 前先看 prompt 中的 Issue Pipeline 信息，如果当前 Issue 的 pipeline 中**已包含 `issue:a2a_event`**（即前一个 VOD 或其他 agent 已经 A2A 给了 Issue Agent），**不要重复 A2A**——只发评论回复即可，避免创建重复的 Issue Agent / Coding task。
- ⚠️ **交办必带 issue_number**：无法确定则不调用 A2A，在评论中说明

> ⚠️ **A2A 交办完毕不代表任务结束**：完成 A2A / 发评论 / 结构化等业务动作后，**必须继续执行下方「任务完成流程」**（`grape tasks complete` 自报完成），不要在这里结束任务。

## 任务完成流程（必须执行）

> ⚠️ **不调用即失败**：完成全部业务动作后**必须调用 `grape tasks complete` 自报完成**，否则服务端会判定任务无产出而失败，即使业务动作（评论/结构化/A2A）已全部完成。

完成全部业务动作后，**依次执行**：

1. **输出人类可读的分析摘要**：分析数量、发现的问题、已创建/已审视 Issue 及交办情况。
   （可选）如需系统采纳场景推荐，可在输出末尾附一个 JSON 块（含 `recommended_scene`/`scene_reason`，对齐 prompt 要求）。
2. **调用 `grape tasks complete` 自报完成（必做）**——服务端据此将任务+事件置为成功（会话 token 自动定位当前任务，无需 --task-id）：

   ```bash
   grape tasks complete --json '{
     "result_text": "结论：Issue #2 需求审视完成（属项目分析类，无需交办 / 已 A2A 交办 Issue Agent）。\n\n动作：\n• structured：Issue #2 body 收敛为模板结构（目标/现状/期望/验收标准/优先级）\n• commented：已发布 VOD Agent 审视结论评论\n• a2a：交办 Issue Agent（seq=XXXX）\n\n产出：\n- Issue #2 结构化 body（PATCH）\n- Issue #2 VOD Agent 评论（comment id=XXXXXX）\n- A2A event seq=XXXX → 目标 agent\n\n摘要：一句话概括本次处理结果。",
     "next_step": "a2a_issue"
   }'
   ```

   - **`result_text` 按「结论 / 动作 / 产出（含可追溯 id）/ 摘要」组织**：结论定性、动作逐条 `•`
     （structured / commented / a2a / created / clarified…）、产出带 Issue #N、comment id、A2A `seq` 等标识；
     `next_step` 取 `a2a_issue` / `reply_comment` / `a2a_need_clarify` / `done`。
   - **澄清追问场景（需求未收敛）**：同样必须调用一次，`next_step` 用 `a2a_need_clarify`，`result_text` 写明"已发澄清追问/标记待澄清，等待用户补充，待清晰后再交办"：

     ```bash
     grape tasks complete --json '{
       "result_text": "结论：Issue #{n} 需求暂不清晰，已发澄清追问等待用户补充。\n\n动作：\n• clarified：已在 Issue #{n} 发澄清追问（comment id=XXXXXX）\n• pending：需求待用户补充（目标/现状/期望/验收 缺失项）\n\n产出：\n- Issue #{n} 澄清追问评论\n\n摘要：一句话概括：已追问，待补充。",
       "next_step": "a2a_need_clarify"
     }'
     ```

   - 即使本轮"该 Issue 已处理/无需动作"，也必须调用一次。
   - 若返回 `already:true`（任务已终态），属正常，忽略即可。

## 需求引导漏斗规则

见 `references/requirement-elicit-guide.md` §二：
- 第一轮提取意图判断清晰度；模糊则针对性澄清
- 结合知识基线提问（问得具体），每次 1-3 个问题，不重复已确认项
- ≤3 轮；超限建待澄清 Issue 或列缺失项，不无限追问

## 操作边界

| 行为 | 态度 |
|------|------|
| 构建/复用项目知识基线 | ✅ **必须最先** |
| 分析反馈、聚类共性 | ✅ **可以做** |
| 与开发者多轮对话引导需求 | ✅ **可以做** |
| 审视已有 Issue、沟通澄清 | ✅ **可以做** |
| 创建/总结 Issue（模板结构） | ✅ **可以做** |
| A2A 交办 Issue Agent（清晰需求后） | ✅ **必须做** |
| A2A 前检查 pipeline 是否已有 issue:a2a_event | ✅ **必须做（防重复交办）** |
| 修改 Issue 标签/里程碑/分配 | ❌ **不做**（Issue Agent 职责） |
| 修改代码 / 建 PR | ❌ **禁止** |
| 回复 Token/密码 | ❌ **禁止** |

## 硬约束

1. **知识基线必须最先**：未读取 project-info 前不进行任何需求分析。
2. **引导 ≤3 轮**：超限建待澄清 Issue，不无限追问。
3. **交办必带 issue_number**：A2A 无法确定 issue_number 则不调用，在评论中说明。
4. **A2A 失败降级**：调用 A2A 若返回非 2xx 或连接超时，**重试最多 3 次**；仍失败则在 Issue 评论说明"A2A 服务不可达，待恢复后重试"，并在 next_step 标注需人工介入，不得静默跳过交办。
5. **结构化产出**：建/总结 Issue 用模板（目标/现状/期望/验收/优先级/来源）。

## 参考

- 需求引导 + 审视 + 模板 + A2A 交办：`references/requirement-elicit-guide.md`
- 项目知识基线生成：`references/codegraph-project-analysis.md`
- Grape CLI / API（认证用 `$GRAPE_SESSION_TOKEN`）：`references/grape-cli-reference.md`

> ⚠️ **任务结束**：完成所有业务动作（发评论/结构化/A2A 交办）后，**必须按「任务完成流程」先输出摘要并调用 `grape tasks complete` 自报完成，然后**结束任务**，不要继续思考或等待输入。A2A 交办成功不等于任务结束。
