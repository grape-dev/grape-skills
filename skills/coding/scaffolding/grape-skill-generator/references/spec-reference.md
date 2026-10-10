# grape-cli Skill 撰写规范要点摘要

> 核心优先级：减少 token 消耗 > 约束 Agent 行为 > 降低幻觉
> 执行原则：CLI 优先 · 任务上下文先行

---

## §1 文件结构

> ⚠️ 生成的 skill 放在**项目根目录 `.grape/skills/{agent_type}/{skill_name}/`** 下；项目根若无该目录，先创建。

```
.grape/skills/{agent_type}/{skill_name}/
├── SKILL.md                          # 主文件（流程 + 约束 + 边界），≤130 行
└── references/                       # 参考文件（按需拆分），每个 ≤250 行
    ├── grape-cli-reference.md         # CLI 命令参考（通用模板）
    ├── {domain-guide}.md              # 领域指南（skill 专属业务逻辑）
    └── {technical-guide}.md           # 技术指南（可选）
```

### 拆分原则

| 内容 | 放 SKILL.md | 放 references/ |
|------|-------------|----------------|
| Agent 定位与职责 | ✅ | |
| 处理流程（步骤） | ✅ | |
| 安全硬约束 | ✅ | |
| 操作边界（能做/不能做表） | ✅ | |
| 任务完成流程 | ✅ | |
| grape CLI 命令清单与示例 | | ✅ grape-cli-reference.md |
| 领域规则（模板、判断标准、话术） | | ✅ {domain-guide}.md |
| 工具操作手册 | | ✅ {technical-guide}.md |

---

## §2 SKILL.md 结构

### §2.1 Frontmatter

```yaml
---
name: {skill_name}        # = 目录名，kebab-case
version: {semver}         # 如 1.0.0
description: |
  一句话定位 + 职责枚举。
  双职责用 ①② 编号。不超过 3 行。
tools:
  - bash                  # 使用 grape CLI 必须声明 bash
---
```

- `tools` 只声明实际需要的工具；不用的不声明
- `description` 第一句是定位，后续枚举职责

### §2.2 正文段落顺序（固定，参照现有 CLI 技能实践）

> 以 grape-skills 库中 vod-cli / issue-cli / coding-cli / qa-cli / deploy-cli / chat-cli 的 SKILL.md 段落结构为基准。生成新 skill 时按下列顺序组织正文：

```
# {技能标题}                                ← 一级标题（可选，多数技能在最前）
## 安全硬约束（必须遵守）                   ← 最先，约束行为底线
## Prerequisites（执行前必检…）              ← 版本 / 契约刷新 / 环境变量校验
## 环境变量（服务端已注入，直接使用）          ← env 表（REPO_OWNER/REPO_NAME/ISSUE_NUMBER/BOT_USERNAME…）
## 定位                                     ← Agent 职责边界 + 下游交办
## {核心原则 / 评论前缀规范}（按需）           ← 如评论前缀、项目知识基线、验证 claim 等
## 处理流程                                 ← runbook 引用 + 场景/入口判定
## {领域规则 / 输出规范}（按需）              ← 如判断标准、报告格式
## 操作边界                                 ← 能做/不能做表
## 硬约束                                   ← 流程级硬性规则
## 参考                                     ← references 索引（含「执行走查表（先读）」）
```

**要点（对齐现有技能）**：
- **Prerequisites 必含**：`grape --version`（≥最低版本）→ `grape refresh`（刷新契约，⚠️ 契约权威 = `grape commands` 实列）→ env `${VAR:+ok}` 校验 → 未通过输出「前置检查未通过」并结束。
- **环境变量表必含**：`GRAPE_SERVER_URL` / `GRAPE_SESSION_TOKEN` / `REPO_OWNER` / `REPO_NAME` / `REPO_FULL_NAME` / `ACCOUNT`(actor，仅 A2A) / `ISSUE_NUMBER` / `GRAPE_SCENE_ID` / `BOT_USERNAME` 等，附敏感信息提示。
- **处理流程 = runbook 引用**：正文写「⚠️ 先读 `references/{x}-runbook.md`，按走查表逐步执行，**照抄执行，不要 `grape --help` / `grape commands` 逐条探索**」+「本技能收尾一律用 `grape tasks complete`（情形一）」；详细步骤放 runbook。
- **正文不改写**（如涉及修改 Issue）：结论/收敛一律 `issues comments create` 发布，`issues update` 不写 body（防覆盖原始描述）。
- **A2A 交办 agent 名**（`coding`/`qa`/`sre`/`vod`/`issue`），非技能名。

### §2.3 安全硬约束（必须最先，≤5 条）

- 编号 + **粗体关键词** + 说明
- 约束的是 Agent 行为，不是描述事实
- **第 2、3 条为所有 skill 必须包含的约束项，不可删改**：
  - 「CLI 优先」：凡 grape CLI 能做的走 CLI，禁止绕过直连 API
  - 「任务上下文先行」：执行前先读任务进展
- **建议附加（对齐现有技能，按需）**：
  - token 作用域：只用 `$GRAPE_SESSION_TOKEN`（`tk_`）；`user_only` 端点（auth/skills）对 `tk_` 返回 403 需 `grape_`/JWT
  - 403/401 处理：403 → 停止并回复「需管理员/维护者权限」；401 → 说明凭据已失效，不换 token
  - token 不写文件/日志/评论
  - 正文不改写：涉及 Issue body 修改时，结论用 `issues comments create` 发布，`issues update` 不写 body

### §2.4 处理流程

- **正文 = runbook 引用**：`## 处理流程` 段落写「⚠️ 先读 `references/{x}-runbook.md`，按走查表逐步执行（Step 概览……），**照抄执行，不要 `grape --help` / `grape commands` 逐条探索**」+「⚠️ 本技能收尾一律用 `grape tasks complete`（情形一）」。
- 详细走查放 `references/{x}-runbook.md`：编号步骤（Step 0/1/2…）+ 每步标题 + 确切命令（`grape <命令> --param {占位符}`）+ 必做标注 + 错误排查速查 + 明确禁止。
- 复杂分支（如按评级/类型路由）在 runbook 中用分支表；正文仅给入口/判定概览。
- 步骤末尾标注是否必做：`（必须最先）` / `（必做）` / `（可选）`。
- **runbook Step 0（必须最先，所有 skill 必须包含）**：读取任务上下文 + Prerequisites 通过后再读 runbook。

### §2.5 操作边界表

固定两列格式：

| 行为 | 态度 |
|------|------|
| {必须做的} | ✅ **必须做** |
| {可以做的} | ✅ **可以做** |
| {禁止的} | ❌ **禁止** |

### §2.6 任务完成流程（所有 skill 必须包含）

```markdown
## 任务完成流程（必做）

完成全部业务动作后，依次执行：

1. **输出人类可读的分析摘要**：{分析对象}分析数量、发现的问题、已完成动作
2. **调用 `grape tasks complete` 自报完成（必做）**：
```

> ⚠️ **结构化字段必填**：`actions[]` / `conclusion` / `artifacts[]` / `issue_summary` 服务端据此组装结构化 `_sd` 写入 archive——**只传 `result_text` 会丢结构化归档**（空数组/空串也会导致结构化框为空）。`result_text` 可选但仍建议给一句结论。

```bash
grape tasks complete --json '{
  "result_text": "结论：Issue #{ISSUE_NUMBER} {处理结论}。\n\n动作：\n• {动作 1}\n• {动作 2}\n\n产出：\n- {产出 1（含可追溯 id，如 comment id / A2A seq / PR #N）}\n\n摘要：一句话概括本次处理结果。",
  "next_step": "a2a_qa",
  "actions": ["{动作 1}"，"{动作 2}"],
  "conclusion": "完成情况总结：{结论}，{待办/后续}",
  "artifacts": ["{产出 1：PR #N / 评论 id / A2A event seq}"],
  "issue_summary": "已{动词} | {摘要要点} | 后续 {下一步}"
}'
```

- **`result_text` 组织**：按「结论 / 动作 / 产出 / 摘要」；动作逐条 `•`；产出带可追溯标识（Issue #N / comment id / A2A `seq` / PR #N / commit sha）。
- **`next_step` 合法值**：`a2a_{目标agent}` / `reply_comment` / `done`。
- 传入结构化字段后，**无需再在答复末尾单独输出 JSON 块**。
- 即便本轮无后续动作、或仅评论回复，也必须调用一次；若返回 `already:true`（任务已终态），属正常，忽略即可。

---

## §3 grape-cli-reference.md 规范

每个使用 grape CLI 的 skill 必须包含此文件。章节：

1. **安装与就绪检查** — 通常预装；未装/版本过低可自行安装（`pip install git+https://gitcode.com/grape-dev/grape-cli.git`），不 curl 直连
2. **认证与配置** — `$GRAPE_SESSION_TOKEN` 自动注入，不需手动 export
3. **常用命令** — **只列本 skill 实际用到的命令**，不列全量 68 个
4. **命令限制与不存在的能力** — 命令遮蔽 + 无 grape api 逃生舱 + 不存在能力清单
5. **退出码** — 0 成功 · 1 通用错误 · 2 用法错误 · ≥400 HTTP 透传 · 130 Ctrl+C
6. **安全与边界** — token 使用范围 + 禁止访问的内部数据路径 + 403/401 处理

### 必须包含的限制声明

- **命令遮蔽**：`tasks status get` 不可执行，用 `tasks wait`
- **无 grape api 逃生舱**：v0.2.2 移除，契约未覆盖端点无法 CLI 调用
- **不存在能力清单**：仓库创建/删除、任务删除、知识上传、Issue/PR 删除、分支创建/删除、Token 管理、tasks create（已移除）、流式输出、交互式提示

---

## §4 命令使用规范

### 命令选择优先级

| 场景 | 用什么 |
|------|--------|
| 有专属契约命令 | 契约命令 |
| 等待异步任务 | `grape tasks wait` |
| 本地 git 操作 | `grape git` |
| 契约未覆盖 | **无 CLI 逃生舱**，输出理由 |

### 参数规则

- path 参数：必填，下划线名（`--task_id` `--skill_id` `--per_page`）
- wait 参数：连字符名（`--task-id`）
- query 参数：可选，空值自动丢弃
- requestBody：`--json '<JSON>'`
- 机器可读输出：`--json-out`
- path 参数类型：`--number`/`--task_id`/`--seq`/`--skill_id` 是 integer

### 命令验证

```bash
grape commands | grep <关键词>    # 验证命令是否存在
grape <group> <verb> --help       # 查参数列表
```

### --json body 字段约束

只用 spec §3.5（本摘要 §5）列出的 schema 字段，不编造。

---

## §5 requestBody Schema 清单

| Body schema | 使用命令 | 必填 | 可选 |
|-------------|---------|------|------|
| `IssueCreateBody` | `git-repo issues create` | `title` | `body`, `assignee` |
| `IssueUpdateBody` | `git-repo issues update` | — | `labels`, `assignee`, `milestone_id`, `state` |
| `CommentBody` | `issues comments create` + `pulls comments create` | `body` | — |
| `LabelCreateBody` | `git-repo labels create` | `name` | `color` |
| `PRCreateBody` | `git-repo pulls create` | — | `title`, `head`, `base`, `related_issue_nums`, `auto_close_issues` |
| `PRUpdateBody` | `git-repo pulls update` | — | `title`, `body`, `labels` |
| `A2AHandoffBody` | `a2a handoff` | — | `agent`, `payload` |
| `TaskStatusBody` | `tasks status` | — | `status` |
| `TaskSelfCompleteBody` | `tasks complete` | — | `task_id`, `result_text`, `next_step`, `conclusion`, `issue_summary` |
| Free-form JSON | `issues create` | — | 任意字段（title/description/assignee/scene_id/is_subtask_mode） |

---

## §6 Token 优化规则

| 规则 | 做法 |
|------|------|
| SKILL.md 长度 | ≤130 行，超出拆到 references |
| reference 文件长度 | ≤250 行 |
| 命令示例 | 只列本 skill 用到的，不列全量 |
| 查询输出 | 加 `--json-out` |
| 默认参数 | 有默认值的省略不写 |
| 命令发现 | 不在 SKILL.md 列全量命令树，用 `grape commands` 按需发现 |
| 重复内容 | grape-cli-reference.md 多 skill 可共用 |

---

## §7 职责上收声明

如果某项能力已上收为服务端统一处理，SKILL.md 必须声明：

```markdown
- ⚠️ **不再自行生成**：{能力}由服务端统一维护；Agent 只需读取 prompt 注入的{章节}
```

references 对应文件开头标注「职责上收：本指南作为服务端实现手册保留，Agent 不再执行」。

---

## §8 质量检查清单

skill 编写完成后，逐项检查：

- [ ] frontmatter 的 tools 包含 bash（如果使用 grape CLI）
- [ ] frontmatter 的 tools 不包含不用的工具
- [ ] 安全硬约束在最前面，≤5 条
- [ ] 安全硬约束包含「CLI 优先」条目（禁止绕过 CLI 直连 API）
- [ ] 安全硬约束包含「任务上下文先行」条目（执行前先读任务进展）
- [ ] 正文含 **Prerequisites**：`grape --version` / `grape refresh` / env `${VAR:+ok}` 校验
- [ ] 正文含 **环境变量表**：`REPO_OWNER`/`REPO_NAME`/`ISSUE_NUMBER`/`BOT_USERNAME`/`GRAPE_SCENE_ID` 等（按需）
- [ ] **处理流程 = runbook 引用**：正文「先读 `references/{x}-runbook.md`，照抄执行」+ 收尾情形势
- [ ] runbook Step 0 为任务上下文读取，标注（必须最先）
- [ ] runbook 有编号步骤 + 每步命令 + 必做标注 + 错误排查 + 明确禁止
- [ ] 操作边界表区分能做/不能做
- [ ] 任务完成流程包含 grape tasks complete 调用
- [ ] result_text 按「结论/动作/产出/摘要」格式，结构化字段（actions/conclusion/artifacts/issue_summary）真实填充
- [ ] A2A 交办用 **agent 名**（coding/qa/sre/vod/issue），非技能名
- [ ] 建 PR 的 base 用 `$WORK_BRANCH`（不硬编码 main/dev）
- [ ] grape-cli-reference.md 包含安装检查、认证配置、常用命令、限制声明、退出码
- [ ] grape-cli-reference.md 包含命令遮蔽和不存在能力的声明
- [ ] grape-cli-reference.md 包含「无 grape api 逃生舱」声明
- [ ] 不存在的能力清单已同步最新（skills upload/delete 已存在，不再列为不存在）
- [ ] 只列本 skill 实际用到的命令，不列全量
- [ ] path 参数用下划线名，wait 参数用连字符名
- [ ] --json body 只用规范 §3.5 列出的字段
- [ ] 查询命令带 --json-out
- [ ] 涉及 Issue body 修改时：用 `issues comments create` 发布，`issues update` 不写 body（回填原始 body）
- [ ] 已上收的能力在 SKILL.md 和 reference 中都做了声明
- [ ] SKILL.md ≤130 行
- [ ] reference 文件 ≤250 行
- [ ] 占位符统一用花括号 `{owner}` 格式
