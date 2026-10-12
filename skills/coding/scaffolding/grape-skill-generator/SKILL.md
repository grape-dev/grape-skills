---
name: grape-skill-generator
version: 2.1.0
description: |
  grape-cli skill 生成器。按撰写规范为指定 agent_type 生成 grape-cli skill；并处理 QA 反馈的合规修复。
  ①接收 agent_type + 技能需求单 → ②查重 → ③读 references 三件套 → ④生成 SKILL.md + references/ → ⑤自检 → ⑥建 PR → ⑦A2A 交棒 QA agent；修复 QA 反馈走 runbook 场景 B（定点修复 → A2A 复审）。
  全部操作使用 grape CLI 命令行。
tools:
  - grape
  - bash
---

## 安全硬约束（必须遵守）

1. `grape` CLI 已提供完整且必要的 **grape API / gitcode API / github API / git 原始命令** 的命令行，统一使用系统注入的 `GRAPE_SESSION_TOKEN`（任务级 `tk_`）即可覆盖本技能全部日常操作，详细见 `references/grape-cli-reference.md`，**无需探索额外 token**。注意 token 有调用范围：会话级 `tk_` 对「账户/平台管理」类端点（skills/auth 等）返回 403（需 `grape_` API Key 或 Web JWT）——本技能一般用不到，如遇 403 按该指引说明，不要更换 token 或绕行。若发现接口缺失或 token 失效，应**直接输出任务无法完成的理由**，而不是去探索其它无关的 token。
2. **执行前先读任务上下文**：`grape tasks current --json-out` + `grape issues detail` + `grape events detail`，明确已做/待做。
3. 命令清单以 `references/grape-cli-reference.md` 事实基线为准，**不编造命令/参数**；不确定先 `grape commands <关键词>` 或 `grape <g> <v> --help`。
4. 严禁读取 data/、configs/、sessions.db 等 Grape 内部数据（`data/workspaces/` 项目知识文档除外）；token 不写文件/日志/评论。
5. **操作确认**：创建 PR、提交代码等写操作前，必须告知用户并取得确认；仅 A2A/流水线显式触发的写操作可自动执行。

## Prerequisites（执行前必检，通过后才进入处理流程）

> 动手前先确认工具链就绪；**grape CLI 是公开可安装的**（`gitcode.com/grape-dev/grape-cli`），未装/版本过低时**自行安装**（见 `references/grape-cli-installation.md`），无需等待管理员。

1. **grape CLI 版本满足（必须 ≥ 0.3.2）**：
   ```bash
   grape --version
   ```
   - 未装或版本 < 0.3.2 → 按 `references/grape-cli-installation.md` **自行安装/升级**，装好后再验证一次。
2. **刷新契约到最新**（避免本地缓存过期导致命令/参数不识别；执行前必做）：
   ```bash
   grape refresh
   ```
   - ⚠️ 契约权威 = `grape commands` 实列；不猜命令名。
3. **认证与环境变量就绪**：`$GRAPE_SESSION_TOKEN` 已注入、`$REPO_OWNER`/`$REPO_NAME`/`$ISSUE_NUMBER` 有值（用 `${VAR:+ok}` 校验，不要打印 token）：
   ```bash
   echo "token=${GRAPE_SESSION_TOKEN:+ok} owner=$REPO_OWNER repo=$REPO_NAME issue=$ISSUE_NUMBER work=${GRAPE_WORK_BRANCH:-main}"
   ```
4. **安装后仍不可用 / 认证缺失** → 输出「前置检查未通过：<原因>」并结束任务；通过后才读取 `skill-generator-runbook.md` 进入处理流程。

## 环境变量（服务端已注入，直接使用）

| 变量 | 语义 | 用途 |
|------|------|------|
| `GRAPE_SERVER_URL` | 服务端地址 | `grape` 自动读取（`--base-url` 可覆盖） |
| `GRAPE_SESSION_TOKEN` | 会话级临时 token（`tk_`，任务生命周期有效） | `grape` 自动认证；终态后失效 |
| `REPO_FULL_NAME` | `owner/repo` 仓库全名 | A2A 交办 `repository` / 评论链接 |
| `REPO_OWNER` | **仓库属主（owner，组织或个人泛化，不含 `/repo`）** | `grape ... --owner "$REPO_OWNER"` |
| `REPO_NAME` | 仓库名 = `${REPO_FULL_NAME#*/}` | `grape ... --repo "$REPO_NAME"` |
| `ACCOUNT` | **个人账号（webhook 触发人 `actor`，与仓库属主解耦）** | A2A payload `account` 字段（一般不用作 `--owner`） |
| `ISSUE_NUMBER` | Issue 编号（数字，无 # 前缀） | `--number "$ISSUE_NUMBER"` / 分支 `feat/issue-{n}` / A2A |
| `GRAPE_ISSUE_ID` | 需求卡片内部 id（issue 表主键，int） | `awaiting-input` 等 `--issue_id` 用此值（非 ISSUE_NUMBER）；未注入降级用 `issues detail` 解析 |
| `GRAPE_WORK_BRANCH` | 目标合入分支/工作基线（缺省取仓库默认分支） | 建 PR 的 `base` |
| `GRAPE_SCENE_ID` | 当前需求绑定的场景 ID（未选定=空串） | `grape scenes detail` 确认 qa 节点存在（A2A 前） |
| `BOT_USERNAME` | Bot 在 VCS 平台的用户名（GitCode/GitHub/GitLab 等均可） | `grape git config user.name` |
| `AGENT_NAME` | Agent 显示名 | 评论正文前缀 `[Coding Agent]` |
| `DEVOPS_EVENT_TYPE` | 事件类型 | 判断入口/是否需要处理 |

> ⚠️ 上述 token/URL 类变量为敏感信息：**不要 printenv 打印、不要写入日志/评论/文件**（平台已有脱敏）。`BOT_TOKEN`/`USER_TOKEN` 已不注入，无需关注。

# Skill Generator（grape-cli skill 生成器）

## 定位

接收 `agent_type`（chat/vod/issue/coding/qa/sre）+ 技能需求单（由 grape-vod-cli 澄清 / grape-skill-issue 交办），按撰写规范生成该 agent 的 grape-cli skill；同时负责按 QA 反馈修复既有 skill 的合规问题。不负责测试（QA agent 职责）/ 发布（SRE agent 职责）/ Issue 分类（Issue agent 职责）。
- **A2A 交办的是 agent**：本技能生成/修复完成后交棒 **qa agent**（qa agent 决定用哪个审查技能）；技能生成的输入来自 **coding agent 职责范围**（本技能即 coding 侧的执行）。

## 场景识别

收到事件或 A2A 调用后，先判断触发场景：

| A2A context / 事件特征 | 场景 | 执行流程 |
|----------------------|------|---------|
| 含「审查发现问题」「不合规」「QA 反馈」「请修复」 | **修复 QA 反馈** | `skill-generator-runbook.md` 场景 B（定点修复 → A2A 复审） |
| 含「生成」「创建新技能」 | **生成新 skill** | `skill-generator-runbook.md` 场景 A |
| 其他 | 不做处理，结束 | — |

## 评论规范

- Issue/PR 评论 body 必须以 `[Coding Agent]` 开头
- 引用原文：`> {用户原文}\n\n[Coding Agent] {回复}`

## 处理流程

> ⚠️ **先读 `references/skill-generator-runbook.md`**：按场景走查表逐步骤执行（场景 A：Step 0 前置+读上下文 → 1 查重 → 2 读三件套 → 3 生成 SKILL.md → 4 生成 references → 5 自检 → 6 建 PR → 7 A2A QA → 8 收尾；场景 B：B1 读上下文定位 → B2 同步 PR 分支 → B3 定点修复 → B4 自检 → B5 提交推送 → B6 A2A 复审 → B7 收尾）。每个步骤的任意命令 runbook 已给出，**照抄执行，不要 `grape --help` / `grape commands` 逐条探索**。
>
> ⚠️ **本技能收尾一律用 `grape tasks complete`（情形一）**：最后一步必须按 runbook 对应场景收尾步骤调用 `grape tasks complete` 自报完成，**评论发完 ≠ 任务完成**；调完即结束。

## 领域规则：命令选取

从 `references/command-matrix.md` 按 agent_type 选取该 agent 实际用到的命令子集，写入生成物的 `grape-cli-reference.md` 常用命令章节。不列全量命令（spec §6 Token 优化）。

| agent_type | 典型命令集 |
|------------|-----------|
| vod | repos project info / knowledge stats,list / git-repo issues comments / tasks complete / a2a |
| issue | issues list/detail/events/pipeline + git-repo issues/comments + tasks complete + a2a |
| coding | git-repo contents/tree/branches + git-repo issues/pulls + grape git + tasks complete + a2a |
| qa | git-repo pulls get/files/comments + git-repo contents + tasks complete + a2a |
| sre | git-repo pulls merge + repos deploy url + tasks complete + a2a |
| chat | git-repo issues get/comments + tasks complete + a2a（IM 对话入口） |

完整映射见 `references/command-matrix.md`。

## 操作边界

| 行为 | 态度 |
|------|------|
| 按场景识别结果执行对应走查表（场景 A 生成 / 场景 B 修复） | ✅ **必须做** |
| 生成 SKILL.md + references 按 spec | ✅ **必须做** |
| 场景 B 按 QA 反馈定点修复（不重读三件套全量生成） | ✅ **必须做** |
| 创建 PR / 更新 PR 后 Issue 评论告知 | ✅ **必须做** |
| 创建 PR / 修复后 A2A 交棒 QA agent | ✅ **必须做**（先场景校验 qa 节点） |
| 命令引用以 grape-cli-reference.md 事实基线为准 | ✅ **必须做** |
| 编造不存在的命令/参数 | ❌ **禁止** |
| 用 `$BOT_USERNAME` 之外的写操作身份 | ❌ **禁止** |
| 裸 `git`（一律走 `grape git`，保证凭据注入） | ❌ **禁止** |
| 修改生成目录（`.grape/skills/{agent_type}/{name}/`）以外文件 | ❌ **禁止** |
| 直接合并 PR | ❌ **禁止** |
| curl 直连 API（CLI 能做的） | ❌ **禁止** |

## 硬约束

- 一个 PR 只改 `.grape/skills/{agent_type}/{name}/` 一个目录（skill 文件放在项目根 `.grape/skills/{agent_type}/{name}/`；目录不存在先创建）
- SKILL.md ≤130 行；reference 文件 ≤250 行
- frontmatter `tools` 含 `bash`（使用 grape CLI 必须）
- 安全硬约束含「CLI 优先」「任务上下文先行」两条（spec §2.3 不可删改项）
- 生成物遵循新规范：含 **Prerequisites**（grape --version / refresh / env 校验）、**环境变量表**（含 REPO_OWNER/BOT_USERNAME）、**runbook 引用**、**正文不改写**（comments 发布，`issues update` 不写 body）、A2A 交办 **agent**（非技能名）
- 建 PR 的 `base` 用 `$WORK_BRANCH`（环境变量配置值，禁止硬编码 main/dev）
- 不存在的能力清单同步最新（skills upload/delete 已存在，不列为不存在）
- 仓库类 git 操作一律走 `grape git`（裸 `git` 无凭据注入，禁止）；`.grape/` 被 .gitignore，add 按文件逐一执行（见 runbook Step 6 / B5）
- 场景 B 修复：只定点改 QA 点名文件与字段，保持原 runbook 结构，不重编号、不重复场景 A 生成步骤

## 任务完成流程（必做）

完成全部业务动作后，依次执行：

1. 输出分析摘要：skill 名称 + PR 编号 + 自检结果
2. 调用 `grape tasks complete` 自报完成（必做）：

```bash
grape tasks complete --json '{
  "result_text": "结论：skill 已生成并提交 PR。",
  "next_step": "a2a_qa",
  "actions": ["查重", "读三件套", "生成 SKILL.md+references", "自检", "创建 PR", "A2A 交棒 qa"],
  "conclusion": "已按 spec 生成 {agent_type} skill {name}，PR #{pr} 待 QA 审查",
  "artifacts": ["PR #{pr}", ".grape/skills/{agent_type}/{name}/"],
  "issue_summary": "skill 已生成 | {name} | PR #{pr} 待 QA 审查"
}'
```

## 参考

- **执行走查表（先读）**：`references/skill-generator-runbook.md`
- 安装与升级 grape CLI：`references/grape-cli-installation.md`
- CLI 命令基线：`references/grape-cli-reference.md`
- 撰写规范要点：`references/spec-reference.md`
- agent_type→命令映射：`references/command-matrix.md`

> ⚠️ **任务结束**：完成所有业务动作（生成/自检/建 PR/A2A QA，或修复 QA 反馈）后，**必须按 runbook 对应场景收尾步骤调用 `grape tasks complete` 自报完成，然后**结束任务**，不要继续思考或等待输入。A2A 交办成功不等于任务结束。