# agent_type → 命令映射参考矩阵

> 来源：基于 grape CLI 契约事实基线 + 5 类帮助分类
> 用途：生成 skill 时**按需参考**选取该 agent 实际用到的命令子集，写入 grape-cli-reference.md 常用命令章节
> ⚠️ **这是常用命令参考与建议，不强制**：每个 skill 仍需根据它所承担的职责，灵活按需选择对应命令，无需局限于下方某 agent 的清单。

---

## 一、所有 agent 共性命令（每个 skill 都应包含的基础能力）

> 项目知识基线、读取 Issue、读取 events、任务上下文、任务完成、A2A 交接等是**所有 agent 都需要的共性命令**，生成 skill 时建议都纳入。

| 场景 | 命令 | 用途 |
|------|------|------|
| 项目知识基线 | `repos project info --owner {owner} --repo {repo} --json-out` | project-graph + project-capabilities（理解项目） |
| 知识沉淀统计 | `knowledge stats --repo {owner}/{repo} --json-out` | 各类知识数量 |
| 知识列表 | `knowledge list --repo {owner}/{repo} --source agent --json-out` | Agent 沉淀知识（前序经验） |
| 我的任务 | `tasks current --json-out` | 获取分配给自己的任务 |
| Issue 详情 | `issues detail --owner {owner} --repo {repo} --number {n} --json-out` | Issue 全貌（含阶段/事件/pipeline） |
| Issue pipeline | `issues pipeline --owner {owner} --repo {repo} --number {n} --json-out` | 路线图（防重复 A2A） |
| Issue 事件 | `issues events --owner {owner} --repo {repo} --number {n} --json-out` | 事件流 |
| Issue 评论列表 | `git-repo issues comments list --owner {owner} --repo {repo} --number {n} --json-out` | 读取讨论上下文 |
| 事件详情 | `events detail --seq {seq} --json-out` | 读取前序 A2A 交接 payload |
| Issue 评论 | `git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"..."}'` | 评论/收敛结论 |
| 任务完成 | `tasks complete --json '{"result_text":"...","next_step":"..."}'` | 自报完成（结构化字段必填） |
| A2A 交接 | `a2a handoff --json '{"agent":"{目标agent}","payload":{...}}'` | 交棒下游 agent（非技能名） |
| 命令发现 | `grape commands [pattern]` | 列出可调用命令 |
| 契约刷新 | `grape refresh` | 重拉最新契约 |

> 提示：澄清类需要时用 `tools`；不同 agent 是否用 `issues events`/`knowledge list` 等由实际职责决定。

---

## 二、流程状态命令池（按需补充，按 issue 阶段设计 / 用户诉求 选用）

> ⚠️ **这不是共性命令**：是否使用取决于**当前流程的 issue 阶段设计**与**用户诉求**。生成 skill 时按该技能承担的环节（澄清/审查/交付决策）判断是否纳入，不强制。

| 场景 | 命令 | 用途与口径 |
|------|------|-----------|
| 待用户补充输入 | `grape issues awaiting-input --issue_id {issue_id} --json '{"questions":"...","reason":"..."}' --json-out` | 显式声明「待用户澄清补充」，置 awaiting_input + 触达用户（澄清追问后收尾用）。**大部分情况在 vod/issue 阶段用，但以用户需求为准**，生成 skill 时按 `flow_nodes` 判断是否需要 |
| 待人工拍板审核点 | `grape issues pending-review --issue_id {issue_id} --json '{"review_points":"...","references":"..."}' --json-out` | 审查通过但 PR 未合入、需用户拍板时置审核点（触达用户）。按需求单 `flow_nodes` 用，不限于 qa |
| 审核通过（继续/完成） | `grape issues review-pass --issue_id {issue_id} --json '{"target":"done","evidence":"..."}' --json-out` | 用户确认后通过；`target=done` 完成 / `target=processing` 继续。随 pending-review 配套 |
| 审核驳回 | `grape issues review-reject --issue_id {issue_id} --json '{"reason":"..."}' --json-out` | 用户驳回。随 pending-review 配套 |
| 任务分派/状态通知 | `grape tasks notify --json '{"assignee":"...","issue_number":{n},"repo_key":"...","task_description":"..."}'` | **通用接口，任何 agent 都可用**，按用户需求/技能职责决定是否用于任务分派通知；生成 skill 时按 `flow_nodes` 判断。⚠️ 结果/部署/完成通知建议用 `git-repo issues comments create`，勿用 tasks notify 传结果 |

> **`issue_id` 获取方式（这些命令共用，必填）**：`issue_id` 是需求卡片内部 id（int），**不是 issue 编号**——**优先用已注入的环境变量 `$GRAPE_ISSUE_ID`**；未注入时才降级用 `grape issues detail` 出参的 `id` 字段：
> ```bash
> ISSUE_ID="${GRAPE_ISSUE_ID:-$(grape issues detail --owner {owner} --repo {repo} --number {n} --json-out | jq -r '.id')}"
> grape issues awaiting-input --issue_id "$ISSUE_ID" --json '{"questions":"...","reason":"..."}' --json-out
> ```
> 解析失败/为空 → 记「issue_id 解析失败」并收尾，**不要传 issue number 兜底**。

> 用法要点：`pending-review`/`review-pass`/`review-reject` 仅在 pending_review 态有效（幂等，`changed:false` 忽略）；`pending-review` 不终态化，本轮仍走 `tasks complete` 收尾。

---

## 三、各 agent_type 常用命令映射（参考建议）

> 下方为各 agent 的**常见**命令集；实际生成时结合该 agent 的职责（对应 skill 定位）按需增删。

### vod（声音反馈 → Issue 引导/审视）

| 场景 | 命令 | 用途 |
|------|------|------|
| （共性命令：知识基线/读 Issue/评论/A2A 等，见「一」） | | |
| A2A 交棒 | `a2a handoff --json '{"agent":"issue","payload":{...}}'` | 交棒 Issue agent |

### issue（Issue 分类/标签/指派/A2A 触发）

| 场景 | 命令 | 用途 |
|------|------|------|
| Issue 列表 | `issues list --owner {owner} --repo {repo} --json-out` | 含阶段/状态聚合 |
| GitCode Issue 列表 | `git-repo issues list --owner {owner} --repo {repo} --json-out` | 原始 Issue |
| 创建评论 | `git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"..."}'` | 分类/标签结论 |
| 创建标签 | `git-repo labels create --owner {owner} --repo {repo} --json '{"name":"bug","color":"#d73a4a"}'` | 打标签 |
| 更新 Issue | `git-repo issues update --owner {owner} --repo {repo} --number {n} --json '{"labels":"bug","assignee":"user"}'` | 指派/标签（⚠️ 先 get 回填 body） |
| A2A 交接 | `a2a handoff --json '{"agent":"coding","payload":{...}}'` | 触发 coding agent |

### coding（代码实现/PR 创建/自我审查）

| 场景 | 命令 | 用途 |
|------|------|------|
| 仓库信息 | `git-repo repo --owner {owner} --repo {repo} --json-out` | clone_url/default_branch |
| 目录树 | `git-repo tree --owner {owner} --repo {repo} --depth single --json-out` | 目录结构 |
| 文件内容 | `git-repo contents --owner {owner} --repo {repo} --path {path} --raw` | 读取文件 |
| 分支列表 | `git-repo branches --owner {owner} --repo {repo} --json-out` | 查看分支 |
| 提交历史 | `git-repo commits --owner {owner} --repo {repo} --json-out` | 提交记录 |
| 本地 git | `grape git add/commit/push` | 本地代码操作 |
| 创建 PR | `git-repo pulls create --owner {owner} --repo {repo} --json '{"title":"feat: ...","body":"## 概述\n\n{描述}","head":"feat/issue-{n}","base":"{WORK_BRANCH}","related_issue_nums":["{n}"],"auto_close_issues":true}'` | 提交 PR（base 用 WORK_BRANCH，body 必带；`related_issue_nums` 传 Issue 号数组，如 `[12]`） |
| PR 评论 | `git-repo pulls comments create --owner {owner} --repo {repo} --number {pr} --json '{"body":"..."}'` | 自我审查/告知 |
| A2A 交接 | `a2a handoff --json '{"agent":"qa","payload":{...}}'` | 交棒 qa agent |

### qa（代码审查/功能验证/安全检查）

| 场景 | 命令 | 用途 |
|------|------|------|
| PR 详情 | `git-repo pulls get --owner {owner} --repo {repo} --number {pr} --json-out` | PR 元信息 |
| PR 变更文件 | `git-repo pulls files --owner {owner} --repo {repo} --number {pr} --json-out` | 变更清单 |
| PR 评论列表 | `git-repo pulls comments list --owner {owner} --repo {repo} --number {pr} --json-out` | 已有评论 |
| PR 评论 | `git-repo pulls comments create --owner {owner} --repo {repo} --number {pr} --json '{"body":"..."}'` | 审查报告 |
| 文件内容 | `git-repo contents --owner {owner} --repo {repo} --path {path} --raw` | 审查代码 |
| 目录树 | `git-repo tree --owner {owner} --repo {repo} --depth single --json-out` | 仓库结构 |
| PR 合并 | `git-repo pulls merge --owner {owner} --repo {repo} --number {pr}` | 审查通过合并（如需） |
| A2A 交接 | `a2a handoff --json '{"agent":"sre","payload":{...}}'` | 交棒 sre（发布/部署） |

### sre（构建部署/发布管理/监控运维）

| 场景 | 命令 | 用途 |
|------|------|------|
| PR 合并 | `git-repo pulls merge --owner {owner} --repo {repo} --number {pr}` | 合并 PR |
| 部署 URL | `repos deploy url --owner {owner} --repo_name {repo} --json-out` | 获取部署地址 |
| 仓库信息 | `git-repo repo --owner {owner} --repo {repo} --json-out` | clone_url |
| 提交历史 | `git-repo commits --owner {owner} --repo {repo} --json-out` | 发布版本确认 |
| 分支列表 | `git-repo branches --owner {owner} --repo {repo} --json-out` | 发布分支确认 |
| A2A 交接 | `a2a handoff --json '{"agent":"issue","payload":{...}}'` | 回传 issue agent |

### chat（IM 对话入口）

| 场景 | 命令 | 用途 |
|------|------|------|
| 查询仓库信息 | `git-repo repo --owner {owner} --repo {repo} --json-out` | 仓库元信息 |
| 查询 Issue/PR | `issues detail` / `git-repo pulls get` | 答复用户查询 |
| 查询文件 | `git-repo contents --owner {owner} --repo {repo} --path {path} --raw` | 项目信息 |
| 创建 Issue | `git-repo issues create --owner {owner} --repo {repo} --json '{"title":"...","body":"..."}'` | 需求引导明确后（按边界） |

### skill-generator（本 skill 自身，生成其他 skill）

| 场景 | 命令 | 用途 |
|------|------|------|
| 查重 | `skills list --repo {owner}/{repo} --q {keyword} --json-out` | 同名 skill 检查 |
| 目录检查 | `git-repo contents --owner {owner} --repo {repo} --path .grape/skills/{agent_type} --json-out` | `.grape/skills/{agent_type}/` 是否存在 |
| 本地 git | `grape git add/commit/push` | 提交生成产物 |
| 创建 PR | `git-repo pulls create --owner {owner} --repo {repo} --json '{"title":"...","head":"feat/issue-{n}","base":"{WORK_BRANCH}"}'` | 提交 PR（base 用 WORK_BRANCH） |
| A2A 交接 | `a2a handoff --json '{"agent":"qa","payload":{...}}'` | 交棒 qa agent（agent，非技能名） |

---

## A2A payload 标准结构

> ⚠️ **A2A 交办的是 agent（`coding`/`qa`/`sre`/`vod`/`issue`），不是技能名**；对应 agent 使用哪个技能由该 agent 自行决定。

```json
{
  "agent": "{目标agent}",
  "payload": {
    "repository": "{owner}/{repo}",
    "account": "{user}",
    "issue_number": {n},
    "pr_number": {pr},
    "context": "{交接说明}"
  }
}
```

- `issue_number` 必填
- `pr_number` 有则必填（PR 涉及时）
- `repository` 与 `account` 必填

---

## next_step 合法值参考

| 场景 | next_step |
|------|-----------|
| 已 A2A 交办下游 | `a2a_{目标agent}`（如 `a2a_qa`、`a2a_sre`） |
| 需等待用户回复 | `reply_comment` |
| 本轮处理完毕 | `done` |