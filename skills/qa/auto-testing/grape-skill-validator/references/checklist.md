# 质量检查清单（展开版）

> 来源：`grape-skill-generator/references/spec-reference.md` §8 质量检查清单（对齐撰写规范最新版）
> 用途：skill-validator 逐项验证被检查 skill 是否合规。每项标注 ✅ 通过 / ❌ 不通过 + 原因。

---

## A. Frontmatter 检查（4 项）

### A1. tools 包含 bash/grape（如果使用 grape CLI）
- **检查**：frontmatter `tools:` 字段是否包含 `bash`（使用 grape CLI 时建议含 `grape`）
- **通过**：使用 grape CLI 的 skill 声明了 `bash`
- **失败**：使用 grape CLI 但未声明 `bash`，或声明了不用的工具

### A2. tools 不包含不用的工具
- **检查**：frontmatter `tools:` 字段是否包含不用的工具（如已上收的 codegraph）
- **通过**：只声明实际需要的工具
- **失败**：声明了不用的工具

### A3. frontmatter 完整性
- **检查**：name + version（semver x.y.z）+ description + tools 字段齐全
- **通过**：四字段齐全，version 为 semver 格式
- **失败**：缺字段或 version 格式错误

### A4. name 与目录名一致（kebab-case）
- **检查**：`name` 是否为 kebab-case（小写字母/数字/连字符）且 = 技能目录名，≤64 字符
- **通过**：一致且合规
- **失败**：不一致或含非法字符

---

## B. 安全硬约束检查（5 项）

### B1. 安全硬约束在最前面，≤5 条
- **检查**：安全硬约束段落是否在 frontmatter 之后正文最开始，条数 ≤5
- **通过**：位置正确且 ≤5 条
- **失败**：位置不对或超过 5 条

### B2. 包含「CLI 优先」条目
- **检查**：安全硬约束是否包含「禁止绕过 CLI 直连 API」条目
- **通过**：包含 CLI 优先条目（禁止 curl/python httpx/requests 等直连）
- **失败**：缺少 CLI 优先约束

### B3. 包含「任务上下文先行」条目
- **检查**：安全硬约束是否包含「执行前先读任务进展」条目
- **通过**：包含任务上下文先行条目
- **失败**：缺少任务上下文先行约束

### B4. 只用 $GRAPE_SESSION_TOKEN（token 作用域）
- **检查**：安全硬约束/认证说明是否只用 `$GRAPE_SESSION_TOKEN`，未引入旧版平台 token 名（`BOT_*`/`USER_*` 等已删除的注入变量）；`user_only` 端点（auth/skills）说明需 `grape_`/JWT
- **通过**：token 说明正确
- **失败**：引用了旧版平台 token 名（`BOT_*`/`USER_*` 类）

### B5. 正文不改写声明（如涉及 Issue body 修改）
- **检查**：涉及修改 Issue/P更新内容的 skill，是否声明「结论用 `issues comments create` 发布，`issues update` 不写 body（防覆盖原始描述）」
- **通过**：有声明
- **失败**：技能会写 Issue 内容但未声明/或示例用 `issues update --json '{"body":...}'` 覆盖 body

---

## C. Prerequisites 检查（3 项）

### C1. 含 `grape --version` 版本校验
- **检查**：Prerequisites 是否包含 `grape --version`（≥0.3.2）
- **通过**：包含版本校验 + 未装/过低时自行安装说明
- **失败**：缺少版本校验

### C2. 含 `grape refresh` 契约刷新
- **检查**：Prerequisites 是否包含 `grape refresh`（契约权威 = `grape commands` 实列）
- **通过**：包含 refresh
- **失败**：缺少

### C3. 含环境变量 ${VAR:+ok} 校验
- **检查**：Prerequisites 是否用 `${VAR:+ok}` 校验 `$GRAPE_SESSION_TOKEN`/`$REPO_OWNER`/`$REPO_NAME`/`$ISSUE_NUMBER` 等
- **通过**：包含 env 校验（不打印 token 值）
- **失败**：缺少 env 校验

---

## D. 环境变量表检查（2 项）

### D1. 含环境变量表
- **检查**：是否有「环境变量（服务端已注入）」表
- **通过**：有 env 表（含 `GRAPE_SERVER_URL`/`GRAPE_SESSION_TOKEN`/`REPO_OWNER`/`REPO_NAME`/`ISSUE_NUMBER` 等）
- **失败**：无 env 表

### D2. env 表含 BOT_USERNAME / GRAPE_SCENE_ID（按需）
- **检查**：env 表是否含 `BOT_USERNAME`（机器人身份）、`GRAPE_SCENE_ID`（A2A 场景核验）、`GRAPE_WORK_BRANCH`（目标合入分支）——按技能职责需要
- **通过**：需要的变量已列
- **失败**：技能用到但未列出

---

## E. 处理流程检查（3 项）

### E1. 处理流程 = runbook 引用
- **检查**：`## 处理流程` 是否引用 `references/{x}-runbook.md`（「先读 runbook，照抄执行，不逐条 --help」）+ 收尾情形势（`grape tasks complete`）
- **通过**：runbook 引用 + 收尾说明齐全
- **失败**：无 runbook 引用（全部内联）且无收尾说明

### E2. runbook Step 0 为任务上下文读取
- **检查**：runbook 第一步是否为 Step 0 读取任务上下文（`grape tasks current` + `grape issues detail` 等），标注（必须最先）
- **通过**：有 Step 0 且标注
- **失败**：缺少

### E3. runbook 有编号步骤 + 每步命令 + 必做标注 + 错误排查 + 明确禁止
- **检查**：runbook 是否有：编号步骤、每步确切命令、必做标注、错误排查速查表、明确禁止列表
- **通过**：五要素齐全
- **失败**：缺要素

---

## F. 任务完成流程检查（3 项）

### F1. 包含 grape tasks complete 调用
- **检查**：任务完成流程是否包含 `grape tasks complete` 调用
- **通过**：包含 `grape tasks complete --json '{...}'` 调用
- **失败**：缺少 complete 调用

### F2. 结构化字段完整（actions/conclusion/artifacts/issue_summary）
- **检查**：`grape tasks complete` 是否含 `actions[]`/`conclusion`/`artifacts[]`/`issue_summary` 结构化字段（不只 result_text）
- **通过**：结构化字段真实填充（空数组/空串=不合格）
- **失败**：只传 `result_text`（丢结构化归档）

### F3. next_step 合法
- **检查**：`next_step` 是否在 `a2a_{目标agent}` / `reply_comment` / `done` 合法值内
- **通过**：取值合法且与本轮动作一致
- **失败**：取值非法或与动作不符

---

## G. grape-cli-reference.md 检查（4 项）

### G1. 包含安装检查、认证配置、常用命令、限制声明、退出码
- **检查**：reference 是否包含固定章节
- **通过**：安装检查 + 认证配置 + 常用命令 + 限制声明（命令遮蔽/无 grape api 逃生舱/不存在能力）+ 退出码 + 安全边界
- **失败**：缺章节

### G2. 包含命令遮蔽和不存在能力的声明
- **检查**：reference 是否声明 `tasks status get` 命令遮蔽 + 不存在能力清单
- **通过**：声明命令遮蔽（用 tasks wait 替代）+ 不存在能力清单
- **失败**：缺少声明

### G3. 包含「无 grape api 逃生舱」声明
- **检查**：reference 是否声明 grape api 已移除，不可 curl 直连
- **通过**：包含声明
- **失败**：缺少声明

### G4. 不存在能力清单已同步最新
- **检查**：不存在能力清单是否将 skills upload/delete 误列为不存在
- **通过**：skills upload/delete 未列为不存在
- **失败**：将已存在能力误列为不存在

---

## H. 命令与参数规范检查（6 项）

### H1. 只列实际用到的命令，不列全量
- **检查**：reference 常用命令是否只列本 skill 实际用到的，不列全量
- **例外**：作为交叉验证基线列全量并明确声明用途——可接受
- **通过**：只列实际用到的命令，或作为交叉验证基线列全量并声明
- **失败**：无理由列全量且未声明

### H2. path 参数用下划线名
- **检查**：path 参数是否用下划线名（`--task_id` `--skill_id` `--per_page` 等）
- **通过**：path 参数用下划线名
- **失败**：path 参数用连字符名

### H3. wait 参数用连字符名
- **检查**：内置 wait 参数是否用连字符名（`--task-id`）
- **通过**：wait 参数用连字符名
- **失败**：wait 参数用下划线名

### H4. --json body 只用规范 §5 列出的字段
- **检查**：--json body 是否只用事实基线 schema 字段（PRCreateBody 用 `related_issue_nums`/`auto_close_issues`，非 `inner_issue_nums`/`close_related_issue`）
- **通过**：字段在 schema 清单内，旧字段未误用
- **失败**：编造 schema 中不存在的字段，或误用已废弃字段名

### H5. 查询命令带 --json-out
- **检查**：查询命令（list/get/detail 等）是否带 `--json-out`
- **通过**：查询命令带 --json-out
- **失败**：查询命令未带 --json-out

### H6. 流程节点与需求单一致（flow_nodes 需求追溯）
- **检查**：A2A payload / Spec「流程设计」声明了 `flow_nodes`（`pending-review`/`awaiting-input`/`tasks notify`）时，被检查 skill 的 runbook 是否落地了对应步骤
- **通过**：
  - `pending-review` → runbook 含「审批节点」：`issues pending-review` → 用户评论续接 `review-pass`/`review-reject`（含收尾 next_step）
  - `awaiting-input` → runbook 含「澄清节点」：发追问评论 + 收尾（next_step=reply_comment）或视需求使用 `issues awaiting-input` 状态接口（接口通用，大部分情况 vod/issue 阶段用，以用户需求为准）
  - `tasks notify` → 可用于任务分派/状态通知（通用接口，任何 agent 均可，按需求）；⚠️ 若被当作结果/部署/完成通知使用（body 应传结果内容而非 assignee/issue_number/repo_key/task_description 分派字段）则 ❌，结果通知应 `git-repo issues comments create`
  - `flow_nodes=无`/未声明 → 不要求（可无流程节点步骤）
- **失败**：声明了节点但 runbook 无对应步骤，或 `tasks notify` 误用于结果通知

---

## I. 交叉验证检查（3 项）

### I1. 命令一致性
- **检查**：skill 中出现的 grape 命令是否在事实基线中存在
- **通过**：所有命令在基线中存在
- **失败**：编造了不存在的命令

### I2. schema 字段一致性
- **检查**：skill 中 --json body 字段是否与事实基线 schema 一致
- **通过**：字段一致
- **失败**：字段不符

### I3. 不存在能力声明一致性
- **检查**：skill 中声明的不存在能力是否与事实基线一致
- **通过**：声明一致
- **失败**：将存在能力误列为不存在，或将不存在能力遗漏

---

## J. A2A / 建 PR 规范检查（3 项）

### J1. A2A 用 agent 名（非技能名）
- **检查**：`grape a2a handoff` 的 `agent` 字段是否是 agent 类型（`coding`/`qa`/`sre`/`vod`/`issue`），非技能名（如 `grape-skill-generator`）
- **通过**：用 agent 名；对应 agent 用哪个技能由该 agent 决定
- **失败**：用技能名作为 agent

### J2. 建 PR 的 base 用 $WORK_BRANCH
- **检查**：建 PR（`pulls create`）的 `base` 是否用 `$WORK_BRANCH`（环境变量配置值），非硬编码 `main`/`dev`
- **通过**：`base: "$WORK_BRANCH"`（或解析逻辑）
- **失败**：硬编码分支名

### J3. A2A 前场景节点核验
- **检查**：需 A2A 的 skill，是否在 runbook 中先 `grape scenes detail` 校验目标 agent 节点命中，未命中不 A2A
- **通过**：有场景核验步骤
- **失败**：无场景核验直接 A2A

---

## K. 其他检查（4 项）

### K1. 已上收能力声明
- **检查**：已上收能力（如项目知识基线由服务端维护）是否在 SKILL.md 和 reference 中都做了声明
- **通过**：两边都有声明
- **失败**：仅一处声明或缺失

### K2. SKILL.md ≤130 行
- **检查**：`wc -l SKILL.md` ≤ 130
- **通过**：≤130 行
- **失败**：>130 行

### K3. reference 文件 ≤250 行
- **检查**：`wc -l references/*.md` 每个 ≤ 250
- **通过**：每个 reference ≤250 行
- **失败**：>250 行

### K4. 占位符统一花括号格式
- **检查**：占位符是否统一用 `{owner}` `{repo}` `{n}` 花括号格式
- **通过**：统一花括号格式
- **失败**：用 `<owner>` 等其他格式

---

## 检查报告输出格式

```
# Skill 合规检查报告

**被检查 skill**：{skill_path}
**检查时间**：{timestamp}
**总体结论**：✅ 全部通过 / ❌ 发现 N 项不合规

## 检查明细

| # | 检查项 | 结果 | 说明 |
|---|--------|------|------|
| A1 | tools 包含 bash | ✅ | — |
| A2 | tools 不包含不用的工具 | ✅ | — |
| ... | ... | ... | ... |
| J1 | A2A 用 agent 名 | ❌ | agent 用了技能名 grape-skill-generator |
| J2 | PR base 用 $WORK_BRANCH | ❌ | 硬编码 base: main |
| K2 | SKILL.md ≤130 行 | ✅ | — |

## 不合规项详情

### J1: A2A 用 agent 名
- 位置：SKILL.md 第 XX 行
- 问题：`a2a handoff` 的 `agent` 字段用了技能名 `grape-skill-generator`，应为 agent 类型 `coding`
- 修正建议：改为 `agent: "coding"`（对应 agent 用哪个技能由其决定）

### J2: PR base 用 $WORK_BRANCH
- 位置：SKILL.md 第 XX 行
- 问题：`pulls create` 的 `base` 硬编码为 `main`
- 修正建议：改为 `base: "$WORK_BRANCH"`（环境变量配置值）
```