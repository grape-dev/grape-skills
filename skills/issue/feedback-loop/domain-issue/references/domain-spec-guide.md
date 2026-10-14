# 领域 Swarm Spec 设计指南（domain-issue）

> 配套 `skills/domain-issue/SKILL.md`

本指南把「vod 交办的领域需求（四要素 + 功能模块期望）」深化为完整 Spec：领域画像 →
落地信息 → 团队角色表 → 技能清单 → 事件通道 → 数据对象 → **领域功能清单** →
交付物清单 → 验收标准。供 domain-issue 设计，并作为 coding/qa/sre 的验收基线。

> 领域 Spec 的灵魂（相对 eduSwarm 模式的最大升级）：**不只是"对话型领域技能"，
> 还要有"可点可查可落库"的领域功能模块**——前端左侧导航页签（如案件管理）+ 后端 RPC（`legal.case.*`）。
> 参考先例 = 基线仓库 `jiuwenswarm`（develop 分支）内的 `extensions/legal_platform/` + 前端 `LegalWorkbenchPanel`。

## 一、领域画像（承接 vod，补全用户场景）

| 字段 | 说明 | 示例（法务 LegalSwarm） |
|------|------|------------------------|
| domain | 领域名（全小写） | `legal` |
| product_key | 产品标识（大驼峰） | `LegalSwarm` |
| brand_name | 中文品牌名 | 法务智能工作台 |
| users | 目标用户列表 | 公司法务部 / 律所初年级律师 |
| tasks | 核心任务列表（≤5） | 合同审查、法规检索、文书生成、案件管理、合规清单 |
| pain_points | 解决痛点 | 人工审合同慢、法规更新追踪难、文书模板不统一 |

## 二、落地信息（二次开发落点，关键决策表）

> 模板 `jiuwenswarm` 是派生之源；所有领域能力走**扩展层**，不侵入框架核心。
> ⚠️ **落地模式固定（v2.4）**：基线模板仓库 `develop` 分支为**只读基线**，二次开发在从 develop 新建的
> `issue-{N}` 开发分支上增量实现（同仓多领域，完成 PR 合回 develop）。**不再提供「模式 A 新仓库派生」，
> 不再询问用户落地方式**。

| 决策点 | 取值（固定，不提供选项） | 说明 |
|--------|------|------|
| 落地模式 | **模式 B（当前模板仓库改造）** | 固定；新仓库派生（模式 A）已废弃 |
| 基线分支 | `develop`（只读） | 只从 develop 派生；**禁止直接改 develop** |
| 开发分支 | `issue-{N}`（从 develop 新建，如 `feat/issue-1`）| 二次开发增量全部落在开发分支，完成 PR 合回 develop |
| 落地位置 | `<repo>/jiuwenswarm/extensions/<domain>_platform/` | 固定 |
| Agent 配置目录 | `<repo>/jiuwenswarm/resources/agent/<domain>_agent_configs/` | 固定 |
| 技能目录 | `<repo>/jiuwenswarm/resources/agent/workspace/skills/`（内置目录，`source='builtin'`）；**交付物必须含 `skills.install <技能名>` 安装说明**（装到用户技能目录后 source 变 `local`，才能出现在前端「技能→我的技能」，否则 UI 不可见） | 固定 |
| 前端模块目录 | `<repo>/jiuwenswarm/channels/web/frontend/src/components/<Domain><Feature>Panel/`（每功能独立组件；可选聚合首页 `<Domain>WorkbenchPanel/`）| 固定（多入口直挂导航）|
| 领域 API 层 | `<repo>/.../src/services/<domain>Api.ts` + `stores/<domain>Store.ts` | 固定 |
| 品牌资源 | `<repo>/.../src/public/<domain>-ai-logo.svg` + i18n `{zh,en}.json` | 固定 |
| 前端端口 | `5173` | 沿用模板（避免与 WorkSwarm 桌面端抢占时另配） |
| 领域网关端口 | `192xx`（避 5173/1793/18092/19000/19001） | 法务先例 19210，新领域 19210+ |
| 后端端口 | `18092` | 与模板一致 |
| 模型 | 默认 GPT-4o / 按模板 config 覆盖 | 沿用 |

## 三、团队角色表（LEADER + N 专职）

> 设计原则：**LEADER 统筹不干活 + N 专职分散职责**，参考 eduSwarm（1 LEADER + 6 worker）。

| # | role_id | member_name | 角色中文名 | persona 摘要 |
|---|---------|-------------|-----------|-------------|
| 0 | `<domain>_leader` | `<domain>_leader` | <领域>主管 LEADER | 统筹任务拆解与团队协调，不亲自干活 |
| 1 | `<domain>_contract_reviewer` | `<domain>_contract_reviewer` | 合同审查员 | 风险条款识别/修改建议/审查意见书落库 |
| 2 | `<domain>_researcher` | `<domain>_researcher` | 法律研究员 | 法规检索报告带来源 |
| ... | ... | ... | ... | ... |

> N 建议 4-8 专职；每人对应 ≥1 领域技能 + 事件通道。

## 四、技能清单（技能名唯一，落 skills 目录）

| # | skill_name | 描述 | 参考案例 |
|---|-----------|------|---------|
| 1 | `合同审查意见生成` | 输入合同文本→风险条款分级意见书 | edu 备课助手 模式 |
| 2 | `法律检索与报告` | 带来源法规检索→检索报告 | ... |
| ... | ... | ... | ... |

## 五、事件通道（CORE_ACTOR/LEADER_REPORT/CONTROL_RETURN 之外的自定义通道）

- 主通道：`core_actor`、`leader_report`、`control_return`（复用模板，start-leader 签名固定不得改）
- 领域自定义通道：如 `docs_review`（Leader→成员）、`case_dispatch` 等，须在 Spec 说明 event_key + 方向

## 六、数据对象（建议 set_tool_register，不引第三方 DB）

| 对象 | 关键字段 |
|------|---------|
| 审查意见书 | id/合同id/风险等级/条款位置/问题描述/修改建议/生成时间 |
| 检索报告 | id/关键词/来源/结论/时间 |
| 案件 | id/案由/当事人/阶段/承办人/时间 |

## 七、领域功能清单（前端页签 + 后端 RPC/REST 落库，Spec 必填）

> **这是领域 Swarm 「能不能用起来」的关键**：每个功能点都要有「前端左侧导航页签可点 → 直调后端 RPC →
> 业务落库」，用户不用依赖 LLM 也能操作（参考法务实现：案件管理/文书起草/合同审查/法规检索/合规检查/法务团队）。
> ⚠️ **多入口直挂**：每功能 1 个独立 `SidebarNavKey` + 1 个独立页面组件，左侧导航逐项并列显示（数量=功能数）；
> 禁止把所有功能打包成单个工作台入口再分 tab/mode 切换（聚合首页如有，仅作补充入口，不替代各功能入口）。
> ⚠️ **页签插位规定（v2.4，qa 24o 判据）**：所有领域功能页签**按功能清单顺序**且**必须出现在「任务」(chat) 之下、`skills` 之上**——
> 静态数组 `domainFeatureNavItems` 紧扣 chat 后、按功能清单顺序排列，应用插件动态页签 `applicationPluginItems` 组装时同样插在
> chat 与 skills 之间（按 `position` 排序）；**禁止 append 导航数组末尾**（gov 实坑：领域页签排到"更新"等
> 平台页签之后、用户滚到底才找得到）。

| # | 功能名 | 前端导航 key（`SidebarNavKey`） | 页面组件 | 后端 RPC（`<domain>.xxx`） | REST 路由 | 落库表 |
|---|--------|-------------------------------|---------|---------------------------|-----------|--------|
| 1 | 案件管理 | `legalCase` | `LegalCasePanel` | `legal.case.list/create/get/update` | `/api/legal/case/*` | cases |
| 2 | 文书起草 | `legalDocument` | `LegalDocumentPanel` | `legal.document.draft/list/save` | `/api/legal/document/*` | documents |
| 3 | 合同审查 | `legalContract` | `LegalContractPanel` | `legal.contract.review/list` | `/api/legal/contract/*` | contract_reviews |
| 4 | 法规检索 | `legalSearch` | `LegalSearchPanel` | `legal.search_law` | `/api/legal/search/*` | search_logs |
| 5 | 合规检查 | `legalCompliance` | `LegalCompliancePanel` | `legal.compliance.check` | `/api/legal/compliance/*` | compliance_reports |
| 6 | 法务团队 | `legalTeam` | `LegalTeamPanel` | `legal.team.list` / `skills.list` | `/api/legal/team/*` | （Agent 配置驱动）|

- 每行「前端 + RPC + 落库」三件套缺一不可；数据报表类允许只读（列明 `只读`）。
- RPC 统一挂在扩展的 WebChannel（`ApplicationPluginExtension` + `bind_web_channel`），浏览器 `webRequest('<domain>.xxx')` 直调。
- 品牌定制项并入功能清单「验收」：左侧栏 logo（`<domain>-ai-logo.svg`）、任务欢迎语（i18n `welcomeHeading/welcomeBubbleText/welcomeSuggestions`）、
  Agent「能做啥」回答 = 平台能力 + 领域能力清单。

### 七·一 每功能「产品设计与前后端交互闭环设计」（Spec 必填，先设计后编码）

> **历史教训（gov 领域实测）**：档案类模块（公文管理/政策法规库…）spec 若只写
> 「列表 + 新增编辑表单，CRUD 落库」几个字，coding 只能做出**能看不能用的壳子**——
> 无字段校验、无空态引导、无 loading、失败不提示、分页缺失，可用性极低。
> 因此本小节**先做产品设计、再定交互闭环**：想清楚用户怎么用起来（建什么字段、
> 校验什么、点完看到什么、空/错/忙时显示什么），coding 才做得可用，qa 才验得过。
> **每个 Spec 功能都要填下表两段**：

#### 段 1：产品设计（模块可用性源头，Spec 必填）

| 项 | 必须写明 |
|----|---------|
| 目标用户与场景 | 谁在该页做什么？（一句话，如"文秘登记收发文、主任审批归档"） |
| **布局与排版规格** | 页面布局方式：**单面板整页** / **多面板等宽平铺** / **卡片网格**；多面板/卡片必须写明在**宿主容器中的占位分配**（等宽平铺声明 `flex: 1 1 0%` + `width: 100%`；grid 写明列数与 `minmax`），**禁止只定义面板内部样式、不声明外部容器伸缩/宽度**（finance 实坑：`.fin-panel` 缺占位 → 四面板 flex 容器中无法等宽平铺）；内容超长时哪些区滚动、页面**无横向溢出** |
| 列表规格 | 每列：列名 / 数据字段 / 是否排序；分页（后端 page/page_size、默认每页 20）；默认排序字段 |
| 查询条件 | 查询区字段与控件（关键字 / 下拉 / 日期范围），一一对应 `list` RPC 入参 |
| 表单规格 | 每字段：名称 / 类型 / 控件（输入/下拉/日期/多行/数字）/ 必填 / 默认值 / **校验规则**（长度、格式、范围、下拉必选、唯一性） |
| 操作按钮集 | 工具栏（新增/批量删除…）+ 行内操作（查看/编辑/删除/状态流转）；每按钮→触发 RPC→成功反馈（提示+列表刷新） |
| 状态与反馈 | **空态**（无数据文案+引导新建）、**错误态**（`ok:false` 红字提示，不静默）、**loading 态**（提交/拉取中禁用按钮）、**删除二次确认**、分页/加载更多 |

#### 段 2：前后端交互闭环四件套（字段级对齐段 1）

| ① 数据模型 | 落库表名 / 字段名（类型/主键/必填）/ 写操作是否持久化；与段 1 表单字段同名映射 |
|---|---|
| ② RPC 规格 | 方法名 `<domain>.<entity>.<action>`；入参 `params` 字段（=表单字段）；返回 `{ok:true,data}` / `{ok:false,error}`；`list` 支持 keyword/page/page_size |
| ③ 前端页面规格 | 查询区/列表区/操作区三段式；列表列 ↔ 段 1 列表规格；表单字段 ↔ 段 1 表单规格 ↔ RPC 入参 ↔ 表字段一一映射；空态·错误·loading 文案固化 |
| ④ 用户操作闭环 | 新增→列表立即可见；修改→刷新显示最新；删除→列表移除（+确认）；查询→过滤生效；每步写明"操作→RPC→落库→界面效果" |

#### 段 2·补：「对话代办操作闭环」（Spec 必填，gov 实测补强）

> **为什么必填（gov 实坑）**：只做页签 + RPC，用户在**主对话**说"帮我查一下 XX 政策/帮我录入一条法规"时，
> 模型要么"只聊不做"（回文本说让我去查结果却从不实际执行）、要么不知道调哪个 RPC。因此每个功能必须
> 明确「对话代办边界」与「指令→RPC→落库→页签可见」链路，coding 据此外为技能写**可执行通道段**，
> qa 据此做**对话代办闭环**验收。**高风险操作（删除/大额修改）建议页面为主、对话按需开放；只读与录入类
> 操作优先支持对话代办。**

| ⑤ 对话代办边界 | 本功能**哪些操作开放主对话代办**（查/录/改/删/报表），哪些不开放（页面为主） |
|---|---|
| ⑥ 对话代办指令示例 | 每条：用户说的话示例（"帮我查一下 XX 法规""帮我录入这条政策：标题=…文号=…正文=…"）→ 触发技能场景 → 调用的 RPC（如 `gov.policy.search` / `gov.policy.import`）→ 返回/落库 → 前端页签可见；标注**可执行通道**：扩展 RPC（本机 WebChannel）+ 领域 REST 网关（`POST /api/<domain>/<action>`，携带 `X-API-Key: <api_key>`，api_key 由 Agent 从 config `<domain>_gateway` 段读取，不硬编码） |

**高质量示例（政务-公文管理，对照"可用性低"教训写细）**：

| 目标用户与场景 | 文秘登记收发文起草，主任审批，档案员归档，全程留痕可查 |
|---|---|
| 布局与排版规格 | 单面板整页（每功能独立面板）；若「报表分析」等多结果需并列展示 → 多面板等宽平铺：面板声明 `flex: 1 1 0%` + `width: 100%`（宿主 flex 容器），列表超长区域内滚、页面无横向溢出 |
| 列表规格 | 列：文号/标题/来文单位/文件类型/密级/收文日期/状态/操作；分页 page_size=20 默认收文日期倒序 |
| 查询条件 | 关键字（标题/文号）+ 文件类型下拉 + 状态下拉 + 日期范围 → 对应 `gov.document.list` 入参 |
| 表单规格 | 标题：文本·必填·≤100 字；文号：文本·必填·**唯一校验**；来文单位：下拉·必填；文件类型：下拉（公文/通知/请示…）必填；密级：下拉（公开/内部/秘密）默认公开；正文：多行·选填 |
| 操作按钮集 | 工具栏「发文登记」；行内「查看/编辑/删除/提交审核」；各自→`gov.document.create/update/delete/submit`→成功 toast+列表刷新；失败红字提示 |
| 状态与反馈 | 空态"暂无公文，点击右上角发文登记"；提交中按钮 loading 防重复；删除弹确认框；分页加载更多 |
| ① 数据模型 | `gov_documents`：id(PK)/doc_no(文号 必填 唯一)/title(标题 必填≤100)/from_unit/type/secret_level/status/body/created_at/updated_at |
|---|---|
| ② RPC 规格 | `gov.document.create{doc_no,title,from_unit,type,secret_level,body}`、`gov.document.list{keyword,type,status,date_from,date_to,page,page_size}`、`gov.document.get{id}`、`gov.document.update{id,...}`、`gov.document.delete{id}`、`gov.document.submit{id}`；写操作返回 `{ok:true,data:{id}}` |
| ③ 前端页面规格 | 查询区（关键字/类型/状态/日期）→ 列表区（上文列+操作）→ 发文登记/编辑弹窗（字段与 RPC 入参同名）；空态/loading/错误红字/删除确认弹窗 |
| ④ 用户操作闭环 | 发文登记→`create`→落库→列表首行出现；编辑→`update`→行内最新值；删除→确认→`delete`→行消失；提交审核→`submit`→状态列变"待审核"；查询→`list`→过滤生效 |
| ⑤ 对话代办边界 | 开放**查询/录入/列表/提交审核**；**删除不开放对话代办**（页面确认框兜底，防误删） |
| ⑥ 对话代办指令示例 | "帮我查一下安全生产相关的政策"→触发技能 `gov-policy-research`→实际调用 `gov.policy.search{keyword:安全生产}`→返回结果列表并可在「政策法规检索」页签复核；"帮我录入这条政策：标题=…文号=…正文=…"→实际调 `gov.policy.import{title,doc_no,body,...}`→落库→「政策法规库」页签首行可见（可执行通道：领域 REST 网关 `POST /api/gov/policy/import` + `X-API-Key` 从 config `<domain>_gateway` 段读取） |

- 只读功能（查询/报表）在段 2 标注「只读」，但段 1 的列表/查询/loading/空态照写；
- 写操作（增/改/删/状态流转）**必须落库并让前端刷新列表**；任何前端操作都**必须有可见反馈**
  （成功提示/失败红字），**禁止"点了没反应"**；
- RPC 方法名约定 `<domain>.<entity>.<action>`（`action∈{list,get,create,update,delete,submit,...}`），
  `list` 支持 keyword/page/page_size；写读动词尽量成套，保证闭环可测；
- **对话代办操作必须可"真执行"**：每个开放的对话代办指令要么落到**扩展 RPC**（本机 WebChannel `webRequest('<domain>.xxx')`）、
  要么落到**领域 REST 网关**（`<domain>_gateway` 段启用 + `X-API-Key` 鉴权）——只写"让 Agent 帮你查一下"而不给可执行通道
  的 Spec 会导致 coding 的技能全是"纯描述聊天"，找不到可执行入口。

## 八、交付物与验收标准（写入 Spec §验收）

| 验收项 | 判据 |
|--------|------|
| 领域扩展层在模板上增量新增，框架核心目录未大改 | diff 检查 |
| 健康检查 | `GET /api/<domain>/health` 返回 success |
| Agent 配置 JSON 数量 ≥ LEADER+N | 域 agent_configs 计数 |
| 技能库含 ≥N 个领域技能 | skills 目录计数 |
| **功能模块 ≥ 6**（前端页签 + RPC + 落库三件套齐全） | 前端 `SidebarNavKey` 含 `domain*` key；RPC 数量 ≥ 功能数 |
| **对话代办操作闭环完整（每功能）** | 每个功能 Spec 段 2 含「⑤ 对话代办边界 + ⑥ 指令示例→RPC→可执行通道（扩展 RPC 或 REST 网关+鉴权）」，且对应 RPC 在段 2 ② 存在 |
| 前端品牌化 | `<domain>-ai-logo.svg` 在左侧栏展示；i18n 欢迎语生效；「能做啥」含平台+领域能力清单 |
| 文档四件套 | README/部署指南/架构图/经验分享 |
| **开源声明保留** | LICENSE/开源声明未删改 |

## 九、Spec 模板（domain-issue 输出骨架）

```markdown
## 领域画像
---

## 落地信息（决策表）
---

## 团队角色表
---

## 技能清单
---

## 事件通道
---

## 数据对象
---

## 领域功能清单（前端页签 + 后端 RPC 落库，三件套缺一不可）
| 功能名 | 前端导航 key | 页面组件 | 后端 RPC | REST 路由 | 落库表 |
> 每功能必附「七·一 产品设计与前后端交互闭环设计」——段 1 产品设计（列表/查询/表单/校验/状态反馈）；
> 段 2 四件套（数据模型 / RPC 规格 / 页面规格 / 用户操作闭环）+ **段 2·补 对话代办操作闭环
> （⑤ 对话代办边界 + ⑥ 指令示例→RPC→可执行通道）**，
> 提交给 coding 实施并作 qa 端到端验收与对话代办闭环验收蓝本；**缺产品设计、闭环设计或对话代办操作闭环均视为 Spec 未完成**。
---

## 交付物清单与验收标准
- 验收项覆盖：扩展层 diff / 健康检查 / Agent 配置数 / 技能数 /
  功能模块（页签数、RPC 数、落库表）/ 品牌（logo、欢迎语、「能做啥」= 平台+领域能力）/
  文档四件套 / 开源声明保留
---

## 附录：风险与兜底
- 框架升级冲突时：仅更新扩展层适配 (尽快与上游同步特性)
- 权限/合规：检索结果必须带来源，不杜撰法条
```