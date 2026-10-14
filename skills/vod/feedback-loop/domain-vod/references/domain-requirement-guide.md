# 领域需求引导漏斗与建 Issue 指南（domain-vod）

> 配套 `skills/domain-vod/SKILL.md`

## 一、知识基线速览（模板与先例）

**基线模板项目 `jiuwenswarm`（develop 分支，派生之源，Apache-2.0）**：

```text
jiuwenswarm/
├── jiuwenswarm/                          # 主平台包
│   ├── __init__.py                       # cli.py 入口，run_agent 化
│   ├── cli.py
│   ├── extensions/                       # 扩展层
│   │   ├── legal_platform/               # ★★★ 最近先例：法务 swarm 完整实现
│   │   │   ├── extension.yaml            #   领域扩展声明（id: legal_platform）
│   │   │   ├── extension.py              #   ApplicationPlugin：bind_web_channel 注册 legal.* RPC
│   │   │   ├── legal_backend.py          #   业务层（dispatch_legal_rpc + SQLite 落库）
│   │   │   ├── legal_gateway.py          #   领域 REST 网关
│   │   │   └── legal_gateway_tool.py     #   Agent 侧网关工具
│   │   └── ...                           #   框架级扩展（agentos/sdk/video_duplex）
│   ├── channels/web/frontend/src/        # 前端实现（功能模块所在地）
│   │   ├── components/LegalCasePanel/ 等    # 每个功能一个独立页面组件（导航多入口直挂；可选 WorkbenchPanel 聚合首页）
│   │   ├── services/legalApi.ts          #   webRequest('legal.xxx') 直调封装
│   │   ├── stores/legalStore.ts          #   领域状态
│   │   ├── utils/frontendPlatform.ts     #   SidebarNavKey 扩展（legalWorkbench/legalCase/...）
│   │   ├── public/legal-ai-logo.svg      #   左上角品牌 logo
│   │   └── i18n/locales/{zh,en}.json     #   nav.* + welcomeHeading/welcomeBubbleText 等
│   └── resources/
│       ├── config/config.example.yaml    # 配置示例（前端端口/模型/工作空间）
│       └── agent/legal_agent_configs/    # 法务 Agent 配置（LEADER + worker）
├── pyproject.toml
├── LICENSE                               # Apache-2.0 必须保留
└── start-backend.bat / start.sh          # 启动脚本
```

**最近先例 `legal_platform`（法务 swarm，当前项目 develop 分支产物，**第一条实施参考**）**：

- 后端：`extensions/legal_platform/` 以 `ApplicationPluginExtension` 暴露 `legal.*` RPC（12+ 个：
  `legal.contract.review` / `legal.document.draft` / `legal.case.create|list|get` / `legal.search_law`
  / `legal.compliance.check` / `legal.skills.list` / `legal.team.list` 等），浏览器 `webRequest('legal.xxx')`
  直连；另起独立 REST 网关 `/api/legal/*`；全部业务走 `legal_backend.dispatch_legal_rpc` 落 SQLite。
- 前端：左侧导航新增 7 个法务页签（案件管理/文书起草/合同审查/法规检索/合规检查/法务团队/法务工作台），
  左上角 logo 替换为 `legal-ai-logo.svg`，任务欢迎语走 i18n，Agent 回答「能做啥」= 平台能力 + 法务能力清单。
- 结论：**领域 Swarm = 领域技能 + 功能模块（前端页面可点可查 + 后端 RPC 落库）+ 品牌定制**。

**远先例 `eduSwarm`（成熟领域 Swarm，AI 智慧课堂，模式补充）**：

```text
eduSwarm/
├── jiuwen_edu/                           # 「新项目根」（模板派生重命名）
├── start.sh / start-backend.bat           # 启动脚本
└── jiuwenswarm/
    ├── extensions/edu_platform/           # 领域扩展层（edu_backend/gateway/extension）
    ├── resources/agent/edu_agent_configs/ # 领域 Agent 配置（10 个 JSON）
    └── resources/agent/workspace/skills/  # 教育技能库（44 md）
```

## 二、需求引导漏斗（判定要不要追问 + 问什么）

### 判定表：当前消息是否已给「领域需求要素」（四要素 + 功能模块期望）

| 要素 | 判定问题 | 示例回答 |
|------|---------|---------|
| 目标用户 | 谁在用？（部门/角色/场景） | 公司法务部 / 律所律师 / 医院科室 |
| 领域任务 | 最想解决的 2-3 个日常任务 | 合同审查、法规检索、文书生成、案件管理、合规清单 |
| 产品命名 | `<Domain>Swarm` + 中文品牌名 | LegalSwarm · 法务智能工作台 |
| 落地模式 | 模式 A 新仓库 / 模式 B 当前模板仓库改造 | 现改 jiuwenswarm（develop 分支） |
| 功能模块期望 | 想在**前端左侧导航看到哪些可点页面**？对应**后端存哪些数据**？**每个功能打开后要能做什么操作（增/删/改/查/报表）、看到哪些字段**？ | 案件管理（列表/详情/建档、可新增/编辑/删除），文书起草，合同审查，法务团队…全部落库 |
| 对话代办操作期望 | **用户想通过主对话直接让 AI 代办哪些操作**？（查/录/改/删/报表，哪些允许对话代办） | 政策法规库：对话"帮我查一下 XX 法规"→真实 `gov.policy.search` 返回结果；"帮我录入/导入这条法规"→真实 `gov.policy.import` 落库；"列出最近 5 条政策"→真实 list。删除/修改慎用对话代办，页面操作为主 |
| 产品设计细节 | 每个功能**做"能用的壳子"要的细节（gov 实测教训）**：列表**每列字段/查询条件/分页**；新增·编辑表单字段（必填/默认值/**校验规则**：长度·格式·唯一）；操作按钮（新增/编辑/删除/状态流转）；删除是否二次确认；**空数据/加载中/操作失败分别显示什么** | 案件建档表单：案由必填≤100 字、当事人必填、金额数字、状态下拉；删除案件弹确认框；无案件时空态提示 + "新建案件"引导 |

### 追问规则

1. **结合最新先例提问**（当前项目 legal_platform 就在模板仓库内，直接举例，不诉诸模板腔）：
   - 「按法务那套（legal_platform），左侧导航有案件管理/文书起草/合同审查/法规检索/合规检查/法务团队。
     你的领域想做成哪几个可点的功能模块？每个大概存什么数据？」
   - 「每个功能打开后要能**做什么操作**？比如案件管理除了看列表，还要能**新增/编辑/删除**案件吗？大概要录哪些字段？
     有没有要自动生成/统计的报告？」（采集操作闭环需求，供 issue 做交互闭环设计）
   - **必问「对话代办操作」（gov 实坑：漏问则功能只剩页面、对话跟 AI 提需求"只聊不做"）**：
     「除了在页面操作，你希望用户能在**主对话**里直接跟我说'帮我**查**一下 XX 法规''帮我**录/导入**一条 XX 数据'
     的时候，我真的去执行**查询/录入/修改/删除**吗？**哪些操作允许这样对话代办**？
     比如政策法规库：说'帮我查一下安全生产政策'我就要真去查并给出可验证结果；说'帮我录入这条政策'我就要真落库。修改/删除这类高风险操作建议页面为主、对话代办按需开放」
     （采集对话代办操作清单，供 issue 写进 Spec 段 2「对话代办操作闭环」、coding 给技能写「可执行通道段」、qa 做「对话代办闭环」验收判据）
   - 「每个功能做出来要**多好用**？表单哪些字段必填、加什么校验（比如文号不能重复）？删除要二次确认吗？
     没有数据时页面显示什么？操作失败要提示什么？」（采集**产品设计细节**，供 issue 做段 1 产品设计——
     只写"列表+CRUD"会生成"能看不能用的壳子"，gov 已踩坑）
   - 「你想要**几个领域专家角色**（LEADER + 几人）？大致分工？」
   - 「产品名想叫什么？比如 LegalSwarm？中文品牌名？」
   - 「在 jiuwenswarm 的 develop 分支上直接增量实现，对吗？」
2. 每次 1-3 个问题，不重复已确认项。
3. **≤3 轮**；超限建「待澄清」Issue（body 列出已获取/缺失清单），主动给占位假设，不阻塞。

## 三、VOD 自建 Issue 要点（简明版）

- 标题：`feat: <Domain>Swarm <中文品牌名> 领域 Swarm 生成`
- 打标签 `enhancement`
- body 按 §四模板只填已确认/已假设项
- 标注 `auto-submitted by domain-vod Agent`

## 四、建 Issue 完整模板

```markdown
---
title: "feat: LegalSwarm 法务智能工作台 领域 Swarm 生成"
labels: ["enhancement"]
assignees: []
---

## 领域需求（domain-vod 自动提交）

### 1. 目标用户
- 公司法务部、律所初年级律师（示例：替换为用户确认内容）

### 2. 领域任务简介（2-3 个核心任务）
- 合同审查：风险条款识别、修改建议
- 法规检索：带来源的检索报告
- 文书生成：起诉状/答辩状/合同初稿
- 【示例占位，由 domain-issue 细化为落地产物】

### 3. 产品命名
- `<Domain>Swarm`：LegalSwarm · 法务智能工作台

### 4. 落地模式
- 模式 B：当前模板仓库 jiuwenswarm **develop 分支**增量实现（默认）
- 模式 A：新仓库（从 jiuwenswarm 模板派生）✩ 待确认

### 5. 功能模块期望（前端左侧导航页签 + 后端能力 + 每功能操作方法 + 产品设计细节）
- 案件管理：列表/详情/新建案件，支持**新增/编辑/删除**（后端 `legal.case.*` 落库，字段：案由/当事人/金额/状态）
  - **产品设计细节**：列表列=案由/当事人/金额/状态/操作；新建表单：案由必填≤100 字、当事人必填、金额数字、
    状态下拉默认"立案"；删除二次确认；无案件空态"暂无案件，点击右下角新建"；加载中 spin、失败红字提示；分页每页 20
  - **对话代办操作**：允许对话代办"查案件/新建案件"；**删除/修改暂不开放对话代办**（页面操作为主）
- 文书起草：模板选择 → 生成 → 保存
  - **对话代办操作**：支持对话"起草一份 XX 文书"→ 真实生成并保存落库
- 合同审查：上传/粘贴 → 风险点 → 审查报告落库
  - **对话代办操作**：支持对话"审查这份合同"→ 真实调用审查 RPC 产出报告落库
- 法务团队：成员/技能展示（由 Agent 配置驱动）
  - **对话代办操作**：对话"你能做什么/团队有哪些人"→ 返回 `team.list`/`skills.list` 真实数据
- 【示例占位，由 domain-issue 抄入 Spec 功能清单（段 1 产品设计 + 段 2 交互闭环 + 段 2 对话代办操作闭环），domain-coding 一一实现】
```

## 五、A2A 交接格式（domain-vod → domain-issue，流水线第一跳）

> v2：交办 payload **必须携带 `readiness`（就绪度评级）与 `next_hop`（下一步=domain-coding）**，
> 并由 `allowed_agents` 允许 coding 接力，保证 vod → issue → coding 第二跳不被截断。

```text
POST /api/a2a
{
  "agent": "issue",
  "payload": {
    "execution": "advance",
    "workspace": "D:/code/jiuwenswarm",
    "project_id": 83,
    "issue_id": 83,
    "pipeline_id": 68,
    "issue_repo_id": 83,
    "issue_repo": "jiuwenswarm",
    "issue_title": "feat: LegalSwarm 法务智能工作台 领域 Swarm 生成",
    "issue_body": "【即可复制 A4 模板内容】",
    "readiness": "ready",                            // v2 新增：ready / almost-ready（needs-discussion 禁止交办）
    "review_items": ["落地模式 A/B 需在 Spec 决策表确认"],  // v2 新增：almost-ready 时的待复核项，ready 可空
    "next_hop": "coding",                            // v2 新增：提示 issue 完成 Spec 后继续交办 domain-coding
    "skill_hints": "参考领域 Spec 设计指南 references/domain-spec-guide.md，复用 jiuwenswarm（develop 分支）模板 + 仓库内 legal_platform 先例（含前端功能模块与品牌定制）",
    "knowledge": {"lar_participants": 1, "template_repo": "D:/code/jiuwenswarm", "branch": "develop", "reference_repo": "D:/code/jiuwenswarm/jiuwenswarm/extensions/legal_platform"},
    "allowed_agents": ["issue", "coding", "qa", "sre"]   // 必须含 coding，保证第二跳
  }
}
```

⚠️ **重复 A2A 检查**：A2A 前看 prompt 中 Issue Pipeline 信息，若已含 `issue:a2a_event`，
**不要重复 A2A**，只发评论回复即可。

### 接力约定（vod → issue → coding）

```text
① domain-vod   → A2A agent=issue        （本技能，第一跳，必发）
② domain-issue → A2A agent=coding        （issue 完成 <spec> 后接力发出，第二跳）
③ domain-coding→ A2A agent=qa           （coding 完成实施后发出，验收）
```

- vod **禁止**直接 A2A `coding` / `qa`：coding 必须以 issue 产出的
  `<spec>`（含领域功能清单 + 验收标准）为实施输入，否则实施无法对齐验收。
- 就绪度评级为「待澄清 / needs-discussion」的 Issue **不进行 A2A**，先评论引导收敛。

## 六、就绪度检查四维速查（A3a 配套）

> 供 domain-vod 在交办前自检，参照 issue-advance 的 developability-analysis 思路领域化。

| 维度 | 通过判据 | 反例（降级/追问） |
|------|---------|------------------|
| 需求完整性 | 四要素 + 功能模块期望 + **每功能对话代办操作期望**全部落到 Issue 模板 | 功能模块期望空白 / 用户角色含糊 / 对话代办操作完全未知且未标注待补 |
| 技术可行性 | 有基线模板 + legal_platform 先例可循（扩展机制/RPC/落库/前端导航） | 引入先例未覆盖的新外部依赖或大改框架核心 |
| 依赖就绪性 | 模板与先例已具备全部依赖（可本地读取） | 需第三方服务/付费 API 且未就绪 |
| 范围确定性 | 落地模式 A/B 已定、端口 192xx 可规划、改动面（扩展+前端+Agent+品牌）可预估 | 落地模式未定 / 功能模块数量完全无法预估 |

评级：四维通过 → `ready`；≤2 维 minor 缺失可推断 → `almost-ready`（payload 带 `review_items`）；
任一 major 缺失 → `needs-discussion`（禁止交办，先引导）。保守原则：ready/almost-ready 犹豫取 almost-ready。