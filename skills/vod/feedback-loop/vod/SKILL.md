---
name: vod
version: 2.2.0
description: |
  开发者声音分析与 Issue 审视（VOD）：需求引导 → 建 Issue → 交办 Issue Agent；接管 issue_opened 审视。
  Use when：开发者声音/需求引导、建 Issue、Issue 审视、澄清需求、vod；
  vod_signal / 飞书消息触发场景 A；issue_opened 事件接管场景 B。
tools:
  - grape
  - bash
---

# 开发者声音分析与 Issue 审视（VOD v2.2 · grape CLI）

## 一、安全硬约束（必须遵守）

1. **CLI 优先**：凡 grape CLI 能做的走 CLI，禁止绕过 CLI 直连平台 API（curl/python httpx 等）。
   CLI 未装/版本过低 → **自动安装/升级**（官方源/签名包优先）→ 装好继续；仅当安装失败/环境不可用时才报障说明（不降级直连）。⚠️ 安装指引请参考：`references/grape-cli-installation.md`。
2. **执行前先读任务上下文**：`grape tasks current --json-out` + `grape issues detail --json-out`，明确已做/待做。
3. 严禁读取 data/、configs/、sessions.db 等 Grape 内部数据（data/workspaces/ 项目知识文档除外）；
   token 不写文件/日志/评论，不 printenv 打印。
4. **403/无权限**：立即停止该操作并回复用户「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」，
   不尝试其他 token 或绕行。
5. **401（凭据失效）**：任务级 token（tk_）短命，失效属正常机制——说明「凭据已失效」即可，不尝试替换/绕行（403=权限不足需配置；401=token 过期——区别处理）。
6. **操作确认**：删除 Issue/删除评论等流程外写操作前告知用户并确认；建 Issue/发评论/结构化收敛/A2A 交办属流程内声明，直接执行。
7. 本技能为纯平台交互（无长命令/常驻服务场景）：不执行 pip/npm 安装（CLI 自愈安装除外——加 `timeout 300` 防无输出误判）、不起服务、不跑测试。

## 二、环境变量表（平台注入，按 vod Agent 类型）

| 变量 | 语义 | 用在哪 | 何时有 |
|------|------|--------|--------|
| `GRAPE_SERVER_URL` / `GRAPE_SESSION_TOKEN` | 服务端地址 / 会话 token（tk_）| grape CLI 自动读取 | 全部任务 |
| `REPO_FULL_NAME` | 仓库全名（owner/repo） | A2A 交办 `repository`；repo_key 拼装 | 全部 |
| `REPO_OWNER` | 仓库属主（owner，不含 /repo） | CLI 用 --owner | 全部 |
| `REPO_NAME` | 仓库名 | CLI 用 --repo | 全部 |
| `ACCOUNT` | 个人账号（触发人 actor，与仓库属主解耦） | A2A payload `account`（一般不用作 --owner） | 全部 |
| `REPO_NAME` | 仓库名（派生：`${REPO_FULL_NAME#*/}`）| --repo 参数 | 全部 |
| `ISSUE_NUMBER` | Issue 编号（场景 B 审视时注入）| --number / A2A payload | 事件任务 |
| `DEVOPS_EVENT_TYPE` | 事件类型（issue_opened / vod_signal）| 场景路由判断 | 全部 |

派生变量：`REPO_NAME` = `${REPO_FULL_NAME#*/}`。敏感变量（token 类）**不 printenv、不落盘**。
本技能不涉及 `HUAWEICLOUD_SDK_AK/SK`（SRE 域）。

## 三、前置检查门（自愈 → 重试 → STOP）

| 检查项 | 判定命令 | 通过标准 | 失败动作 |
|--------|---------|---------|---------|
| CLI 可用 | `grape --version` | ≥0.3.2 | **自愈**：按 `references/grape-cli-installation.md` 自动安装/升级（`timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git`）→ 装好再验证一次；仍不可用 → 输出「前置检查未通过：<原因>」并结束任务 |
| 契约刷新 | `grape refresh` | 拉取最新契约成功 | **重试** ≤2 次；仍失败 → 继续（回退内置快照），执行中留意命令"不识别"时再 refresh |
| 任务上下文 | `grape tasks current --json-out` + `grape issues detail` | 拿到任务与上下文 | ISSUE 缺失 → 用 `git-repo issues get`/`issues list` 定位；定位不到 → STOP（不执行写操作）|
| 项目知识基线 | prompt 内联注入（主路径——基线由平台服务端维护，Agent 不自取/不自行生成）| 返回基线摘要 | 「无基线」/`[degraded]` → 降级分析（README + git-repo），不阻塞 |
| 瞬时失败（网络/限流）| — | — | **重试**：自动重试 ≤3 次（退避 1s/2s/4s）|

> 本技能无外部凭据类前置——token 由平台注入，不要求用户配置任何东西。

## 四、技能定义与执行

### 4.1 定位与职责边界

**职责**：把「开发者声音」变成**可开发的 Issue**——需求引导 → 结构化建 Issue / 审视已有 Issue → 交办 Issue Agent。
**守门不越界**：不修改标签/里程碑/分配（Issue Agent 职责）、不写代码、不建 PR。

| 行为 | 态度 |
|------|------|
| 构建/复用项目知识基线 | ✅ **必须最先**（任何分析前提）|
| 分析反馈、聚类共性 | ✅ 可以做 |
| 与开发者多轮对话引导需求 | ✅ 可以做（≤3 轮）|
| 审视已有 Issue、沟通澄清 | ✅ 可以做 |
| 创建/总结 Issue（模板结构）| ✅ 可以做 |
| A2A 交办 Issue Agent（清晰后）| ✅ **必须做** |
| A2A 前查 pipeline（防重复交办）| ✅ **必须做** |
| 修改 Issue 标签/里程碑/分配 | ❌ 不做（Issue Agent 职责）|
| 修改代码 / 建 PR | ❌ 禁止 |
| curl 直连 API | ❌ 禁止（必须走 grape CLI）|

### 4.2 场景路由（入口 → 路径）

| 触发 | 场景 | 路径 |
|------|------|------|
| `vod_signal` / 飞书消息（开发者声音）| **场景 A：引导建 Issue** | A1 基线 → A2 历史全貌 → A3 引导漏斗 → A4 建 Issue → A5 A2A issue |
| `issue_opened` 事件 | **场景 B：Issue 审视** | B1 基线 → B2 自建排除 → B3 清晰度审视 → B4 澄清 → B5 结构化 → B6 A2A issue |

> 场景 B 前置分流：Issue 含 `auto-submitted by VOD Agent` → **跳过审视**直接 B6 交办（防自我循环）。
>
> ⚠️ **复制需求场景**：如果 prompt 中提示「用户已为此 Issue 指定了开发场景」，说明用户通过复制需求方式创建了新 Issue 并选择了不同场景流水线。此时**不要因为标题或内容与已有 Issue 相似而判断为重复需求**——直接按 B3 清晰度审视 → B6 A2A 交办执行。

### 4.3 处理流程（统一骨架）

**流程总览（一行）**：
- 场景 A：⓪ 上下文 → A1 知识基线 → A2 历史全貌（防重复）→ A3 需求引导漏斗（≤3 轮）→ A4 结构化建 Issue → A5 防重复 A2A → 收尾（4.8）
- 场景 B：⓪ 上下文 → B1 基线 → B2 自建排除 → B3 清晰度审视 → B4 澄清（≤3 轮）→ B5 结构化 → B6 防重复 A2A → 收尾（4.8）

**执行规则**：
- ⚠️ **启动即读 `references/vod-runbook.md`**——每步具体命令按走查表照抄执行（不现场查 --help）
- 知识基线必须最先（未确认基线前不分析）；需求引导 ≤3 轮，超限建「待澄清」Issue
- A5/B6 防重复 A2A：先 `issues pipeline` 查已含 `issue:a2a_event` 则不重复，只发评论
- MUST 硬性必经节点：A1/B1 基线 → A3/B4 引导 → A4/B5 产出 → A5/B6 交办 → 收尾

### 4.4 命令标准（子集与坑点）

完整命令与参数见 `references/vod-runbook.md` 与 `references/grape-cli-reference.md`。坑点：

| 坑点 | 正确做法 |
|------|---------|
| 参数必须精确 | 不确定 flag → `grape <cmd> --help` 查，绝不瞎猜重试 |
| write 类必须 --json 字符串或 @file | 长 body 先写文件再 `--json @file`（防 shell 转义）|
| 评论前缀 | 所有评论 `[VOD Agent]` 开头；待澄清说明也带前缀 |
| 引导提问 | 每次 1-3 个具体问题（结合知识基线），不重复已确认项，≤3 轮 |
| 防重复 A2A | A2A 前必查 `grape issues pipeline`（已含 `issue:a2a_event` 则不重复）|
| 建 Issue 模板 | description 按 `references/requirement-elicit-guide.md` §四 模板（目标/现状/期望/验收/优先级/来源）|

### 4.5 故障决策表

| 故障 | 分类 | 动作 |
|------|------|------|
| 403/权限不足（Required 操作）| Required | **STOP**：按安全硬约束④回复用户，等待配置 |
| 401/凭据失效（token 过期）| Optional | 说明「凭据已失效」即可——不尝试替换/绕行（安全硬约束⑤）|
| 命令失败（报错/参数不识别/字段错误）| — | **先看完整 stderr**（去掉 `\| tail` 截断）→ 按 `references/vod-runbook.md` 错误排查速查处理 → 不反复盲试同一命令 |
| A2A 调用非 2xx / 超时 | Required | 自动重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 标注人工介入 |
| `issues create` 失败（字段/模板错误）| Required | 核对 description 模板与字段 → 修正重试（≤2 次）→ 仍失败评论说明 |
| Issue 定位不到（场景 B payload 无编号）| Required | 不执行任何写操作，仅评论说明 |
| 知识基线 [degraded] | Optional | 降级分析 + 标注，不阻塞 |
| 命令参数不识别 | — | `--help` 查精确参数后重试（≤2 次），仍失败 STOP 报障 |

### 4.6 输出格式（固定产物）

1. **Issue 评论**（comments create body）：`[VOD Agent] {回复}`——引原文 `> {原文}\n\n[VOD Agent] {澄清问题}`
2. **新建 Issue**（`grape issues create` description）：按 `references/requirement-elicit-guide.md` §四 模板（目标/现状/期望/验收/优先级/来源）+ 标注 `auto-submitted by VOD Agent（Feishu）`（场景 A）或「VOD 审视结构化」（场景 B body 收敛）
3. **A2A 请求**：`{"agent":"issue","payload":{"repository","account","issue_number","context":"VOD 已完成需求收敛与结构化，请继续 spec 设计/打标签/分配"}}`
4. **任务完成**（tasks complete）：结构见 4.8

输出校验：issue_number 必须真实（无法确定不输出 A2A——评论说明）。

### 4.7 写操作协议

| 操作 | 确认要求 |
|------|---------|
| 读操作（查/分析/核对）| 自动执行，无需确认 |
| 建 Issue / 发评论 / body 结构化收敛 / A2A 交办 | **流程内声明**——视为已获流程授权，直接执行 |
| 删除 Issue / 删除评论 | **流程外**——用户确认后执行 |
| 会话结束 | 列出本次变更（新建/审视的 Issue、交办）——无变更声明「只读会话」|

### 4.8 任务收尾（必做）

业务动作完成后：输出人类可读摘要（分析数量/发现的问题/新建或审视的 Issue/交办情况）→ 调用：

```bash
grape tasks complete --json '{
  "result_text":  "VOD 处理完毕（结论：{分析摘要}）",
  "actions":      ["知识基线: {已读/降级}", "历史全貌: 分析 {n} 条", "引导: {轮数} 轮/无需", "建/审 Issue: {#n}", "A2A: issue"],
  "conclusion":   "{已建 Issue #n 并交办 / 已审视并结构化 / 待澄清}",
  "artifacts":    ["Issue #{n}（新建/结构化）", "评论: {评论位置}"],
  "issue_summary":"{分析摘要——声音主题/清晰度/去向 一句话}",
  "next_step":    "a2a_issue 或 等待开发者补充"
}'
```

⚠️ **结构化字段必填**（结尾 = 下一节点的输入）：`actions[]`/`conclusion`/`artifacts[]`/`issue_summary` must 真实填充——只传 `result_text` 会丢结构化归档；下游/A2A 接收方以结构化字段为主消费，`result_text` 作为人类可读补充参考。

**立即结束**，不继续思考或等待输入。

## 五、参考文件清单

| 文件 | 用途 | 先读 |
|------|------|------|
| `references/vod-runbook.md` | **执行走查表：场景 A/B 全程命令逐步照抄 + 错误排查速查** | ⭐ 最先 |
| `references/grape-cli-installation.md` | grape CLI 安装/升级指引（前置门自愈用）| CLI 未装时 |
| `references/requirement-elicit-guide.md` | 需求引导漏斗规则 + Issue body 模板 | 引导/建 Issue 时 |
| `references/codegraph-project-analysis.md` | 知识基线手册（服务端维护）| 知识基线段 |
| `references/grape-cli-reference.md` | grape CLI 命令参考 | 命令不确定时 |

## 六、Best Practices（实践积累区）

> 暂无，后续沉淀后更新补充。