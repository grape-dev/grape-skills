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
version: 2.3.0
---

# Common Skill Creator

> 本技能遵循统一技能框架 v2.1.0（与 skill-issue / skill-publish / rest-api-skill-creator / rest-api-skill-tester 同构）。

## 一、安全硬约束（必须遵守）

1. **链路节点定位**：本技能以**本地文件操作**为主（生成/校验/迭代 Skill 目录），并在**流水线场景**下**创建 PR 入库 + A2A 交棒 `common-skill-tester`**（对齐 rest-api/huawei 系已跑通的链路）。平台管理命令面 = PR 创建（走 `scripts/create_common_skill_pr.sh`）+ 发评论（`grape git-repo issues comments create`）+ `a2a handoff`（交棒）+ 4.8 `tasks complete`（收尾）；**仍不合并 PR、不发布、不做 lint/test/audit 全面测试**（合并归 tester、发布归 skill-publish、全面测试归 common-skill-tester）。**平台 API 返回 403/401 → 立即停止操作**，回复「该操作需要管理员/维护者权限，请在仓库设置中配置后重试」——**不尝试其他 token、不绕行**。
2. **平台交互唯一通道（grape CLI）**：所有平台管理操作（PR 创建/评论/A2A 交棒/任务收尾）必须经 `grape CLI`（或封装脚本 `scripts/create_common_skill_pr.sh`）执行——**禁止 curl 直连平台 API**（`grape api` 已于 0.2.2 移除——契约未覆盖的端点不可调用）。执行前必须过前置门 5（`grape --version` 校验——缺失自动安装 → 重试 → 仍失败 STOP）；CLI 不可用时**不尝试绕过**（不拼 URL、不裸调 API）。
3. **严禁读取内部数据**：不读取平台内部数据（data/、configs/、sessions.db、user_accounts 等）。
4. **不写死凭据**：生成的 Skill 与脚本中禁止硬编码凭据（AK/SK/密码/token）——一律使用环境变量引用或占位符。校验脚本若检出硬编码凭据（credential scan），必须修复后才能进入下一步。
5. **在线规范动态拉取**：Phase 4b 的 lint 检查点（`common_skillslinter.json`）**不硬编码、不凭记忆**——每次执行必须用 `scripts/fetch_checks.js` 从在线地址拉取最新版；拉取失败按 4.5 故障决策表降级（本地保存文件复用 → 仅跑 4a 并标记 4b 待办 → 重试），**不得**凭旧快照/记忆假装执行。
6. **外部域界**：fetch_checks.js 访问的在线规范源（gitcode.com 生态规范文件仓库）属**外部规范源域**——脚本内 https 请求合法；此域与 grape 平台管理 API 严格区分（平台管理一律走 CLI 纪律，此处无 CLI 通道也不制造）。
7. **不 mock 不臆造**：校验判定（pass/fail/warn/skip）必须基于**客观证据**（文件存在、grep 命中、行号、统计数字）——禁止凭印象判定。
8. **交互输入禁止**：生成的脚本必须无交互输入（agent 无法应答交互提示）——`--help`、环境变量、参数、stdin 是合法输入方式；交互式脚本直接拒绝并要求改写。
9. **产物清理**：Step 6 收尾时清理 phase-N-summary.json 临时产物（`rm -f {skill-path}/phase-*.json`），不留半成品状态文件。

## 二、环境变量表

| 变量 | 来源 | 说明 |
|------|------|------|
| `GRAPE_SESSION_TOKEN` | 平台注入 | 会话令牌——**平台交互（PR 创建/评论/A2A 交棒/任务收尾）使用**（CLI 自动读取，不手动传入）|
| `REPO_FULL_NAME` | 平台注入 | 仓库全名 `owner/repo`（PR 脚本与 A2A 必填——`OWNER=${REPO_FULL_NAME%/*}`、`REPO=${REPO_FULL_NAME#*/}`）|
| `ISSUE_NUMBER` | 平台注入 | Issue 编号（PR 脚本/A2A payload/评论必填）|
| `ACCOUNT` | 平台注入 | 触发者账号（actor——A2A payload 的 `account` 字段用）|
| `PR_NUMBER` | 平台注入 | PR 编号（A2A payload 的 `pr_number` 提取——评论/A2A 必填；standalone 场景改由 `create_common_skill_pr.sh` 脚本 stdout 输出取得）|
| `DEVOPS_SKILLS_DIR` | 平台注入 | Skills 目录路径——生成的 Skill 若需并入技能库，目标父目录从这里取 |
| `NODE` / `PYTHON`（可选）| 环境探测 | node / python3 可执行文件路径——预检时探测，不存在则按三、前置检查门自愈 |

## 三、前置检查门（自愈 → 重试 → STOP）

1. **node ≥ 12**（运行 `scripts/fetch_checks.js` 拉取在线检查点）：`node --version` 检查——缺失或版本过低 → 尝试安装/升级（nvm / 包管理器）→ 重试 → 仍失败则 STOP（无法动态拉取规范 = Phase 4b 无法执行）。
2. **python3**（运行 `scripts/init-skill.py`、`scripts/validate-skill.sh` 内部逻辑）：`python3 --version` 检查——缺失 → 尝试安装 → 重试 → 仍失败则 STOP。
3. **bash**（运行 `scripts/validate-skill.sh`）：`bash --version` 检查——缺失 → STOP（脚本无法执行）。
4. **目标位置可写**：生成位置（用户指定或 `--output`）存在且可写——不可写 → 报错并请用户换位置，不静默改路径。
5. **grape CLI（流水线场景必须——PR/评论/A2A/收尾依赖）**：`grape --version` 检查——缺失 → 尝试安装（见 `references/grape-cli-installation.md`）→ 重试 → 仍失败 STOP；**standalone（无平台注入）跳过此项**。
6. 任一前置门失败 → 输出「前置检查未通过：<原因>」并结束任务，不无限重试。

## 四、技能定义与执行

### 4.1 定位与职责边界

- **做什么**：按官方 Agent Skills 规范引导用户走五阶段流水线（需求分析 → 设计 → 生成 → 验证 → eval 迭代），产出完整合规的 Skill 包。Phase 4 验证强制规范 **和** 动态 lint 检查点双通过。
- **不做什么**：
  - 不生成 Huawei Cloud 专用 skill（那是 `huawei-cloud-skill-creator` 的职责）——识别后交棒/告知用户换技能。
  - 不做 REST API 类 skill 的生成（那是 `rest-api-skill-creator` 的职责——目标系统 API 编排）。
  - 不合并 PR、不发布产物（合并由 `common-skill-tester` 验证通过后执行、上架交 `skill-publish`）——本技能交付到 **创建 PR 入库 + A2A 交棒 tester** 为止。
  - 不做 skill 的 lint/test/audit 全面测试（那是 `common-skill-tester` 的职责——本技能只做 Phase 4b 的 lint 检查点自检）。

### 4.2 场景路由

| 入口 | 路径 |
|------|------|
| 平台流水线 A2A 触发（Issue 交办创建 skill）| 4.3 全流程（Step 1-6）→ Step 7 创建 PR → Step 8 A2A 交棒 tester |
| 用户要新建/脚手架一个 skill（含未明说"skill"但明显是创建技能的场景）| 4.3 全流程（Step 1-6）→ **流水线上下文**（`REPO_FULL_NAME`/`ISSUE_NUMBER` 已注入）→ Step 7 创建 PR + Step 8 A2A 交棒（创建完成即交付——对齐 huawei mandatory delivery）；standalone（无注入）→ 停在 Step 6 并告知产物路径 |
| 用户要对已有 skill 做描述优化 / 触发词优化 | 4.3 Step 4c（从已有描述出发，跳过 Step 1-3 生成）|
| 用户要校验已有 skill 是否符合规范 | 4.3 Step 4a-4b（validate-skill.sh + lint 检查点）|
| 用户要对已有 skill 做 eval 迭代 | 4.3 Step 5（需先有 Skill 实体）|
| 用户要的是 Huawei/REST API 类 skill | 交棒对应技能（见 4.1 边界），不重复造轮子 |
| 其他场景 | 不做处理——告知本技能边界并结束（不硬套流水线）|

### 4.3 处理流程（统一骨架）

**流程总览（一行）**：

Step 0 就绪（前置门） → Step 1 需求分析 → Step 2 设计 → Step 3 生成
→ Step 4 验证（4a 规范 / 4b lint / 4c 描述优化）
→ Step 5 eval 迭代（复杂 skill 推荐） → Step 6 收尾清理
→ Step 7 创建 PR（流水线场景必做） → Step 8 A2A 交棒 tester（流水线场景必做） → 4.8 任务收尾

**执行规则**：

- ⚠️ **启动即读 `references/creator-runbook.md`**——每步具体命令按走查表照抄执行（不现场查 --help）
- **五阶段链式不可跳**：任何阶段缺失 → 从缺失处重启（Step 1-5 产物 phase-1~5-summary.json 链式依赖）
- **验证门禁**（Step 4）：4a 规范合规（validate-skill.sh 11 项硬性约束）+ 4b 动态 lint 检查点（fetch_checks.js 在线拉取——**Critical fail 一票否决、评分 ≥ 95 才合格**，公式详见 runbook）——双通过才进 Step 5
- **Step 7**：单 PR 单 Skill——pulls 走 `scripts/create_common_skill_pr.sh`（幂等查重/契约字段 related_issue_nums + auto_close_issues/补 body/base 校验）——创建后**必须发 Issue 评论**（模板见 4.6）
- **Step 8**：A2A payload **必带 issue_number + pr_number**（tester 拉取/合并/交棒依赖）——agent 用场景标准节点名 `qa`（⚠️ **不传技能名**——#10 not_in_scene 教训）
- **收尾顺序**：流水线场景 Step 7/8 完成 → 4.8 tasks complete（**先交棒再关任务**）；standalone（无平台注入）→ 停在 Step 6 告知产物路径，跳过 7/8

> 每步阶段摘要/命令/产物详表 → 按 `references/creator-runbook.md` Step 1-8 照抄执行。

### 4.4 命令标准（本技能命令子集）

本技能的 grape 命令面**四条**——① PR 创建（走 `scripts/create_common_skill_pr.sh`——内部封装 pulls list/create/update 幂等与 base 校验，**不直接手敲 pulls**）② `grape git-repo issues comments create`（Step 7 发 PR 成功评论）③ `grape a2a handoff`（Step 8 交棒 tester）④ `grape tasks complete`（4.8 任务收尾——平台全部技能通用协议）。**不合并 PR**（tester 验证通过后由 QA 节点合并）、不发布（skill-publish 职责）、Issue 其他读写不用。命令面 = 本地脚本 + PR 脚本 + 评论 + a2a + tasks complete：

| 命令 | 用途 | 前置 |
|------|------|------|
| `python3 scripts/init-skill.py <name> [--output <dir>] [--with-scripts] [--with-references] [--with-assets] [--with-evals]` | 脚手架建目录 | python3 |
| `bash scripts/validate-skill.sh <skill-path> [--fix]` | Phase 4a 规范校验 | bash |
| `node common-skill-creator/scripts/fetch_checks.js [-o <file>] [<url>]` | 拉取在线 lint 检查点 | node ≥ 12 |
| `bash scripts/create_common_skill_pr.sh "<skill_name>" [--base main]` | Step 7 创建 PR（内部 pulls list/create/update——幂等 + body 补写 + base 校验）| bash + grape CLI |
| `grape git-repo issues comments create --owner ... --number "$ISSUE_NUMBER" --json '{...}'` | Step 7 发 PR 成功评论（body 以 `[Coding Agent]` 开头）| 平台任务上下文 |
| `grape a2a handoff --json '{"agent":"qa","payload":{...}}'` | Step 8 交棒 tester（**必带 issue_number + pr_number**；agent 用节点名 qa）| 平台任务上下文 |
| `grape tasks complete --json '{...}'` | **4.8 任务收尾**（A2A 交棒之后调用）| 平台任务上下文 |

> ⚠️ **不存在的命令（防误用——本技能禁止尝试）**：
>
> | 命令 | 理由 |
> |------|------|
> | `grape git-repo pulls create/merge` 等 pulls 手敲 | **不直接手敲**——PR 创建走 `scripts/create_common_skill_pr.sh`（幂等/补 body/base 校验封装）；**合并 PR 禁止**（tester 通过后由 QA 节点执行）|
> | `grape git-repo issues` 其他子命令（list/get/update 状态等）| 本技能不用（只允许 `issues comments create` 发 PR 成功评论——standalone 场景不发）|
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
| 创建 PR 失败（grape 无输出/exit 2）| 重试 1 次 → 仍失败 → Issue 评论说明失败原因（不创建 PR 不交棒）|
| PR base 校验不过 | 检查 `--base` 参数（默认 main）——修正后重新执行脚本 |
| PR 幂等查重命中（已有本 skill 的 PR）| 复用该 PR 编号——不重复创建——直接走 Step 8 交棒 |
| A2A 交棒失败（非 2xx/超时）| 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入 |
| 本地 standalone 创建（无 issue/PR 上下文）| 跳过 Step 7/8（不建 PR 不交棒）——完成后告知用户产物路径（入库/上架由用户自行安排）|
| 生成目录不在仓库 worktree 内 | 脚本 `git add` 无变更 → 空 PR 风险 | **不建 PR**——评论告知产物路径（`<绝对路径>`），入库/上架由用户或后续流程安排；仍可走 A2A 交棒需有 PR 前提——无 PR 则跳过交棒并说明 |

### 4.6 输出格式（固定产物）

- **阶段摘要**：每阶段产出 `phase-N-summary.json`（Step 6 清理）
- **evaluations**：`evals/evals.json` + `grading.json` + `benchmark.json` + `feedback.json`（Step 5 产物）
- **最终交付**：完整 Skill 目录（SKILL.md + references/ + scripts/（按需）+ assets/（按需））
- **PR 产物**（流水线场景）：PR #N（单 PR 单 Skill——pulls 幂等）——创建后**必须发 Issue 评论**（成功模板）：
```
[Coding Agent] ✅ Skill 已创建并提交 PR #<n>
**Skill 名称**：<name>　**功能摘要**：<一句话>
**PR 链接**：https://gitcode.com/<owner>/<repo>/merge_requests/<n>
**下一步**：QA（common-skill-tester）功能验证——通过后合并发布
```
- **对话汇报**：每阶段结束向用户汇报该阶段结论与下一阶段预告；全流程完成给出交付清单（目录路径 + 文件清单 + 校验结果摘要 + PR 链接（如有））；流水线场景汇报**不再自称「全面测试通过」**——改「五阶段生成完成，全面测试由 QA（common-skill-tester）执行」

### 4.7 写操作协议

- **写入范围**：仅生成位置（**用户指定 > `${DEVOPS_SKILLS_DIR}`（平台注入技能库）> 当前目录**——Step 0 门 4 验证可写）——不越界写其他路径
- **脚本可执行位**：生成的 `scripts/*.py` 或 `*.sh` 保持可执行（`chmod +x`）
- **破坏性操作**：覆盖已有同名 skill 目录前必须用户确认（或 `--dry-run` 预览）
- **临时产物**：`phase-*.json` 属流程内临时状态——Step 6 清理，不留在交付目录
- **创建 PR**（Step 7——流水线场景必做）：走 `scripts/create_common_skill_pr.sh`（pulls 幂等封装——不直接手敲）——创建后必发 Issue 评论
- **A2A 交棒 tester**（Step 8——流水线场景必做）：`grape a2a handoff`——payload 必带 issue_number + pr_number
- **合并 PR**：❌ **禁止**（tester 验证通过后由 QA 节点合并——本技能不合并）
- **提交顺序**：Step 6 清理临时产物后再建 PR（PR 不含 phase-*.json 半成品）

### 4.8 任务收尾（必做）

业务动作全部完成后（含 Step 7 创建 PR + Step 8 A2A 交棒——流水线场景）：

1. **最后调 `grape tasks complete` 关闭当前任务**（任务中心闭环——必须在 A2A 交棒之后，先交棒再关任务）：
```bash
grape tasks complete --json '{"result_text": "生成/优化/校验完成：<skill 名称与结论>", "actions": ["五阶段流水线执行（需求/设计/生成/验证/eval）", "created:<skill_name>", "submitted:PR#<n>", "a2a:qa"], "conclusion": "<交付结论>", "artifacts": ["<skill 目录路径>", "PR#<n>链接"], "next_step": "<QA 验证/用户下一步选择>"}'
```
2. **再在最终答复末尾输出结构化 JSON 块**（平台读取）：
```json
{
  "actions": ["五阶段流水线执行", "created:<skill_name>", "submitted:PR#<n>", "a2a:qa"],
  "conclusion": "交付结论",
  "artifacts": ["<skill 目录路径>", "PR#<n>链接"],
  "next_step": "QA 验证/用户下一步选择",
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
| `references/creator-runbook.md` | **执行走查表：Step 0-8 全程命令逐步照抄 + 错误排查速查** | ⭐ **最先**——启动即读，全流程照抄不查 --help |
| `references/grape-cli-installation.md` | grape CLI 安装/升级/验证（前置门 5 自愈）| 前置检查发现缺失/版本过低时 |
| `references/grape-cli-reference.md` | grape CLI 命令契约（子集 + ❌ 警示 + token scope）| Step 7/8 平台交互前 |

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
| 创建 PR 入库（流水线场景必做——pulls 幂等 + 发评论）| Step 7 |
| A2A 交棒 tester（流水线场景必做——payload 带 issue_number + pr_number）| Step 8 |