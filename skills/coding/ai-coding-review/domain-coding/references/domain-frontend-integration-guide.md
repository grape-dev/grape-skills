# 前端功能模块与品牌定制指南（domain-coding v2.3）

> 配套 `skills/domain-coding/SKILL.md`。**领域 Swarm 线上化的关键**：不仅要有"对话型领域技能"，
> 还要把 Spec 功能清单做成「前端左侧导航可点页面 → 直调后端 `<domain>.*` RPC → 数据落库」的完整闭环，
> 并完成品牌定制（**左上角 logo / 浏览器页签 title / 任务对话窗口欢迎语（含组件硬编码）/ 分享导出图
> 片品牌名 / 「能做啥」回答=平台能力+领域能力 / 全仓品牌名清零**）。
>
> **第一参考先例：基线仓库 `jiuwenswarm` 的 `legal_platform` 实现（可直接照抄目录骨架）。**
> 前端根目录 = `<repo>/jiuwenswarm/channels/web/frontend/`，下文以 `src/` 简写。

## 0. 导航形态硬规则（必须先读，多入口直挂 Multi-Entry Direct Nav）

- **每个 Spec 功能模块 = 左侧导航 1 个独立入口（1 个 `SidebarNavKey` + 1 个 `SessionSidebar` 导航项）+
  1 个独立页面组件**；`App.tsx` 为每个 key 写独立渲染分支。
- **禁止**把多个功能打包成单个"XX 工作台"入口、再在页面里分 tab/mode 切换子功能页。
  （可选）聚合首页 `<Domain>WorkbenchPanel`（各功能快捷卡片/引导）只作**补充入口**，
  **不得替代**各功能的独立导航入口与独立页面组件。
- **验收判据①**：左侧导航直接看到 **N 个（= Spec 功能数）领域入口**，每个入口都能点进**自己独立的页面组件**；
  ② 每个页面组件完成一次"增 / 查 / 落库"闭环。

## 0.1 涉及文件总览（落地即合格）

```text
frontend/src/
├── public/<domain>-ai-logo.svg            # ① 左上角品牌 logo（替换默认图标）
├── utils/frontendPlatform.ts              # ② SidebarNavKey 扩展（左侧导航 key，每功能一个）
├── components/<Domain><Feature>Panel/     # ③ 每功能一个独立页面组件目录（如 LegalCasePanel/）
│   └── index.tsx                          #    组件 + 样式；目录/组件数 = Spec 功能数
├── components/<Domain>WorkbenchPanel/     # ⓞ (可选) 聚合首页：功能快捷卡片，仅补充入口，不替代独立组件
├── services/<domain>Api.ts                # ④ 后端 RPC 的 webRequest 封装
├── stores/<domain>Store.ts                # ⑤ 领域状态
├── i18n/locales/zh.json / en.json         # ⑥ nav.<domain>* + 欢迎语（welcomeHeading 等）
└── components/SessionSidebar/index.tsx    # ⑦ 左上角 logo 引用 + 左侧导航 items 挂载（多入口）
```

## 1. 左上角品牌 logo（按领域实现更换）

- 在 `src/public/` 放置 `<domain>-ai-logo.svg`（领域图标，如天平+文档 = 法务 ai-logo）。
- 在 `SessionSidebar/index.tsx` 顶部 logo 处改为引用该图：

```tsx
const logoIcon = '/<domain>-ai-logo.svg';   // 法务先例 = '/legal-ai-logo.svg'
```

- **浏览器页签 title（必做）**：`frontend/index.html` 的 `<title>`（浏览器标签页标题，模板默认如
  `WorkSwarm`）改为领域品牌名；同时 i18n `app.title` 同步领域化：

```html
<!-- index.html：浏览器顶部标签页标题 -->
<title>LegalSwarm</title>
```

  **这处极易漏改**（只改侧栏 logo/欢迎语不会改变浏览器标签页标题），验收时以「浏览器标签页标题 =
  领域品牌名」为准。

## 2. 左侧导航注册（每功能一个入口，核心）

- **`utils/frontendPlatform.ts`**：向 `SidebarNavKey` 枚举追加领域 key，**每个 Spec 功能一个**（法务先例
  `<domain>Case` / `<domain>Document` / `<domain>Contract` / `<domain>Search` / `<domain>Compliance` /
  `<domain>Team`），与 Spec 功能清单一一对应，数量 = 功能数。
- **`SessionSidebar/index.tsx`**：**新增 `domainFeatureNavItems` 常量数组**（每功能一项），
  ⚠️ **页签排序铁律：领域功能页签固定插在「任务」(chat) 之下、skills 之前**——`mainNavItems` 中
  `chat` 项之后紧接 `...domainFeatureNavItems`；**禁止直接 append 到导航数组末尾**（否则会排在
  "更新"等平台页签之后）。基线已验证形状（finance 先例）：
- ⚠️⚠️ **两条贡献路径都要插位，缺一即页签跑末尾（gov 实坑）**：领域页签可能走两条路径，**两条都必须
  落在 `chat` 之后、`skills` 之前**：
  - **路径一（静态数组）**：`domainFeatureNavItems` 常量数组（见下），在 `mainNavItems` 里紧跟 `chat`；
  - **路径二（应用插件动态页签，FrontendContribution 机制）**：后端扩展通过 `applicationPlugins`
    贡献页签，前端在 `visibleMainNavItems` 组装。**禁止写成 `[...mainNavItems, ...applicationPluginItems]`
    （append 末尾会让所有领域/插件页签排到"更新"等平台页签之后）**——gov 项目正是这么写导致领域页
    排末尾；必须拆出 `chat` 与 `skills` 之间的插位区间，再按 `position` 排序后插入：

```tsx
// 路径一：静态数组 —— 领域功能页签固定插在任务(chat)与技能(skills)之间
const domainFeatureNavItems: NavItem[] = [
  { key: '<domain>-asset', labelKey: 'nav.<domain>Asset', icon: <领域图标/> },  // 每 Spec 功能一项
  { key: '<domain>-tax',   labelKey: 'nav.<domain>Tax',   icon: <领域图标/> },
];
const mainNavItems: NavItem[] = [
  { key: 'chat', labelKey: 'nav.work', icon: <WorkIcon/> },
  ...domainFeatureNavItems,          // ← 领域页签紧跟任务，不得放在数组末尾
  { key: 'skills', ... }, { key: 'agents', ... }, ...,
];

// 路径二：应用插件动态页签 —— 拆 chat/skills 插位，不能 [...main, ...appPlugins] append 末尾
const [chatNavItem, ...tailNavItems] = mainNavItems;          // 拆出 chat
const skillsIdx = tailNavItems.findIndex((it) => it.key === 'skills');
const skillsNavItem = skillsIdx >= 0 ? tailNavItems[skillsIdx] : null;
const restBeforeSkills = skillsIdx >= 0 ? tailNavItems.slice(0, skillsIdx) : tailNavItems; // 含领域静态数组
const restAfterSkills = skillsIdx >= 0 ? tailNavItems.slice(skillsIdx + 1) : [];
// 领域静态页签 + 应用插件动态页签（按 position 排序）都插在 chat 之后、skills 之前
const orderedAppPluginItems = [...applicationPluginItems].sort((a, b) => (a.position ?? 0) - (b.position ?? 0));
const visibleMainNavItems = [
  chatNavItem,
  ...restBeforeSkills,        // 含 domainFeatureNavItems，紧贴 chat
  ...orderedAppPluginItems,   // 应用插件页签也在 chat→skills 之间，禁止 append 末尾
  ...(skillsNavItem ? [skillsNavItem] : []),
  ...restAfterSkills,
];
```

- **⚠️ 导航滚动容器（必做，页签过多可滑轮）**：领域功能项 + 平台原生项合计超出左侧栏可视高度时
  **必须可滚动**。实现：导航 items 渲染处用 `<div className="icon-rail-nav-list">` 整体包裹
  （div 放入 aside 内容区、包住全部 item button），并在 `SessionSidebar.css` 增加滚动样式：

```tsx
// SessionSidebar/index.tsx —— items 渲染处（结构性改动：外包一层滚动容器）
<div className="icon-rail-nav-list">
  {visibleMainNavItems.map((item) => (
    <button key={item.key} className="icon-rail-nav-item ..." onClick={...}>
      <span className="icon-rail-nav-item__icon">{item.icon}</span>
      <span className="icon-rail-nav-item__label">{getNavItemLabel(item)}</span>
    </button>
  ))}
</div>
```

```css
/* SessionSidebar.css —— 与 .icon-rail-nav-item 同级新增 */
.icon-rail-nav-list {
  display: flex;
  flex-direction: column;
  align-items: center;
  flex: 1 1 auto;
  min-height: 0;            /* 关键：配合 flex 父容器允许收缩后才可滚动 */
  width: 100%;
  overflow-y: auto;         /* 关键：垂直滚动 */
  overflow-x: hidden;
  scrollbar-width: thin;
  scrollbar-color: var(--color-border-default) transparent;
}
.icon-rail-nav-list::-webkit-scrollbar { width: 4px; }
.icon-rail-nav-list::-webkit-scrollbar-track { background: transparent; }
.icon-rail-nav-list::-webkit-scrollbar-thumb { background: var(--color-border-default); border-radius: 2px; }
```

  （基线先例：`jiuwenswarm` 当前副栏 7 个 legal 页签 + 平台原生项后已用 `.icon-rail-nav-list` 实现滑轮。）
  **验收判据**：页签较多时侧栏出现滚动条、鼠标滚轮可滚到底部、**每个页签都可见可点**。

- **`App.tsx`**：侧栏选中项 switch **为每个 key 写独立渲染分支**，分别渲染对应独立页面组件
  （不能用同一个组件 + mode 参数切换）。注意当前 jiuwenswarm 的 `SidebarNavKey` 是字符串字面量
  type 联合（`'chat' | 'skills' | ...`），直接追加领域 key 字符串即可：

```tsx
case '<domain>-case':     return <Domain>CasePanel />;
case '<domain>-document': return <Domain>DocumentPanel />;
```

- 未注册的 key 不会出现在侧栏 → **验收判据：左侧导航能看到 Spec 功能清单全部门户，每功能一个入口，
  每个入口点进独立页面组件**。（若做了可选聚合首页 `<Domain>WorkbenchPanel`，它有自己的 key，是第 N+1 个入口。）

## 3. 后端 RPC 的前端直调层 `<domain>Api.ts`

浏览器通过 WebChannel 直调后端 RPC（不走 LLM，页面也可独立使用）：

```ts
import { webRequest } from './webRequest';       // 沿用平台封装
export const legalApi = {
  caseList: ()       => webRequest('legal.case.list'),
  caseCreate: (p)    => webRequest('legal.case.create', p),
  contractReview: (p)=> webRequest('legal.contract.review', p),
  documentDraft: (p) => webRequest('legal.document.draft', p),
  searchLaw: (p)     => webRequest('legal.search_law', p),
  skillsList: ()     => webRequest('legal.skills.list'),
  teamList: ()       => webRequest('legal.team.list'),
};
```

- RPC 名与后端 `extension.py` 注册的 `channel.register_method('<domain>.<业务>.<动作>', ...)` 严格一致。
- 依赖注入：`@injectable` 单例（参考 `legalApi` 如何在组件中 `useLegal`/store 中调用）。

## 4. 领域状态 `<domain>Store.ts`

- 收放：领域列表/详情/操作结果（如 `cases`、`currentCase`、`skills`、`team`）。
- 操作封装 `legalApi` 调用 + loading/error 状态 + 成功后刷新列表（保证"落库后页面更新"闭环）。

## 5. 功能页组件（每功能一个独立组件，可选聚合首页）

- **每个 Spec 功能 = 一个独立页面组件** `components/<Domain><Feature>Panel/index.tsx`
  或 `components/<Domain><Feature>Panel.tsx`（如 `LegalCasePanel`/`LegalDocumentPanel`/`LegalContractPanel`…
  与 §9 对齐清单的"页面组件"列一致），组件数 = 功能数。
- 每个功能组件 = **列表 + 查询 + 新增/编辑表单 + 行操作，四段闭环**（对应 Spec「交互闭环设计」落地）：
  - **列表区**：列与 Spec「页面规格」一致；渲染 Store 中数组；空态文案（如"暂无数据，点击右上角新增"）；
  - **查询区**：关键字搜索框（`<domain>.<entity>.list` 带 keyword）；
  - **表单区**：新增/编辑表单，**字段名 = RPC 入参 = 落库表字段（同名映射）**，提交调
    `<domain>.<entity>.create/update` 后 `fetchList()` 刷新；
  - **行操作区**：每行 编辑/删除 按钮 → 改调 `get/update`、删调 `delete`，成功后刷新列表 = **操作闭环**
    （新增→列表立即可见、修改→显示最新、删除→移除）。调用失败用 `ok:false/error` 红字提示，不静默。
  顶部标题 + 描述（品牌化文案）。
- 样式：每组件独立 css（整页浅色清爽、字号 ≥13px、行高 ≥1.6）。
- ⚠️ **面板占位分配（finance 排版实坑）**：组件 css **先声明"自身在宿主容器中的占位分配"再写内部布局**：
  - **多面板等宽平铺**（工作台/并列报表等）：`.xx-panel { flex: 1 1 0%; width: 100%; ... }`（宿主 flex）
    或 grid `repeat(auto-fit, minmax(…, 1fr))`（宿主 grid）；❌ 只写 `display:flex; flex-direction:column;
    height:100%` → 面板按内容宽排布、无法等宽/堆叠（`.fin-panel` 缺这两行 → 记账凭证/资金池/资产负债/利润
    四面板 flex 容器中排布错乱，补 `flex:1 1 0%` + `width:100%` 即平铺）；
  - **单面板整页**：`width:100%`/`max-width` 自适应、不横向溢出；内容超长由内部 body 区 `overflow-y:auto`。
- ⚠️⚠️ **CSS 主题变量契约（v2.3，gov 实坑：`--color-bg` 未定义 → 弹窗透明）**：
  - **只准引用主题真实存在、有定义的变量**。判断标准：**构建产物 `dist/assets/index-*.css` 中
    `:root` 里实际定义过的变量**才算存在（`--color-surface-page` / `--color-surface-elevated` /
    `--color-surface-popover` / `--color-text-primary` / `--color-border-default` /
    `--color-action-primary` 等）；**`src` 里搜不到定义、dist `:root` 里也没有的变量一律视为不存在**
    ——`--color-bg` / `--color-text` / `--color-accent` / `--color-danger` / `--color-ok` 等
    "直觉命名"正是 gov 面板 9 个全挂的占位变量（弹窗内容写 `background: var(--color-bg)`，
    变量未定义 → 背景解析为透明，整个弹窗变透明）。
  - **每个 `var(--x)` 必须带兜底色值**：`background: var(--color-surface-elevated, #ffffff)`、
    `color: var(--color-text-primary, #1f2532)`。双重保险：变量存在时用主题色、不存在时回退明确色，
    **任何情况下都不透明**。
  - **弹窗/浮层类（`.gov-modal__content` 等）必须实底渲染**：白色卡片或主题 elevated 表面色 +
    圆角（如 `border-radius: 10px`）+ 阴影（`box-shadow`）+ `1px` 边框（`--color-border-default`），
    背景禁止复用页面级背景变量（页面背景常为磨砂半透明），否则弹窗内容透出下层页面。
  - **组件样式自包含**：每个 `<Domain><Feature>Panel/` 目录必须自带 `index.css` 并在组件顶部
    `import './index.css'`——**禁止依赖其他面板的全局 css 生效**（gov 实坑：Policy/Petition
    面板未 import 自己的样式，视觉全靠 Document 面板的 css 偶然成形，修一个面板误伤一片）；
    公共样式可放 `src/styles/` 或单独 `gov.css` 由各面板显式 import，不隐式依附。
  - 完成后自查：对每个新组件 `grep -n "var(--" <Panel>/index.css`，确认每处都有兜底值、
    且变量名都在 dist `:root` 里存在。
- **可选（非必须）聚合首页** `components/<Domain>WorkbenchPanel/index.tsx`：功能快捷卡片 + 引导，
  只作补充入口；即便存在，各功能独立入口与独立组件也必须保留，App.tsx 不得用 mode 把多个功能塞进一个组件。
- **验收判据**：左侧导航每功能一个入口，每个入口点进自己独立的页面组件，完成一次"增 / 查 / 落库"，
  刷新后数据仍在；整个领域入口总数 = 功能数（+可选聚合首页）。

## 6. 领域 i18n 文案（zh.json / en.json）

```jsonc
"nav": {
  "<domain>Case":     "案件管理",            // 每个功能一个 key，数量 = 功能数
  "<domain>Document": "文书起草",
  "<domain>Contract": "合同审查",
  "<domain>Search":   "法规检索",
  "<domain>Compliance":"合规检查",
  "<domain>Team":     "法务团队"
  // "<domain>Workbench": "工作台首页",      // 仅当做了可选聚合首页时才加此 key
}
```

新增 key 时 **zh.json 与 en.json 必须成对提交**，否则 QA 自检会报缺失。

## 7. 任务界面欢迎语 / 回话提示语（领域化）

- **⚠️ 硬编码欢迎语（必查，不只 i18n）**：任务对话窗口（`ChatPanel/index.tsx` 的欢迎语组件等）
  **可能直接在代码里写死中英文两套品牌名与标语**（如 `WorkSwarm 轻松解决工作每个问题！` /
  `makes work easier!`），**不在 i18n 里**。必须全文替换为领域版，否则任务对话窗口仍是旧品牌名：

```tsx
// ChatPanel/index.tsx —— WelcomeHeading（中英文两套都改）
<span className="chat-welcome__heading-highlight">LegalSwarm</span>
<span>让法律工作更轻松高效！</span>          // isZh 分支（中文）
<span>making legal work easier!</span>      // 英文分支（en）
```

- **分享/导出图片品牌名（必查）**：`shareImageExport.tsx` 等导出卡片组件内的品牌名
  （如 masthead 品牌名 `WorkSwarm` + AIGC `producer: 'WorkSwarm'` 标签）同步替换，
  否则用户导出的图片/AIGC 元数据仍是旧品牌：

```tsx
// shareImageExport.tsx
<div className="share-image-brand__name">LegalSwarm</div>
const producer = 'LegalSwarm';   // buildAigcLabel() 的 producer 标签
```

- 输入框 placeholder、会话默认空态文案同样领域化。
- **i18n 散落品牌名（必清，zh/en 成对）**：不仅 `welcomeHeading`，`app.title`、
  `connectionDescription`、SkillNet `usageNotice*`、定时任务 `viaChatPrompt`、
  团队成员 `instructionHint` 等文案中出现的旧品牌名也需逐一替换：
  收尾用 `git grep -n "<旧品牌名>"`（如 WorkSwarm）全量扫描、确认零残留。
- Agent greeting / 首次自述 mention 该领域品牌名与能力，保持与前端欢迎语口径一致。

## 8. 「能做啥」回答 = 平台能力 + 领域能力（必须同时包含）

Agent 被用户问「你能做什么/你能干啥」时，**禁止只讲平台能力或只讲领域能力**：

```
回答结构：
一、平台原生能力：多 Agent 团队协作、上下文对话、文件/图片处理、联网/检索、任务编排等（沿用模板描述）。
二、本领域能力（本项目 <product_key> 实现）：<功能清单逐条>……
   - 案件管理：建档 / 列表 / 详情 / 更新，全部落库
   - 文书起草：选模板 → 生成初稿 → 保存
   - 合同审查：粘贴/上传 → 风险点分级 → 审查意见书落库
   - 法规检索：带来源的检索报告
   - 合规检查：对照清单出合规评估
   - 法务团队：查看成员与技能
三、可让用户直接说需求的引导句（如"你可以说：审一下这份合同"）。
```

- 实现数据驱动：Agent persona 可用 `skills.list / team.list` RPC 动态取能力清单；
  也可在 system prompt 的领域上下文段写死（二段式：平台能力模板 + 领域能力清单）。
- 后端 `legal.skills.list` 返回的能力描述与会话层"能做啥"保持同一来源，避免口径漂移。

## 9. 与后端对齐清单（页面 ↔ RPC ↔ 落库）

| 前端页签 key | 页面组件 | 后端 RPC（extension.py 注册） | REST | 落库表 |
|-------------|---------|------------------------------|------|--------|
| `<domain>Case` | `<Domain>CasePanel` | `<domain>.case.list/create/get/update` | `/api/<domain>/case/*` | cases |
| `<domain>Document` | `<Domain>DocumentPanel` | `<domain>.document.draft/save/list` | `/api/<domain>/document/*` | documents |
| `<domain>Contract` | `<Domain>ContractPanel` | `<domain>.contract.review/list` | `/api/<domain>/contract/*` | contract_reviews |
| `<domain>Search` | `<Domain>SearchPanel` | `<domain>.search_law` | `/api/<domain>/search/*` | search_logs |
| `<domain>Compliance` | `<Domain>CompliancePanel` | `<domain>.compliance.check` | `/api/<domain>/compliance/*` | compliance_reports |
| `<domain>Team` | `<Domain>TeamPanel` | `<domain>.team.list / <domain>.skills.list` | `/api/<domain>/team/*` | 配置驱动 |

## 10. 常见坑（法务实施过程中踩过）

1. **端口冲突**：WorkSwarm 桌面端可能占用 `5173`。启动实例用
   `JIUWENSWARM_FRONTEND_PORT=<空闲口>` 等**正确的 `JIUWENSWARM_*_PORT` 前缀变量**固定端口组，
   否则 `compute_auto_port` 会因冲突把整组端口 fallback（gateway/web 漂移到 19xxx/20xxx）。
2. **GBK 编码**：Windows 上 Python `logging` 输出 `✓` 等非 GBK 字符会抛 `UnicodeEncodeError`
   （`_print_port_banner`），banner 均用 ASCII 或先 `chcp 65001`。
3. **i18n 成对**：zh/en 不同步会触发改动校验失败。
4. **RPC 与前端 method 名不一致**：两端任意改名都要三处同步（extension.py / <domain>Api.ts / 后端 dispatch）。
5. **webRequest 通道**：前端直调走 WebChannel，方法名必须以 `<domain>.` 为前缀，避免与平台命名空间冲突。
6. **导航过多整页拉伸**：新增页签后不包滚动容器，侧栏内容会被挤出可视区、底部页签点不到 → 必加
   `.icon-rail-nav-list` 滚动容器（见 §2）。
7. **只编译不冒烟**：`tsc` 通过 ≠ 页面可用。登录后务必实测每个页签可点、页面完成一次增/查/落库，
   否则会产生"build 过了但界面白屏/按钮无效"的返工。
8. **前端依赖悬空**：`<domain>Api.ts` 引用了不存在的 method 时页面报错但不阻塞编译——RPC 各调用点
   都要与后端注册名逐一对齐，并在启动后实测对应页面。
9. **漏改品牌名**：只改侧栏 logo / `welcomeHeading` i18n，通常漏掉**浏览器页签 title（index.html）**、
   **ChatPanel 硬编码中英文欢迎语/标语**、**分享图 producer 标签**、**i18n 散落文案**
   （`app.title`/`connectionDescription`/`usageNotice*`/`viaChatPrompt`/`instructionHint`）
   → 收尾必须 `git grep -n "<旧品牌名>"` 全仓扫描清零，并经 `npm run build` 后冒烟验证。
10. **改了前端但页面仍显示旧品牌**：后端静态服务直接读 `frontend/dist`，**无需重启服务**；
    但浏览器可能缓存了旧 bundle（同名 hash 文件未变）。先强制刷新（Ctrl+F5），若仍旧则重新
    `npm run build`（生成新 hash 文件名）后重试；排查时可直接请求
    `<后端>/assets/index-*.js` 确认实际下发内容里新品牌名是否存在。
11. **RPC 注册成 lambda / 同步 handler**：`channel.register_method` 的 handler 契约是
    `async def (ws, req_id, params, session_id)` + 自行 `send_response`。写成
    `lambda p: dispatch(...)` 或返回 dict 的同步函数会 `TypeError`，前端一直 pending →
    页面按钮"点了没反应"。排查顺序：浏览器 Network → WS frame（确认回包）→ extension.py handler 形状。
12. **扩展配置依赖 `registry.config`**：`ExtensionRegistry` 的 `.config.config` 为空 `{}`；
    从它取 `<domain>_gateway` 判断 enabled 会永远不启动 REST 网关 → `/api/<domain>/health` 404。
    必须 `from jiuwenswarm.common.config import get_config` 读全局配置。
13. **新页签 append 导航数组末尾**：领域页签必须插在 `chat`（任务）之下（`mainNavItems` 中
    `chat` 后 `skills` 前），禁止数组末尾追加——否则排队在"更新"后面，与"功能页签在任务下"的
    产品预期不符，QA 页签排序断言会 FAIL。
14. **CSS 变量未定义 → 弹窗/表单透明（gov 实坑，v2.3）**：面板样式写
    `background: var(--color-bg)` / `color: var(--color-text)` 等**直觉变量名**，但主题 `:root`
    **从未定义过它们** → `var()` 解析失败、背景回退为透明，弹窗整块透明、文字与按钮跟随下层底色
    糊成一片，视觉几乎不可用。**根治**：① 只引用构建产物 `dist/assets/index-*.css` 中 `:root`
    实际定义的变量（如 `--color-surface-elevated` / `--color-text-primary` / `--color-border-default`）；
    ② 每个 `var(--x)` 带兜底色值（`var(--color-surface-elevated, #fff)`）；③ 弹窗内容层实底渲染
    （白卡/表面色 + 圆角 + 阴影 + 1px 边框），不复用页面级半透明背景；④ 每个 Panel 自带 `index.css`
    并在组件顶部 import，禁止隐式依赖其他面板的全局 css。改样式后**必须重新 `npm run build`**，
    前端服务读的是 `dist` 产物，只改 src 不重新构建页面不会变（且浏览器可能缓存旧 bundle，先 Ctrl+F5）。
15. **面板只定义内部样式、不声明宿主容器占位 → 多面板无法等宽平铺/堆叠（finance 实坑）**：
    面板 css 写 `display:flex; flex-direction:column; height:100%`（只解决内部布局），却漏掉
    **自己在外部容器里的伸缩与宽度分配** → 多个面板放进 flex/`app-section` 容器时按内容宽度排列，
    宽度不均/堆叠/溢出，排版错乱（finance：`.fin-panel` 缺 `flex:1 1 0%` + `width:100%`，
    记账凭证/资金池/资产负债/利润四面板无法等宽平铺，补两行即恢复）。**根治**：每个面板/卡片 css
    必须带外部占位（`flex:1 1 0%; width:100%` 或 grid `repeat(auto-fit, minmax(…,1fr))`）；
    `npm run build` 后浏览器打开各页签一次做**视觉自检**（等宽/无堆叠/无横向溢出/内容区可滚动），
    这是 coding 静态交付义务内的快速检查，发现布局问题当场修 CSS 再 build 复看 1 次。