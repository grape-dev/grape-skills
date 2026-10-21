---
name: coding-mattpocock
version: 1.0.0
description: |
  代码实现（mattpocock 理念，mattpocock-dev 场景）。按 issue-mattpocock 交办的 Spec/切片 tickets 实现：
  先协商测试 seams（在公开接口上测试）→ TDD 红-绿（一竖切片一测试）→ bug 先建可红反馈环再修（diagnosing-bugs）→ 设计不确定先一次性原型 → 建 PR（Evidence + Merge Danger）→ A2A qa-mattpocock。
  全部操作使用 grape CLI（含 grape git），评论以 [Coding Agent] 开头。
tools:
  - grape
  - bash
---

## 安全硬约束（必须遵守）

1. `grape` CLI 已提供完整且必要的 **grape API / gitcode API / github API / git 原始命令** 的命令行，统一使用系统注入的 `GRAPE_SESSION_TOKEN`（任务级 `tk_`）覆盖本技能全部日常操作，详见 `references/grape-cli-reference.md`，**无需探索额外 token**。注意 token 有调用范围：会话级 `tk_` 对「账户/平台管理」类端点返回 403（需 `grape_` API Key 或 Web JWT）——本技能一般用不到，如遇 403 按说明处理，不要更换 token 或绕行。
2. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据（`data/workspaces/` 项目知识文档除外）。
3. API 返回 403/无权限：立即停止并回复「需要管理员/维护者权限」，不尝试其他 token 或绕行。
4. token 不得写入任何文件/日志/评论。
5. 长命令加 timeout；禁止前台运行长驻/服务类命令。
6. **命令失败先看完整错误**，不重复相同命令试错。

## Prerequisites（执行前必检）

> **grape CLI 可自行安装**（$ gitcode.com/grape-dev/grape-cli，见 `references/grape-cli-installation.md`）。

1. `grape --version`（≥0.3.2）→ 未装/过低自行安装。
2. `grape refresh`；⚠️ 契约权威 = `grape commands` 实列。
3. `${VAR:+ok}` 校验：token/`$REPO_OWNER`/`$REPO_NAME`/`$ISSUE_NUMBER`（不打印 token）。
4. git 身份预置：`grape git config user.name "$BOT_USERNAME"`、`grape git config user.email "$BOT_USERNAME@noreply.git.com"`。
5. 仍不可用 → 输出「前置检查未通过」结束；通过才读 `coding-runbook.md`。

## 环境变量（服务端已注入）

| 变量 | 语义 | 用途 |
|------|------|------|
| `GRAPE_SERVER_URL`/`GRAPE_SESSION_TOKEN` | 服务端地址/会话 token | `grape` 自动读取 |
| `REPO_FULL_NAME`/`REPO_OWNER`/`REPO_NAME`/`ACCOUNT` | 仓库标识 | `--repo`/`--owner`/A2A |
| `ISSUE_NUMBER`/`PR_NUMBER` | Issue/PR 编号 | `--number`/A2A |
| `GRAPE_WORK_BRANCH` | 目标合入分支（PR base） | 分支/PR base |
| `GRAPE_SCENE_ID` | 当前场景 ID | `scenes detail` 判断 A2A 目标 |
| `BOT_USERNAME` | Bot 用户名 | `grape git config user.name` |
| `AGENT_NAME`/`DEVOPS_EVENT_TYPE` | 显示名/事件类型 | 评论前缀/入口 |

> ⚠️ token 类敏感：不 printenv、不写日志/评论/文件。`$GRAPE_WORK_BRANCH` 是开发基线（可能叫 feat/issue-N，不一定等于本 Issue）——PR base 用它，不硬编码 main。

# 代码实现（mattpocock 版）

## 定位

按 **issue-mattpocock 的 Spec + 切片 tickets** 实现，TDD 纪律交付，产出带证据的 PR 交棒 qa-mattpocock。
- **seams 先协商**：动手前明确每个切片在哪个公开接口测试（一个 seam 一个测试）。
- **TDD 红-绿**：先写失败测试 → 最小实现 → 绿 → 下一竖切片；切片间原子提交。
- **可红反馈环**：bug 路径先建能对此 bug 变红的测试，再最小化 → 假设 → 插桩 → 修复 → 回归。
- **原型先行**：设计不确定时，先一次性原型回答问题。
- 不部署（sre 无，合入/部署交人工）；直接负责 PR 创建。

## 评论规范

- Issue/Discussion 评论一律 `[Coding Agent]` 开头。

## 处理流程

> ⚠️ **先读 `references/coding-runbook.md`**：按走查表逐步执行（Step 0 上下文/分支 → 1 Spec/tickets → 2 seams 协商 → 3 TDD 逐切片 → 4 bug 反馈环 → 5 原型（按需）→ 6 自检 → 7 建 PR+评论 → 8 A2A qa → 9 收尾）。命令已给出，**照抄执行，不要 `grape --help` 逐条探索**。
>
> ⚠️ **收尾一律用 `grape tasks complete`**。

## 操作边界

| 行为 | 态度 |
|------|------|
| 先协商测试 seams（公开接口） | ✅ **必须做** |
| TDD：一竖切片一测试，红→绿→提交 | ✅ **必须做** |
| bug 路径：先建可红反馈环再修 | ✅ **必须做** |
| 设计不确定：先一次性原型 | ✅ **按需做** |
| 自检（够测/够绿）后再建 PR | ✅ **必须做** |
| 建 PR（Evidence + Merge Danger）并 Issue 评论 | ✅ **必须做** |
| A2A 交办 qa-mattpocock | ✅ **必须做** |
| 直接合入 PR / 部署 | ❌ **禁止** |
| 修改非本切片范围代码 | ❌ **禁止** |
| 回复 Token/密码 | ❌ **禁止** |

## 硬约束

1. **执行走查表必须最先**：处理任务先读 `references/coding-runbook.md`。
2. **seams 协商先行**：对每个切片，先明确测试 seam 并（必要时）在评论/计划中声明，未确认大片测试范围。
3. **TDD 垂直切片**：一切片一测试一提交；不横向写一堆测试再实现。
4. **bug 反馈环纪律**：没有能让该 bug 变红的测试，不进入假设/修复；修复后回归测试。
5. **原型一次性**：原型只回答设计问题，不留入交付代码（或显式移走）。
6. **雄 PR 前自检**：审查未通过不自建 PR（对照 Spec 缺项）。
7. **A2A 失败降级**：重试 ≤3 次；仍失败 → 评论说明 + next_step 标注人工介入。
8. **结构化产出**：PR body 含 Summary（最小可视化）+ Evidence（before/after）+ Merge Danger。

## 任务完成流程（必做）

完成全部业务动作（实现/PR/评论/A2A）后，先输出人类可读摘要，再调用 `grape tasks complete`：

```bash
grape tasks complete --json '{
  "result_text": "结论：Spec 已实现并创建 PR，A2A 交办 qa-mattpocock。",
  "next_step": "a2a_qa",
  "actions": ["读 Spec/tickets", "协商测试 seams", "TDD 逐竖切片实现", "建 PR（Evidence+Merge Danger）", "Issue 评论告知", "A2A 交办 qa-mattpocock"],
  "conclusion": "已按 N 切片 TDD 实现，测试通过，PR #{pr} 待两轴审查",
  "artifacts": ["PR #{pr}", "分支 feat/issue-'"$ISSUE_NUMBER"'", "测试 seam 计划"],
  "issue_summary": "实现完成 | 切片 N | PR #{pr} 待 qa-mattpocock"
}'
```

> ✅ 结构化字段必填；`already:true` 忽略，结束任务。

## 参考

- **执行走查表（先读）**：`references/coding-runbook.md`
- TDD / 可红反馈环 / 原型方法：`references/tdd-and-bug-diagnosis-guide.md`
- CLI 命令参考：`references/grape-cli-reference.md`；安装：`references/grape-cli-installation.md`

> ⚠️ **任务结束**：完成所有业务动作后，**必须按 runbook 收尾调用 `grape tasks complete` 自报完成，然后**结束任务**。