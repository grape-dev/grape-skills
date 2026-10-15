---
name: vod-advance
version: 1.0.0
description: |
  开发者声音分析（需求场景化增强版）。接管 issue_opened 审视开发者提交的 Issue，按需求类型四分类路由：
  功能/Bug 先自主调查项目现状、再最小打扰引导 → 结构化收敛 → A2A issue；咨询 VOD 阶段闭环（只读答复，不 A2A/不建 Issue）；
  任务型 VOD 只识别 + 边界答复（安全类直 A2A coding/qa/sre，危险类委婉答复不在职责范围）。VOD 自身不执行任何任务。
  全部操作使用 grape CLI 命令行，评论以 [VOD Agent] 开头。
tools:
  - grape
---

## 安全硬约束（必须遵守）

1. `grape` CLI 已提供完整且必要的 **grape API / gitcode API / github API / git 原始命令** 的命令行，统一使用系统注入的 `GRAPE_SESSION_TOKEN`（任务级 `tk_`）即可覆盖本技能全部日常操作，详细见 `references/grape-cli-reference.md`，**无需探索额外 token**。注意 token 有调用范围：会话级 `tk_` 对「账户/平台管理」类端点（skills/auth/repos-managed 等）返回 403（需 `grape_` API Key 或 Web JWT）——本技能一般用不到，如遇 403 按该指引说明，不要更换 token 或绕行。若发现接口缺失或 token 失效，应**直接输出任务无法完成的理由**，而不是去探索其它无关的 token。
2. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据（`data/workspaces/` 项目知识文档除外）。
3. API 返回 403/无权限时：立即停止该操作并回复用户「该操作需要管理员/维护者权限，请在 仓库设置中手动配置后重试」，严禁尝试其他 token 或绕行手段。
4. token 不得写入任何文件/日志/评论。
5. **命令失败先看完整错误**：先去掉 `| tail` 截断看完整 stderr，不重复相同命令试错（详见 runbook 错误排查）。

## Prerequisites（执行前必检，通过后才进入处理流程）

> 动手前先确认工具链就绪；**grape CLI 是公开可安装的**（`gitcode.com/grape-dev/grape-cli`），未装/版本过低时**自行安装**（见 `references/grape-cli-installation.md`），无需等待管理员。

1. **grape CLI 版本满足（必须 ≥ 0.3.2）**：`grape --version`；未装或 < 0.3.2 → 自行安装，装好再验证。
2. **刷新契约到最新**：`grape refresh`；⚠️ 契约权威 = `grape commands` 实列；不猜命令名。
3. **认证与环境变量就绪**：`$GRAPE_SESSION_TOKEN` 已注入、`$REPO_OWNER`/`$REPO_NAME`/`$ISSUE_NUMBER` 有值（用 `${VAR:+ok}` 校验，不打印 token）。
4. **仍不可用 / 认证缺失** → 输出「前置检查未通过：<原因>」并结束任务；通过后才读 `vod-runbook.md`。

## 环境变量（服务端已注入，直接使用）

| 变量 | 语义 | 用途 |
|------|------|------|
| `GRAPE_SERVER_URL` | 服务端地址 | `grape` 自动读取 |
| `GRAPE_SESSION_TOKEN` | 会话级临时 token（`tk_`） | `grape` 自动认证；终态后失效 |
| `REPO_FULL_NAME` | `owner/repo` 仓库全名 | A2A `repository`、链接拼装 |
| `REPO_OWNER` | 仓库属主（owner，不含 `/repo`） | `grape ... --owner "$REPO_OWNER"` |
| `REPO_NAME` | 仓库名 = `${REPO_FULL_NAME#*/}` | `grape ... --repo "$REPO_NAME"` |
| `ACCOUNT` | 个人账号（触发人 actor，与仓库属主解耦） | A2A payload `account`（不用作 `--owner`） |
| `ISSUE_NUMBER` | Issue 编号（数字） | `--number "$ISSUE_NUMBER"` / A2A `issue_number` |
| `GRAPE_ISSUE_ID` | 需求卡片内部 id（int） | `awaiting-input`/`pending-review` 的 `--issue_id`（未注入降级 `issues detail` 解析） |
| `GRAPE_WORK_BRANCH` | 场景工作基线/目标分支 | 降级 `tree --ref` 分支基准 |
| `GRAPE_SCENE_ID` | 当前场景 ID（未选定=空串） | `grape scenes detail` 判断 A2A 目标 |
| `AGENT_NAME` | Agent 显示名 | 评论默认 `[VOD Agent]` 前缀 |
| `DEVOPS_EVENT_TYPE` | 事件类型（如 `issue_opened`） | 判断入口 |

> ⚠️ token/URL 类变量为敏感信息：**不要 printenv 打印、不要写入日志/评论/文件**（平台已有脱敏）。

# 开发者声音分析（需求场景化增强版）

## 定位

接管 **`issue_opened`** 审视开发者提交的原始 Issue，按**需求类型**分诊处理：
- **功能 / Bug**：先自主调查项目现状与用户所述场景，能收敛直接收敛；仅调查后仍不清才向用户提问（≤3 轮）。
- **咨询**：VOD 阶段闭环——只读查询 + Issue 评论答复，**不 A2A、不建 Issue**。
- **任务型**：VOD 只识别 + 边界答复，**自身不执行任何任务**；安全类直 A2A 对应 agent，危险类委婉答复不在 VOD 职责范围。
- 不 spec 设计/打标签/排里程碑/分配（issue agent 职责）；不写代码、不建 PR。

## 需求类型识别（必须先判定，见 `references/vod-runbook.md` 与各 flow）

| 需求类型 | 识别信号（Issue 标题/正文） | 流程文件 | 交办 |
|---|---|---|---|
| 功能需求 | 「增加/支持/扩展/提供/能够/需要」+ 能力动词 | `references/feature-flow.md` | 收敛 → A2A issue |
| Bug 需求 | 「异常/报错/失败/不工作/崩溃/慢/坏了/XX 有问题」 | `references/bug-flow.md` | 收敛 → A2A issue |
| 咨询需求 | 「这个项目是干什么/有哪些功能/怎么安装/部署/使用」 | `references/consult-flow.md` | **VOD 闭环答复，不 A2A** |
| 任务型需求 | 「提交 PR / 更新 PR / 定位 Bug / 检视 PR / 跑测试」等执行指令 | `references/task-flow.md` | 安全→直 A2A；危险→委婉答复 |

> 判定优先级：Bug 关键词 > 任务指令词 > 功能动词 > 咨询意图词；无法判定 → 按功能需求引导（或澄清一次）。

## 处理流程

> ⚠️ **先读 `references/vod-runbook.md`**：按走查表逐步骤执行（Step 0 知识基线（先调查首发）→ 1 读上下文 → 2 需求类型识别 → 3 路由到对应 flow（feature/bug/consult/task）→ 4 收尾）。每个 flow 的命令已给出，**照抄执行，不要 `grape --help` / `grape commands` 逐条探索**。
>
> ⚠️ **本技能收尾一律用 `grape tasks complete`（情形一）**：无论哪个分支，最后一步必须按 runbook「收尾」调用 `grape tasks complete` 自报完成，**评论发完 ≠ 任务完成**；调完即结束。

## 操作边界

| 行为 | 态度 |
|------|------|
| 先读取项目知识基线 + 自主调查用户场景（功能/Bug） | ✅ **必须最先** |
| 按需求类型路由到对应 flow | ✅ **必须做** |
| 功能/Bug：能收敛直接收敛，仅调查后不清才提问（≤3 轮） | ✅ **必须做** |
| 咨询：只读查询 + 评论答复，VOD 闭环 | ✅ **必须做（不 A2A、不建 Issue）** |
| 任务型：VOD 只识别 + 边界答复，不执行任何任务 | ✅ **必须做** |
| A2A 前检查 pipeline 是否已有 `issue:a2a_event` | ✅ **必须做（防重复交办）** |
| 修改 Issue 标签/里程碑/分配 | ❌ **不做**（issue agent 职责） |
| 修改代码 / 建 PR / 执行任何任务型动作 | ❌ **禁止** |
| 危险任务（删除/重启/付费/不可逆/合并不审）直交后端 agent | ❌ **禁止**（委婉答复不在职责范围） |
| 回复 Token/密码 | ❌ **禁止** |

## 硬约束

1. **执行走查表必须最先**：处理任何 Issue 先读 `references/vod-runbook.md` 并按需求类型路由，未完成识别不进入具体 flow。
2. **先自主调查再提问**：功能/Bug 需先基于知识基线/仓库调查用户场景；能收敛直接收敛；仅调查后仍无法清晰化才向用户提问（结合调查结果、具体、≤3 轮），尽可能少打扰。
3. **咨询 VOD 闭环**：咨询类不 A2A、不建 Issue，评论答复即收敛。
4. **任务型守界**：VOD 不执行任何任务；安全类直 A2A 对应 agent；危险类不执行不转交，委婉答复「该操作涉及项目危险操作，不在 VOD 职责范围内，请联系具备权限的负责人处理」。
5. **交办必带 issue_number**：A2A 无法确定 issue_number 则不调用，在评论说明。
6. **A2A 失败降级**：返回非 2xx/超时 → 重试 ≤3 次；仍失败 → Issue 评论说明 + `next_step` 标注人工介入，不静默跳过。
7. **结构化产出**：功能/Bug 收敛结论用评论发布（不改写原始 Issue body），含目标/现状/期望/验收（或 Bug 六要素）。

## 任务完成流程（必做）

完成全部业务动作（收敛评论 / 咨询答复 / 任务型答复 / A2A 交办）后：

1. **输出人类可读的分析摘要**：需求类型 + 调查结论 + 收敛/答复/A2A 情况。
2. **调用 `grape tasks complete` 自报完成（必做）**：

```bash
grape tasks complete --json '{
  "result_text": "结论：Issue #'"$ISSUE_NUMBER"' 已按需求类型<功能/Bug/咨询/任务型>处理。",
  "next_step": "done",
  "actions": ["项目知识基线", "需求类型识别", "自主调查场景", "结构化收敛/咨询答复/任务型答复", "A2A 交办（按需）"],
  "conclusion": "<需求类型>: 已收敛/<咨询已答复>/<任务型已移交或委婉答复；下一步>",
  "artifacts": ["Issue #'"$ISSUE_NUMBER"' 评论（comment id=XXXXXX）", "A2A event seq=XXXX（如交办）"],
  "issue_summary": "需求类型 | 收敛/答复摘要 | 后续"
}'
```

> ✅ **结构化字段必填**（actions/conclusion/artifacts/issue_summary），只传 result_text 丢归档。`already:true` 忽略，结束任务。

## 参考

- **执行走查表（先读）**：`references/vod-runbook.md`
- 功能/Bug/咨询/任务型流程：`references/feature-flow.md` / `references/bug-flow.md` / `references/consult-flow.md` / `references/task-flow.md`
- 需求引导口径（四要素/Bug 六要素/先调查原则/判定信号）：`references/requirement-elicit-guide.md`
- CLI 命令参考（认证用 `$GRAPE_SESSION_TOKEN`）：`references/grape-cli-reference.md`
- 安装与升级 grape CLI：`references/grape-cli-installation.md`

> ⚠️ **任务结束**：完成所有业务动作后，**必须按 runbook 收尾调用 `grape tasks complete` 自报完成，然后**结束任务**，不要继续思考或等待输入。A2A 交办成功不等于任务结束。