---
name: common-skill-creator
description: >
  Create, validate, and iterate on generic Agent Skills following the official Agent Skills
  specification. Use when the user wants to create a new skill, scaffold a skill
  directory, write or improve a SKILL.md, optimize skill descriptions for triggering,
  validate skill compliance, or set up eval-driven skill iteration — even if they
  don't explicitly mention "skill" or "specification." Triggers include: "create skill",
  "new skill", "skill creator", "common skill creator", "scaffold a skill", "write SKILL.md",
  "optimize skill description", "validate skill", "skill eval", "创建skill", "新建skill",
  "skill脚手架", "帮我创建一个skill", "生成skill", "skill创建器", "通用skill创建器",
  "build skill", "make a skill".
version: 2.1.0
---

# Common Skill Creator

> 本技能遵循统一技能框架 v2.1.0（与 skill-issue / skill-publish / rest-api-skill-creator / rest-api-skill-tester 同构）。

## 一、安全硬约束（必须遵守）

1. **本地生成器定位**：本技能只做**本地文件操作**——在用户指定位置生成/校验/迭代 Skill 目录。不调用 grape 平台管理命令（issues/pulls/a2a/refresh 等均不适用）；唯一平台接口是 4.8 任务收尾的 `tasks complete`。
2. **严禁读取内部数据**：不读取平台内部数据（data/、configs/、sessions.db、user_accounts 等）。
3. **不写死凭据**：生成的 Skill 与脚本中禁止硬编码凭据（AK/SK/密码/token）——一律使用环境变量引用或占位符。校验脚本若检出硬编码凭据（credential scan），必须修复后才能进入下一步。
4. **在线规范动态拉取**：Phase 4b 的 lint 检查点（`common_skillslinter.json`）**不硬编码、不凭记忆**——每次执行必须用 `scripts/fetch_checks.js` 从在线地址拉取最新版；拉取失败按 4.5 故障决策表降级（本地保存文件复用 → 仅跑 4a 并标记 4b 待办 → 重试），**不得**凭旧快照/记忆假装执行。
5. **外部域界**：fetch_checks.js 访问的在线规范源（gitcode.com 生态规范文件仓库）属**外部规范源域**——脚本内 https 请求合法；此域与 grape 平台管理 API 严格区分（平台管理一律走 CLI 纪律，此处无 CLI 通道也不制造）。
6. **不 mock 不臆造**：校验判定（pass/fail/warn/skip）必须基于**客观证据**（文件存在、grep 命中、行号、统计数字）——禁止凭印象判定。
7. **交互输入禁止**：生成的脚本必须无交互输入（agent 无法应答交互提示）——`--help`、环境变量、参数、stdin 是合法输入方式；交互式脚本直接拒绝并要求改写。
8. **产物清理**：Step 6 收尾时清理 phase-N-summary.json 临时产物（`rm -f {skill-path}/phase-*.json`），不留半成品状态文件。

## 二、环境变量表

| 变量 | 来源 | 说明 |
|------|------|------|
| `GRAPE_SESSION_TOKEN` | 平台注入 | 会话令牌——**仅 4.8 任务收尾的 `tasks complete` 使用**（CLI 自动读取，不手动传入）|
| `DEVOPS_SKILLS_DIR` | 平台注入 | Skills 目录路径——生成的 Skill 若需并入技能库，目标父目录从这里取 |
| `NODE` / `PYTHON`（可选）| 环境探测 | node / python3 可执行文件路径——预检时探测，不存在则按三、前置检查门自愈 |

## 三、前置检查门（自愈 → 重试 → STOP）

1. **node ≥ 12**（运行 `scripts/fetch_checks.js` 拉取在线检查点）：`node --version` 检查——缺失或版本过低 → 尝试安装/升级（nvm / 包管理器）→ 重试 → 仍失败则 STOP（无法动态拉取规范 = Phase 4b 无法执行）。
2. **python3**（运行 `scripts/init-skill.py`、`scripts/validate-skill.sh` 内部逻辑）：`python3 --version` 检查——缺失 → 尝试安装 → 重试 → 仍失败则 STOP。
3. **bash**（运行 `scripts/validate-skill.sh`）：`bash --version` 检查——缺失 → STOP（脚本无法执行）。
4. **目标位置可写**：生成位置（用户指定或 `--output`）存在且可写——不可写 → 报错并请用户换位置，不静默改路径。
5. 任一前置门失败 → 输出「前置检查未通过：<原因>」并结束任务，不无限重试。

## 四、技能定义与执行

### 4.1 定位与职责边界

- **做什么**：按官方 Agent Skills 规范引导用户走五阶段流水线（需求分析 → 设计 → 生成 → 验证 → eval 迭代），产出完整合规的 Skill 包。Phase 4 验证强制规范 **和** 动态 lint 检查点双通过。
- **不做什么**：
  - 不生成 Huawei Cloud 专用 skill（那是 `huawei-cloud-skill-creator` 的职责）——识别后交棒/告知用户换技能。
  - 不做 REST API 类 skill 的生成（那是 `rest-api-skill-creator` 的职责——目标系统 API 编排）。
  - 不执行平台发布/PR/A2A 链路（本技能产物由用户自行安排入库/上架）。
  - 不做 skill 的 lint/test/audit 全面测试（那是 `common-skill-tester` 的职责——本技能只做 Phase 4b 的 lint 检查点自检）。

### 4.2 场景路由

| 入口 | 路径 |
|------|------|
| 用户要新建/脚手架一个 skill（含未明说"skill"但明显是创建技能的场景）| 4.3 全流程（Step 1-6）|
| 用户要对已有 skill 做描述优化 / 触发词优化 | 4.3 Step 4c（从已有描述出发，跳过 Step 1-3 生成）|
| 用户要校验已有 skill 是否符合规范 | 4.3 Step 4a-4b（validate-skill.sh + lint 检查点）|
| 用户要对已有 skill 做 eval 迭代 | 4.3 Step 5（需先有 Skill 实体）|
| 用户要的是 Huawei/REST API 类 skill | 交棒对应技能（见 4.1 边界），不重复造轮子 |
| 其他场景 | 不做处理——告知本技能边界并结束（不硬套流水线）|

### 4.3 处理流程（五阶段流水线 → 统一骨架）

```
Step 0 就绪（前置门） → Step 1 需求分析 → Step 2 设计 → Step 3 生成
→ Step 4 验证（4a 规范 / 4b lint / 4c 描述优化）
→ Step 5 eval 迭代（复杂 skill 推荐） → Step 6 收尾清理 + 任务收尾
```

**Step 0 就绪**：跑三、前置检查门（node/python3/bash/目标位置）——全过后开始。

**Step 1 需求分析（Socratic Q&A）**

一次只问**一个问题**，覆盖维度：

| # | 维度 | 关键问题 |
|---|------|---------|
| 1 | 领域 / 目的 | 解决什么问题？哪个领域？|
| 2 | 功能范围 | 具体做什么？**不**做什么？（内聚单元——不窄不宽）|
| 3 | 触发场景 | agent 何时激活？用户会怎么说？（含不直呼领域名的场景）|
| 4 | 输入 / 输出 | 输入什么？输出什么格式？|
| 5 | 复杂度 | 单文件 skill，还是需要 scripts/、references/、assets/？|
| 6 | 环境前置 | 依赖什么语言/工具/包？（写入 compatibility 字段）|
| 7 | 素材来源 | 有无现成文档/代码/runbook/事故报告作领域知识输入？|

- 每 5 问或覆盖全部维度 → 展示需求汇总表 → **等用户明确确认** → 才进 Step 2
- 鼓励用户提供项目现成产物（runbook/API spec/评审意见/事故报告）作为素材——真实经验 > 通用知识

**输出**：`phase-1-summary.json`（用户已确认的需求）

**Step 2 设计**

1. **命名**——按规范约束：1-64 字符、小写 `a-z0-9-`、不以连字符开头/结尾、无连续 `--`、**必须与父目录名一致**
2. **草拟 description**——按 `references/description-optimization.md` 原则（祈使句「Use this skill when...」/ 聚焦用户意图 / 偏激进入 / ≤1024 字符）
3. **规划 token 预算**（渐进披露）：SKILL.md 正文 < 5000 token、< 500 行；详细素材进 `references/`；写明**何时**加载各文件
4. **选指令模式**——按任务特征选（见 `references/instruction-patterns.md`）：Gotchas / 输出模板 / 检查清单 / 验证循环 / plan-validate-execute
5. **定脚本方案**（见 `references/script-design-guide.md`）：一次性命令（uvx/npx/pipx/go run）直接写 SKILL.md；可复用逻辑进 `scripts/`（自包含脚本）
6. **建目录骨架**——目标父目录取值：**用户指定 > `${DEVOPS_SKILLS_DIR}`（平台注入技能库路径）> 当前目录**：
```bash
python3 scripts/init-skill.py <skill-name> --output "${DEVOPS_SKILLS_DIR:-<用户指定父目录>}" [--with-scripts] [--with-references] [--with-assets] [--with-evals]
```
7. **控制校准**：脆弱操作（顺序敏感/一致性关键）→ 强指令；灵活任务（多条可行路径）→ 给自由度 + 解释 why

**输出**：`phase-2-summary.json`（设计文档 + 目录结构）

**Step 3 内容生成**

**SKILL.md 生成规则**：

| 部分 | 要求 |
|------|------|
| YAML frontmatter | `name`（必填）+ `description`（必填）+ 可选 `license`/`compatibility`/`metadata`/`allowed-tools` |
| 正文核心原则 | **只写 agent 不知道的内容**——项目约定、领域专用流程、非常规边界；不解释 PDF 是什么/HTTP 怎么工作 |
| 指令粒度 | 与脆弱性匹配——脆弱 = 强指令；灵活 = 自由 + 理由 |
| 工具选择 | 给**默认项 + 简要逃生口**，不给等权菜单 |
| 方法论 | 教**方法**（可复用的做法），不教**实例**（具体答案）。流程 > 声明 |

**SKILL.md 推荐段落**：Overview / Prerequisites / Workflow or Steps / Core Commands or Patterns / Gotchas（最高价值）/ Edge Cases / Available Scripts / Reference Documents（references/ 下文件 + 加载时机）

**支撑文件**（按 Step 2 决策）：
- `scripts/`——必须符合 agentic 设计原则：无交互输入、`--help` 输出、结构化输出（JSON/CSV）、友好报错、幂等、破坏性操作 `--dry-run`、有意义的退出码
- `references/`——聚焦单主题文件；SKILL.md 中写明**何时**加载（示例文案：「当 API 返回非 200 状态码时读取 references/api-errors.md」——实际文件名按生成内容定，无此文件则不写）
- `assets/`——模板、数据文件、schema

**输出**：`phase-3-summary.json`（生成文件清单 + 结构校验）

**Step 4 验证**

**4a. 规范合规检查**——运行 `scripts/validate-skill.sh`：

| 检查项 | 级别 | 验证方式 |
|--------|------|---------|
| SKILL.md 存在 | Critical | 文件存在性 |
| name 匹配 `^[a-z0-9]+(-[a-z0-9]+)*$` | Critical | 正则匹配 |
| name ≤ 64 字符 | Critical | 长度检查 |
| name == 父目录名 | Critical | 目录名比较 |
| description 非空且 ≤ 1024 字符 | Critical | 字符计数 |
| frontmatter 是合法 YAML | Critical | YAML 解析 |
| SKILL.md ≤ 500 行 | High | 行数 |
| 文件引用相对路径、一层深 | Medium | 路径分析 |
| 无硬编码凭据 | Critical | 模式扫描 |
| 脚本无交互输入 | Critical | 代码审查 |
| 脚本提供 `--help` | High | 运行 `--help` |

失败 → 先修复再进 4b（不跳过不降级）。

**4b. 通用 lint 检查点（skill-linter 集成）**

检查点**动态**加载——不硬编码、不凭记忆：

```bash
node common-skill-creator/scripts/fetch_checks.js                        # 拉取在线检查点
node common-skill-creator/scripts/fetch_checks.js -o /tmp/checks.json    # 保存到文件（断点续跑/复查）
node common-skill-creator/scripts/fetch_checks.js "https://..."          # 自定义检查点 URL
```

对**每一个**检查项针对生成目录执行——按 `references/lint-checks.md` 方法映射以**客观证据**判定 pass/fail/warn/skip（结构/frontmatter/命名/.env/危险脚本/资源限制/凭据扫描/安全评分/删除操作确认等）。简单 skill 也不跳过——每项按实据判。

评分与门禁：
```
Lint 评分 = 100 - (Critical_fail × 15) - (High_fail × 8) - (Medium_fail × 4) - (Low_fail × 2) - (warn × 1)
```
- **任何 Critical fail（含 failure_handling=FAIL）→ 阻断门禁**：修复后才能进 Step 5
- **评分 ≥ 95 → 通过**（与 lint/tester/auditor 质量门槛一致）；< 95 → 列必改/建议项 → 修复 → 重新拉取重跑直到通过

记录进 `phase-4-summary.json`：total/pass/fail/warn/skip、Lint 评分、星级、fail/warn 全清单（含修复建议 + 检查点版本 doc 字段）。

**4c. 描述触发优化**（见 `references/description-optimization.md`）：

1. 设计 ~20 条触发 eval 查询：8-10 应触发（变换措辞/显式度/细节/复杂度）+ 8-10 不应触发（**近失配优先**——共享关键词但需要不同响应）
2. 分 train/validation 集（60/40）防过拟合
3. 测触发率（环境支持时）：每条查 3 次算触发率——应触发 > 0.5 通过；不应触发 < 0.5 通过
4. 按失败修订：应触发失败 → 拓宽范围/补适用语境；不应触发误触发 → 补「不做什么」边界；**不**从失败查询里扣关键词（过拟合）——找一般类别
5. 复核修订后 description 仍 < 1024 字符
6. 按验证集通过率选最优迭代

**输出**：`phase-4-summary.json`（4a+4b 结果、Lint 评分）+ 优化后 description

**Step 5 eval 驱动迭代（复杂 skill 推荐，简单 skill 可跳过）**

按 `references/eval-workflow.md` 全流程：

1. 设计测试用例 → `evals/evals.json`（2-3 起：prompt + expected_output + 可选 input files；变换措辞/覆盖边界/真实语境）
2. 跑 eval——每条用例跑两次：**with_skill**（agent 带 skill 加载）vs **without_skill**（基线/旧版）；每次干净上下文；记录 token/时长
3. 首跑后写断言（可编程验证：合法 JSON/文件存在/计数正确；具体可观察，不模糊）
4. 评分 → `grading.json`（每条断言 PASS/FAIL + 实证；PASS 不给 benefit of the doubt）
5. 聚合 → `benchmark.json`（with vs without 的 pass_rate/time/token；算 delta——skill 的成本与收益）
6. 分析模式：删双配置恒过断言（无区分度）/ 查双配置恒失败（断言坏或测试过难）/ 研究 with 过 without 不过（skill 的价值）/ 结果不稳定（高 stddev）→ 收紧指令
7. 人工评审 → `feedback.json`（逐用例具体可执行反馈）
8. 迭代：三信号（失败断言 + 人工反馈 + 执行转录）+ 当前 SKILL.md 给 LLM → 提改进（从反馈泛化/保持精简/解释 why/合并重复工作）→ 应用 → 新迭代重跑全部 → 满意或无明显改进即停

**输出**：`phase-5-summary.json`（eval 结果 + benchmark + 最终 SKILL.md）

**Step 6 收尾清理**

```bash
# 完整性确认：5 个 phase 摘要齐全（Phase 5 简单 skill 已标记跳过亦可）
# 缺失 → 从缺失阶段重启
rm -f {skill-path}/phase-*.json    # 清理临时产物
```

### 4.4 命令标准（本技能命令子集）

本技能的 grape 命令面**仅一条**——4.8 任务收尾的 `grape tasks complete`（平台全部技能通用的收尾协议，不由本技能发起任何业务操作）。**平台管理命令**（issues/pulls/a2a/refresh 等）本技能**不使用**——命令面 = 本地脚本 + 外部规范源拉取：

| 命令 | 用途 | 前置 |
|------|------|------|
| `python3 scripts/init-skill.py <name> [--output <dir>] [--with-scripts] [--with-references] [--with-assets] [--with-evals]` | 脚手架建目录 | python3 |
| `bash scripts/validate-skill.sh <skill-path> [--fix]` | Phase 4a 规范校验 | bash |
| `node common-skill-creator/scripts/fetch_checks.js [-o <file>] [<url>]` | 拉取在线 lint 检查点 | node ≥ 12 |
| `grape tasks complete --json '{...}'` | **仅 4.8 任务收尾** | 平台任务上下文 |

> ⚠️ **不存在的命令（防误用——本技能禁止尝试）**：
>
> | 命令 | 理由 |
> |------|------|
> | `grape git-repo issues / pulls / a2a handoff / refresh` 等平台管理命令 | 本技能无平台业务交互——本地生成器不走链路 |
> | `grape api` | 已移除（0.2.2 起），且平台禁止直连 API |
> | 脚本中的交互式输入（`input()` / `read` 等待键盘）| agent 无法应答——一律改为参数/环境变量/--help |

### 4.5 故障决策表

| 场景 | 处理 |
|------|------|
| 用户说「直接创建」不给细节 | 提醒需求分析是必需——从 Step 1 提问开始 |
| 用户要跳过 Step 5（eval 迭代）| 简单 skill 允许；复杂 skill 强烈建议执行 |
| skill 名与现有 skill 冲突 | 建议替代名或分类前缀 |
| description 超 1024 字符 | 精简冗余、合并重叠场景、优先进取触发词 |
| SKILL.md 超 500 行 | 详细内容迁 `references/`，SKILL.md 只留核心指令 |
| 脚本需交互输入 | 拒绝——改写为 flags/环境变量/stdin（交互会挂死 agent）|
| validate-skill.sh 凭据扫描失败 | 硬编码凭据换环境变量引用 |
| 4b lint：Critical fail | **阻断门禁**——先修（列文件+行号+建议），再重新拉取重跑 |
| 4b lint：评分 < 95 | 列全部 fail/warn 项 → 修复 → 重新拉取重跑直到 ≥ 95 |
| 4b 拉取失败（网络断）| 降级：复用本地已存 JSON（`-o` 保存的，把路径当 URL 传）；无本地文件 → 跑 4a 检查、4b 标记 pending、结束 Phase 4 前重试拉取 |
| 4b JSON 含未知/新检查项 | 按其 `rule` 描述执行——**绝不跳过未知项** |
| 触发 eval 触发率差 | 按 4c 修订：应触发失败拓宽、不应触发失败加边界 |
| eval 显示 skill 无增量价值 | skill 可能不需要——考虑 agent 无 skill 本就能处理 |
| Step 5 发现缺阶段 | 从缺失阶段重启直到完整 |

### 4.6 输出格式（固定产物）

- **阶段摘要**：每阶段产出 `phase-N-summary.json`（Step 6 清理）
- **evaluations**：`evals/evals.json` + `grading.json` + `benchmark.json` + `feedback.json`（Step 5 产物）
- **最终交付**：完整 Skill 目录（SKILL.md + references/ + scripts/（按需）+ assets/（按需））
- **对话汇报**：每阶段结束向用户汇报该阶段结论与下一阶段预告；全流程完成给出交付清单（目录路径 + 文件清单 + 校验结果摘要）

### 4.7 写操作协议

- **写入范围**：仅生成位置（**用户指定 > `${DEVOPS_SKILLS_DIR}`（平台注入技能库）> 当前目录**——Step 0 门 4 验证可写）——不越界写其他路径
- **脚本可执行位**：生成的 `scripts/*.py` 或 `*.sh` 保持可执行（`chmod +x`）
- **破坏性操作**：覆盖已有同名 skill 目录前必须用户确认（或 `--dry-run` 预览）
- **临时产物**：`phase-*.json` 属流程内临时状态——Step 6 清理，不留在交付目录

### 4.8 任务收尾（必做）

业务动作全部完成后：

1. **先调 `grape tasks complete` 关闭当前任务**（任务中心闭环）：
```bash
grape tasks complete --json '{"result_text": "生成/优化/校验完成：<skill 名称与结论>", "actions": ["五阶段流水线执行（需求/设计/生成/验证/eval）"], "conclusion": "<交付结论>", "artifacts": ["<skill 目录路径>", "phase-4-summary.json"], "next_step": "<用户下一步选择>"}'
```
2. **再在最终答复末尾输出结构化 JSON 块**（平台读取）：
```json
{
  "actions": ["五阶段流水线执行"],
  "conclusion": "交付结论",
  "artifacts": ["<skill 目录路径>"],
  "next_step": "用户下一步选择",
  "issue_summary": "本次任务最新聚合结论（紧凑文本，用 | 分隔）"
}
```

## 五、参考文件清单

| 文件 | 职责 | 何时加载 |
|------|------|---------|
| `references/spec-summary.md` | SKILL.md 格式、frontmatter 字段、命名约束速查 | Step 2 设计 / 需要核格式时 |
| `references/lint-checks.md` | 动态 lint 检查点：来源、JSON 结构、方法映射、评分公式、Phase 4b 门禁 | Step 4b |
| `references/description-optimization.md` | 描述撰写原则 + 触发精度优化 | Step 2 描述 / Step 4c |
| `references/script-design-guide.md` | agentic 脚本设计原则（无交互/--help/结构化输出/报错）| Step 3 生成脚本时 |
| `references/eval-workflow.md` | eval 迭代全流程：工作区结构、断言示例、评分模板 | Step 5 |
| `references/instruction-patterns.md` | 指令模式目录（gotchas/模板/清单/验证循环/plan-validate-execute）| Step 2 模式选择 |
| `scripts/validate-skill.sh` | 规范校验执行器（Phase 4a）| Step 4a |
| `scripts/fetch_checks.js` | 在线 lint 检查点拉取器（Phase 4b）| Step 4b |
| `scripts/init-skill.py` | 目录脚手架（Step 2/3）| Step 2-3 |
| `templates/skill-template.md` | 生成物模板：SKILL.md 骨架（与 init-skill.py 内嵌模板同款，供人工参考/独立复用）| Step 2-3 |
| `templates/evals-template.json` | 生成物模板：eval 用例骨架（完整 3 用例版；init-skill.py 使用内嵌 1 用例简化版）| Step 5 初始化 eval 时 |
| `templates/trigger-queries-template.json` | 生成物模板：触发查询集骨架（8 应触发 + 12 不应触发备选）| Step 4c 触发 eval 时 |
| `references/creator-runbook.md` | 执行走查表（命令固化——照着执行不查 help）| 全流程 |

## 六、Best Practices

- **素材优先**：Step 1 鼓励用户提供现成项目产物（runbook/API spec/评审意见/事故报告）作领域知识源
- **内聚范围**：Step 2 保持 skill 内聚——不窄（一个任务拆多个 skill）不宽（激活不精准）
- **「agent 会错吗」检验**：Step 3 每条内容自问「没有这条 agent 会做错吗？」——不会则删
- **给默认不给菜单**：Step 3 工具选型给默认项 + 简短备选，不给等权菜单
- **近失配负例**：Step 4c 用近失配查询作 should-not-trigger——最有价值的负例
- **Critical 先修**：Step 4b 先修 Critical，再重跑到评分 ≥ 95——绝不交付不过规范门禁的 skill
- **聚焦区分度断言**：Step 5 删双配置恒过的断言——关注 skill 真正提供的增量
- **保持精简**：更少、更好的指令通常胜过穷举式规则
- **五阶段不可跳**：阶段链式依赖——任何阶段缺失都从缺失处重启

## 附：五阶段流水线一览（映射）

| 原阶段 | 新步骤 |
|--------|--------|
| Phase 1 需求分析（Socratic Q&A）| Step 1 |
| Phase 2 Skill 设计 | Step 2 |
| Phase 3 内容生成 | Step 3 |
| Phase 4 验证（4a 规范 / 4b lint / 4c 描述优化）| Step 4 |
| Phase 5 eval 驱动迭代 | Step 5 |
| Final Completeness Check + 清理 | Step 6 |