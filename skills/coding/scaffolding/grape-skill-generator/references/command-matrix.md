# agent_type → 命令映射矩阵

> 来源：基于 cli-code-analysis-spec.md 事实基线 + 5 类帮助分类
> 用途：生成 skill 时按 agent_type 选取实际用到的命令子集，写入 grape-cli-reference.md 常用命令章节
> 原则：只列该 agent 实际用到的命令，不列全量 68 个（spec §6 Token 优化）

---

## 帮助分类（5 类）与 agent_type 对应关系

| 类别 | 包含组 | 主要 agent_type |
|------|--------|----------------|
| Core workflows | tasks, a2a | 全部 agent（任务管理 + A2A 交接） |
| Agent Context | issues, events, knowledge | issue / vod / coding / qa（上下文读取） |
| Code & repositories | git, git-repo | coding / qa（代码仓库操作） |
| Account & platform | agents, auth, chat, repos, scenes, skills | sre / skill-generator（平台资源管理） |
| CLI utilities | commands, refresh | 全部 agent（命令发现 + 契约刷新） |

---

## 各 agent_type 命令映射

### vod（声音反馈 → Issue 创建）

| 场景 | 命令 | 用途 |
|------|------|------|
| 读取上下文 | `knowledge context --repo {owner}/{repo} --agent_type vod --json-out` | 合并注入上下文 |
| 读取知识全文 | `knowledge content --repo {owner}/{repo} --file {path} --json-out` | 读取知识文件 |
| 读取 Issue | `issues detail --owner {owner} --repo {repo} --number {n} --json-out` | Issue 全貌 |
| 创建 Issue | `issues create --owner {owner} --repo {repo} --json '{"title":"...","description":"..."}'` | 反馈转 Issue |
| Issue 评论 | `git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"..."}'` | 结构化结论写评论 |
| 任务完成 | `tasks complete --json '{"result_text":"...","next_step":"done"}'` | 自报完成 |
| A2A 交接 | `a2a handoff --json '{"agent":"issue","payload":{...}}'` | 交棒 Issue Agent |

### issue（Issue 分类/标签/指派/A2A 触发）

| 场景 | 命令 | 用途 |
|------|------|------|
| Issue 列表 | `issues list --owner {owner} --repo {repo} --json-out` | 含阶段/状态聚合 |
| Issue 详情 | `issues detail --owner {owner} --repo {repo} --number {n} --json-out` | 阶段+事件+pipeline |
| Issue 事件 | `issues events --owner {owner} --repo {repo} --number {n} --json-out` | 事件流 |
| Issue pipeline | `issues pipeline --owner {owner} --repo {repo} --number {n} --json-out` | 路线图 |
| 事件详情 | `events detail --seq {seq} --json-out` | 读取 A2A 交接 payload |
| GitCode Issue 列表 | `git-repo issues list --owner {owner} --repo {repo} --json-out` | 原始 Issue |
| 创建 Issue 评论 | `git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"..."}'` | 分类/标签结论 |
| 创建标签 | `git-repo labels create --owner {owner} --repo {repo} --json '{"name":"bug","color":"#d73a4a"}'` | 打标签 |
| 更新 Issue | `git-repo issues update --owner {owner} --repo {repo} --number {n} --json '{"labels":"bug","assignee":"user"}'` | 指派/标签 |
| 任务完成 | `tasks complete --json '{"result_text":"...","next_step":"a2a_coding"}'` | 自报完成 |
| A2A 交接 | `a2a handoff --json '{"agent":"coding","payload":{...}}'` | 触发 Coding Agent |

### coding（代码实现/PR 创建/自我审查）

| 场景 | 命令 | 用途 |
|------|------|------|
| 读取上下文 | `knowledge context --repo {owner}/{repo} --agent_type coding --json-out` | 合并注入上下文 |
| 仓库信息 | `git-repo repo --owner {owner} --repo {repo} --json-out` | clone_url/default_branch |
| 目录树 | `git-repo tree --owner {owner} --repo {repo} --ref {ref} --json-out` | 目录结构 |
| 文件内容 | `git-repo contents --owner {owner} --repo {repo} --path {path} --raw` | 读取文件 |
| 分支列表 | `git-repo branches --owner {owner} --repo {repo} --json-out` | 查看分支 |
| 提交历史 | `git-repo commits --owner {owner} --repo {repo} --json-out` | 提交记录 |
| Issue 列表 | `git-repo issues list --owner {owner} --repo {repo} --json-out` | 关联 Issue |
| 创建 PR | `git-repo pulls create --owner {owner} --repo {repo} --json '{"title":"feat: ...","head":"feat/issue-{n}","base":"main"}'` | 提交 PR |
| PR 评论 | `git-repo pulls comments create --owner {owner} --repo {repo} --number {pr} --json '{"body":"..."}'` | 自我审查说明 |
| 本地 git | `grape git add/commit/push` | 本地代码操作 |
| Issue 评论 | `git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"..."}'` | 告知 PR |
| 任务完成 | `tasks complete --json '{"result_text":"...","next_step":"a2a_qa"}'` | 自报完成 |
| A2A 交接 | `a2a handoff --json '{"agent":"qa","payload":{...}}'` | 交棒 QA |

### qa（代码审查/功能验证/安全检查）

| 场景 | 命令 | 用途 |
|------|------|------|
| PR 详情 | `git-repo pulls get --owner {owner} --repo {repo} --number {pr} --json-out` | PR 元信息 |
| PR 变更文件 | `git-repo pulls files --owner {owner} --repo {repo} --number {pr} --json-out` | 变更清单 |
| PR 评论列表 | `git-repo pulls comments list --owner {owner} --repo {repo} --number {pr} --json-out` | 已有评论 |
| PR 评论 | `git-repo pulls comments create --owner {owner} --repo {repo} --number {pr} --json '{"body":"..."}'` | 审查报告 |
| 文件内容 | `git-repo contents --owner {owner} --repo {repo} --path {path} --raw` | 审查代码 |
| 目录树 | `git-repo tree --owner {owner} --repo {repo} --ref {ref} --json-out` | 仓库结构 |
| Issue 详情 | `issues detail --owner {owner} --repo {repo} --number {n} --json-out` | 验收标准 |
| PR 合并 | `git-repo pulls merge --owner {owner} --repo {repo} --number {pr}` | 审查通过合并 |
| 任务完成 | `tasks complete --json '{"result_text":"...","next_step":"a2a_sre"}'` | 自报完成 |
| A2A 交接 | `a2a handoff --json '{"agent":"sre","payload":{...}}'` | 交棒 SRE 发布 |

### sre（构建部署/发布管理/监控运维）

| 场景 | 命令 | 用途 |
|------|------|------|
| PR 详情 | `git-repo pulls get --owner {owner} --repo {repo} --number {pr} --json-out` | PR 信息 |
| PR 合并 | `git-repo pulls merge --owner {owner} --repo {repo} --number {pr}` | 合并 PR |
| 部署 URL | `repos deploy url --owner {owner} --repo_name {repo} --json-out` | 获取部署地址 |
| 仓库信息 | `git-repo repo --owner {owner} --repo {repo} --json-out` | clone_url |
| 提交历史 | `git-repo commits --owner {owner} --repo {repo} --json-out` | 发布版本确认 |
| 分支列表 | `git-repo branches --owner {owner} --repo {repo} --json-out` | 发布分支确认 |
| Issue 评论 | `git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"..."}'` | 发布通知 |
| 任务完成 | `tasks complete --json '{"result_text":"...","next_step":"done"}'` | 自报完成 |
| A2A 交接 | `a2a handoff --json '{"agent":"issue","payload":{...}}'` | 回传 Issue Agent |

### skill-generator（本 skill 自身，生成其他 skill）

| 场景 | 命令 | 用途 |
|------|------|------|
| 查重 | `skills list --repo {owner}/{repo} --q {keyword} --json-out` | 同名 skill 检查 |
| 目录检查 | `git-repo contents --owner {owner} --repo {repo} --path skills/{agent_type} --json-out` | 目录是否存在 |
| 读取已有 skill | `skills detail --skill_id {id} --json-out` | 参考已有 skill |
| 本地 git | `grape git add/commit/push` | 提交生成产物 |
| 创建 PR | `git-repo pulls create --owner {owner} --repo {repo} --json '{"title":"...","head":"...","base":"main"}'` | 提交 PR |
| Issue 评论 | `git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"..."}'` | 告知 PR |
| 任务完成 | `tasks complete --json '{"result_text":"...","next_step":"a2a_qa"}'` | 自报完成 |
| A2A 交接 | `a2a handoff --json '{"agent":"qa","payload":{...}}'` | 交棒 QA 审查 |

---

## 全部 agent 共用命令

| 场景 | 命令 | 用途 |
|------|------|------|
| 我的任务 | `tasks mine --json-out` | 获取分配给自己的任务 |
| Issue 详情 | `issues detail --owner {owner} --repo {repo} --number {n} --json-out` | Issue 全貌 |
| 事件详情 | `events detail --seq {seq} --json-out` | 读取 A2A 交接 payload |
| 澄清 | `tasks clarify --task_id {id} --json '{"message":"..."}'` | 向上游提问 |
| 澄清历史 | `tasks clarifications --task_id {id} --json-out` | 澄清问答记录 |
| 命令发现 | `grape commands [pattern]` | 列出可调用命令 |
| 帮助 | `grape <group> <verb> --help` | 查参数/Body fields |
| 契约刷新 | `grape refresh` | 重拉最新契约 |

---

## A2A payload 标准结构

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
