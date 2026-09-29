# 通用 Skill 生成执行走查表（common-skill-creator runbook）

> 目的：把 common-skill-creator 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> **命令纪律**：本技能为**本地生成器**——命令面 = 本地脚本（python3/node/bash）+ **唯一平台接口** 4.8 任务收尾 `tasks complete`。**禁止**尝试 grape 平台管理命令（issues/pulls/a2a/refresh——本技能无平台业务交互）；grape CLI 在平台任务上下文外不可用。

## Step 0 就绪（前置检查门）

| 检查 | 命令 | 通过标准 | 失败处理 |
|------|------|---------|---------|
| node | `node --version` | ≥ 12 | 尝试安装（nvm/包管理器）→ 重试 → 仍失败 STOP |
| python3 | `python3 --version` | 存在 | 尝试安装 → 重试 → 仍失败 STOP |
| bash | `bash --version` | 存在 | STOP |
| 目标位置可写 | `test -w "<目标父目录>"` | 可写 | 报错请用户换位置，不静默改路径 |

任一失败 → 输出「前置检查未通过：<原因>」结束任务，不无限重试。

## Step 1 需求分析（Socratic Q&A）

- 一次只问**一个问题**，维度循环：领域/目的 → 功能范围（含**不**做什么）→ 触发场景 → 输入/输出 → 复杂度（scripts/references/assets 是否需要）→ 环境前置 → 素材来源
- 每 5 问或覆盖全维度 → 展示需求汇总表 → **等用户明确确认** → 才进 Step 2
- 鼓励用户提供现成产物（runbook/API spec/评审意见/事故报告）作领域知识源
- 产出：`phase-1-summary.json`（用户已确认需求）

## Step 2 设计

1. **命名**：1-64 字符 / 小写 `a-z0-9-` / 不以连字符开头结尾 / 无 `--` / **必须与父目录名一致**
2. **草拟 description**：祈使句「Use this skill when...」/ 聚焦用户意图 / 偏激进入 / **≤1024 字符**
3. **token 预算**：SKILL.md < 5000 token、< 500 行；细节进 `references/`；写明**何时**加载各文件
4. **选指令模式**（`references/instruction-patterns.md`）：Gotchas / 输出模板 / 检查清单 / 验证循环 / plan-validate-execute
5. **定脚本方案**（`references/script-design-guide.md`）：一次性命令直接写 SKILL.md；可复用逻辑进 `scripts/`
6. **建目录骨架**（父目录取值：用户指定 > `${DEVOPS_SKILLS_DIR}`（平台注入技能库）> 当前目录）：
```bash
python3 scripts/init-skill.py <skill-name> --output "${DEVOPS_SKILLS_DIR:-<用户指定父目录>}" [--with-scripts] [--with-references] [--with-assets] [--with-evals]
```
7. **控制校准**：脆弱操作 → 强指令；灵活任务 → 自由度 + why
- 产出：`phase-2-summary.json`（设计 + 目录结构）

## Step 3 内容生成

**SKILL.md 规则**：frontmatter（name+description 必填，可选 license/compatibility/metadata/allowed-tools）/ **只写 agent 不知道的内容**（项目约定/领域流程/非常规边界；不解释 PDF 是什么）/ 指令粒度匹配脆弱性 / 给默认不给菜单 / 教方法不教实例。

**推荐段落**：Overview / Prerequisites / Workflow or Steps / Core Commands or Patterns / Gotchas（最高价值）/ Edge Cases / Available Scripts / Reference Documents。

**支撑文件**：
- `scripts/`——无交互输入、`--help`、结构化输出（JSON/CSV）、友好报错、幂等、破坏性操作 `--dry-run`、有意义退出码
- `references/`——聚焦单主题；SKILL.md 写明**何时**加载
- `assets/`——模板/数据/schema

- 产出：`phase-3-summary.json`（文件清单 + 结构校验）

## Step 4 验证

### 4a 规范合规检查

```bash
bash scripts/validate-skill.sh <skill-path>          # 只校验
bash scripts/validate-skill.sh <skill-path> --fix    # 自动修复可修项
```
- 11 项硬性约束：SKILL.md 存在 / name 正则+长度+父目录一致 / description 非空≤1024 / frontmatter 合法 YAML / ≤500 行 / 引用相对一层深 / **无硬编码凭据（Critical）** / 脚本无交互（Critical） / 脚本 --help
- 失败 → 先修复再进 4b（不跳过不降级）
- 校验脚本检出硬编码凭据 → 换环境变量引用后重跑

### 4b 通用 lint 检查点（动态拉取）

```bash
node common-skill-creator/scripts/fetch_checks.js                          # 拉取在线检查点（raw → gitcode API v5 自动回退）
node common-skill-creator/scripts/fetch_checks.js -o /tmp/checks.json      # 保存到文件（断点续跑/复查）
node common-skill-creator/scripts/fetch_checks.js "https://..."            # 自定义检查点 URL
```
- 对**每一个**检查项 → 按 `references/lint-checks.md` 方法映射 → 客观证据判 **pass/fail/warn/skip**
- 评分：`100 - (Critical×15 + High×8 + Medium×4 + Low×2 + warn×1)`
- **门禁**：任何 Critical fail（含 failure_handling=FAIL）→ 阻断，先修；**评分 ≥ 95 才合格** → < 95 列必改/建议项 → 修复 → 重新拉取重跑
- 记录：`phase-4-summary.json`（total/pass/fail/warn/skip + Lint 评分 + 星级 + fail/warn 清单含修复建议 + 检查点版本 doc）

### 4c 描述触发优化

- 设计 ~20 条触发查询：8-10 应触发（变换措辞/显式度/细节/复杂度）+ 8-10 不应触发（**近失配优先**——共享关键词但需求不同）
- 分 train/validation（60/40）防过拟合（固定 split 跨迭代）
- 测触发率：每条查询跑 3 次——应触发 > 0.5 通过 / 不应触发 < 0.5 通过
- 修订：应触发失败 → 拓宽范围/补语境；不应触发误触发 → 补「不做什么」边界；**不从失败查询扣关键词**（过拟合）
- 复核 < 1024 字符 → 按验证集通过率选最优迭代
- 产出：`phase-4-summary.json`（4a+4b 结果 + Lint 评分）+ 优化后 description

## Step 5 eval 驱动迭代（复杂 skill 推荐；简单 skill 可跳过）

按 `references/eval-workflow.md`：

1. 设计 2-3 用例 → `evals/evals.json`（prompt + expected_output + 可选 files）
2. 每条跑两次：**with_skill** / **without_skill**（基线或旧版快照：`cp -r <skill-path> <workspace>/skill-snapshot/`）；干净上下文（subagent/独立会话）；记录 timing
3. 首跑后写断言（可编程验证：合法 JSON/文件存在/计数；具体可观察）
4. 评分 → `grading.json`（断言 PASS/FAIL + **实证**——PASS 不给 benefit of the doubt）
5. 聚合 → `benchmark.json`（with vs without 的 pass_rate/time/tokens + delta——skill 的成本与收益）
6. 分析：删双配置恒过断言 / 查恒失败断言 / 研究 with 过 without 不过（skill 价值）/ 结果不稳定 → 收紧指令
7. 人工评审 → `feedback.json`（具体可执行反馈；空 = 通过）
8. 迭代：三信号（失败断言 + 人工反馈 + 执行转录）+ 当前 SKILL.md → 改进 → 新迭代重跑 → 满意/无实质改进即停
- 产出：`phase-5-summary.json`（eval 结果 + benchmark + 最终 SKILL.md）

## Step 6 收尾清理 + 任务收尾

```bash
# 完整性确认：phase-1~5-summary.json 齐全（Phase 5 简单 skill 已标记跳过亦可）；缺失 → 从缺失阶段重启
rm -f {skill-path}/phase-*.json    # 清理临时产物（不留半成品状态文件）
```

### 平台任务收尾（唯一 grape 交互——必做）

业务动作全部完成后，**先调 tasks complete 关任务，再在最终答复末尾输出 JSON 块**：

```bash
grape tasks complete --json '{"result_text": "生成/优化/校验完成：<skill 名称与结论>", "actions": ["五阶段流水线执行（需求/设计/生成/验证/eval）"], "conclusion": "<交付结论>", "artifacts": ["<skill 目录路径>", "phase-4-summary.json"], "next_step": "<用户下一步选择>"}'
```
```json
{
  "actions": ["五阶段流水线执行"],
  "conclusion": "交付结论",
  "artifacts": ["<skill 目录路径>"],
  "next_step": "用户下一步选择",
  "issue_summary": "本次任务最新聚合结论（紧凑文本，用 | 分隔）"
}
```

## 错误排查速查

| 症状 | 原因 | 处理 |
|------|------|------|
| `node: command not found` 或版本 < 12 | node 缺失/过旧 | 前置门自愈（nvm/包管理器装）→ 重试 → 仍失败 STOP |
| `validate-skill.sh` 凭据扫描失败 | 生成内容含硬编码 AK/SK/token | 换环境变量引用 → 重跑 4a |
| 脚本含交互输入（`input()`/`read`）| 违反 agentic 设计 | 拒绝交付，改写为 flags/环境变量/stdin |
| 4b 拉取失败（网络断）| raw + API v5 双失败 | 复用本地 `-o` 保存的 JSON（路径当 URL 传）；无本地文件 → 跑 4a、4b 标记 pending、结束 Phase 4 前重试 |
| 4b JSON 含未知新检查项 | 在线规范更新 | 按该项 `rule` 描述执行——绝不跳过 |
| 4b Critical fail / 评分 < 95 | 生成物不合规 | 列文件+行号+修复建议 → 修复 → 重新拉取重跑直到通过 |
| 触发率差（应触发不触发 / 不应触发误触发）| description 过窄 / 过宽 | 按 4c 修订：拓宽范围 或 加「不做什么」边界 |
| eval 显示 skill 无增量 | skill 可能不必要 | 与用户确认是否放弃/简化 |
| `grape tasks complete` 失败 | 非平台任务上下文 | 跳过收尾（无任务可关），照常交付产物 |
| 覆盖已有同名 skill 目录 | 破坏性操作 | 先用户确认或 `--dry-run` 预览，不静默覆盖 |