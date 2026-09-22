# grape-cli Skill 撰写规范要点摘要

> 来源：grape-cli-skill-authoring-spec.md（附件 fb84eb4e）
> 基于 cli-code-analysis-spec.md 事实基线（CLI v0.2.8，58 paths / 68 operations）
> 核心优先级：减少 token 消耗 > 约束 Agent 行为 > 降低幻觉
> 执行原则：CLI 优先 · 任务上下文先行

---

## §1 文件结构

```
skills/{agent_type}/{skill_name}/
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

### §2.2 正文段落顺序（固定）

```
## 安全硬约束（必须遵守）       ← 最先，约束行为底线
# {技能标题}                    ← 一级标题
## 定位                         ← Agent 职责边界
## {业务前缀}规范               ← 如评论前缀、输出格式
## 处理流程                     ← 核心步骤（①②③，⓪为任务上下文读取）
## {领域规则}                   ← 如判断标准
## 操作边界                     ← 能做/不能做表
## 硬约束                       ← 流程级硬性规则
## 参考                         ← references 文件索引
```

### §2.3 安全硬约束（必须最先，≤5 条）

- 编号 + **粗体关键词** + 说明
- 约束的是 Agent 行为，不是描述事实
- **第 2、3 条为所有 skill 必须包含的约束项，不可删改**：
  - 「CLI 优先」：凡 grape CLI 能做的走 CLI，禁止绕过直连 API
  - 「任务上下文先行」：执行前先读任务进展

### §2.4 处理流程

- 用编号步骤（①②③）而非 markdown 列表
- 每个步骤：标题一行 + `-` 列表动作 + grape 命令内联示例 `grape <命令> --param {占位符}`
- 引用 reference：`见 references/{file}.md §{章节}`
- 步骤末尾标注是否必做：`（必须最先）` / `（必做）` / `（可选）`
- **步骤⓪（必须最先，所有 skill 必须包含）**：读取任务上下文

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

1. **输出人类可读的分析摘要**
2. **调用 `grape tasks complete` 自报完成（必做）**：

   grape tasks complete --json '{
     "result_text": "{按格式组织的结论}",
     "next_step": "{下一步标识}"
   }'
```

**result_text 格式**：按「结论 / 动作 / 产出 / 摘要」组织；动作逐条用 `•`；产出带可追溯标识
**next_step 合法值**：`a2a_{目标agent}` / `reply_comment` / `done`

---

## §3 grape-cli-reference.md 规范

每个使用 grape CLI 的 skill 必须包含此文件。章节：

1. **安装与就绪检查** — grape 预装，`which grape` 无结果直接报障，不自行安装
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
| `PRCreateBody` | `git-repo pulls create` | — | `title`, `head`, `base`, `inner_issue_nums`, `close_related_issue` |
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
- [ ] 处理流程步骤⓪为任务上下文读取，标注（必须最先）
- [ ] 处理流程有编号步骤，每步标注是否必做
- [ ] 操作边界表区分能做/不能做
- [ ] 任务完成流程包含 grape tasks complete 调用
- [ ] result_text 按「结论/动作/产出/摘要」格式
- [ ] grape-cli-reference.md 包含安装检查、认证配置、常用命令、限制声明、退出码
- [ ] grape-cli-reference.md 包含命令遮蔽和不存在能力的声明
- [ ] grape-cli-reference.md 包含「无 grape api 逃生舱」声明
- [ ] 不存在的能力清单已同步最新（skills upload/delete 已存在，不再列为不存在）
- [ ] 只列本 skill 实际用到的命令，不列全量
- [ ] path 参数用下划线名，wait 参数用连字符名
- [ ] --json body 只用规范 §3.5 列出的字段
- [ ] 查询命令带 --json-out
- [ ] 已上收的能力在 SKILL.md 和 reference 中都做了声明
- [ ] SKILL.md ≤130 行
- [ ] reference 文件 ≤250 行
- [ ] 占位符统一用花括号 `{owner}` 格式
