---
name: grape-skill-generator
version: 1.0.0
description: |
  skill-generator。按撰写规范为指定 agent_type 生成 grape-cli skill。
  ①接收 agent_type + 需求描述 → ②查重 → ③读取 references 三件套 → ④生成 SKILL.md + references/ → ⑤自检 → ⑥建 PR → ⑦A2A 交棒 QA。
tools:
  - bash
---

# Skill Generator（grape-cli skill 生成器）

## 安全硬约束（必须遵守）

1. **凡 grape CLI 能做的走 CLI**，禁止 curl 直连 API。CLI 未安装时报障，不降级直连。
2. **执行前先读任务上下文**：`grape tasks mine --json-out` + `grape issues detail` + `grape events detail`，明确已做/待做。
3. 命令清单以 `references/grape-cli-reference.md` 事实基线为准，**不编造命令/参数**；不确定先 `grape commands | grep` 或 `grape <g> <v> --help`。
4. 严禁读取 data/、configs/、sessions.db 等 Grape 内部数据；token 不写文件/日志/评论。
5. **操作确认**：创建 PR、提交代码等写操作前，必须告知用户并取得确认；仅 A2A/流水线显式触发的写操作可自动执行。

## 定位

接收 `agent_type`（vod/issue/coding/qa/sre）+ 需求描述，按撰写规范生成该 agent 的 grape-cli skill。不负责测试（QA 职责）/ 发布（SRE 职责）/ Issue 分类（Issue Agent 职责）。

## 评论规范

- Issue/PR 评论 body 必须以 `[Coding Agent]` 开头
- 引用原文：`> {用户原文}\n\n[Coding Agent] {回复}`

## 处理流程

⓪ 读取任务上下文（必须最先）
- `grape tasks mine --json-out` 获取分配给自己的任务
- `grape issues detail --owner {owner} --repo {repo} --number {n} --json-out` 了解 Issue 全貌
- `grape events detail --seq {seq} --json-out` 读取前序 A2A 交接 payload
- 从 prompt 提取 `agent_type` + 需求描述；信息不全用 `grape tasks clarify --task_id {id} --json '{"message":"..."}'`

① 查重（必做）
- `grape skills list --repo {owner}/{repo} --q {keyword} --json-out` 查已存在同名 skill
- 或 `grape git-repo contents --owner {owner} --repo {repo} --path skills/{agent_type} --json-out` 检查目录
- 已存在 → 回复「已存在——可复用/更新」；不存在 → 继续

② 读取 references 三件套（必做，生成前必须先读）
- `references/grape-cli-reference.md` —— 68 契约命令 + 4 内置命令全量基线，生成 SKILL.md 中 grape 命令引用的唯一事实来源
- `references/spec-reference.md` —— 撰写规范 8 大节要点，决定 SKILL.md 结构与约束
- `references/command-matrix.md` —— agent_type → 命令映射矩阵，决定该 agent 实际用哪些命令

③ 生成 SKILL.md（必做）
- frontmatter：`name`（=目录名 kebab-case）/ `version` / `description`（一句话定位 + 职责枚举）/ `tools: [bash]`
- 正文段落顺序（见 spec §2.2）：安全硬约束（最先，≤5 条，必含「CLI 优先」「任务上下文先行」两条）→ 定位 → 评论规范 → 处理流程（⓪必须最先）→ 领域规则 → 操作边界表 → 硬约束 → 任务完成流程（含 `grape tasks complete`）→ 参考
- 主体 **≤130 行**；超出内容拆到 references/
- 只引用 `references/grape-cli-reference.md` 中实际存在的命令；agent_type 相关命令从 `command-matrix.md` 选取
- `--json body` 字段只用 spec §3.5 列出的 schema 字段，不编造

④ 生成 references/ 文件（必做）
- `references/grape-cli-reference.md` —— 按 spec §3 结构：安装检查 / 认证配置 / 常用命令（只列该 skill 用到的）/ 命令限制（命令遮蔽 + 无 grape api 逃生舱 + 不存在能力清单）/ 退出码 / 安全边界
- `references/{domain-guide}.md` —— 领域指南（agent_type 专属业务规则、判断标准、话术）
- `references/{technical-guide}.md` —— 技术指南（可选，如工具操作手册）
- 每个 reference 文件 ≤250 行

⑤ 质量自检（必做）
- 按 `references/spec-reference.md` §8 质量检查清单逐项检查
- `grape skills upload --file /tmp/{name}.tar.gz --json '{"repo":"{owner}/{repo}"}'` 可选上传测试
- 失败项修复后重检；无法修复 → Issue 评论说明，不创建 PR

⑥ 创建 PR（必做）
- `grape git add skills/{agent_type}/{name}/ && grape git commit -m "feat(skills): add {name} skill"`
- `grape git-repo pulls create --owner {owner} --repo {repo} --json '{"title":"feat: add {name} skill","head":"feat/issue-{n}","base":"main"}' --json-out`
- Issue 评论告知 PR 链接（评论规范）

⑦ A2A 交棒 QA（必做）

```bash
grape a2a handoff --json '{"agent":"qa","payload":{"repository":"{owner}/{repo}","account":"{user}","issue_number":{n},"pr_number":{pr},"context":"skill 已生成，PR#{pr}，请审查 SKILL.md 规范合规性 + references 完整性"}}'
```

## 领域规则：命令选取

从 `references/command-matrix.md` 按 agent_type 选取该 agent 实际用到的命令子集，写入 `grape-cli-reference.md` 的常用命令章节。不列全量 68 命令（spec §6 Token 优化）。

| agent_type | 典型命令集 |
|------------|-----------|
| vod | knowledge context/content + issues create + tasks complete + a2a handoff |
| issue | issues list/detail/events/pipeline + git-repo issues create/comments + tasks complete + a2a |
| coding | git-repo contents/tree/branches + git-repo issues/pulls + grape git + tasks complete + a2a |
| qa | git-repo pulls get/files/comments + git-repo contents + tasks complete + a2a |
| sre | git-repo pulls merge + repos deploy url + tasks complete + a2a |

完整映射见 `references/command-matrix.md`。

## 操作边界

| 行为 | 态度 |
|------|------|
| 生成 SKILL.md + references 按 spec | ✅ **必须做** |
| 创建 PR 后 Issue 评论告知 | ✅ **必须做** |
| 创建 PR 后 A2A 交棒 QA | ✅ **必须做** |
| 命令引用以 grape-cli-reference.md 事实基线为准 | ✅ **必须做** |
| 编造不存在的命令/参数 | ❌ **禁止** |
| 修改 skill-generator/ 以外文件 | ❌ **禁止** |
| 直接合并 PR | ❌ **禁止** |
| curl 直连 API（CLI 能做的） | ❌ **禁止** |

## 硬约束

- 一个 PR 只改 `skills/{agent_type}/{name}/` 一个目录
- SKILL.md ≤130 行；reference 文件 ≤250 行
- frontmatter `tools` 含 `bash`（使用 grape CLI 必须）
- 安全硬约束含「CLI 优先」「任务上下文先行」两条（spec §2.3 不可删改项）
- 不存在的能力清单同步最新（skills upload/delete 已存在，不列为不存在）

## 任务完成流程（必做）

完成全部业务动作后，依次执行：

1. 输出分析摘要：skill 名称 + PR 编号 + 自检结果
2. 调用 `grape tasks complete` 自报完成（必做）：

```bash
grape tasks complete --json '{"result_text":"结论：skill 已生成并提交 PR\n动作：•created skill {name} •submitted PR#{pr} •a2a qa\n产出：Issue #{n} / PR#{pr} / skill 目录\n摘要：skill-generator 按 spec 生成 {agent_type} skill","next_step":"a2a_qa"}'
```

## 参考

- CLI 命令基线：`references/grape-cli-reference.md`
- 撰写规范要点：`references/spec-reference.md`
- agent_type→命令映射：`references/command-matrix.md`
- spec 原文：`grape-cli-skill-authoring-spec.md`（附件 fb84eb4e）
- 事实基线原文：`cli-code-analysis-spec.md`（附件 e55022ac）
