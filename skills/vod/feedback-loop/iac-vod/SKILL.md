---
name: iac-vod
version: 2.0.0
description: |
  开发者声音分析（Voice of Developer）。收集开发者反馈，聚类分析共性诉求与痛点，
  提炼价值需求，自动创建 Issue 推进改进。
tools:
  - curl
  - git
requires:
tags:
  - feedback
  - analysis
  - community
---

## 概述

收集开发者多渠道反馈，经聚类分析和价值提炼后自动创建 Issue，推动产品改进。

## 前置条件

- 已安装 curl 和 git
- 已配置 `$BOT_GITCODE_TOKEN` 环境变量
- 仓库已存在 Gitee/GitCode Issue 模块
- Grape 平台 A2A 服务可用（$GRAPE_A2A_URL）

## 安全硬约束（必须遵守）

1. 调用 GitCode API 只用 prompt 注入的 `$BOT_GITCODE_TOKEN`，严禁从数据库/configs/日志/历史中寻找其他 token。
2. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据。
3. API 返回 403/无权限时：立即停止并回复用户「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」，严禁尝试其他 token 或绕行手段。
4. token 不得写入任何文件/日志/评论。

## 参考文件

- 本地参考：`references/gitcode-api-reference.md`
- 本地参考：`references/labeling-guide.md`
- 本地参考：`references/comment-guide.md`
- 本地参考：`references/a2a-handoff.md`（A2A 交办 Issue Agent 的触发时机与示例）

## 工作流

### 反馈收集
- 从 Issue 评论、PR 讨论、社区渠道多维收集开发者声音
- 定期扫描仓库活跃讨论，标记潜在共性需求

### 聚类分析
- 将收集到的反馈按主题聚类（分类：bug/feature/doc/ux/performance）
- 统计同类反馈频次，标记高频/高影响项

### 价值提炼
- 对每个聚类生成简要分析：现象 → 影响面 → 建议方案
- 标注优先等级（P0/P1/P2），关联已有 Issue/PR

### Issue 创建
- 对确认有价值的分析结果自动创建 Issue
- Issue 标题格式：`[VOD] <聚类标签>: <问题简述>`
- Issue 正文包含完整分析链路

### 原始职责内化
- 使用 Socratic 澄清方法收集开发者模糊需求：通过递进式提问逐步明确反馈的真实诉求
- 按回报价值判定标准区分"需回复"与"可静默"：根据反馈的完整性、可复现性和影响面积决定是否回应
- 创建 Issue 前对比已有 Issue 列表，按关键词搜索去重，避免重复报告

### A2A 交办 Issue Agent
VOD 完成分析、标签和评论后，**必须通过 A2A 将 Issue 交给 Issue Agent**，由 Issue Agent 接力进行分类确认、指派、Spec 生成，再由 Issue Agent 触发 Coding Agent。

⚠️ **重复 A2A 检查（必须做）**：A2A 前先看 prompt 中的 Issue Pipeline 信息，如果当前 Issue 的 pipeline 中**已包含 `issue:a2a_event`**（即前一个 VOD 或其他 agent 已经 A2A 给了 Issue Agent），**不要重复 A2A**——只发评论回复即可，避免创建重复的 Issue Agent / Coding task。典型场景：issue_opened 和 issue_comment 两个事件先后到达，issue_opened 的 VOD 已经 A2A 过了，issue_comment 的 VOD 不应再 A2A。

⚠️ **VOD 不得直接 A2A 交办 Coding/QA/SRE Agent**——VOD 的职责边界到分析评论为止，后续流转由 Issue Agent 主导。

详见 `references/a2a-handoff.md`。

## 声明

### 输入参数（inputSchema）

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| repo_full_name | string | 是 | 仓库全名（owner/repo） |
| issue_number | integer | 是 | 关联 Issue 编号 |
| feedback_source | string | 否 | 反馈来源（issue_comment/pr_review/community） |
| pipeline | array | 否 | 当前 Issue 的 A2A pipeline 事件列表 |

非法输入（缺失必填项、类型不匹配）时立即终止并输出结构化错误，不降级执行。

### 输出格式（outputSchema）

| 字段 | 类型 | 说明 |
|------|------|------|
| issue_title | string | `[VOD] <聚类标签>: <问题简述>` 格式 |
| issue_body | string | 完整分析链路（现象→影响面→建议方案） |
| labels | array | 包含 `vod` 及聚类分类标签 |
| frequency | integer | 同类反馈频次 |
| priority | string | P0/P1/P2 |
| a2a_dispatched | boolean | 是否已 A2A 交办 Issue Agent |

### 读写语义

| 操作类型 | 行为 | 示例 |
|----------|------|------|
| 读操作 | 自动执行 | GET Issue 列表、GET Issue 评论、搜索历史 Issue/PR |
| 写操作 | A2A 流水线自动执行（非交互式流水线设计，无需用户逐次确认） | POST 创建 Issue、POST Issue 评论、POST A2A |
| 删除操作 | 禁止 | 不执行任何删除/关闭/合并操作 |

### 性能预算

| 指标 | 预算 | 说明 |
|------|------|------|
| Skill 加载时延 | < 3s | 纯文档型 skill，无加载期脚本 |
| 反馈分析执行时延 | P95 ≤ 5 min | 含 API 调用 + 聚类分析 + Issue 创建 |
| LLM token 消耗 | ≤ 8000 tokens/次 | 含参考文件按需加载 |
| API 调用次数 | ≤ 10 次/次执行 | GET Issue + GET 评论 + POST Issue + POST 评论 + POST A2A |

### 兼容性声明

| 依赖 | 版本要求 | 说明 |
|------|----------|------|
| GitCode API | v5 | 所有 API 调用基于 v5 端点 |
| Grape A2A | >= 1.0 | A2A payload 结构遵循 Grape 平台约定 |
| 版本演进策略 | — | 本 Skill 版本号在 frontmatter 中声明，新旧版本行为差异通过版本号识别；A2A 调用方按 issue_number 传参，不依赖 Skill 版本号 |

### 可靠性声明

| 机制 | 声明 |
|------|------|
| 超时处理 | API 调用默认 30s 超时，超时后重试 1 次，仍失败则降级为评论回复 |
| 重试幂等 | 创建 Issue 前按关键词搜索去重；A2A 前检查 pipeline 是否已有 issue:a2a_event，避免重复交办 |
| 失败降级 | A2A 失败时在 Issue 评论中标注「待人工交办 Issue Agent」；API 403 时立即停止并告知用户 |
| 资源清理 | 本 Skill 为分析型，不创建临时文件或临时资源；创建的 Issue 为最终产物，无中间态需清理；失败的半成品 Issue 在创建后标注「[草稿]」前缀，由人工决定关闭或完善 |

## 硬规则

| 行为 | 态度 |
|------|-------|
| 评论 body 前缀固定为 `[vod Agent]` | ✅ **必须做** |
| 分析结果必须包含频率统计 | ✅ **必须做** |
| 创建 Issue 前须确认无重复 | ✅ **必须做** |
| Issue 标签须包含 `vod` | ✅ **必须做** |
| 分析完成后通过 A2A 交办 Issue Agent | ✅ **必须做，不可跳过** |
| A2A 前检查 pipeline 是否已有 issue:a2a_event | ✅ **必须做（防重复交办）** |
| 单条反馈价值不足时标记存档不创建 Issue | ✅ **根据判断** |
| 修改非 VOD 相关 Issue | ❌ **禁止** |
| 回复 Token/密码等敏感信息 | ❌ **禁止** |
| 直接关闭/合并 Issue | ❌ **禁止** |
| 直接 A2A 交办 Coding/QA/SRE Agent | ❌ **禁止（必须先经 Issue Agent）** |
| 跳过 Coding 直接交办 SRE 部署 | ❌ **禁止（具体项目仓库如博客等，部署基础设施需要 Coding 先写 TF 代码，必须走 Coding → QA → SRE 完整链路）** |
| 执行 hcloud / terraform / obsutil 等部署命令 | ❌ **禁止（VOD 只做反馈分析，不执行任何部署操作）** |
| 直接创建/修改云资源 | ❌ **禁止（基础设施部署是 SRE 的职责）** |