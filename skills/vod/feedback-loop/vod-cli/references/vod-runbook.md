# VOD 执行走查表（runbook）

> 目的：把 VOD 处理 Issue 的**每一步要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$ACCOUNT`（owner）、`$REPO_NAME`（repo 名）、`$ISSUE_NUMBER`、`$REPO_FULL_NAME`（owner/repo）、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> **评论前缀硬规（场景 A/B 通用）**：所有 VOD 评论 body 一律以 `[VOD Agent]` 开头（用 `grape git-repo issues comments create ... --json '{"body":"[VOD Agent] ..."}'`）。
> 命令取舍速查：读 Issue 聚合用 `issues detail`；取原始字段/评论用 `git-repo issues get` / `issues comments list`；列目录用 `contents --path ""` 或 `tree --depth 2`（**`tree` 无 `--path`**）。

---

## 场景 B：已有 Issue 审视（`issue_opened`，最常用）

> 收到事件时先按此走查表执行；下表步骤按顺序，命中分支后到对应步骤，**未命中的步骤直接跳过**。

### Step 0 · 项目知识基线（必须最先，任何分支都要做）
- 读 prompt「项目知识基线」章节末尾标注的 **`project-info/` 全文副本路径**（`read` 工具）。
- 知识基线已覆盖 README/结构/接口时：**不再**用 `grape git-repo` 逐文件探索，直接进入 Step 1。
- 仅当 prompt 标注「无项目知识基线」或 `[degraded]` 才降级：`grape git-repo repo`/`grape git-repo tree --depth 2`。

### Step 1 · 读 Issue 上下文（必做）
```bash
# 聚合视图（含阶段/状态/事件/路线图），首选
grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 需要评论/讨论细节时再取评论（按需，不必每次都调）
grape git-repo issues comments list --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```

### Step 2 · 项目历史全貌（判断重复/已解决/已有方案）
```bash
grape issues list --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out
grape git-repo pulls list --owner "$ACCOUNT" --repo "$REPO_NAME" --state all --per_page 10 --json-out
```
- 已处理/已解决/重复 → 发一条说明评论（Step 4c 模板）→ **进入 Step 6，`next_step=reply_comment`**。
- 否则继续 Step 3。

### Step 3 · 清晰度判断
对照 `requirement-elicit-guide.md` §一 四要素（目标/现状/期望/验收）判断；追问漏斗细则见 §二（结合知识基线、每次 1-3 个问题、不重复已确认项、≤3 轮）：
- **清晰** → Step 4a
- **不清晰**（需澄清，≤3 轮）→ Step 4b
- **纯咨询 / 无新需求**（如"介绍一下项目""这是做什么的"）→ Step 4c

### Step 4a · 需求清晰 → 结构化收敛
按 §四 模板写 body 到文件，再更新 Issue：
```bash
# 先写 /tmp/vod-body-N.md（模板见 requirement-elicit-guide.md §四），再转 JSON 提交
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json "{\"body\":\"$(jq -Rs . < /tmp/vod-body-N.md)\"}" --json-out
# 或长文用 @file：先转成 {"body":"..."} 的 json 文件再 --json @file
```
> 更稳：`printf '{"body":"%s"}' "$(cat /tmp/vod-body-N.md)" > /tmp/body.json` 再 `--json @/tmp/body.json`。
- 收敛后 **进入 Step 5**（如 pipeline 已有 `issue:a2a_event` 则跳过 A2A，直接 Step 6 + `next_step=reply_comment`）。

### Step 4b · 需求不清晰 → 澄清追问
```bash
# body 以 [VOD Agent] 开头，1-3 个具体问题；长文用 @file
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 您指的是……？请补充：1) … 2) …"}'
```
- **直接进入 Step 6，`next_step=a2a_need_clarify`**（不要等待用户回复，也不要 A2A）。

### Step 4c · 纯咨询 / 已解决 / 无需动作 → 回复说明
```bash
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] <项目介绍 / 已解决说明 / 无需动作说明>"}'
```
- **直接进入 Step 6，`next_step=reply_comment`**。
- ⚠️ **发出评论后必须继续 Step 6**：没有调用 `grape tasks complete` 就是任务未完成，即使评论已发、即使没有 A2A/标签/Spec 等结构化产物——**不要因"纯咨询只是回条评论"就提前结束**。

### Step 5 · A2A 交办 Issue Agent（仅 Step 4a 收敛后）
```bash
# 模板见 requirement-elicit-guide.md §五；issue_number 必填
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
  "result_text": "结论：Issue #'$ISSUE_NUMBER' <按分支写结论>。\n\n动作：\n• <动作逐条>：……\n\n产出：\n- <产出>：……\n\n摘要：一句话概括。",
  "next_step": "a2a_need_clarify"
}'
```
> `result_text` 按「结论 / 动作 / 产出（含可追溯 id）/ 摘要」组织，动作逐条 `•`，产出带 Issue #N / comment id / A2A `seq` 等标识。
> 若返回 `already:true`（任务已终态），属正常，忽略即可。**然后结束任务**，不要继续思考或等待输入。

---

## 场景 A：飞书 VOD Bot 收集的需求建议（无目标 Issue）

> 与场景 B 共用 Step 0/3/4a/6；差异在沟通渠道用飞书群，产出为**新建 Issue**。

```bash
# 引导收敛清晰后，创建 Issue（body 标注来源 Feishu；用 git-repo 组命令，body 字段明确）
grape git-repo issues create --owner "$ACCOUNT" --repo "$REPO_NAME" \
  --json '{"title":"<清晰标题>","body":"<§四 模板 body，尾部标注：来源=飞书 / auto-submitted by VOD Agent（Feishu）>"}'
# 更新/收敛：同上（若后续需收敛 body 用 git-repo issues update）
# 交办与收尾同场景 B Step 5/6
```
- 超限仍不清晰 → 建「待澄清」Issue（body 列出已获取/缺失信息）→ **仍必须 Step 6 收尾**（`next_step=a2a_need_clarify`）。

---

## 错误排查速查（命令返回异常时）

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook / reference 抄写；仍不确定再 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 里有契约不允许的字段，看确认的 Body fields，删掉多余字段 |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT，本技能不涉及 |
| `contents` 路径不存在 | 用 `tree --depth 2` 或 `contents --path ""` 定位 |

## 明确禁止

- ❌ 不查 `grape --help | head`、`grape commands` 逐条探索——runbook 已给齐本技能所需命令，照抄即可。
- ❌ 不用 `tree --path`（该参数不存在），层级用 `--depth`。
- ❌ 不因"等待用户回复"跳过 Step 6（tasks complete）——澄清追问也算本轮完成，必须收尾。