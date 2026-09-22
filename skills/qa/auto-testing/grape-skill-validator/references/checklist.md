# 质量检查清单（展开版）

> 来源：grape-cli-skill-authoring-spec.md §8 质量检查清单（20 项）
> 用途：skill-validator 逐项验证被检查 skill 是否合规。每项标注 ✅ 通过 / ❌ 不通过 + 原因。

---

## A. Frontmatter 检查（3 项）

### A1. tools 包含 bash（如果使用 grape CLI）
- **检查**：frontmatter `tools:` 字段是否包含 `bash`
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

---

## B. 安全硬约束检查（3 项）

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

---

## C. 处理流程检查（3 项）

### C1. 步骤⓪为任务上下文读取，标注（必须最先）
- **检查**：处理流程第一步是否为 ⓪ 读取任务上下文，标注「必须最先」
- **通过**：步骤⓪存在且标注（必须最先），包含 grape tasks mine / issues detail 等命令
- **失败**：缺少步骤⓪或未标注

### C2. 有编号步骤，每步标注是否必做
- **检查**：处理流程是否用 ①②③ 编号，每步标注（必做）/（可选）
- **通过**：编号步骤 + 每步标注必做/可选
- **失败**：无编号或未标注必做/可选

### C3. 操作边界表
- **检查**：是否有操作边界表，区分能做/不能做
- **通过**：两列格式（行为 | 态度），区分 ✅必须做/可以做 / ❌禁止
- **失败**：缺少操作边界表

---

## D. 任务完成流程检查（2 项）

### D1. 包含 grape tasks complete 调用
- **检查**：任务完成流程是否包含 `grape tasks complete` 调用
- **通过**：包含 `grape tasks complete --json '{...}'` 调用
- **失败**：缺少 complete 调用

### D2. result_text 按「结论/动作/产出/摘要」格式
- **检查**：result_text 是否按结论/动作/产出/摘要格式组织
- **通过**：result_text 包含结论、动作（• 逐条）、产出（可追溯标识）、摘要
- **失败**：格式不符

---

## E. grape-cli-reference.md 检查（4 项）

### E1. 包含安装检查、认证配置、常用命令、限制声明、退出码
- **检查**：reference 是否包含 5 个固定章节
- **通过**：安装检查（§2）+ 认证配置（§8）+ 常用命令（§3+§4）+ 限制声明（§7）+ 退出码（§8） 齐全
- **失败**：缺章节

### E2. 包含命令遮蔽和不存在能力的声明
- **检查**：reference 是否声明 `tasks status get` 命令遮蔽 + 不存在能力清单
- **通过**：声明命令遮蔽（用 tasks wait 替代）+ 不存在能力清单
- **失败**：缺少声明

### E3. 包含「无 grape api 逃生舱」声明
- **检查**：reference 是否声明 v0.2.2 移除 grape api，不可 curl 直连
- **通过**：包含声明
- **失败**：缺少声明

### E4. 不存在能力清单已同步最新
- **检查**：不存在能力清单是否将 skills upload/delete 误列为不存在
- **通过**：skills upload/delete 未列为不存在（v0.2.6 已存在）
- **失败**：将已存在能力误列为不存在

---

## F. 命令与参数规范检查（5 项）

### F1. 只列实际用到的命令，不列全量
- **检查**：reference 常用命令是否只列本 skill 实际用到的，不列全量 68 个
- **例外**：本 skill 的 grape-cli-reference.md 作为交叉验证基线，§4 需列全量 68 命令供核对——此为设计必要，非违规
- **通过**：只列实际用到的命令，或作为交叉验证基线列全量并明确声明
- **失败**：无理由列了全量命令且未声明用途

### F2. path 参数用下划线名
- **检查**：path 参数是否用下划线名（`--task_id` `--skill_id` `--per_page` 等）
- **通过**：path 参数用下划线名
- **失败**：path 参数用连字符名

### F3. wait 参数用连字符名
- **检查**：内置 wait 参数是否用连字符名（`--task-id`）
- **通过**：wait 参数用连字符名
- **失败**：wait 参数用下划线名

### F4. --json body 只用规范 §3.5 列出的字段
- **检查**：--json body 是否只用事实基线 §3.5 列出的 schema 字段
- **交叉验证**：对照 `references/grape-cli-reference.md §6 requestBody Schema 清单`
- **通过**：字段在 schema 清单内
- **失败**：编造了 schema 中不存在的字段（如 IssueCreateBody 加 priority/labels）

### F5. 查询命令带 --json-out
- **检查**：查询命令（list/get/detail 等）是否带 `--json-out`
- **通过**：查询命令带 --json-out
- **失败**：查询命令未带 --json-out

---

## G. 交叉验证检查（3 项）

### G1. 命令一致性
- **检查**：skill 中出现的 grape 命令是否在事实基线中存在
- **交叉验证**：对照 `references/grape-cli-reference.md §4 契约命令清单`
- **通过**：所有命令在基线中存在
- **失败**：编造了不存在的命令（如 `grape repos create`）

### G2. schema 字段一致性
- **检查**：skill 中 --json body 字段是否与事实基线 §3.5 一致
- **交叉验证**：对照 `references/grape-cli-reference.md §6 requestBody Schema 清单`
- **通过**：字段一致
- **失败**：字段不符

### G3. 不存在能力声明一致性
- **检查**：skill 中声明的不存在能力是否与事实基线 §7.3 一致
- **交叉验证**：对照 `references/grape-cli-reference.md §7 不存在的能力`
- **通过**：声明一致
- **失败**：将存在能力误列为不存在，或将不存在能力遗漏

---

## H. 其他检查（3 项）

### H1. 已上收能力声明
- **检查**：已上收能力是否在 SKILL.md 和 reference 中都做了声明
- **通过**：两边都有声明
- **失败**：仅一处声明或缺失

### H2. SKILL.md ≤130 行
- **检查**：`wc -l SKILL.md` ≤ 130
- **通过**：≤130 行
- **失败**：>130 行

### H3. reference 文件 ≤250 行
- **检查**：`wc -l references/*.md` 每个 ≤ 250
- **通过**：每个 reference ≤250 行
- **失败**：>250 行

### H4. 占位符统一花括号格式
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
| G1 | 命令一致性（交叉验证） | ✅ | 所有命令在基线中存在 |
| G2 | schema 字段一致性 | ❌ | IssueCreateBody 编造了 priority 字段 |
| G3 | 不存在能力声明一致性 | ✅ | — |

## 不合规项详情

### G2: schema 字段一致性
- 位置：SKILL.md 第 XX 行
- 问题：IssueCreateBody 使用了 `priority` 字段，但事实基线 §3.5 中 IssueCreateBody 只有 `title`（必填）和 `body`/`assignee`（可选）
- 修正建议：删除 `priority` 字段
```
