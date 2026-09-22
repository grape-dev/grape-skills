---
name: iac-coding
version: 2.0.0
description: |
  IaC 代码实现与 PR 创建/优化。通过 A2A 协议被 Issue Agent 调用时执行新开发。
  负责编码、提交、创建 PR 及自我审查。调用 TF 生成器生成 Terraform 配置，
  通过华为云资源查询能力验证资源规格可用性，通过 GitCode 推送能力创建 MR。
tools:
  - git
  - curl
requires:
tags:
  - implementation
  - pr-management
  - development
---

## 概述

接收 issue skill 的 A2A 指令后，完成代码开发、自我审查、PR 创建，并通过 A2A 触发 QA 审查。

## 前置条件

- 已安装 git 和 curl
- 已配置 `$BOT_TOKEN` 环境变量
- Issue 的 git worktree 分支已就绪（feat/issue-{issue_number}）
- Grape 平台 A2A 服务可用
- 华为云凭证已通过 Grape 控制台注入（`HUAWEICLOUD_SDK_AK`/`HUAWEICLOUD_SDK_SK`）

## 安全硬约束（必须遵守）

1. 调用 VCS API 只用 prompt 注入的 $BOT_TOKEN，严禁从数据库/configs/日志/历史中寻找其他 token。
2. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据。
3. API 返回 403/无权限时：立即停止该操作并回复用户「该操作需要管理员/维护者权限，请在 仓库设置中手动配置后重试」，严禁尝试其他 token 或绕行手段。
4. token 不得写入任何文件/日志/评论。
5. 调用 VCS API 一律以 `references/vcs-api-reference.md` 为准，严禁根据经验/记忆/猜测自行拼写 API 路径。
6. 长命令执行会静默，加 timeout 限制并一次只装必要依赖。
7. 禁止前台运行长驻/服务类命令，改用后台启动+验证+关闭模式。
8. 华为云 AK/SK 不得硬编码到任何 .tf 文件，一律走环境变量（Grape 控制台注入 `HUAWEICLOUD_SDK_AK`/`HUAWEICLOUD_SDK_SK` → 映射为 `HW_ACCESS_KEY`/`HW_SECRET_KEY`）。

## 参考文件

- 本地参考：`references/vcs-api-reference.md`
- 本地参考：`references/code-review-checklist.md`
- 本地参考：`references/huaweicloud-tf-conventions.md`（华为云 TF 编码规范、凭证设置约定、cn-north-4 避坑指南）
- 外部技能参考：TF 生成器的 reference/ 目录（guardrails.md、terraform-generation-guide.md、validation-workflow.md、56个服务best-practice模板），需从 multica-squad 仓获取

## 工作流

### 1. 场景识别
根据 A2A context 特征判断执行场景：

| A2A context 特征 | 场景 | 执行流程 |
|-----------------|------|---------|
| 含「PR 审查反馈」「审查发现问题」「需要修改」「优化」 | 代码优化 | 根据审查意见修改代码 |
| 含「启动开发」「实现」「feature」「bug」 | 新开发（从 issue skill） | 开发 -> PR -> A2A 通知 QA 审查 |
| 其他 | 不做处理，结束 | - |

### 2. 开发

#### 2.1 资源规格查询验证（生成 TF 前必须执行）
生成 Terraform 配置前，**必须先查询目标区域的资源规格可用性**，查询结果作为 TF 配置的验证依据：

- ECS flavor：通过华为云计算资源查询能力执行 `list_flavors.py --region <region> --availability_zone <az>`，确认所选 flavor 在目标区域可用
- 镜像：通过华为云计算资源查询能力执行 `list_images.py --region <region> --imagetype gold --platform <os>`，获取镜像精确名称（含版本号）
- 可用区：通过华为云计算资源查询能力查询可用区列表，由用户/Issue 确认具体可用区
- VPC/子网/安全组：通过华为云网络资源查询能力查询现有网络资源，避免 CIDR 冲突
- OBS bucket：通过华为云存储资源查询能力查询桶名是否已被占用

⚠️ **禁止跳过查询直接写 TF 配置——未验证的规格可能导致 terraform plan 失败或 apply 时报错。**
⚠️ **查询失败时不允许"降级继续"——必须修复查询环境后重试，或报告问题等待解决。**

#### 2.2 TF 配置生成
- 所有 TF 代码和脚本文件统一放在仓库的 `iac/` 子目录下，不得放在仓库根目录或其他目录
- 如仓库中不存在 `iac/` 目录，新建该目录
- 调用 TF 生成器生成 TF 配置，遵循以下规范：
  - 生成器工作流：需求理解 → 资源规划 → 规格验证 → TF生成 → 校验（参考 generator 的 SKILL.md）
  - 编码规范：遵循 `references/huaweicloud-tf-conventions.md`（目录结构、凭证映射、cn-north-4 避坑、provider 版本约束、OBS backend 配置）
  - best-practice 模板：参考 generator 的 `reference/<service>-best-practices/` 目录中的模板
- ⚠️ grape 环境约束：生成器原版工作流包含 terraform apply，但在 grape A2A 流程中 **coding agent 只执行到 terraform plan，terraform apply 由 SRE Agent 执行**

#### 2.3 校验
- 按方案执行 terraform fmt → terraform init → terraform validate → terraform plan -out=tfplan
  - `terraform plan` 只预览变更不创建资源，用于提前发现镜像/flavor/provider/API 等问题
  - ⚠️ 到 plan 为止，**不执行 terraform apply / terraform destroy**
- 凭证映射（Grape 控制台注入 → Terraform 期望）：
  ```bash
  export HW_ACCESS_KEY="${HUAWEICLOUD_SDK_AK}"
  export HW_SECRET_KEY="${HUAWEICLOUD_SDK_SK}"
  export HW_REGION="cn-north-4"
  export AWS_ACCESS_KEY_ID="$HW_ACCESS_KEY"
  export AWS_SECRET_ACCESS_KEY="$HW_SECRET_KEY"
  export AWS_DEFAULT_REGION="cn-north-4"
  ```

### 3. 自审查
参考 `references/code-review-checklist.md` 逐项检查。

### 4. 提交 PR
- 通过 GitCode 推送能力推送特性分支到远端并创建 MR
- MR body 四段齐全：变更说明、资源清单、文件变更、后续步骤
- 遵循 Conventional Commits

### 5. A2A 通知审查
创建 PR 后通过 A2A 通知 QA Agent 进行代码审查。

### 原始职责内化
- 开工前按模块关键词搜索历史 Issue/PR，了解常见问题模式，避免重复踩坑

## 声明

### 输入参数（inputSchema）

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| repo_full_name | string | 是 | 仓库全名（owner/repo） |
| issue_number | integer | 是 | 关联 Issue 编号 |
| branch | string | 是 | 工作分支（feat/issue-{N}） |
| context | string | 是 | A2A 传入的开发指令和上下文摘要 |
| pipeline | array | 否 | 当前 Issue 的 A2A pipeline 事件列表 |

非法输入（缺失必填项、分支不存在、worktree 未就绪）时立即终止并输出结构化错误，不降级执行。

### 输出格式（outputSchema）

| 字段 | 类型 | 说明 |
|------|------|------|
| pr_number | integer | 创建的 MR 编号 |
| pr_url | string | MR 的 GitCode URL |
| mr_body | object | 四段结构：变更说明、资源清单、文件变更、后续步骤 |
| plan_summary | string | terraform plan 摘要（create/update/destroy 资源数） |
| self_review_passed | boolean | 自审查是否通过 |
| a2a_dispatched | boolean | 是否已 A2A 通知 QA Agent |

### 读写语义

| 操作类型 | 行为 | 示例 |
|----------|------|------|
| 读操作 | 自动执行 | GET Issue/PR 信息、GET PR diff、搜索历史 Issue/PR、terraform plan（只读预览） |
| 写操作 | A2A 流水线自动执行（非交互式流水线设计，无需用户逐次确认） | git push、POST 创建 MR、POST A2A、terraform fmt/init/validate |
| 删除操作 | 禁止 | 不执行 terraform apply/destroy、不删除文件、不合并 PR |

### 性能预算

| 指标 | 预算 | 说明 |
|------|------|------|
| Skill 加载时延 | < 3s | 纯文档型 skill，无加载期脚本 |
| 开发执行时延 | P95 ≤ 10 min | 含 TF 生成 + fmt/init/validate/plan + git push + MR 创建（不含云侧资源创建时延） |
| terraform init | ≤ 3 min | 镜像源生效时 |
| LLM token 消耗 | ≤ 12000 tokens/次 | 含参考文件按需加载 |
| API 调用次数 | ≤ 15 次/次执行 | VCS API + A2A |

### 兼容性声明

| 依赖 | 版本要求 | 说明 |
|------|----------|------|
| terraform | >= 1.7.5, <= 1.10.5 | OBS backend 兼容窗口 |
| git | >= 2.20 | 基础 git 操作 |
| curl | >= 7.60 | VCS API 调用 |
| VCS API | v5 | 所有 API 调用基于 v5 端点 |
| Grape A2A | >= 1.0 | A2A payload 结构遵循 Grape 平台约定 |
| TF 生成器 | >= 1.0 | TF 配置生成（声明在 requires 中） |
| 版本演进策略 | — | 本 Skill 版本号在 frontmatter 中声明；新旧版本差异通过版本号识别；A2A 调用方按 issue_number 传参，不依赖 Skill 版本号 |

### 可靠性声明

| 机制 | 声明 |
|------|------|
| 超时处理 | terraform 命令默认 300s 超时；git push 默认 60s 超时；API 调用 30s 超时；超时后重试 1 次，仍失败则报告错误 |
| 重试幂等 | terraform plan 可安全重跑（只读）；git push 失败重试不产生重复提交（幂等）；MR 创建前检查是否已有同分支的 open MR，避免重复创建 |
| 失败降级 | terraform init/validate/plan 任一步骤失败 → 不创建 PR，在 Issue 评论报告失败原因和修复建议；git push 失败 → 检查分支状态后重试 1 次；A2A 失败 → 在 Issue 评论标注「待人工通知 QA Agent」 |
| 资源清理 | terraform plan 产生的 tfplan 文件为中间产物，PR 创建后可删除；不创建临时云资源；不修改 .terraform/ 目录以外的系统文件；worktree 由平台管理，Skill 不负责清理 |

## 硬规则

| 行为 | 态度 |
|------|------|
| 评论 body 前缀固定为 `[coding Agent]` | ✅ **必须做** |
| 按场景识别结果执行对应流程 | ✅ **必须做** |
| 所有 feature 开发必须先输出需求文档和方案设计再编码 | ✅ **必须做** |
| 所有开发任务必须包含测试用例 | ✅ **必须做** |
| 生成 TF 前必须通过查询技能验证资源规格可用性 | ✅ **必须做，不可跳过** |
| 创建 PR 前必须先执行自审查（参考 code-review-checklist.md） | ✅ **必须做，不可跳过** |
| 创建 PR 后必须在 Issue 发评论告知 | ✅ **必须做，不可跳过** |
| 创建 PR 后必须通过 A2A 通知 QA Agent 进行代码审查 | ✅ **必须做，不可跳过** |
| 代码优化场景修改完成后必须在 PR 评论告知 | ✅ **必须做** |
| 每个提交一个原子变更 | ✅ **必须做** |
| 所有 TF 代码和脚本放在仓库 `iac/` 子目录下 | ✅ **必须做** |
| 只通过 VCS API 获取信息 | ✅ **必须做** |
| 仅实现当前 Issue 描述的内容 | ✅ **保持范围** |
| 直接合并 PR | ❌ **禁止（仅创建，等待人工审批）** |
| 执行 terraform apply / terraform destroy | ❌ **禁止（部署是 SRE Agent 职责，Coding 只负责到 PR 创建）** |
| 跳过资源规格查询直接生成 TF 配置 | ❌ **禁止** |
| 修改非 Issue 相关的代码 | ❌ **禁止** |
| 回复 Token、密码等敏感信息 | ❌ **禁止** |
