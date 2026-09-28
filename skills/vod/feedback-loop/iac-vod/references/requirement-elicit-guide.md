# IaC 需求引导与 Issue 审视指南（iac-vod）

> 配套 `skills/vod/feedback-loop/iac-vod/SKILL.md`（v2.2）。覆盖：清晰度四要素 + IaC 特化要素、引导漏斗、IaC Issue 审视流程、结构化模板、A2A 交办。

## 一、清晰度四要素 + IaC 特化要素

判断一条 IaC 开发者声音（消息 / Issue）是否构成**清晰 IaC 开发者需求**：

### 通用四要素

| 要素 | 判断问题 | 不清晰示例 |
|------|---------|-----------|
| 目标 | 一句话能说清要达成什么？ | "搞一下这个基础设施" |
| 现状 | 当前行为/缺失是否明确？ | 未说明当前 IaC 配置状态 |
| 期望行为 | 期望的具体行为/场景步骤是否清晰？ | "更好用点" |
| 验收标准 | 是否可验证？ | 无任何可检验描述 |

### IaC 特化要素

| 要素 | 判断问题 | 不清晰示例 |
|------|---------|-----------|
| 目标云资源类型 | 涉及哪些云服务（ECS/VPC/RDS/OBS/CCE 等）？ | "需要一些服务器" |
| IaC 工具链 | 使用 terraform / pulumi / cloudformation / hcl？ | 未明确工具链 |
| 目标区域/环境 | 部署到哪个区域？哪个环境（dev/staging/prod）？ | "部署到华为云" |
| 资源规模 | 预期实例数量、规格、带宽？ | 未说明规模 |

四要素 + IaC 特化要素齐全 → 清晰；任一缺失/含糊 → 需引导。

## 二、需求引导漏斗（多轮对话）

### 规则
| 规则 | 说明 |
|------|------|
| 第一轮 | 提取意图，判断清晰度；模糊则提 1-3 个针对性澄清问题（结合知识基线，问得具体） |
| 判断标准 | 通用四要素 + IaC 特化要素齐全 → 清晰 |
| 多轮 | 每次基于上一轮回答追问，不重复已确认项 |
| 上限 | 最多 3 轮；超限 → 建「待澄清」Issue（场景 A）或在 Issue 评论列缺失项（场景 B），不无限追问 |
| 语气 | 中文、简洁、引导式（不用"请填写模板"式，用具体问题） |

### 提问原则
- **结合知识基线**：参考项目知识基线中 IaC 相关部分（terraform modules / pulumi stacks / cloudformation templates / 部署脚本），让问题贴合项目实际
- IaC 场景示例：
  ```
  用户："能不能加个 RDS 实例到这个项目？"
  iac-vod（结合 project-graph 已知项目使用 terraform + 华为云）：
    "您需要的是哪种 RDS 引擎？（MySQL / PostgreSQL / SQL Server）
     另外预期实例规格是？（如 基础版 / 通用型 / 专属型）
     目标区域是 cn-north-4 还是其他？"
  ```
- **Issue 评论追问格式**（body 以 `[iac-vod Agent]` 开头）：
  ```bash
  grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
    --json '{"body": "> 用户的问题原文\n\n[iac-vod Agent] 您需要的是哪种 RDS 引擎？……"}' --json-out
  ```

### IaC 必问清单
当 Issue 涉及 IaC 但信息不全时，以下问题按需追问（不必全问，选择缺失项）：

| 维度 | 问题模板 |
|------|---------|
| 云资源类型 | "您需要的云资源是？（ECS / VPC / RDS / OBS / CCE / 其他）" |
| IaC 工具链 | "使用 terraform / pulumi / cloudformation 还是其他 IaC 工具？" |
| 目标区域 | "部署到哪个区域？（如 cn-north-4 / cn-south-1）" |
| 环境 | "目标环境是？（dev / staging / prod）" |
| 资源规模 | "预期实例数量和规格？（如 2台 s6.large.2）" |
| 网络需求 | "需要几层网络隔离？是否需要 NAT 网关 / EIP？" |
| 状态后端 | "terraform state 后端用 OBS 还是本地？" |
| 安全约束 | "是否有安全合规要求？（等保 / 数据加密 / 访问控制）" |

## 三、IaC Issue 审视流程（场景 B，`issue_opened`）

1. **复制需求场景**：prompt 提示「用户已为此 Issue 指定了开发场景」→ 不因标题/内容相似判重复——跳过审视，直接 B3 → B6 执行
2. **自建排除**：Issue 含 `auto-submitted by iac-vod Agent` 标记 → 跳过审视，直接 A2A 交办 IaC Issue Agent
3. **IaC 相关性判定**：Issue 内容涉及 terraform / hcl / pulumi / cloudformation / 云资源编排 / 基础设施部署 → 属于 iac-vod 管辖范围；纯应用层 Issue → 回退到通用 vod 流程
4. **清晰度审视**：读取 Issue 完整内容（title/body/标签/评论），对照四要素 + IaC 特化要素；结合知识基线判断 IaC 可执行性/重复/歧义
5. **沟通澄清**（不清晰时）：在 Issue 评论 @开发者 追问（body 以 `[iac-vod Agent]` 开头），或飞书群沟通；≤3 轮
6. **结构化总结**：`grape git-repo issues update --json`（body 写文件 @file）将 body 收敛为 IaC 模板结构
7. **A2A 交办**：`grape a2a handoff --json '{"agent":"iac-issue",...}'` → IaC Issue Agent 做 spec/标签/里程碑/分配（命令见 iac-vod-runbook A5/B6）

## 四、结构化 IaC Issue 模板

```markdown
## 目标
{用户想达成的 IaC 结果，一句话}

## 现状
{当前 IaC 配置/基础设施状态，结合知识基线描述}

## 期望行为
{清晰描述期望的 IaC 变更，可含使用场景步骤}

## 验收标准
- [ ] {可验证的验收项 1}
- [ ] {验收项 2}

## 优先级
P0（紧急）/ P1（重要）/ P2（一般）

## IaC 扩展信息

### 目标云服务
{ECS / VPC / RDS / OBS / CCE / 其他}

### IaC 工具链
{terraform / pulumi / cloudformation / hcl}

### 目标区域
{cn-north-4 / cn-south-1 / 其他}

### 资源规模预估
{实例数量、规格、带宽等}

### 安全约束
{等保要求 / 数据加密 / 访问控制 / 无特殊要求}

---
来源：{飞书用户反馈 / Issue 评论 / PR 评论}
auto-submitted by iac-vod Agent（Feishu）
```

## 五、A2A 交办格式

```bash
# 一律用 grape a2a handoff（禁 curl 直连——命令见 iac-vod-runbook A5/B6）：
grape a2a handoff --json '{
  "agent": "iac-issue",
  "payload": {"repository": "$ACCOUNT/$REPO_NAME", "account": "$ACCOUNT", "issue_number": {真实编号}, "pr_number": null, "context": "iac-vod 已完成 IaC 需求收敛与结构化，请继续 spec 设计/打标/分配"}
}' --json-out
# A2A 前必查防重复：grape issues pipeline（已含 iac-issue:a2a_event 则不重复）
```

> ⚠️ `issue_number` 必填；无法确定则不调 A2A，在评论中说明。交办后 Issue 生命周期进入 `iac-issue` 阶段（`issue_state` 归属更新）。
>
> ⚠️ **失败降级**：A2A 调用返回非 2xx 或连接超时 → 重试最多 3 次（每次间隔数秒）；仍失败 → 在 Issue 评论说明"A2A 服务不可达，待恢复后重试交办"，并在 `next_step` 标注需人工介入，不得静默跳过。
>
> ⚠️ **重复 A2A 检查**：A2A 前先看 prompt 中的 Issue Pipeline 信息，如果当前 Issue 的 pipeline 中**已包含 `iac-issue:a2a_event`**，**不要重复 A2A**——只发评论回复即可。
