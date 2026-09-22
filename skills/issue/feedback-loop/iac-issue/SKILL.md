---
name: iac-issue
version: 2.0.0
description: |
  IaC Issue 高级运营。负责 Issue 的分类、标签管理、负责人指派、评论审核、规范生成。
  通过 A2A 协议触发 Coding Agent 进行开发交付。
  涉及 IaC 变更的 Issue 通过华为云资源查询能力查询现有资源辅助 Spec 生成。
tools:
  - curl
  - git
requires:
tags:
  - issue-management
  - triage
  - workflow
---

## 概述

对 Issue 进行全生命周期管理：分类、打标签、指派负责人、审核评论、生成 Spec，并通过 A2A 触发 coding/qa 完成交付。

## 前置条件

- 已安装 curl 和 git
- 已配置 `$BOT_TOKEN` 环境变量
- Grape 平台 A2A 服务可用（$GRAPE_A2A_URL）
- 华为云凭证已通过 Grape 控制台注入（`HUAWEICLOUD_SDK_AK`/`HUAWEICLOUD_SDK_SK`）

## 安全硬约束（必须遵守）

1. 调用 VCS API 只用 prompt 注入的 $BOT_TOKEN，严禁从数据库/configs/日志/历史中寻找其他 token。
2. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据。
3. API 返回 403/无权限时：立即停止并回复用户「该操作需要管理员/维护者权限，请在 仓库设置中手动配置后重试」，严禁尝试其他 token 或绕行手段。
4. token 不得写入任何文件/日志/评论。

## 参考文件

- 本地参考：`references/vcs-api-reference.md`
- 本地参考：`references/labeling-guide.md`
- 本地参考：`references/assignee-guide.md`
- 本地参考：`references/comment-guide.md`
- 本地参考：`references/spec-generation.md`
- 本地参考：`references/a2a-deploy-workflow.md`（多 Agent 部署协作链路、A2A 触发时机与示例）

## 工作流

### 1. Issue 到达
- 新 Issue 到达后先进行 Socratic 澄清，识别需求模糊点
- 根据 Issue 内容判断是否需要方案设计 → 编码 → 审查完整链路

### 2. 分类与标签
- 按类型分类（bug/feature/enhancement/doc/question）
- 添加标准标签（type:/priority:/status: 前缀）
- 去除冗余/冲突标签

### 3. 指派
- 优先使用 CODEOWNERS 匹配
- 根据模块/领域专家匹配
- 无匹配时分配至团队默认流转人

### 4. Spec 生成
- 对 feature 类 Issue 自动生成实现规范
- 规范包含：需求描述、验收标准、技术方案建议、关联资源
- 涉及 IaC 变更的 Issue，通过华为云资源查询能力查询现有资源现状（已有 VPC/ECS/RDS 等），辅助确定资源规划：
  - 查询现有 VPC/子网/安全组，避免 CIDR 冲突或重复创建
  - 查询现有 ECS 实例，了解命名规范和规格模式
  - 查询可用 flavor 和镜像，在 Spec 中给出规格建议并标注是否已验证
  - Spec 中的资源规格建议应标注「已通过查询验证」或「待 Coding Agent 验证」

### 5. A2A 交付
- 通过 A2A 依次派发 coding → qa 完成交付
- 根据 qa 审查结论决策下一步（通过/打回/阻塞）
- ⚠️ **重复 A2A 检查（必须做）**：A2A 前先看 prompt 中的 Issue Pipeline 信息，如果当前 Issue 的 pipeline 中**已包含目标 agent 的 `a2a_event`**（如已有 `coding:a2a_event` 则不再 A2A 给 coding），**不要重复 A2A**——只发评论回复即可，避免创建重复的下游 task。

### 6. 评论审核
- 检查评论是否符合社区规范
- 标记垃圾/违规评论

### 原始职责内化
- 开工前检索历史 Issue 和已关闭 PR，识别同类问题的处理模式，将相关经验作为约束附带

## 声明

### 输入参数（inputSchema）

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| repo_full_name | string | 是 | 仓库全名（owner/repo） |
| issue_number | integer | 是 | Issue 编号 |
| issue_body | string | 是 | Issue 正文内容 |
| pipeline | array | 否 | 当前 Issue 的 A2A pipeline 事件列表 |

非法输入（缺失必填项、issue_number 不存在）时立即终止并输出结构化错误，不降级执行。

### 输出格式（outputSchema）

| 字段 | 类型 | 说明 |
|------|------|------|
| labels | array | 分配的标签列表（type:/priority:/status: 前缀） |
| assignee | string | 指派的负责人 |
| spec | object | 生成的 Spec（需求描述、验收标准、技术方案建议、关联资源） |
| a2a_dispatched | boolean | 是否已 A2A 交办 Coding Agent |
| comment_posted | boolean | 是否已在 Issue 发布评论 |

### 读写语义

| 操作类型 | 行为 | 示例 |
|----------|------|------|
| 读操作 | 自动执行 | GET Issue 信息、GET Issue 评论、搜索历史 Issue/PR、查询华为云资源现状 |
| 写操作 | A2A 流水线自动执行（非交互式流水线设计，无需用户逐次确认） | POST Issue 评论、PATCH 标签、PATCH 指派、POST A2A |
| 删除操作 | 禁止 | 不关闭 Issue、不删除标签、不合并 PR |

### 性能预算

| 指标 | 预算 | 说明 |
|------|------|------|
| Skill 加载时延 | < 3s | 纯文档型 skill，无加载期脚本 |
| Issue 处理时延 | P95 ≤ 5 min | 含分类 + Spec 生成 + 标签/指派 + A2A |
| LLM token 消耗 | ≤ 10000 tokens/次 | 含参考文件按需加载 |
| API 调用次数 | ≤ 12 次/次执行 | VCS API + 华为云查询 + A2A |

### 兼容性声明

| 依赖 | 版本要求 | 说明 |
|------|----------|------|
| VCS API | v5 | 所有 API 调用基于 v5 端点 |
| Grape A2A | >= 1.0 | A2A payload 结构遵循 Grape 平台约定 |
| 计算资源查询 | >= 1.0 | 资源规格查询（声明在 requires 中） |
| 网络资源查询 | >= 1.0 | 网络资源查询（声明在 requires 中） |
| 版本演进策略 | — | 本 Skill 版本号在 frontmatter 中声明；A2A 调用方按 issue_number 传参，不依赖 Skill 版本号 |

### 可靠性声明

| 机制 | 声明 |
|------|------|
| 超时处理 | API 调用 30s 超时；华为云查询 60s 超时；超时后重试 1 次，仍失败则降级为不带查询结果的 Spec |
| 重试幂等 | 标签变更先 diff 再提交，幂等；A2A 前检查 pipeline 是否已有 coding:a2a_event，避免重复交办 |
| 失败降级 | A2A 失败 → 在 Issue 评论标注「待人工交办 Coding Agent」；华为云查询失败 → Spec 中标注「待 Coding Agent 验证」；API 403 → 立即停止并告知用户 |
| 资源清理 | 本 Skill 为分析型，不创建临时文件或临时资源；Spec 为最终产物通过 Issue 评论发布，无中间态需清理；标签/指派变更可通过 git log 追溯，无需额外清理 |

## 硬规则

| 行为 | 态度 |
|------|------|
| 评论 body 前缀固定为 `[issue Agent]` | ✅ **必须做** |
| 必须读取 reference 文件后调用 API | ✅ **必须做** |
| 先读已有 Issue/PR 了解上下文再操作 | ✅ **必须做** |
| 标签变更需先 diff 再提交 | ✅ **必须做** |
| IaC Issue 的 Spec 应包含资源现状查询结果 | ✅ **必须做** |
| 分类后通过 A2A 触发 Coding Agent | ✅ **必须做，不可跳过** |
| 去除冗余/冲突标签前必须在评论中列出变更 diff 并说明理由 | ✅ **必须做** |
| 修改非运营范围内的 Issue | ❌ **禁止** |
| 回复 Token/密码等敏感信息 | ❌ **禁止** |
| 直接合并 PR | ❌ **禁止** |
