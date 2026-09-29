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
version: 2.1.0
---

# Common Skill Tester

> 本技能遵循统一技能框架 v2.1.0（与 common-skill-creator 同构）。

## 一、安全硬约束（必须遵守）

1. **本地测试器定位**：本技能对用户指定的 Skill 目录做**只读检查**——Lint 规范检查、Test 功能测试、Audit 安全审计三合一。不修改被测 Skill 的任何文件；**唯一写操作**是 4.7 的输出报告文件。不调用 grape 平台管理命令（issues/pulls/a2a/refresh 等均不适用）；唯一平台接口是 4.8 任务收尾的 `tasks complete`。
2. **动态规范拉取**：三份规范 JSON（lint `common_skillslinter.json` / test `common_functions.json` / audit `common_auditor.json`）**不硬编码、不凭记忆、不用缓存**——每次执行从在线地址拉取最新版（`scripts/fetch_specs.js`，raw → gitcode API v5 自动回退）；拉取失败按 4.5 降级（该套件标记「未执行(原因)」+ 本地文件指定恢复），**不得**用旧快照/记忆假装执行。
3. **外部域界**：fetch_specs.js 访问的在线规范源（gitcode.com 生态规范文件仓库）属**外部规范源域**——脚本内 https 请求合法；此域与 grape 平台管理 API 严格区分（平台管理一律走 CLI 纪律，此处无 CLI 通道也不制造）。
4. **客观证据判定**：每项 pass/fail/warn/skip 必须基于**客观证据**（文件存在、grep 命中、行列号、统计数字）——不主观臆断；audit 每条 fail 必须关联 CWE 编号并引用文件/行号/代码片段。
5. **不写死凭据**：检查/扫描中不向被测文件写入任何内容；被测 skill 的凭据（`{PREFIX}_*`）只读不写；本技能自身不硬编码任何 AK/SK/密码/token。
6. **不跳过未知项**：在线规范新增/未知条目按其 `rule`/`input`/`detection` 描述自行设计检查方法执行——**绝不跳过**；网络不可用时才允许标记「未执行(原因)」。

## 二、环境变量表

| 变量 | 来源 | 说明 |
|------|------|------|
| `GRAPE_SESSION_TOKEN` | 平台注入 | 会话令牌——**仅 4.8 任务收尾的 `tasks complete` 使用**（CLI 自动读取，不手动传入）|
| `NODE`（可选）| 环境探测 | node 可执行文件路径——预检时探测；缺失时按三、前置检查门自愈（或 Agent 直接 curl 拉规范）|
| `{PREFIX}_*`（可选）| 被测 skill 上下文 | 被测 skill 的目标系统凭据——**只读**（若被测 skill 需要运行时验证且其文档声明该读取方式）|

## 三、前置检查门（自愈 → 重试 → STOP）

1. **node ≥ 12**（运行 `scripts/fetch_specs.js` 拉取三份规范）：`node --version` 检查——缺失 → 尝试安装 → 重试 → 仍失败则 **Agent 直接用 curl/网络工具拉取规范 JSON** 继续（不阻塞主流程）。
2. **目标 Skill 目录存在**：`<skill_path>` 是存在的目录——不存在/非目录 → 返回错误提示，**不执行任何检查**。
3. **可选依赖**：bash（目标脚本 `bash -n` 语法检查）/ python（目标脚本 `py_compile` 检查）——缺失则该类检查项标记 skip 并注明原因，不阻塞。
4. 任一前置门失败 → 输出「前置检查未通过：<原因>」并结束任务，不无限重试。

## 四、技能定义与执行

### 4.1 定位与职责边界

- **做什么**：对 Skill 目录做一站式质量验证，整合三个套件：
  | 套件 | 对应原工具 | 职责 | 规范来源（在线动态拉取）|
  |------|-----------|------|------------------------|
  | **Lint 规范检查** | skill-linter | 结构合规、安全基线、资源限制、提交隔离 | `common_skillslinter.json` |
  | **Test 功能测试** | skill-tester | 运行时功能验证：正确性/性能/兼容/可靠/编排 | `common_functions.json` |
  | **Audit 安全审计** | skill-auditor | 恶意代码、后门、注入、凭据窃取、CWE 漏洞 | `common_auditor.json` |
- **不做什么**：
  - 不修改/修复被测 Skill（检测出问题只报告，修复交还用户/creator）。
  - 不生成 skill（那是 `common-skill-creator` 的职责）。
  - 不判定产物是否可上线发布（那是质量门禁消费方的职责——本技能只出报告与综合判定）。
  - 不执行平台发布/PR/A2A 链路。
- **默认三合一执行（mode=all）**，也可 `mode=lint|test|audit` 单套件——输出一份组合报告（综合判定 + 各套件子报告）。

### 4.2 场景路由

| 入口 | 路径 |
|------|------|
| 用户要检查/测试/审计一个 skill 目录（默认）| 4.3 全流程（mode=all）|
| 用户只要规范检查 | 4.3 流程（mode=lint——只执行 Lint 套件章节）|
| 用户只要功能测试 | 4.3 流程（mode=test）|
| 用户只要安全审计 | 4.3 流程（mode=audit）|
| 用户在平台任务上下文中收到「测试某 skill」交办 | 4.3 全流程 + 4.8 任务收尾 |
| 其他场景 | 不做处理——告知本技能边界并结束（不硬套流程）|

### 4.3 处理流程（三合一 → 统一骨架）

```
Step 0 就绪（前置门） → Step 1 拉取规范 → Step 2 收集信息
→ Step 3 Lint → Step 4 Test → Step 5 Audit → Step 6 汇总报告 + 任务收尾
```

**Step 0 就绪**：跑三、前置检查门（node/目标目录/可选依赖）；确认 mode（默认 all；非法 mode 回退 all 并在报告注明）。

**Step 1 拉取三份规范**

```bash
node common-skill-tester/scripts/fetch_specs.js                              # 全部三份，输出合并 JSON
node common-skill-tester/scripts/fetch_specs.js --type lint                  # 只拉 lint 检查点
node common-skill-tester/scripts/fetch_specs.js --type test                  # 只拉功能测试点
node common-skill-tester/scripts/fetch_specs.js --type audit                 # 只拉安全审计规则
node common-skill-tester/scripts/fetch_specs.js "https://...json" --type lint  # 自定义 URL
node common-skill-tester/scripts/fetch_specs.js -o /tmp/specs.json           # 保存到文件供后续引用
```

拉取成功 → 解析 JSON 读对应字段（结构见 `references/spec-sources.md`）；失败 → 按 4.5 降级。**核心原则：以拉取到的实际 JSON 内容为准，不硬编码任何检查项/测试项/规则**——在线新增分组/条目自动纳入执行范围。

**Step 2 收集目标 Skill 信息（一次收集，三套复用）**

1. **目录结构**：列出所有文件和子目录，记录路径、大小、扩展名（重点标记可执行代码 .sh/.py/.js/.ts/.go/.rs）
2. **SKILL.md 内容**：读完整文本，提取 YAML Frontmatter（name/description/version），解析 Workflow、inputSchema/outputSchema、读写操作声明
3. **脚本文件内容**：读所有 .sh/.py/.js/.ts 文件（可执行代码与依赖声明的安全审计素材）
4. **配置文件**：检查 .env 是否存在；读 package.json/requirements.txt/pyproject.toml 等依赖声明
5. **危险模式预扫描**（一次 grep 三套复用）：凭据（AK/SK/密码/token）、内网 IP/域名、危险命令（sudo/rm -rf）、敏感路径（~/.ssh、~/.aws）、网络请求 URL、动态执行/系统命令调用函数
6. **文件统计**：总大小、文件数、SKILL.md 行数、文件类型列表
7. **跨引用与集成声明**：SKILL.md 中引用的其他具名 Skill、多 Skill 编排、数据传递机制

工具：Glob（列文件）/ Read（读内容）/ Grep（模式搜索）/ Bash（统计/语法检查）。

**Step 3 Lint 规范检查（mode 含 lint 时执行）**

1. 对**每一个**检查项（`groups[].items[]`）按 `references/lint-methods.md` 方法映射表逐项检查（结构/命名/frontmatter/.env/危险脚本/资源限制/凭证/删除操作确认等）
2. 判定 pass/fail/warn/skip——全部基于**客观证据**
3. 按公式算 Lint 总分：`100 - (Critical×15 + High×8 + Medium×4 + Low×2 + warn×1)`
4. Critical fail 记录为必改项（附具体修改建议）；非 Critical fail 和 warn 为建议修改项
5. 输出到报告「三、Lint 检查结果」章节

**Step 4 功能测试（mode 含 test 时执行）**

1. 对**每一条**测试用例（`test_groups[].items[]`）按 `references/test-methods.md` 方法映射表执行（触发词/工作流/Schema/读写语义/性能/兼容/可靠/编排等）
2. 以**静态分析**为主（验证 SKILL.md 是否声明必要机制），可实际运行时结合运行结果
3. 判定 pass/fail/warn/skip + 客观证据（引用章节/行号/内容）
4. 通过率：`pass / (总用例数 - skip) × 100%`；P0 必测项单独统计，任一 fail 标记「建议打回」
5. 输出到报告「四、功能测试结果」章节

**Step 5 安全审计（mode 含 audit 时执行）**

1. 对**每一条**检测规则（`groups[].items[]` + CWE 模式）按 `references/audit-methods.md` 方法映射表检测（网络请求/敏感文件/危险命令/注入/后门/混淆/依赖安全等）
2. 判定 pass/fail/warn/skip；fail 必须**关联 CWE 编号**并引用文件、行号、代码片段
3. 安全分：`100 - (CRITICAL×20 + WARNING×8 + INFO×2 + warn×1)`；CRITICAL fail 一票否决
4. CWE 覆盖率：`已检测 CWE 数 / 总 CWE 数 × 100%`
5. 输出到报告「五、安全审计结果」章节

**Step 6 汇总报告 + 综合判定**

按 `references/report-template.md` 生成组合报告：

1. 三套统计 → 综合分：`round((Lint总分 + Test通过率 + Audit安全分) / 3)`
2. 判定：✅ 通过 / ⚠️ 有条件通过 / ❌ 不通过（见 4.6 判定表）
3. 输出两处：**对话输出**（Markdown 直接给用户）+ **文件输出**（被测 Skill 父目录下 `{skill-name}-tester-report-{YYYYMMDD-HHmmss}.md`——从 skill_path 提取目录名）
4. 判定 ❌ 时对话明确列未达标项（fail 清单 + 未达 95 的套件 + 原因）+ 修复建议
5. **平台任务上下文**：收尾 4.8（tasks complete + JSON 块）

### 4.4 命令标准（本技能命令子集）

本技能的 grape 命令面**仅一条**——4.8 任务收尾的 `grape tasks complete`（平台全部技能通用的收尾协议，不由本技能发起任何业务操作）。**平台管理命令**（issues/pulls/a2a/refresh 等）本技能**不使用**——命令面 = 本地脚本 + 外部规范源拉取：

| 命令 | 用途 | 前置 |
|------|------|------|
| `node common-skill-tester/scripts/fetch_specs.js [--type lint\|test\|audit] [-o <file>] [<url>]` | 拉取三份在线规范 | node ≥ 12 |
| `grape tasks complete --json '{...}'` | **仅 4.8 任务收尾** | 平台任务上下文 |

> ⚠️ **不存在的命令（防误用——本技能禁止尝试）**：
>
> | 命令 | 理由 |
> |------|------|
> | `grape git-repo issues / pulls / a2a handoff / refresh` 等平台管理命令 | 本技能无平台业务交互——本地测试器不走链路 |
> | `grape api` | 已移除（0.2.2 起），且平台禁止直连 API |
> | 检查中的写操作（修改被测文件/`sed -i`/覆盖 SKILL.md）| 本技能只读——检测不改动 |

### 4.5 故障决策表

| 场景 | 处理 |
|------|------|
| skill_path 不存在或非目录 | 返回错误提示，不执行任何检查 |
| 某份规范拉取失败（网络不可用）| 该套件标记「未执行(原因)」，其余照常；提示用户可指定本地 JSON 文件（`-o` 保存的或手动指定路径作为 URL 参数）|
| 用户只要某一种检查 | mode 指定 lint/test/audit，只执行对应套件章节 |
| mode 传非法值 | 回退 all，并在报告中注明 |
| 目标 Skill 无脚本/可执行代码 | audit 中代码相关规则 skip；lint 的脚本检查项 skip 或 pass（注明原因）|
| 目标 Skill 无写操作 | test 中读写语义、幂等、资源清理等用例 skip（注明原因）|
| 在线规范新增未知条目 | 按 `rule`/`input`/`detection` 描述自行设计检查/测试/检测方法，不跳过 |
| 报告过长 | 按模板章节结构输出，详细记录表保留全部条目 |
| 三套评分均 ≥ 95 但存在 warn | 判定 ⚠️ 有条件通过，报告列 warn 项及修正建议 |
| CRITICAL/P0 fail 多处出现 | 判定 ❌ 不通过，全部列出；修复后建议重跑全量 |
| 断点续跑 | 已拉取规范用 `-o` 保存；中断后重新指定该文件作为对应 URL 参数（本地文件路径直接读取）恢复执行 |
| node 不可用 | Agent 直接用 curl/网络工具拉取规范 JSON 后继续（不阻塞主流程）|

### 4.6 输出格式（固定产物）

**三套评分公式与门禁**：

| 套件 | 公式 | 一票否决项 |
|------|------|-----------|
| Lint | `总分 = 100 - (Critical×15 + High×8 + Medium×4 + Low×2 + warn×1)` | Critical fail |
| Test | `通过率 = pass / (总用例 - skip) × 100%` | P0 必测项 fail |
| Audit | `安全分 = 100 - (CRITICAL×20 + WARNING×8 + INFO×2 + warn×1)` | CRITICAL 严重发现 |

**星级标准**（三套统一 + 综合分）：90-100 ⭐⭐⭐⭐⭐ / 75-89 ⭐⭐⭐⭐ / 60-74 ⭐⭐⭐ / 40-59 ⭐⭐ / 0-39 ⭐

**综合判定**：

| 判定 | 条件 |
|------|------|
| ✅ 通过 | 三套评分均 ≥ 95，且无 lint Critical fail、无 test P0 fail、无 audit CRITICAL 发现 |
| ⚠️ 有条件通过 | 无上述三类 fail，但存在 warn 或任一评分在 75-94（按报告修正后复测）|
| ❌ 不通过 | 存在任一上述 fail 类型，或任一评分 < 75 |

**报告结构**（`references/report-template.md`）：综合概览 → 综合判定与评分 → Lint 结果 → Test 结果 → Audit 结果；报告为纯 Markdown，含 `{OVERALL_SCORE}`/`{LINT_SCORE}`/`{TEST_PASS_RATE}`/`{AUDIT_SCORE}`/`{VERDICT}` 等占位符数值供 CI/CD 门禁解析。报告使用中文输出。

**文件输出**：`{被测 Skill 父目录}/{skill-name}-tester-report-{YYYYMMDD-HHmmss}.md`（从 skill_path 提取目录名；例：`skill_path=/repos/skills/dev/my-skill` → `/repos/skills/dev/my-skill-tester-report-20260916-120000.md`）

### 4.7 写操作协议

- **唯一写操作**：报告文件写入被测 Skill **父目录**（文件名含 skill 名 + 时间戳——重复执行覆盖写入，幂等无副作用）。
- **绝不修改被测 Skill 目录内任何文件**（检测只读）；不创建临时文件（拉取规范用 `-o` 保存的文件由用户决定清理）。
- 报告保存后在对话中提示报告路径。

### 4.8 任务收尾（必做）

业务动作全部完成后：

1. **先调 `grape tasks complete` 关闭当前任务**（任务中心闭环）：
```bash
grape tasks complete --json '{"result_text": "三合一测试完成：<skill 名称> 综合判定 <✅/⚠️/❌>", "actions": ["拉取规范/lint/test/audit/汇总报告"], "conclusion": "<综合判定与关键发现>", "artifacts": ["<报告文件路径>"], "next_step": "<按判定给用户的下一步（修复后重测/通过) 建议>"}'
```
2. **再在最终答复末尾输出结构化 JSON 块**（平台读取）：
```json
{
  "actions": ["拉取规范/lint/test/audit/汇总报告"],
  "conclusion": "综合判定与关键发现",
  "artifacts": ["<报告文件路径>"],
  "next_step": "按判定给用户的下一步建议",
  "issue_summary": "本次任务最新聚合结论（紧凑文本，用 | 分隔）"
}
```

## 五、参考文件清单

| 文件 | 职责 | 何时加载 |
|------|------|---------|
| `references/spec-sources.md` | 三份规范的在线地址、合并输出结构、各自预期 JSON 结构、最新规范概要 | Step 1 拉取后核对结构时 |
| `references/lint-methods.md` | Lint 检查方法映射表 + 判定逻辑 + 评分公式 | Step 3 |
| `references/test-methods.md` | 功能测试方法映射表 + 判定逻辑 + 通过率公式 + 证据要求 | Step 4 |
| `references/audit-methods.md` | 安全审计方法映射表 + 判定逻辑 + 安全评分 + CWE 映射要求 | Step 5 |
| `references/report-template.md` | 组合报告模板（综合判定 + 三套子报告）| Step 6 |
| `scripts/fetch_specs.js` | 三份规范动态拉取器（raw → API v5 回退；--type/-o/--help）| Step 1 |
| `references/tester-runbook.md` | 执行走查表（命令固化——照着执行不查 help）| 全流程 |

## 六、Best Practices

- **动态规范为本**：每次执行都必须从在线地址拉取最新规范——不使用缓存或硬编码条目；三份 JSON 结构/字段/条目变化时以实际内容为准
- **客观证据**：每项 pass/fail 基于文件内容/grep 命中/行列号/统计数字——不主观臆断
- **证据与 CWE**：test 每条结果附证据；audit 每条 fail 必须关联 CWE 编号
- **门禁语义**：lint Critical / test P0 / audit CRITICAL 一票否决；三套评分全 ≥ 95 才判定通过
- **不跳过未知项**：在线新增条目按其字段描述执行
- **只读纪律**：检测不改动被测文件——发现问题列清单与修复建议，修复交还用户
- **复用收集**：Step 2 一次收集信息三套复用，避免重复读目标文件；规范 JSON 解析后仅保留必要字段（丢弃 summary/legend 冗余）控制上下文