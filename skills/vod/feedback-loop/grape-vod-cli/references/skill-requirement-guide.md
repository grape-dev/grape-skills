# Grape 技能创建需求引导指南

> 配套 `skills/vod/feedback-loop/grape-vod-cli/SKILL.md`。本技能是 **grape-skill-dev 流水线入口**：把用户「想要一个什么样的 grape 技能」的意图（新建/改造均可），引导收敛成**结构化技能需求单**，交棒 issue agent（通常用 grape-skill-issue 技能）。
> ⚠️ 所有 API 调用通过 grape CLI 完成，禁止 raw curl；评论 body 一律以 `[VOD Agent]` 开头。

## 一、先理解两件事（缺一不可）

**① 用户要建什么样的技能** —— 决定生成什么技能（见 §二/§三）。
**② 技能服务哪个项目 —— 默认就是当前项目**：当前项目通过环境变量（`$REPO_OWNER`/`$REPO_NAME`）与 prompt（内联注释）已注入，**无需引导用户回答**。用项目知识基线（`grape repos project info`）了解当前仓库的技术栈、已有 skills、CI/工作流，确认新技能与项目能力**契合**（做项目真需要的事，而非拍脑袋）。

> ⚠️ **触发场景无需引导**：vod 技能配置进对应工作流后，**所有 issue 过来 Grape 都会自动调用本技能**——触发方式是固定的，不需要用户描述「什么时候被调用」。

## 二、技能需求引导要素（≤3 轮，一次 1-3 个问题）

对照以下要素逐项确认，缺失/含糊即追问：

| # | 要素 | 引导问题示例 | 说明 |
|---|------|-------------|------|
| 1 | **agent_type**（必填） | 「你希望这个技能承担哪类职责？」（chat/vod/issue/coding/qa/sre） | 决定目录位置、命令子集、下游节点；见 §四速查 |
| 2 | **skill name**（必填） | 「技能叫什么名字？」（小写连字符，如 `blog-manager`） | kebab-case，= 目录名，≤64 字符，不与已有技能冲突 |
| 3 | **description**（必填） | 「一句话描述这个技能做什么？」 | 含职责；对齐 skill-description.json 描述 |
| 4 | **目标系统 / 操作对象** | 「这个技能要操作什么系统/服务/命令？」（如 hcloud、REST API、华为云、计算器） | 决定命令面：CLI/SDK/API；REST API 类需 API 地址/认证/文档 |
| 5 | **流程审批节点**（按需） | 「处理过程中需要哪些流程节点？（如需要用户输入补充 / 需要评审审批 / 需要任务通知；可都不选）」 | 是否需要 `awaiting-input`（用户输入）、`pending-review`/`review-pass`（评审审批）、`tasks notify`（任务通知）等，由技能职责 + issue 阶段设计决定，**不强制** |
| 6 | **自定义环境变量**（按需） | 「技能需要哪些凭据/配置项？（如目标系统 API Key、地址）；变量叫什么名字？」 | 是否注入自定义 env（场景 custom_fields）。需要时与用户确认变量**名称**——命名须遵循 GRAPE 约束：**全大写 `[A-Z][A-Z0-9_]*`、非空、不以 `GRAPE_` 开头、不与系统保留变量冲突**；密钥类建议带 `_KEY/_SK/_TOKEN/_PASSWORD` 后缀（自动掩码） |
| 7 | **验收 / 风险** | 「怎么算做好？涉及付费/删除/不可逆操作吗？」 | 危险场景（付费资源/删除/不可逆）要显式识别 |

> ⚠️ **自定义环境变量命名约束（skill 用到时必遵守）**：命名须全大写、非空、不以 `GRAPE_` 开头、不与系统保留变量冲突（`REPO_*`/`ISSUE_NUMBER`/`PR_NUMBER`/`BOT_USERNAME`/`ACCOUNT`/`GRAPE_SESSION_TOKEN`/`GRAPE_ISSUE_ID` 等均为保留）；密钥类变量建议改用 `_KEY/_SK/_TOKEN/_PASSWORD/_SECRET` 后缀（自动 `is_secret=true` 掩码）。**命名违反规则会被拒绝注入，技能将读不到该变量**——与用户确认名字时就校验合规，横杠/小写/`GRAPE_` 前缀直接给出符合规范的替代名。

## 三、输出：技能需求单（评论发布模板）

需求收敛后，以评论发布（body 以 `[VOD Agent]` 开头，**不改写原始 Issue**）：

```markdown
[VOD Agent] 📋 技能需求单（已收敛）

## agent_type
{chat / vod / issue / coding / qa / sre}

## skill name
{小写连字符，无后缀如 -skill/-cli}

## description
{一句话：做什么}

## 目标系统 / 操作对象
{系统名 / REST API 地址与认证 / CLI 命令 / 华为云服务等}

## 服务项目
（默认当前项目 {owner}/{repo}；技能服务于其 {开发/CI/部署/运维/对话} 环节，基于当前项目知识基线确认契合）

## 流程审批节点
{按需：需用户输入实时补充（awaiting-input / 评审审批 pending-review / 任务通知 tasks notify…）；无则写"无"}

## 自定义环境变量
{按需：变量名（遵循全大写/非 GRAPE_ 前缀/不与保留冲突/密钥带后缀），如 CLOUD_API_KEY；无则写"无"}

## 验收标准
- [ ] {可验证验收项 1}
- [ ] {验收项 2}

## 风险 / 注意
{付费资源 / 删除 / 不可逆操作 等危险场景；无则写"无"}
```

## 四、agent_type 判定速查（引导判定关键）

**先判定 agent_type** —— 它决定目录（`skills/{agent_type}/`）、命令子集与下游链路。用「用户要它做什么」倒推：

| 用户意图描述 | agent_type | 目录 | 下游 |
|-------------|-----------|------|------|
| 助手/入口：识别对话、查信息答复 | `chat` | chat/ | 无（直接答复） |
| 收集/引导需求：把反馈变清晰需求 | `vod` | vod/ | → issue |
| 运营/分类/Spec：把需求变可开发任务 | `issue` | issue/ | → coding |
| 代码/生成：把需求/Spec 变可交付产物 | `coding` | coding/ | → qa |
| 审查/门禁：PR 质量与工作流审查 | `qa` | qa/ | → coding/sre |
| 部署/构建/运维：上线与交付 | `sre` | sre/ | → done |

> 若用户是「做一个操作 X 系统的技能」（如管理博客、查 ECS），最常见落在 **coding**（生成代码型 skill，如 REST API skill creator 流程）或 **sre**（运维命令型）。判定不清 → 追问，不硬猜。

## 五、Grape 技能注册元数据规范（供引导确认 name/description 是否合规）

新技能最终要注册到 `skill-description.json`，字段如下（引导时校验 name/description 对齐）：

| 字段 | 约束 |
|------|------|
| `name` | kebab-case（小写字母/数字/连字符），≤64 字符，= 技能目录名 |
| `agent_type` | `vod / issue / coding / qa / sre / chat` 之一 |
| `sub_scene` | 子场景（`feedback-loop / ai-coding-review / code-quality / app-release / im / scaffolding / auto-testing / ci / observability` 等） |
| `path` | 三段式 `{agent_type}/{sub_scene}/{skill_name}`，与目录严格对应 |
| `description` | 一句话：职责 + 触发词 +（CLI 版则注明「CLI 版」）|

## 六、危险场景识别（必做，对齐 skill-issue 门控）

- 涉及**付费资源**（云资源创建/计费）、**删除**（删数据/删资源）、**不可逆操作** → 在需求单「风险」节显式标注，交由 issue 节点做门控确认。
- 不主动规避，但如实采集，供下游判断。

## 七、常见问题口径

- **用户只说「创建一个技能」没细节** → 从 agent_type 提问开始（「你想让它承担哪类职责？」），不跳过引导。
- **命名冲突**（`grape skills list` 已存在同名）→ 建议替代名后再收敛。
- **REST API 类技能** → 引导对齐 `rest-api-skill-creator` 需求模板：API base_url、认证方式、API 文档（OpenAPI/Markdown/描述）。
- **华为云类技能** → 引导对齐 `huawei-cloud-*` 规范：Target Service / Feature Scope / Execution Mode / CLI Operations / Skill Name / IAM Permissions / Trigger Scenarios。