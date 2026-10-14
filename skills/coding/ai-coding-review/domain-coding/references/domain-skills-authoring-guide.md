# 领域技能与 Agent 配置编写规范

> 配套 `skills/domain-coding/SKILL.md`。定义领域技能（SKILL.md）与领域 Agent 配置（JSON）的编写规范，
> 确保生成结果可被模板的 Agent 运行时正确加载，**且每个功能能在任务对话中被模型识别并调用**（对话可识别）。

## 一、领域技能目录规范

技能存放在 `jiuwenswarm/resources/agent/workspace/skills/<skill-name>/`，目录统一：

```
<skill-name>/
├── SKILL.md        # 主定义（必选，frontmatter + 指令内容）
├── README.md       # 技能简介（必选）
├── references/     # 辅助资料（可选，如法规清单、审查要点库）
├── scripts/        # 可执行脚本（可选，如批量审查脚本）
├── templates/      # 模板文件（可选，如文书模板）
└── assets/         # 静态资源（可选）
```

命名：kebab-case 小写，语义即职责：`contract-review`、`legal-research`、`legal-drafting`、`case-timeline`、`compliance-check`。

## 二、SKILL.md 编写规范

```markdown
---
name: contract-review
description: 合同审查技能：必备条款核查、风险条款识别、修改意见生成，输出审查意见书入库。
steps:
  1. 读取待审合同（legal.contract.review 的合同文件路径）
  2. 逐条核查必备条款（价款/交付/验收/违约责任/知识产权/保密/解除/争议解决…）
  3. 输出风险条款与修改建议
    - output: 审查意见书（含风险点逐条 + 修改文本建议）
    - save_to_db: true
---

# 合同审查技能

## 主要步骤
1. 获取合同文件 → `legal.contract.review` 能力
2. 风险点识别规则（对齐审查要点库）…
3. 输出审查意见书并落库（产出ID/路径）

## 注意事项
- 合同涉及金额/违约条款必须明确提示，不得含糊
- 意见书格式：风险等级 / 条款位置 / 问题描述 / 修改建议

## 边界
- 不代签法律意见（最终意见由主办律师确认）
- 不杜撰法条——检索结果必须带来源
```

规范要点：
1. **frontmatter 必须合法**：`name` + `description` 必填；`steps` 建议写 `name / steps / output` 结构（框架支持「技能卡片」渲染）。
2. **对接领域 RPC**：步骤中明确写 `legal.<x>.y` 能力调用，确保技能可执行、产出可落地。
3. **每个技能给 1 个"立马能用"的步径**：用户一上来就能跑通一个最小用例。
4. **单技能聚焦**：一个技能解决一类问题，不做大杂烩；需要组合时交给 LEADER 调度多个技能。
5. **中文内容 + 结构清晰**：步骤编号、要点列表，方便 LLM 按序执行。
6. **必须写「适用场景」**：SKILL.md 开头明确用户的哪种说法/需求会触发该技能（如"用户要生成报表、查询历史报表、解读财务数据"），
   ——这是模型在任务对话中识别功能归属的依据。
7. **必须写「操作要点 → 调用 RPC」**：每个功能标注**调用哪个 `<domain>.<x>.<y>` RPC + 关键参数**（如
   `finance.report.generate`，参数 `report_type/period`），模型据此在对话中发起真实调用；仅描述业务不写 RPC 的技能无法触发落库。
8. **（v3.6 强制）必须写「可执行通道段」**：只写"调用 `gov.policy.search`"还不够——模型需要知道**怎么真实发起这个调用**，
   否则会陷入"只聊不做"（回复"好的，已为您查询"却从未调用）。每个 RPC 至少给一条可执行通道，二选一：
   - **领域 REST 网关通道**：
     ```
     POST http://127.0.0.1:<gateway_port>/api/<domain>/<action>
     Header: Content-Type: application/json
             X-API-Key: <api_key>          # api_key 从 config.yaml 的 <domain>_gateway 段读取，禁止硬编码
     Body:   { "keyword": "安全生产" }      # 与 <domain>.<x>.<y> 的 params 同名同型契约
     返回:   { "ok": true, "data": [ ... ] }
     ```
   - **Agent 可直接调用的领域工具**：注明使用 `<domain>_gateway_tool.py` 注册的工具（工具名 + 入参 schema），
     或本机 WebChannel `webRequest('<domain>.<x>.<y>', params)` 等效调用。
   - 判据：**模型拿到技能文档后能写出真实可发起的调用**（curl / webRequest / 工具调用），而非"依赖 Agent 自己发挥"。
     缺「可执行通道段」的技能在对话中无法代办落地，qa 验收 24t 判 FAIL。

## 二·一、「可执行通道段」编写示例（SKILL.md 必含，对话代办落地关键）

> 场景：政策法规库技能。用户在任务对话说"帮我查一下安全生产政策""帮我录入这条政策"，模型要**真的执行**
> `gov.policy.search` / `gov.policy.import`，而非回复文本。SKILL.md 需如下写：

```markdown
## 适用场景
- 用户说："帮我查一下 XX 政策 / 有哪些安全生产法规？"→ 查询政策法规
- 用户说："帮我录入/导入这条政策：标题=…、文号=…、正文=…"→ 录入政策法规（落库）

## 操作要点
- 查询：调用 `gov.policy.search`，参数 `{keyword: string, page?, page_size?}` → 返回 `{ok:true, data:[{id,title,doc_no,body,publish_date}]}`
- 录入：调用 `gov.policy.import`，参数 `{title, doc_no, body, category?, publish_date?}` → 返回 `{ok:true, data:{id}}` 并落库

## 可执行通道段
- REST 网关（推荐）：`POST http://127.0.0.1:19220/api/gov/policy/search`
  Header：`Content-Type: application/json`、`X-API-Key: <api_key>`
  其中 `<api_key>` 从 `config.yaml` 的 `gov_gateway` 段读取，禁止硬编码，缺省时用
  `jiuwenswarm.common.config.get_config()["gov_gateway"]["api_key"]` 获取。
  Body 示例：`{"keyword":"安全生产","page":1,"page_size":20}`；返回 `{"ok":true,"data":[...]}`。
- 或 Agent 工具：使用 `gov_gateway_tool.py` 注册的 `gov_policy_search(params)` 工具
  （等价 `webRequest('gov.policy.search', params)` 直连本机 WebChannel）。
- 输出后把结果整理成可读列表回复用户（条目/总数），并提示"可在左侧「政策法规库」页签复核"。

## 注意事项
- 查询结果必须带来源/文号，不杜撰法规；录入前校验必填（标题/文号/正文）。
- 删除等高危操作不开放对话代办（页面二次确认）。
```

## 三、技能在「技能 → 我的技能」中的可见性（归属机制）

> gov 实测问题：领域技能只写在 `resources/agent/workspace/skills/`（内置技能目录、`source='builtin'`），
> 但运行时用户在 UI「技能 → 我的技能」**看不到**——因为前端 `computeMySkills` 会排除
> 「内置技能源码存在但未安装」的技能（`is_builtin_source && installed===False && source!=='local'`）。
> 只有把技能"安装"到用户技能目录使其 `source='local'`，才会出现在「我的技能」。

- **位置规范**：领域技能仍写入 `resources/agent/workspace/skills/<skill-name>/`（随仓库分发，所有实例可加载）；
  每个技能目录 `SKILL.md` frontmatter 完整（`name`/`description` 必填，`steps` 结构化）——这是安装与识别的先决条件。
- **必须提供"一键安装到我的技能"的途径（新增硬性交付物）**：在生成项目的 `快速部署指南.md` / README 中
  写明安装命令，例如：
  ```
  # 把内置领域技能安装到用户技能目录（source 变 local，出现在「技能 → 我的技能」）
  skills.install <skill-name>
  ```
  （`skills.install <bare name>` 会走内置技能安装通道，复制到用户技能目录 `~/.jiuwenswarm/agent/workspace/skills/`
  并注册为 local；安装后前端「技能 → 我的技能」默认可见、可启用。）
- **验收判据**：安装后 `skills.list` 中该技能 `source` 为 `local`；前端「技能 → 我的技能」能搜到并启用。
  未安装时至少保证「内置技能」入口可一键安装，禁止"写入内置目录后不提供安装途径"导致技能在 UI 全不可见。

## 四、法律领域技能清单（首批参考）

| 技能 | 服务 Agent | 依赖能力 RPC |
|------|-----------|-------------|
| contract-review 合同审查 | 合同审查师 | legal.contract.review |
| legal-research 法律检索 | 法律检索师 | legal.research.search |
| legal-drafting 文书生成 | 文书引擎师 | legal.draft.generate |
| case-timeline 案件时间线管理 | 案件管理师 | legal.case.* |
| compliance-check 合规清单 | 合规审查师 | legal.compliance.check |
| legal-counsel 法律答疑 | 法律顾问 | legal.research.search + legal.draft.generate |
| legalswarm-leader 法务主管调度 | LEADER | legal.team.* |

> 通用规则：每类领域给出 5~17 个技能；第一个版本覆盖「领域核心工作流」即可（对应 EduSwarm 17 个内置技能）。

## 五、Agent 配置 JSON 规范（完整可替换模板见 templates.md「3. 领域 Agent 配置 agent_config.json」）

```json
{
  "id": "legal_leader",
  "agent_id": "legal_leader",
  "name": "法务主管",
  "persona": "你是法务主管 LEADER，只做任务拆解与团队协调，不亲自审合同/写文书。…",
  "skills": ["legalswarm-leader-orchestrator"],
  "knowledge_base": {},
  "source": "custom",
  "max_iterations": 200,
  "model": {
    "model_source": "default",
    "provider": "azure",
    "model": "gpt-4o",
    "temperature": 0
  },
  "updated_at": "2026-..."
}
```

字段约束：
- `id` / `agent_id` 统一 `<domain>_<role>`，小写。
- `name` 填中文角色名（用于前端展示）。
- `persona` 必须含 6 段：定位与唯一职责 / 不做什么 / 可调用领域 RPC 能力清单 / 交付规范（产出ID+路径入库、返回 CONTROL_RETURN）/ 示例领域话术 / **「能做啥」回答（平台能力 + 领域能力，见 §五）**。
- `persona` 中的领域能力描述与 `skills.list / team.list` RPC 返回、前端「团队成员」页展示**同口径**。
- `skills` 引用 `workspace/skills/` 真实存在的技能目录名。
- `model.model_source: "default"` 跟随平台，避免每 Agent 配 key；需要单独模型时设置 provider/model。
- 删除时停用配置文件即可，不要物理删除（保留历史 Agent 可用）。

## 六、LEADER persona 模板（各领域替换角色名）

```
你是<领域>主管，LEADER 角色，统筹<领域>任务拆解与团队协调。
你的团队：<成员角色 list>。
调度规则：
0. 先对照「委派映射」表（协调技能 *-swarm-coordination/SKILL.md）识别用户任务归属的功能模块，
   再按 1-5 规则调度。
1. 先判断任务复杂度：简单任务（单次单产出）直接调用领域 RPC 解决，不组队；
   复杂任务（多环节依赖/需迭代）才组队，并向用户亮出团队名单。
2. 单发言人：只有你直接对用户说话，成员只向你汇报。
3. 一次只激活一个成员，等成员返回 CONTROL_RETURN（含产出摘要 + 产出ID/路径）再切换。
4. 严禁嵌套组队；成员交付必须落地入库，禁止只输出文本。
5. 成员失败 → 你兜底直调该成员能力，不让流程卡死。
示例话术：
- 简单：「审一下这份 NDA，标出风险条款」
- 复杂：「为 XX 项目出一套<领域>文件…」
- 长周期：「接手这个案件，管理立案到结案全流程」

当用户询问你能做什么时，按以下固定结构回答（**平台能力 + 领域能力，缺一不可**）：
一、平台原生能力：多 Agent 团队协作、上下文对话、文件与图片处理、联网检索、任务编排等（沿用平台口径）。
二、本领域能力（<DomainSwarm> 已实现）：<逐条功能清单：案件管理 / 文书起草 / 合同审查 / 法规检索 / 合规检查 / 法务团队>。
三、引导句：「你可以说：审一下这份采购合同」「接手这个案件，管理立案到结案全流程」。
```

## 七、能力对齐清单（技能 ↔ RPC ↔ Agent ↔ 团队 ↔ 前端功能模块 ↔ 品牌）

| 校验项 | 规则 | 验证方式 |
|--------|------|---------|
| 技能引用存在 | agent 配置的 `skills` 目录必须存在 | validate_domain_project.py 自动核查 |
| RPC 已注册 | 技能/角色提及的 `legal.*` 必须在 extension.py 注册 | grep extension.py |
| 团队成员有效性 | `team` 段的 member_name 与 agent 配置、persona 一一对应 | validate_domain_project.py |
| 端口/鉴权配置 | <domain>_gateway 段齐全且不与默认端口冲突 | validate_domain_project.py |
| 前端功能模块（v2） | Spec 功能清单每项一个独立 `SidebarNavKey`（`<domain>-*`）+ 一个独立页面组件，`<domain>Api.ts` 有对应 RPC | validate_domain_project.py（前端检查节） |
| 品牌定制（v3） | `<domain>-ai-logo.svg` 存在于 `public/`；**浏览器页签 title（`index.html` `<title>`+`app.title`）已领域化**；i18n 欢迎语（zh+en）；**任务对话窗口 ChatPanel 硬编码中英文欢迎语/标语已领域化**；persona「能做啥」=平台+领域能力；**前端 `git grep -n "<旧品牌名>"` 零残留** | validate_domain_project.py + grep |
| 「能做啥」口径一致 | persona 能力描述 = `skills.list/team.list` 返回 = 前端「团队成员」页 | 冒烟对比 |
| 对话可识别-委派映射 | 协调技能 `*-swarm-coordination/SKILL.md` 含「委派映射」表，**每个 Spec 功能一行**（触发关键词→专员 id） | validate_domain_project.py + grep 委派映射 |
| 对话可识别-技能 RPC | 每个功能技能 SKILL.md 有「适用场景」+「调用 `<domain>.<x>.<y>`（参数）」；方法名与 extension.py/Api.ts/dispatch **四处一致** | validate_domain_project.py（技能 RPC 引用检查） |
| 对话可识别-persona | LEADER/worker persona「能做啥」逐条枚举领域功能，与 team.list/skills.list 同口径 | grep persona |
| **对话可执行-可执行通道段（v3.6）** | 每个功能技能 SKILL.md 含「可执行通道段」：REST 网关地址+方法+鉴权头（api_key 来自 config）+ 参数 JSON 契约，或已注册的 Agent 领域工具——模型拿到文档即能发起真实调用 | grep "可执行通道" + 抽查 SKILL.md |
| 对话可执行-对话代办冒烟 | 主对话下达查/录类指令 → **看日志/落库数据变化**（非只看回复文本）确认真实 RPC 调用；录类断言行数+1 可复核 | 由 domain-qa 全量执行（24l/24t，见 `../../domain-qa/SKILL.md`） |

## 八、常见错误

1. **技能名与目录不一致**：配置写 `contract-review`，目录叫 `contract_review` → 运行时加载不到。
2. **persona 里没说"不做什么"** → LEADER 抢活，成员职责漂移。
3. **技能步骤不落库** → 「交付=文本」违反领域交接入库原则。
4. **技能是纯描述**，没有对接 RPC/工具 → 无法真正执行。
5. **Agent 配置 id 不唯一/大小写混用** → 前端下拉与 RPC 路由错乱。
6. **「能做啥」回答只讲平台或只讲领域** → 必须二段式（平台能力 + 领域能力）。
7. **前端 RPC 名不一致**：`extension.py` / `<domain>Api.ts` / `dispatch_<domain>_rpc` 三处改其一忘其二 → 页面调用 404。
8. **i18n 不成对**：zh/en 只改一个 → 语言切换缺 key。
9. **功能清单未落库**：只做了前端展示没有后端写表 → 「交付=文本」界面化，验收不过。
10. **功能只有前端页签、任务对话不可识别**：技能 SKILL.md 没写「适用场景」/没写「调用 `<domain>.<x>.<y>`」、
    协调技能没加委派映射行、persona 没枚举该功能 → 用户在主对话说"生成一个财务报告"时模型不知道调 `report.generate`，
    功能形同虚设。做法：**每个新功能 = 前端页签 + 后端 RPC 落库 + 协调技能委派映射行 + 功能技能 SKILL.md 触发场景与 RPC**。
11. **技能"只聊不做"——模型能描述却发不起请求（v3.6 重点）**：技能只写了"调用 `gov.policy.search`"却没写**怎么调用**
    （REST 网关地址/方法/鉴权头/参数契约，或已注册的 Agent 领域工具）→ 模型回复"好的，已为您查询"却从未真实执行，
    数据无变化。做法：**每个功能技能 SKILL.md 必含「可执行通道段」**（见 §二·一 示例），录类操作对话代办后
    落库行数必须可复核（`count(*)` 或 list RPC），否则 qa 验收 24t 判 FAIL。