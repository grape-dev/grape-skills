---
name: common-skill-tester
description: >
  Use when the user asks to lint, test, run functional tests, audit, security-scan, or
  vulnerability-check a Skill directory. A unified tester integrating three toolkits in one:
  Linter (structure & spec compliance), Tester (runtime functional verification), and Auditor
  (security audit, malicious code, CWE vulnerabilities). Triggers: "检查 skill", "扫描 skill",
  "lint skill", "测试 skill", "功能测试", "运行测试", "功能验证", "安全审计", "安全测试",
  "漏洞检测", "恶意代码检测", "安全评分", "skill 规范", "skill-linter", "skill-tester",
  "skill-auditor", "common-skill-tester", "检查报告", "validate skill", "test skill",
  "audit skill", "check skill", "lint my skill", "帮我检查skill", "帮我测试skill",
  "帮我审计skill", "检测恶意代码".
---

# Common Skill Tester — 通用 Skill 三合一测试器

## 概述

本技能整合三个通用测试工具的全部功能点，对 Skill 目录进行**一站式**质量验证：

| 套件 | 对应原工具 | 职责 | 规范来源（在线动态拉取） |
|------|-----------|------|--------------------------|
| **Lint 规范检查** | skill-linter | 结构合规、安全基线、资源限制、提交隔离 | `common_skillslinter.json` |
| **Test 功能测试** | skill-tester | 运行时功能验证：正确性/性能/兼容/可靠/编排 | `common_functions.json` |
| **Audit 安全审计** | skill-auditor | 恶意代码、后门、注入、凭据窃取、CWE 漏洞 | `common_auditor.json` |

三套规范均**不写死**在技能中，每次执行从在线地址动态拉取最新版本。默认三合一执行（`mode=all`），也可单独执行某一套（`mode=lint|test|audit`），输出一份组合报告（综合判定 + 三份子报告），保留各套件的评分公式、P0/CRITICAL 门禁、CWE 映射等全部功能点。

## 输入参数（inputSchema）

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| skill_path | string | 是 | 目标 Skill 目录路径 |
| mode | string | 否 | 执行模式：`all`（默认，三合一）/ `lint` / `test` / `audit` |
| checks_url | string | 否 | 自定义 lint 检查点 JSON 地址（默认在线地址） |
| tests_url | string | 否 | 自定义 test 测试点 JSON 地址（默认在线地址） |
| rules_url | string | 否 | 自定义 audit 规则 JSON 地址（默认在线地址） |
| output_file | string | 否 | 报告输出文件路径（不指定则写入被测 Skill 父目录） |

合法输入：`skill_path` 为存在的目录路径；各 URL 为返回 JSON 的地址。
非法输入：`skill_path` 不存在或非目录 → 返回错误提示，不执行任何检查。

## 输出格式（outputSchema）

输出为 Markdown 格式的组合报告，结构遵循 `references/report-template.md`，包含以下固定部分：

1. 综合概览（时间、目标、模式、三份规范来源/版本、总体统计摘要）
2. 综合判定与评分（综合分、星级、判定结果、一票否决项统计）
3. Lint 检查结果（概览 + 评分 + 必改项 + 建议修改 + 通过项 + 跳过项 + 详细记录）
4. 功能测试结果（概览 + 通过率 + P0 详情 + 失败/警告分析 + 通过项 + 跳过项 + 详细记录 + 分组汇总）
5. 安全审计结果（概览 + 安全评分 + 严重/警告/提示发现 + CWE 检测结果 + 通过项 + 详细记录）

报告为纯 Markdown 文本，可被其他 Skill（如 huawei-cloud-skill-reporter）和 CI/CD 流水线解析引用。`mode` 为 `lint`/`test`/`audit` 单模式时，仅输出对应套件章节（保留原单工具报告结构）。

## 执行流程

```
第 1 步 拉取规范 → 第 2 步 收集信息 → 第 3 步 Lint → 第 4 步 Test → 第 5 步 Audit → 第 6 步 汇总报告
```

### 第 1 步：拉取三份规范

运行辅助脚本拉取在线规范 JSON：

```bash
node common-skill-tester/scripts/fetch_specs.js                              # 全部三份，输出合并 JSON
node common-skill-tester/scripts/fetch_specs.js --type lint                  # 只拉 lint 检查点
node common-skill-tester/scripts/fetch_specs.js --type test                  # 只拉功能测试点
node common-skill-tester/scripts/fetch_specs.js --type audit                 # 只拉安全审计规则
node common-skill-tester/scripts/fetch_specs.js "https://...json" --type lint  # 自定义 URL
node common-skill-tester/scripts/fetch_specs.js -o /tmp/specs.json           # 保存到文件供后续引用
```

拉取成功后解析 JSON，读取对应字段（详细结构见 `references/spec-sources.md`）。

**核心原则：以拉取到的实际 JSON 内容为准，不硬编码任何检查项/测试项/规则。** 在线新增分组或条目时自动纳入执行范围。

### 第 2 步：收集目标 Skill 信息（一次收集，三套复用）

对用户指定的 Skill 目录，收集以下信息：

1. **目录结构**：列出所有文件和子目录，记录路径、大小、扩展名（重点标记可执行代码文件 .sh/.py/.js/.ts/.go/.rs）
2. **SKILL.md 内容**：读取完整文本，提取 YAML Frontmatter（name/description/version），解析 Workflow、inputSchema/outputSchema、读写操作声明
3. **脚本文件内容**：读取所有 .sh/.py/.js/.ts 文件（可执行代码与依赖声明的安全审计素材）
4. **配置文件**：检查 .env 是否存在；读取 package.json/requirements.txt/pyproject.toml 等依赖声明
5. **危险模式预扫描**（一次 grep，三套复用）：凭据（AK/SK/密码/token）、内网 IP/域名、危险命令（sudo/rm -rf）、敏感路径（~/.ssh、~/.aws）、网络请求 URL、动态执行/系统命令调用函数
6. **文件统计**：总大小、文件数、SKILL.md 行数、文件类型列表
7. **跨引用与集成声明**：SKILL.md 中引用的其他具名 Skill、多 Skill 编排、数据传递机制

使用工具：`Glob`（列文件）、`Read`（读内容）、`Grep`（模式搜索）、`Bash`（统计/语法检查）。

### 第 3 步：Lint 规范检查（mode 含 lint 时执行）

对拉取到的**每一个检查项**（`groups[].items[]`）执行：

1. 按 `references/lint-methods.md` 的方法映射表逐项检查（结构/命名/frontmatter/.env/危险脚本/资源限制/凭证/删除操作确认等）
2. 判定每个检查项：pass / fail / warn / skip，全部基于**客观证据**（文件存在、grep 命中、统计数字）
3. 按公式计算 Lint 总分：`100 - (Critical×15 + High×8 + Medium×4 + Low×2 + warn×1)`
4. 记录 Critical fail 为必改项（附具体修改建议），非 Critical fail 和 warn 为建议修改项
5. 输出到报告的"三、Lint 检查结果"章节

### 第 4 步：功能测试（mode 含 test 时执行）

对拉取到的**每一条测试用例**（`test_groups[].items[]`）执行：

1. 按 `references/test-methods.md` 的方法映射表执行（触发词/工作流/Schema/读写语义/性能/兼容/可靠/编排等）
2. 以**静态分析**为主（验证 SKILL.md 是否声明了必要机制），可实际运行时结合运行结果
3. 判定：pass / fail / warn / skip，附带客观证据（引用章节/行号/内容）
4. 计算通过率：`pass / (总用例数 - skip) × 100%`；P0 必测项单独统计，任一 fail 标记"建议打回"
5. 输出到报告的"四、功能测试结果"章节

### 第 5 步：安全审计（mode 含 audit 时执行）

对拉取到的**每一条检测规则**（`groups[].items[]` + CWE 模式）执行：

1. 按 `references/audit-methods.md` 的方法映射表检测（网络请求/敏感文件/危险命令/注入/后门/混淆/依赖安全等）
2. 判定：pass / fail / warn / skip；fail 必须**关联 CWE 编号**并引用文件、行号、代码片段
3. 计算安全分：`100 - (CRITICAL×20 + WARNING×8 + INFO×2 + warn×1)`；CRITICAL fail 一票否决
4. 计算 CWE 覆盖率：`已检测 CWE 数 / 总 CWE 数 × 100%`
5. 输出到报告的"五、安全审计结果"章节

### 第 6 步：汇总报告与综合判定

按 `references/report-template.md` 生成组合报告：

1. 汇总三套统计，计算综合分：`round((Lint总分 + Test通过率 + Audit安全分) / 3)`
2. 按"评分与综合判定"章节规则给出判定结果（✅ 通过 / ⚠️ 有条件通过 / ❌ 不通过）
3. 将完整报告输出到两个地方：
   - **对话输出**：Markdown 直接输出给用户查看
   - **文件输出**：写入被测 Skill 的**父目录**下，文件名 `{skill-name}-tester-report-{YYYYMMDD-HHmmss}.md`
     - 从 `skill_path` 提取目录名作为 `{skill-name}`；示例：`skill_path=/repos/skills/dev/my-skill` → `/repos/skills/dev/my-skill-tester-report-20260916-120000.md`
     - 使用 `Write` 工具写入后，在对话中提示报告保存路径
4. 判定为 ❌ 时，对话中明确列出未达标项（fail 清单 + 未达 95 的套件 + 原因），并给出修复建议

## 评分与综合判定

### 三套评分公式

| 套件 | 公式 | 一票否决项 |
|------|------|-----------|
| Lint | `总分 = 100 - (Critical×15 + High×8 + Medium×4 + Low×2 + warn×1)` | Critical fail |
| Test | `通过率 = pass / (总用例 - skip) × 100%` | P0 必测项 fail |
| Audit | `安全分 = 100 - (CRITICAL×20 + WARNING×8 + INFO×2 + warn×1)` | CRITICAL 严重发现 |

### 星级标准（三套统一口径 + 综合分）

| 分数 | 星级 | 等级 |
|------|------|------|
| 90-100 | ⭐⭐⭐⭐⭐ | 优秀 |
| 75-89 | ⭐⭐⭐⭐ | 良好 |
| 60-74 | ⭐⭐⭐ | 合格 |
| 40-59 | ⭐⭐ | 需改进 |
| 0-39 | ⭐ | 不合格 |

### 综合判定

| 判定 | 条件 |
|------|------|
| ✅ 通过 | 三套评分均 ≥ 95，且无 lint Critical fail、无 test P0 fail、无 audit CRITICAL 发现 |
| ⚠️ 有条件通过 | 无上述三类 fail，但存在 warn 或任一评分在 75-94 之间（按报告修正后复测） |
| ❌ 不通过 | 存在任一上述 fail 类型，或任一评分 < 75 |

> 门禁语义：lint Critical / test P0 / audit CRITICAL 均为**一票否决**项。该判定规则与质量门槛要求一致（三套检查评分全 ≥ 95 才合格），可直接用于 CI/CD 门禁解析。

## 使用方式

用户可以这样说：

- "检查+测试+审计 .opencode/skills/my-skill 目录"（mode=all，默认）
- "用 common-skill-tester 测一下 /path/to/skill"
- "只检查规范：lint /path/to/skill"
- "只做功能测试：test /path/to/skill"
- "只做安全审计：audit /path/to/skill"
- "这个 skill 有没有问题？"（→ 默认三合一）

执行顺序固定：第 1 步 → 第 2 步 →（第 3/4/5 步按 mode）→ 第 6 步。`mode` 单模式时只执行对应套件，报告只含对应章节（保留原单工具结构）。

## 性能预算

| 指标 | 预估值（all 模式） | 说明 |
|------|--------|------|
| LLM 调用次数 | 30-90 次 | 三套并跑，取决于目标 Skill 文件数和条目数 |
| token 消耗 | 15000-45000 token | SKILL.md(~3k) + 拉取三份 JSON(~9k) + 目标文件内容(可变) + 执行推理 |
| 加载时延 | < 1s | 6 文件 / ~30KB |
| 执行时延 | 1-8min | 单模式约为 all 的 1/3 |

上下文压缩策略：拉取的规范 JSON 解析后仅保留各套件的 `items[]` 必要字段（`check`/`rule`/`severity`/`failure_handling`/`input`/`expected`/`priority`/`detection`/`cwe` 等），丢弃 `summary`/`legend` 等冗余字段。三套共享第 2 步收集的信息，避免重复读取目标文件。

## 版本管理

- 当前版本：v1.0（Frontmatter 无 version 字段，遵循 v1.0 规范）
- **规范版本兼容**：三份 JSON 结构可能各自变化，本 Skill 以实际拉取内容为准执行，新增/变更条目自动纳入；未知字段或新分组根据 `rule`/`input`/`detection` 描述自行判断，不影响既有逻辑
- **向后兼容**：`mode` 单模式输出结构兼容原 skill-linter / skill-tester / skill-auditor 的独立报告结构，原报告的解析方无需改动
- **灰度策略**：如在线规范发生重大变更，建议先手动拉取 JSON 审查（`fetch_specs.js -o` 保存）后再执行

## 可靠性声明

| 机制 | 声明 |
|------|------|
| 断点续跑（resume） | 拉取的规范 JSON 可通过 `-o` 保存到临时文件；执行中断后重新指定该文件作为对应 URL 参数（`checks_url`/`tests_url`/`rules_url` 指向本地文件路径时直接读取）恢复执行，无需重新拉取 |
| 重试幂等 | 重复执行同一目标 Skill 产生相同结果（规范动态拉取可能因在线更新导致结果略有差异）；输出报告覆盖写入指定文件，幂等无副作用 |
| 资源清理 | 执行过程不创建临时文件，仅读取目标目录和在线 JSON；使用 `-o` 保存的规范文件由用户决定是否清理 |
| 降级策略 | 每份规范独立降级：raw URL 失败(403) → 回退 gitcode API v5（base64 解码）→ 仍失败则仅该套件标记"未执行(原因)"，其余套件照常执行，并在报告中注明 |

## 依赖兼容

| 依赖 | 版本要求 | 说明 |
|------|----------|------|
| node | ≥ 12 | 运行 `scripts/fetch_specs.js`（仅用 http/https/fs 标准库） |
| 网络 | 需可访问 gitcode.com | 拉取规范 JSON；不可用时走本地文件指定（见可靠性声明） |
| bash | 可选 | 目标脚本的 `bash -n` 语法检查 |
| python | 可选 | 目标脚本的 `py_compile` 语法检查 |

如 `node` 不可用，由 agent 直接用 `curl`/网络工具拉取规范 JSON 后继续执行，不阻塞主流程。

## 跨 Skill 协作

- 输出报告为固定结构 Markdown，可被其他 Skill 消费：`huawei-cloud-skill-reporter` 可解析综合判定作为上报结论；CI/CD 可解析 `{OVERALL_SCORE}`、`{LINT_SCORE}`、`{TEST_PASS_RATE}`、`{AUDIT_SCORE}`、`{VERDICT}` 等占位符数值作为门禁判断
- 可引用其他 Skill 的报告作为上下文：如先由本 Skill 输出 lint/test/audit 三套结果，再交给人审或修复 Skill 使用
- 报告按章节标题解析（一~五章固定），各套件子报告保留原单工具结构，兼容旧解析方

## 可用脚本

- **`scripts/fetch_specs.js`** — 动态拉取三份规范 JSON（lint 检查点/test 测试点/audit 规则），raw URL 失败自动回退 gitcode API v5；支持 `--type` 单拉、自定义 URL、`-o` 保存、`--help`

## 参考文档

- **`references/spec-sources.md`** — 三份规范的在线地址、合并输出结构与各自预期 JSON 结构、最新规范概要。第 1 步拉取后核对结构时读取。
- **`references/lint-methods.md`** — Lint 检查方法映射表 + 判定逻辑 + 评分公式。第 3 步执行时读取。
- **`references/test-methods.md`** — 功能测试方法映射表 + 判定逻辑 + 通过率公式 + 证据要求。第 4 步执行时读取。
- **`references/audit-methods.md`** — 安全审计方法映射表 + 判定逻辑 + 安全评分 + CWE 映射要求。第 5 步执行时读取。
- **`references/report-template.md`** — 组合报告模板（综合判定 + 三套子报告）。第 6 步生成报告时读取。

## 边界情况

| 场景 | 处理 |
|------|------|
| skill_path 不存在或非目录 | 返回错误提示，不执行任何检查 |
| 网络不可用 | 某套规范拉取失败则该套标记"未执行(原因)"，其余照常；提示用户可指定本地 JSON 文件 |
| 用户只要某一种检查 | `mode` 参数指定 lint/test/audit，只执行对应套件 |
| mode 传非法值 | 回退到 `all`，并在报告中注明 |
| 目标 Skill 无脚本/可执行代码 | audit 中代码相关规则 skip；lint 的脚本检查项 skip 或 pass（注明原因） |
| 目标 Skill 无写操作 | test 中读写语义、幂等、资源清理等用例 skip（注明原因） |
| 在线规范新增未知条目 | 按 `rule`/`input`/`detection` 描述自行设计检查/测试/检测方法，不跳过 |
| 报告过长 | 按模板章节结构输出，详细记录表保留全部条目 |
| 三套评分均 ≥ 95 但存在 warn | 判定为 ⚠️ 有条件通过，报告列出 warn 项及修正建议 |
| CRITICAL/P0/CRITICAL fail 同时多处出现 | 判定 ❌ 不通过，全部列出；修复后建议重跑全量 |

## 注意事项

- **规范动态加载**：每次执行都必须从在线地址拉取最新规范，不使用缓存或硬编码条目
- **以实际 JSON 为准**：三份 JSON 的结构、字段、条目变化时，以拉取到的实际内容为准执行
- **不跳过未知项**：在线新增的、本 SKILL.md 未描述的条目，根据其字段描述自行判断执行方法
- **客观判定**：每项 pass/fail 必须基于客观证据（文件内容、grep 命中、行列号、统计数字），不主观臆断
- **证据与 CWE**：test 每条结果附证据；audit 每条 fail 必须关联 CWE 编号
- **门禁语义**：lint Critical / test P0 / audit CRITICAL 一票否决；三套评分全 ≥ 95 才判定通过
- **报告语言**：报告使用中文输出