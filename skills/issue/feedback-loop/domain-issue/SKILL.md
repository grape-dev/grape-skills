---
name: domain-issue
version: 2.5.0
description: |
  面向 jiuwenswarm 领域模板仓库的领域 Swarm 二次开发设计（Grape Issue 阶段）：把 vod 需求深化为可实施规格 <spec>（领域画像/落地决策/
  团队角色/技能清单/事件通道/数据对象；功能模块：前端页签+页面组件+后端 RPC/REST+落库表；每功能产品设计
  与前后端交互闭环、对话代办闭环；品牌规格；交付物与验收标准）。更新 Issue body，A2A 交 domain-coding，
  只输出规格不写代码。方向预设（最高优先）：在模板仓库 develop 分支上二次开发完整领域化 swarm，全程
  不问方向，缺要素默认决策记 review_items；落地 = 从 develop 新建 issue 分支增量实现（基线只读）。
  段 1 产品设计必含「布局与排版规格」——布局方式（单面板/多面板等宽平铺/卡片网格）、多面板须
  声明宿主容器占位分配（等宽平铺 `flex:1 1 0%`+`width:100%`），溢出滚动、无横向溢出。
tools:
  - grape
  - bash
---
## 安全硬约束（必须遵守）

1. **CLI 优先**：凡 grape CLI 能做的走 CLI，禁止绕过 CLI 直连平台 API（curl/python httpx 等）。CLI 未装/版本过低 → **自动安装/升级**（官方源/签名包优先）→ 装好继续；仅当安装失败/环境不可用时才报障说明（不降级直连）。⚠️ 安装指引见 `references/grape-cli-installation.md`。
2. 调用仓库 API 只用 prompt 注入的 `$GRAPE_SESSION_TOKEN`，严禁从数据库/configs/日志/历史中寻找其他 token。
3. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据（`data/workspaces/` 项目知识文档除外）。
4. API 返回 403/无权限时：立即停止该操作并回复用户「该操作需要管理员/维护者权限，请手动配置后重试」，严禁绕行手段。
5. 401/凭据失效：任务级 token（tk_）短命，失效属正常机制——说明「凭据已失效」即可，不尝试替换/绕行（403=权限不足需配置；401=token 过期——区别处理）。
6. token 不得写入任何文件/日志/评论。
7. **本技能只改 Issue body 与评论，绝不写实现代码、不建 PR。** 模板项目受 Apache-2.0 保护，不删不改开源声明。

# 领域 Swarm 二次开发设计（domain-issue v2.5）

## 环境变量表（平台注入，按 issue Agent 类型）

| 变量 | 语义 | 用在哪 | 何时有 |
|------|------|--------|--------|
| `$GRAPE_SERVER_URL` / `$GRAPE_SESSION_TOKEN` | 服务端地址 / 会话 token（tk_） | grape CLI 自动读取 | 全部任务 |
| `$REPO_FULL_NAME` | 仓库全名（owner/repo） | A2A 交办 `repository`；`--owner`/`--repo` 拼装 | 全部任务 |
| `$REPO_OWNER` | 仓库属主 | CLI 用 `--owner` | 全部 |
| `$REPO_NAME` | 仓库名（派生：`${REPO_FULL_NAME#*/}`） | CLI 用 `--repo` | 全部 |
| `$ACCOUNT` | 个人账号（触发人 actor） | A2A payload `account` | 全部 |
| `$ISSUE_NUMBER` | Issue 编号（A2A 接入时注入） | `--number` / A2A payload | 全部任务 |
| `$DEVOPS_EVENT_TYPE` | 事件类型 | 场景路由判断 | 全部 |

派生变量：`REPO_NAME` = `${REPO_FULL_NAME#*/}`。敏感变量（token 类）**不 printenv、不落盘**。

## 前置检查门（自愈 → 重试 → STOP）

| 检查项 | 判定命令 | 通过标准 | 失败动作 |
|--------|---------|---------|---------|
| CLI 可用 | `grape --version` | ≥0.3.2 | **自愈**：按 `references/grape-cli-installation.md` 自动安装/升级（`timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git`）→ 装好再验证一次；仍不可用 → 输出「前置检查未通过：<原因>」并结束任务 |
| 契约刷新 | `grape refresh` | 拉取最新契约成功 | **重试** ≤2 次；仍失败 → 继续（回退内置快照） |
| 任务上下文 | `grape tasks current --json-out` + `grape issues detail` | 拿到任务与上下文（含 A2A payload） | ISSUE 缺失 → 用 `grape git-repo issues get` / `issues list` 定位；定位不到 → STOP（不执行写操作） |
| 项目知识基线 | prompt 内联注入（主路径——基线由平台服务端维护） | 返回基线摘要 | 「无基线」/`[degraded]` → 降级分析（references + README），不阻塞 |
| 瞬时失败（网络/限流） | — | — | **重试**：自动重试 ≤3 次（退避 1s/2s/4s） |

> 本技能无外部凭据类前置——token 由平台注入，不要求用户配置任何东西。

## 定位

领域 Swarm 工厂流水线的**第二站**，职责是「把二次开发需求定义成可实施的前后端改造规格」：

- **职责内**：编写领域 Spec（画像/落地/角色/技能/通道/数据 + **功能模块实施规格** + **品牌改造规格** + 验收）→ 更新 Issue body → A2A 交办 `domain-coding`。
- **职责外**：不写前后端代码（domain-coding）、不质检（domain-qa）、不部署（domain-sre）。

### 方向预设（最高优先，v2.4）

> ⚠️ **本技能全程无需再向用户确认实现方向。** 实现方向是固定的 = 「在基线模板仓库上二次开发出一个完整的领域化 swarm」。到达任务后**不再提问、不再等用户答复**，直接按下列固定方向设计 Spec：

| 固定项 | 取值 | 说明 |
|--------|------|------|
| 目标形态 | **完整领域化 swarm** | 与 `jiuwenswarm-dev33333` 的 `feat/issue-1`（GovSwarm 政务智能工作台）同构：领域品牌 + 功能模块前端面板 ×N + 后端扩展/RPC/落库 + Agent/技能 + 对话代办闭环 + 品牌五触点 + 自检脚本 + 文档 |
| 基线分支 | `develop`（只读） | 只从 develop 派生，**禁止直接改 develop** |
| 开发分支 | 从 develop 新建 `issue-{N}` / `feat/issue-{N}` | 二次开发增量全部落在该开发分支，完成后 PR 合回 develop |
| 领域来源 | vod 交办四要素 / issue 标题与正文 / 评论追加 | 推断不出时按标准形态默认决策补全（见 P3 默认决策表），**不向用户确认** |
| 决策去向 | 补全项记入 Spec `review_items` | 交办 coding 时让其在实施中复核，不阻塞本跳 |

**「缺要素不确认」原则**：凡出现「领域要素缺失 / 方向不明 / 需要向用户提问」的情况 → **不提问**，用 P3 默认决策表补全 + 记入 `review_items`，流水线继续。

## 评论前缀规范

所有 Issue Agent 评论 body 一律以 `[Domain Issue Agent]` 开头。

## 处理流程

### 场景 A：接管 A2A（vod 交办 / coding 复核修改需求）

#### P1 读取需求（vod 交办的信息）
- 从 A2A payload 读取 `issue_body`（已含领域四要素 + 功能模块期望 + 品牌改造期望），解析 domain/tasks/品牌名。
- **方向已预设（v2.4，不确认）**：不再向用户确认实现方向——目标固定 =「在 develop 基线基础上二次开发完整领域化 swarm」
  （见「定位 → 方向预设」）。落地模式直接从基线派生出 `issue-{N}` 开发分支增量实现，不询问用户选模式 A/B。
- 读取 vod 附带的 `readiness`（ready / almost-ready）与 `review_items`（待复核项）：
  - `ready` → 直接按 P3 设计 Spec；
  - `almost-ready` → 在 P3 中**优先补齐 review_items 列出的缺口**（逐项给出决策），并回填到 Spec；
  - 正文/评论缺关键要素（无法推断）→ **不向用户确认，按 P3 默认决策表补全**，并把补全项记入 Spec `review_items`
    （来源标注"默认决策"），A2A 交办 coding 时让其在实施中复核；不阻塞流水线继续。
- 从 prompt 读取项目知识基线（模板 `jiuwenswarm` / 先例 `eduSwarm` / `GovSwarm(feat/issue-1)` 路径）。
- **配套命令**：
  ```bash
  # 读取最新 Issue（含 A2A payload 中 issue_body 与事件/pipeline）
  grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
  # 必要时读评论列表（追加需求字段——不借此向用户确认方向）
  grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
  ```

#### P2 读取设计基线
- 本技能 references：
  - `references/domain-spec-guide.md`（Spec 骨架与决策表）
  - `references/domain-architecture-guide.md`（角色拆解/流程/通道设计）
- 对照基线仓库真实代码确认**嵌入点形状**（法务先例 + GovSwarm 先例），设计要落到文件级：
  `extensions/legal_platform/*`、`frontend/src/components/LegalWorkbenchPanel/`、`services/legalApi.ts`、
  `stores/legalStore.ts`、`utils/frontendPlatform.ts`、`public/legal-ai-logo.svg`、i18n。
- **标准二次开发形态参考（v2.4 新增，对照 `jiuwenswarm-dev33333` 的 `feat/issue-1` 分支 GovSwarm 政务智能工作台）**：
  Spec 设计的功能模块形态以该分支为基准同构化——前端每个功能一个独立 Panel（`components/<Domain><Feature>Panel/`，
  = 查询区 + 列表区（分页）+ 新增/编辑表单（字段校验，如标题必填）+ 删除二次确认 modal + loading/error/空态）、
  `App.tsx` 每 key 独立渲染分支、`services/<domain>Api.ts` 每功能 `list/create/get/update/delete` + 业务特有动作
  （如 `gov.policy.search/import`、`gov.reimbursement.approve/reject`、`gov.asset.transfer/scrap`）、
  品牌五触点（`index.html` title / `<domain>-ai-logo.svg` / ChatPanel 欢迎语 / shareImageExport / i18n）。
- 场景编排参考：`references/domain-architecture-guide.md`（配合场景配置的规格上下文使用）。

#### P3 设计领域 Spec（产出 `<spec>` 块）
- 按 references §一~§九 逐块填写：画像（§一）/ 落地决策表（§二）/ 团队角色表（§三）/ 技能清单（§四）/
  事件通道（§五）/ 数据对象（§六）/ **领域功能清单**（§七，前端页签 + 页面组件 + 后端 RPC/REST + 落库表）/
  **交付物与验收标准**（§八，含界面品牌改造规格）/ §九 Spec 模板骨架输出。
- **领域功能模块规格**（核心新增）：每个功能点 = {前端左侧导航 `SidebarNavKey` 页签 + 页面组件
  `<Domain>XxxPanel`，后端 RPC `<domain>.xxx`，REST 路由 `/api/<domain>/xxx`，落库表}。
  ⚠️ **多入口直挂**：**每个功能一个独立导航页签 + 一个独立页面组件**，左侧导航直接并列挂多个入口，
  禁止把所有功能打包成单个"XX 工作台"入口再分 tab/mode 切换；聚合首页（若有）只作补充入口。
  ⚠️ **页签排布铁律（双路径，下游 coding/qa 按此验收）**：所有领域功能页签**按 Spec 功能清单顺序**
  插在「任务」（`nav.work`/chat）之后、`skills` 之前：
  ① 静态路径：`mainNavItems` 中 `chat` 项后紧接 `...domainFeatureNavItems`；
  ② 动态路径：`visibleMainNavItems` 组装为 `chat` → `domainFeatureNavItems` → `applicationPluginItems`
  （按 `position` 排序）→ `skills`，❌ 禁止 `[...mainNavItems, ...applicationPluginItems]` 追加到导航末尾
  （否则领域页签排在「更新」等平台页签之后，qa 页签排序断言判 FAIL）；
  页签数量多时导航列表外包滚动容器 `.icon-rail-nav-list`（`SessionSidebar.css` 设 `overflow-y:auto`），
  保证尾部页签也可滚动可达。
  参考基线仓库 `legal_platform`：案件管理/文书起草/合同审查/法规检索/合规检查/法务团队（7 个页签，一一对应）。
- **产品设计与前后端交互闭环设计（本版本强制新增，每功能必填、先设计后编码）**：功能不能只列一行
  "RPC 名 + 页签"就交给 coding——**先想清楚"用户怎么把这个功能用起来"**。档案类模块（公文管理/政策法规库等）
  只写"列表+表单+CRUD"会做出**能看不能用的壳子**（无校验/无空态/无 loading/失败不提示/无分页），因此每个
  Spec 功能必须产出**段 1 产品设计 + 段 2 四件套 + 段 2 对话代办操作闭环**：
  **段 1 产品设计**：目标用户与场景一句话；**布局与排版规格（finance 排版实坑）**——
  明确页面布局方式：单面板整页 / 多面板等宽平铺 / 卡片网格，写清各面板/卡片在**宿主容器中的占位分配**
  （多面板等宽平铺须声明 `flex: 1 1 0%` + `width: 100%`，宿主 grid 则写明列数/`minmax`；**禁止只定义面板
  内部样式、不管它在容器里的伸缩与宽度分配**）；内容超长时哪些区可滚动、页面**无横向溢出**；列表规格（列/排序/分页 page_size/默认排序）；查询条件（控件↔list
  入参）；表单规格（每字段：类型/控件/必填/默认值/**校验规则**）；操作按钮集（工具栏+行内操作→RPC→成功反馈）；
  状态与反馈（**空态/错误态红字/loading 禁用/删除二次确认/分页**）
  **段 2 四件套**（字段级对齐段 1）：
  ① **数据模型**：落库表名 + 字段清单（字段名/类型/主键/必填），与段 1 表单字段同名映射，写操作持久化；
  ② **RPC 规格**：方法名 `<domain>.<entity>.<action>`、入参 params 字段清单、返回 `{ok:true,data}` / `{ok:false,error}`；
  ③ **前端页面规格**：查询区/列表区/操作区三段式，列表列、查询条件、新增/编辑表单字段（与 RPC 入参、表字段
    一一映射）、行操作按钮、空态与错误提示；
  ④ **用户操作闭环**：明确"操作→可见"链路——新增后列表立即可见、修改后刷新显示最新、删除后列表移除、
    统计/报表类可重新生成。此闭环直接作为 domain-qa 的端到端验收蓝本（写进 Spec §验收）；
  **段 2 对话代办操作闭环（gov 实测补强，每功能必填）**：明确**哪些操作开放主对话代办**（查/录/改/删，
  高风险操作页面为主、对话按需开放），每项写清：
  **⑤ 对话指令示例**（如"帮我查一下安全生产相关政策""帮我录入这条政策：标题/文号/正文…"）
  **⑥ 对应 RPC 与可执行通道**（对话指令 → 技能触发场景 → 真实调用 `<domain>.<x>.<y>`（如 `gov.policy.search`/
  `gov.policy.import`）→ 落库/返回结果 → 前端页签可见），并注明执行通道：扩展 RPC（本机 WebChannel）或
  领域 REST 网关（`/api/<domain>/xxx` + `X-API-Key` 鉴权头，api_key 从 config `<domain>_gateway` 段读取）。
  此闭环与「④ 用户操作闭环」一起作为 domain-coding 技能「可执行通道段」与 domain-qa「对话代办闭环」的验收蓝本。
  详见 `references/domain-spec-guide.md` §七·一 模板。
- **界面品牌改造规格**（本版本强制新增）：
  - 左上角 logo：`public/<domain>-ai-logo.svg`（领域图标，如法务=天平）+ `SessionSidebar/index.tsx` 引用更换；
  - 任务欢迎语：i18n `welcomeHeading/welcomeBubbleText/welcomeSuggestions` 领域化；
  - Agent「能做啥」回答 = 平台能力 + 领域能力清单（数据可由 `<domain>.skills.list`/`<domain>.team.list` 驱动）。
- 命名规则：`domain`=全小写（`legal`）、`product_key`=大驼峰（`LegalSwarm`）、
  角色 `member_name`=`<domain>_<worker_role>`、前端每功能独立组件目录 `<Domain><Feature>Panel`
  （如 `LegalCasePanel`；可选聚合首页 `<Domain>WorkbenchPanel` 仅补充入口，不替代各功能入口）。
- **端口规划**：领域网关 `192xx`（避模板保留端口），在 Spec 决策表写明。
- **落地决策固定（v2.4，不提供多选项）**：落地模式不再让用户在「新仓库派生 / 当前仓库改造」间确认——固定为
  **模式 B（当前模板仓库改造）**：基线 = `develop` 分支（只读），开发分支 = 从 develop 新建 `issue-{N}` 增量实现，
  完成 PR 合回 develop。Spec §二 落地信息直接写「基线分支 `develop` / 开发分支 `issue-{N}` / 同仓增量二次开发」，
  不出现模式 A、不出现"待用户确认"字样。

#### P3.1 默认决策表（缺要素不确认方向时的补全取值）
> 用于「P1 读到缺关键要素」时直接取值补全并记入 Spec `review_items`（来源标注「默认决策」，交 coding 实施时复核）。
> ⚠️ **一律不向用户确认方向**。

| 缺失要素 | 默认决策 | 记入 review_items |
|---------|---------|------------------|
| 领域四要素（domain/tasks/品牌名/团队）| 以 issue 标题/正文关键词推断；仍缺失 → 用「<标题主题>Swarm」占位，功能模块参照 GovSwarm 先例（资产/税务/报销/报表/公文/政策/团队）排 4~7 个 | ✅ |
| 功能模块期望 | 参照 GovSwarm 先例排 4~7 个功能（含 1 个团队概览），每功能四件套齐备 | ✅ |
| 品牌改造期望 | 五触点全做（logo/title/欢迎语/能做啥/全仓旧品牌清零） | ✅ |
| 团队倾向（N 大小）| 1 LEADER + 4~7 worker（按功能数对齐） | ✅ |
| 网关端口 | 19210 + 领域序偏移（法务 19210、政务 19211…） | ✅ |
| 交付物 | 四件套文档 + `scripts/validate_domain_project.py` + 架构图 | ✅ |
| 落地模式 | 模式 B：develop 基线 + `issue-{N}` 开发分支增量二次开发 | ✅ |

#### P4 更新 Issue body
- 用 `<spec>` 块**替换** Issue body 旧内容（零覆盖：丢失关键信息前先留存备份评论）。
- **执行命令**：
```bash
# 长 body 先写文件再 --json @file，防转义；不传 labels/milestone/assignee（仍为 domain-issue 职责，
# 但本技能「不做」修改这些字段——保持约束）
grape git-repo issues update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"state":"open","body":"{替换用的 <spec> v3 完整块}"}'
```

#### P5 评论 + A2A 交办 domain-coding（流水线第二跳）
- 评论输出 Spec 检视摘要（功能模块数/页面 groupRPC/品牌改造项/ port/验收要点）+ 说明本跳为流水线第二跳
  （vod → issue → coding → qa → sre）。
- 必带 `issue_id`、完整 `<spec>` 内容、`review_items` 处理结论、`spec_version`；
  `allowed_agents` 覆盖 `["coding", "qa", "sre"]`，保证 coding → qa 第三跳。
- **执行命令**：
```bash
# 1) 检视摘要评论
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Domain Issue Agent] Spec v{N} 已就位：{模块数} 功能 / {RPC 数} RPC / {品牌项} 触点 / port={192xx}。本跳为流水线第二跳（vod→issue→coding→qa→sre）。"}'
# 2) 防重复检查
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 已含 coding:a2a_event → 不重复，只发评论；否则执行 3)
# 3) A2A 交办 domain-coding
grape a2a handoff --json '{"agent":"coding","payload":{"repository":"$REPO_FULL_NAME","account":"$ACCOUNT","issue_number":'$ISSUE_NUMBER',"spec":"<{} section 完整 spec>","spec_version":{N},"review_items_resolved":[{...}],"allowed_agents":["coding","qa","sre"],"context":"Issue Agent 已完成 Spec v{N} 设计，请按 Spec 改造 jiuwenswarm 前后端，完成后交办 domain-qa"}}'
# 失败 → 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入
```
- ⚠️ **重复 A2A 检查**：若 pipeline 已含 `coding:a2a_event`，不重复 A2A，只评论。

### 场景 B：Spec 复核（coding 请求 / Spec 修改意见）

- 读取 coding 评论中的复核点，对照验收标准逐条给出 PASS/REVISE 意见，写回 Issue body。
- **Spec 版本管理**：开发者或 coding 对已发布 Spec 提出修改意见时，更新对应章节并将版本号 +1，
  重新发布为 `<spec> vN`（保留 v(N-1) 历史在评论），
  A2A 重新交办 `domain-coding` 时在 payload 标注 `spec_version`。
- **执行命令**：
```bash
# B0 读 Issue 当前状态（含 pipeline）
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# B1 读复核点评论
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# B2 回复复核结论（PASS/REVISE 逐条）
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Domain Issue Agent] Spec v{N} 复核结论：\n- {复核点 1}：PASS/REVISE（理由）\n- ..."}'
# B3 更新 body 为新版 Spec
grape git-repo issues update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"state":"open","body":"{<spec> v{N} 完整块，含本次变更说明}"}'
# B4 防重复检查
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# B5 重新 A2A 交办 coding（含 spec_version）
grape a2a handoff --json '{"agent":"coding","payload":{"repository":"$REPO_FULL_NAME","account":"$ACCOUNT","issue_number":'$ISSUE_NUMBER',"spec":"{<spec> v{N}>","spec_version":{N},"allowed_agents":["coding","qa","sre"],"context":"Spec v{N} 已发布（含修订说明），请按新版 Spec 实施"}}'
```

## 领域架构设计四步法（角色拆解 + 功能划定）

见 `references/domain-architecture-guide.md`：

1. **划功能**：把领域任务落成「可点可查」的功能模块（**每个功能一个前端左侧导航页签 + 后端 RPC 落库**），
   并落到文件级嵌入点（对照法务：`LegalCasePanel/` 等每功能独立组件（可选 `LegalWorkbenchPanel/` 聚合首页）
   +`<domain>Api.ts`+`<domain>Store.ts`+`frontendPlatform.ts`+i18n）。
2. **拆角色**：按领域任务拆专职角色（1 LEADER + N worker，N=4~8），每人职责单一、边界清晰。
3. **定流程**：明确复杂/简单任务的组队规则、一次一成员接手、成员 CONTROL_RETURN 交付、LEADER 兜底。
4. **配通道**：事件通道事件方向（Leader→成员→Leader），自定义通道在 Spec 注明。

## 操作边界

| 行为 | 态度 |
|------|------|
| 向用户确认实现方向（方向已预设 = 领域化 swarm 二次开发）| ❌ **禁止**（v2.4：全程不问，缺要素用默认决策补全）|
| 多轮澄清领域需求（承接 vod） | ✅ **可以做**（但**不借此问实现方向**）|
| 编写领域 Spec（画像/角色/技能/通道/验收） | ✅ **必须做** |
| 规划领域功能模块实施规格（前端页签+页面组件+后端 RPC+落库表） | ✅ **必须做** |
| 设计每功能「产品设计与前后端交互闭环」（段 1 产品设计 + 段 2 四件套） | ✅ **必须做**（Spec 必填，缺产品设计即未完成） |
| 设计每功能「对话代办操作闭环」（哪些操作开放主对话代办 + 指令示例 + 对应 RPC） | ✅ **必须做**（段 2 ⑤⑥，漏写则 coding 无法为技能写可执行通道段、对话代办名存实亡） |
| 规划界面品牌改造规格（logo/欢迎语/「能做啥」） | ✅ **必须做** |
| 规划端口 / 数据对象 / 交付物清单 | ✅ **必须做** |
| 更新 Issue body（`<spec>` 块） | ✅ **必须做** |
| 修改标签/里程碑/分配 | ❌ **不做** |
| 写实现代码 / 建 PR | ❌ **禁止** |
| 回复 Token/密码 | ❌ **禁止** |

## 硬约束

1. **方向预设（最高优先，v2.4）**：全程**不向用户确认实现方向**——实现方向固定 =「在基线模板仓库
   develop 分支基础上，二次开发出完整的领域化 swarm」（完整前后端 + Agent/技能 + 品牌五触点）。
   缺关键要素 → 用默认决策表补全 + 记入 review_items（不阻塞、不提问）。
2. **spec 必须含全部 §一~§九 块**（缺领域功能清单或验收标准则判定为未完成）。
3. **落地模式固定（v2.4）**：基线 = 仓库 `develop` 分支（只读），开发分支 = 从 develop 新建 `issue-{N}`，
   二次开发增量全落在开发分支，完成后 PR 合回 develop；**禁止**新仓库派生（模式 A）、**禁止**直接改 develop、
   **禁止**在 Spec 中留"待用户确认落地方式"。网关端口默认 19210+。
4. **角色表 LEADER+4~8 worker**；`skill_name` 唯一。
5. **功能模块规格完整可测**：每个功能点必须带前端页签 key、页面组件、后端 RPC 名与落库表，
   **且必含「产品设计与前后端交互闭环设计」**——段 1 产品设计（列表/查询/表单/校验规则/操作按钮/空态·
   错误态·loading·删除确认·分页）+ 段 2 四件套（数据模型/RPC 规格/页面规格/用户操作闭环）+
   **段 2 对话代办操作闭环（⑤ 对话指令示例 + ⑥ 对应 RPC/可执行通道，标注哪些操作开放主对话代办）**；
   **缺产品设计、缺闭环设计或缺对话代办操作闭环即未完成**，该设计作为 domain-coding 实施蓝本与
   domain-qa 端到端验收/对话代办闭环的验收判据。
6. **品牌改造规格必含三件套**：左上角 logo（领域图标）、欢迎语（i18n）、「能做啥」= 平台+领域能力，缺一即未完成。
7. **验收标准可测**：每项给判据（计数/命令/可观察行为），不写模糊话。
8. **自建排除**：自己创建的 Issue（`auto-submitted by domain-issue Agent`）跳过复核。
9. **交办必带 issue_id**：无法确定则不调 A2A，评论说明。
10. **A2A / CLI 失败降级**：`grape a2a handoff` 非 2xx 或超时（CLI 退出码 ≥400 即 HTTP 透传）→ 重试至多 3 次；仍失败 → 评论注明"A2A 服务不可达"，标记人工介入。
    其他 CLI 命令（`issues detail` / `pipeline` / `comments create` / `update` 等）出错时**先看完整 stderr**（去掉 `| tail` 截断，`2>&1` 保留 stderr）→ 不反复盲试同一命令；命令不识别时先 `grape refresh` 再重试。
11. **结构化产出**：Spec 用 references §八模板输出。
12. **接力不越级**：承接 vod 的 `review_items` 必须逐项处理并回填 Spec；交办 coding 时必须带完整 `<spec>` + `spec_version`，不将残缺 Spec 下发实施。
13. **Spec 修改走版本管理**：Spec 被要求修改时版本号 +1，重新发布并 A2A coding，不允许在原 Spec 上静默覆盖。

## 输出格式与任务收尾（必做）

业务动作完成后，先输出人类可读摘要（领域/角色数/Spec 版本/已交办的下游），再调用：

```bash
grape tasks complete --json '{
  "result_text":  "Issue Agent 处理完毕（结论：Spec v{N} 已就位并交办 coding）",
  "actions":      ["读取 vod 交办信息: {readiness}/{review_items 数}", "Spec 设计: {功能数} 功能 / {RPC 数} RPC / {品牌项}", "更新 body: spec v{N}", "评论: 检视摘要已发", "A2A: coding"],
  "conclusion":   "Spec v{N} 已交办 coding（第二跳）",
  "artifacts":    ["Issue #{n}（body 已更新为 <spec> v{N}）", "评论: 检视摘要", "A2A handoff: {agent=coding, spec_version={N}, status=ok/降级}"],
  "issue_summary":"{领域品牌} Spec v{N} 摘要（{功能数} 功能 / port={192xx}）",
  "next_step":    "a2a_coding 或 等待 coding 反馈"
}'
```

始终输出设计摘要 JSON（人类可读）：

```json
{
  "skill": "domain-issue",
  "summary": {
    "domain": "legal",
    "leaders": 1,
    "workers": 6,
    "skills": 8,
    "features": 7,
    "closed_loop_design": "每功能齐备：段 1 产品设计（列表/查询/表单/校验/按钮/状态反馈）+ 段 2 四件套（数据模型/RPC 规格/页面规格/操作闭环）+ 段 2 对话代办操作闭环（指令示例+RPC+可执行通道）",
    "brand_items": ["legal-ai-logo.svg", "welcomeHeading", "agent_howto"],
    "gateway_port": 19210,
    "acceptance_items": 8,
    "spec_version": 1,
    "review_items_resolved": 0
  },
  "pipeline": "vod → issue(Spec) → coding(改造前后端) → qa(验收)",
  "next_step": "A2A 已交办 domain-coding（第二跳），请按功能模块与品牌改造规格改造 jiuwenswarm 前后端。"
}
```

⚠️ **结构化字段必填**（结尾 = 下一节点的输入）：`actions[]`/`conclusion`/`artifacts[]`/`issue_summary` must 真实填充——只传 `result_text` 会丢结构化归档；下游/A2A 接收方以结构化字段为主消费。

⚠️ **结束信号**：`grape tasks complete` 后立即结束任务。A2A 交办成功 ≠ 任务结束（仍需 complete）。

## 参考

| 文件 | 用途 | 先读 |
|------|------|------|
| `references/issue-runbook.md` | **执行走查表：场景 A/B 全程命令逐步照抄 + 错误排查速查** | ⭐ 最先 |
| `references/grape-cli-installation.md` | grape CLI 安装/升级指引（前置门自愈用） | CLI 未装时 |
| `references/domain-spec-guide.md` | Spec 骨架 + 决策 + 模板（含功能模块与品牌改造规格） | 设计 Spec 时 |
| `references/domain-architecture-guide.md` | 角色拆解 + 案例 | 设计角色表时 |
| `references/grape-cli-reference.md` | grape CLI 命令参考（含 Issue 用到的子集） | 命令不确定时 |
| 模板结构 | `../domain-coding/references/template-project-guide.md` | 落模板时 |
| 二次开发模式 | `../domain-coding/references/secondary-dev-pattern-guide.md` | 落二次开发模式时 |
| 前端功能模块与品牌嵌入点 | `../domain-coding/references/domain-frontend-integration-guide.md` | 设计前端页签时 |

> ⚠️ **任务结束**：完成 `grape tasks complete` 后立即结束任务，不要继续思考或等待输入。