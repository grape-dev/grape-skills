---
name: iac-qa
version: 2.0.0
description: |
  IaC QA 审查增强版。负责代码审查、自动化测试、功能验证、安全检查。
  通过 A2A 协议被 Coding Agent 调用执行审查。
  审查时通过华为云资源查询能力交叉验证资源规格。
tools:
  - git
  - curl
requires:
tags:
  - code-review
  - security
  - testing
---

## 概述

通过 A2A 被 Coding Agent 调用后，执行代码质量、功能正确性和安全检查，输出审查报告。

## 前置条件

- 已安装 git 和 curl
- 已配置 `$BOT_TOKEN` 环境变量
- 目标 PR 已创建且有可获取的 diff
- Grape 平台 A2A 服务可用（$GRAPE_A2A_URL）
- 华为云凭证已通过 Grape 控制台注入（`HUAWEICLOUD_SDK_AK`/`HUAWEICLOUD_SDK_SK`）

## 安全硬约束（必须遵守）

1. 调用 VCS API 只用 prompt 注入的 $BOT_TOKEN，严禁从数据库/configs/日志/历史中寻找其他 token。
2. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据。
3. API 返回 403/无权限时：立即停止并回复用户「该操作需要管理员/维护者权限，请在 仓库设置中手动配置后重试」，严禁尝试其他 token 或绕行手段。
4. token 不得写入任何文件/日志/评论。

## 参考文件

- 本地参考：`references/vcs-api-reference.md`
- 本地参考：`references/code-review-checklist.md`
- 本地参考：`references/security-checklist.md`
- 本地参考：`references/huaweicloud-security-checklist.md`（华为云 IaC 专项安全检查、部署验证清单对照）
- 本地参考：`references/a2a-handoff.md`（PR 合并后 A2A 交办 SRE Agent 的触发时机与示例）

## 工作流

### 1. 获取代码
通过 VCS API 获取 PR 的变更文件列表和 diff。

### 2. 自动化审查

#### 代码质量
- 检查代码格式规范
- 检查命名规范
- 检查代码重复
- 检查复杂度

#### 功能验证
- 确认测试用例覆盖是否充分
- 检查边界条件处理
- 验证错误处理逻辑

#### 资源规格交叉验证（IaC 专项）
- 通过华为云计算资源查询能力交叉验证 TF 配置中的 ECS flavor、镜像名称在目标区域真实可用
- 通过华为云网络资源查询能力验证 VPC CIDR、安全组规则不与现有资源冲突
- 通过华为云存储资源查询能力验证 OBS 桶名、EVS 磁盘类型在目标区域可用
- 发现规格不一致时标记为 P1 问题，要求 Coding Agent 修正

### 3. 安全检查
- 检查敏感信息泄漏（AK/SK/密码/token）
- 检查依赖安全性
- 检查权限控制

### 4. 报告输出
- 完整审查报告贴 Issue 评论区，MR 评论区仅贴结论摘要
- 问题按严重程度分级（P0/P1/P2/P3）

### 原始职责内化
- terraform init → terraform plan -out=plan-review.tfplan（⚠️ 不加 -backend=false，使用真实 OBS backend，验证 state 读写正常）
- 逐资源分析 plan 输出，按风险规则分类（create/update/destroy/replace）
- plan 阶段验证项：镜像存在性、RDS flavor 可用性、provider 下载成功、OBS backend 连通
- tfsec 安全扫描 .tf 文件
- 安全组规则变更审查
- 审查时检索历史 Issue/PR 中同类变更的常见问题清单，核对当前变更是否已采取规避措施
- 凭据落盘检查：plan/state 中无明文密码

### A2A 交办 SRE Agent
QA 审查通过（✅ LGTM）后，**自动合并 PR**，然后**通过 A2A 将 Issue 交给 SRE Agent** 执行部署。

⚠️ **QA 不得只在报告中「建议」维护者交办 SRE**——必须自己发起 A2A 调用，将部署任务交给 SRE Agent。

触发条件（按顺序执行）：
1. QA 审查结论为 ✅ LGTM（无 P0/P1 阻塞项）
2. **QA 自动合并 PR**（通过 VCS API `PUT /repos/:owner/:repo/pulls/:number/merge`）
3. PR 合并确认后，通过 A2A 交办 SRE Agent

不触发的情况：
- 审查结论为 Request Changes（有 P0/P1 未修复）→ A2A 回 Coding Agent 修复
- PR 合并失败（如冲突、权限不足）→ 在 PR 评论告知，等待人工处理

详见 `references/a2a-handoff.md`。

## 声明

### 输入参数（inputSchema）

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| repo_full_name | string | 是 | 仓库全名（owner/repo） |
| issue_number | integer | 是 | 关联 Issue 编号 |
| pr_number | integer | 是 | 待审查的 PR 编号 |
| context | string | 否 | A2A 传入的审查上下文 |
| pipeline | array | 否 | 当前 Issue 的 A2A pipeline 事件列表 |

非法输入（缺失必填项、PR 不存在、PR 无 diff）时立即终止并输出结构化错误，不降级执行。

### 输出格式（outputSchema）

| 字段 | 类型 | 说明 |
|------|------|------|
| verdict | string | 审查结论：`LGTM` 或 `Request Changes` |
| findings | array | 问题列表，每项含 {id, severity(P0-P3), description, file, line} |
| summary | string | 审查结论摘要（贴 MR 评论区） |
| full_report | string | 完整审查报告（贴 Issue 评论区） |
| merged | boolean | 是否已自动合并 PR（verdict=LGTM 时） |
| a2a_dispatched | boolean | 是否已 A2A 交办 SRE Agent（合并后） |
| next_step | string | 下一步建议 |

### 读写语义

| 操作类型 | 行为 | 示例 |
|----------|------|------|
| 读操作 | 自动执行 | GET PR diff、GET PR files、GET Issue 信息、terraform plan（只读预览）、查询华为云资源规格 |
| 写操作 | A2A 流水线自动执行（非交互式流水线设计，无需用户逐次确认） | POST Issue 评论、POST MR 评论、PUT 合并 PR、POST A2A |
| 删除操作 | 禁止 | 不执行 terraform apply/destroy、不删除 PR、不删除分支 |

### 性能预算

| 指标 | 预算 | 说明 |
|------|------|------|
| Skill 加载时延 | < 3s | 纯文档型 skill，无加载期脚本 |
| 审查执行时延 | P95 ≤ 8 min | 含 diff 获取 + 代码审查 + 安全扫描 + 资源交叉验证 + 报告输出 |
| terraform plan | ≤ 5 min | 含 init + plan（OBS backend 连通） |
| LLM token 消耗 | ≤ 12000 tokens/次 | 含参考文件按需加载 |
| API 调用次数 | ≤ 15 次/次执行 | VCS API + 华为云查询 + A2A |

### 兼容性声明

| 依赖 | 版本要求 | 说明 |
|------|----------|------|
| terraform | >= 1.7.5, <= 1.10.5 | OBS backend 兼容窗口 |
| git | >= 2.20 | 基础 git 操作 |
| curl | >= 7.60 | VCS API 调用 |
| VCS API | v5 | 所有 API 调用基于 v5 端点 |
| Grape A2A | >= 1.0 | A2A payload 结构遵循 Grape 平台约定 |
| 计算资源查询 | >= 1.0 | 资源规格交叉验证（声明在 requires 中） |
| 网络资源查询 | >= 1.0 | 网络资源交叉验证（声明在 requires 中） |
| 存储资源查询 | >= 1.0 | 存储资源交叉验证（声明在 requires 中） |
| 版本演进策略 | — | 本 Skill 版本号在 frontmatter 中声明；A2A 调用方按 issue_number/pr_number 传参，不依赖 Skill 版本号 |

### 可靠性声明

| 机制 | 声明 |
|------|------|
| 超时处理 | API 调用 30s 超时；terraform plan 300s 超时；华为云查询 60s 超时；超时后重试 1 次，仍失败则降级 |
| 重试幂等 | PUT 合并 PR 前检查 PR 状态（已合并则跳过）；A2A 前检查 pipeline 是否已有 sre:a2a_event；terraform plan 可安全重跑 |
| 失败降级 | 合并失败 → 在 PR 评论告知等待人工处理，不提前 A2A 交办 SRE；A2A 失败 → 在 Issue 评论标注「待人工交办 SRE Agent」；华为云查询失败 → 审查报告中标注「资源规格未交叉验证」；API 403 → 立即停止并告知用户 |
| 资源清理 | terraform plan 产生的 plan-review.tfplan 为中间产物，审查完成后可删除；不创建临时云资源；不修改 .terraform/ 目录以外的系统文件 |

## 硬规则

| 行为 | 态度 |
|------|-------|
| 评论 body 前缀固定为 `[qa Agent]` | ✅ **必须做** |
| 审查必须包含代码质量/功能/安全三方面 | ✅ **必须做** |
| IaC PR 审查必须交叉验证资源规格可用性 | ✅ **必须做** |
| 发现问题必须在 PR 评论中详细描述 | ✅ **必须做** |
| 问题按严重程度分级（P0/P1/P2/P3） | ✅ **必须做** |
| 审查通过后必须在 PR 评论标记 ✅ LGTM | ✅ **必须做** |
| 审查通过（✅ LGTM）后自动合并 PR | ✅ **必须做，不等维护者手动合并** |
| PR 合并成功后通过 A2A 交办 SRE Agent | ✅ **必须做，不可跳过** |
| 审查不通过时通过 A2A 回 Coding Agent 修复 | ✅ **必须做** |
| 回复 Token/密码等敏感信息 | ❌ **禁止** |
| 只在报告中建议交办 SRE 而不实际调用 A2A | ❌ **禁止** |
| 执行 terraform apply / terraform destroy | ❌ **禁止（部署是 SRE Agent 职责，QA 只做 plan 审查）** |
