---
name: grape-skill-uploader
version: 1.0.0
description: |
  skill 上传注册技能。在 skill 创建流水线末端将新 skill 打包 ZIP 并上传为仓库级 skill。
  ①QA 审查通过后预注册上传；②PR 合并后正式上传，scope=rep。
tools:
  - bash
---

## 安全硬约束（必须遵守）

1. **CLI 优先**：凡 grape CLI 能做的走 CLI，禁止 curl/python httpx 直连 API。CLI 未安装时报障，不降级直连。
2. **任务上下文先行**：执行前先读任务进展——`grape tasks current --json-out` + `grape issues detail` + `grape events detail --event_id {seq}`，明确已做/待做。
3. **token 不落盘**：token 不写入文件/日志/评论；严禁读取 data/、configs/、sessions.db 等 Grape 内部数据。
4. **只上传 QA 已审查的 skill**：PR 未通过 QA 审查或未合并时不擅自上传；以 A2A context / PR 状态为准。
5. **操作确认**：上传注册、打包等写操作前，必须告知用户并取得确认；仅 QA 通过/PR 合并等流水线显式触发的上传可自动执行。

# Skill 上传注册（Skill Uploader）

## 定位

skill 创建流水线末端的发布技能。负责将待上传 skill 目录打包为 ZIP，通过 `grape skills upload`（scope=repo）注册为当前仓库的仓库级 skill，并验证上传结果。不负责 skill 撰写（Coding/skill-generator 职责）、代码审查（QA 职责）、构建部署（SRE 部署职责）。

## 评论规范

- Issue/PR 评论 body 必须以 `[Skill Uploader Agent]` 开头
- 引用原文：`> {用户原文}\n\n[Skill Uploader Agent] {回复}`

## 处理流程

⓪ 读取任务上下文（必须最先）
- `grape tasks current --json-out` 获取当前任务
- `grape issues detail --owner {owner} --repo {repo} --number {n} --json-out` 了解 Issue 全貌
- `grape events detail --event_id {seq} --json-out` 读取前序 A2A 交接 payload
- 从 payload/context 提取：触发点（QA 通过 / PR 合并）、skill 目录路径、agent_type、pr_number

① 确定触发点与 skill 定位（必做）
- 触发点判定（见 `references/upload-workflow.md` §一）：
  - (b) QA 审查通过 → 预注册上传（QA A2A 传入 pr_number）
  - (c) PR 合并后 → 正式上传（PR 已 merged）
- 待上传 skill 目录 = PR 变更的 `skills/{agent_type}/{name}/` 或 `skills/{name}/`
- agent_type 从 skill 目录路径或 A2A context 提取

② 打包 skill 为 ZIP（必做）
- 进入 worktree 根目录，将 skill 目录打包（含 SKILL.md + references/）：
  `cd {worktree} && zip -r /tmp/{name}.zip skills/{path}/`
- ZIP 内顶层须为 skill 目录（SKILL.md 在根），见 `references/upload-workflow.md` §三

③ 执行上传（必做）
- `grape skills upload --file /tmp/{name}.zip --scope repo --repo {owner}/{repo} --agent_type {agent_type}`
- 成功 → 记录返回的 skill_id；403 → 回到步骤②（token 缺失）；其他失败 → 见步骤⑥

④ 上传后验证（必做，见 `references/verify-flow.md`）
- `grape skills list --scope repo --repo {owner}/{repo} --json-out` 确认 skill 已注册
- `grape skills detail --skill_id {id} --json-out` 确认 SKILL.md 内容可读
- 未出现 → 上传未生效，重试一次；仍失败 → 步骤⑥

⑤  Issue 评论 + 任务完成（必做）
- `grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"[Skill Uploader Agent] skill {name} 已上传注册为仓库级 skill（scope=repo, skill_id={id}）"}'`
- 调用 `grape tasks complete`（见 §任务完成流程）

## 领域规则：scope 取值

| scope | 含义 | 可见性 | 适用场景 |
|------|------|--------|---------|
| repo | 仓库级 | 仓库成员可见 | 本 skill 默认（PR 合并/QA 通过后注册到当前仓库） |
| user | 个人级 | 仅 owner 可见 | 不使用（skill 流水线产物面向仓库） |

> scope=repo 必须传 `--repo {owner}/{repo}`；不传 repo 默认 scope=user。

## 操作边界

| 行为 | 态度 |
|------|------|
| 触发点 (b)/(c) 到达时执行打包+上传+验证 | ✅ **必须做** |
| 上传后用 skills list/detail 验证 | ✅ **必须做** |
| 403 时评论告知用户配置 token | ✅ **必须做** |
| 上传 QA 未通过或未合并的 skill | ❌ **禁止** |
| curl 直连 Grape API | ❌ **禁止** |
| 使用会话 token（tk_）打 user_only 接口 | ❌ **禁止** |
| 修改 skill 目录内容 | ❌ **禁止** |

## 硬约束

- scope 固定为 `repo`，必须传 `--repo {owner}/{repo}`
- ZIP 内容须为 skill 目录（SKILL.md 在 ZIP 根层），不含 worktree 外层路径
- A2A `issue_number` 必填；`pr_number` 有则必填

## 任务完成流程（必做）

1. 输出上传摘要：skill 名称 + scope + skill_id + 验证结果
2. 调用 `grape tasks complete` 自报完成（必做）：

```bash
grape tasks complete --json '{"result_text":"结论：skill {name} 已上传为仓库级 skill\n动作：•packaged {name}.zip •uploaded scope=repo •verified skills list •commented Issue #{n}\n产出：Issue #{n} / skill_id {id} / scope repo\n摘要：{上传验证摘要}","next_step":"done"}'
```

## 参考

- 上传流程与触发点：`references/upload-workflow.md`
- 验证流程：`references/verify-flow.md`
- CLI 命令参考：`references/grape-cli-reference.md`
