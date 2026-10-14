---
name: domain-coding
version: 4.5.0
description: |
  面向 jiuwenswarm 领域模板仓库的领域 Swarm 二次开发实施（Grape Coding 第三站）：按 domain-issue Spec 在基线 jiuwenswarm 上改造
  前后端——后端扩展 RPC+SQLite 落库+REST 网关；前端功能页+Api/Store+品牌；领域 Agent+技能；交付
  自检交 domain-qa。产出须可用：RPC 4 参异步契约、get_config、gateway 生效、前端可编译、页签
  插任务(chat)下对话→委派→RPC→落库闭环。account 实坑：开放对话代办功能必建
  <domain>_gateway_tool.py 并注册进 interface_deep.py。finance 实坑：扩展模块必须绝对导入，
  禁相对导入（No module named 'jiuwenswarm.loaded_extension' → 全域 RPC unknown method）。
  面板除内部布局外必须声明宿主容器占位（多面板平铺 `flex:1 1 0%`+`width:100%`），前端改动后
  build+视觉自检属交付义务。
tools:
  - grape
  - bash
---
## 安全硬约束（必须遵守）

1. **CLI 优先**：凡 grape CLI 能做的走 CLI，禁止绕过 CLI 直连平台 API（curl/python httpx 等）。CLI 未装/版本过低 → **自动安装/升级**（官方源/签名包优先）→ 装好继续；仅当安装失败/环境不可用时才报障说明（不降级直连）。⚠️ 安装指引见 `references/grape-cli-installation.md`。
2. 调用仓库 API 只用 prompt 注入的 `$GRAPE_SESSION_TOKEN`，严禁从数据库/configs/日志/历史中寻找其他 token。
3. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据（`data/workspaces/` 项目知识文档除外）。
4. API 返回 403/无权限时：立即停止该操作并回复用户「该操作需要管理员/维护者权限，请手动配置后重试」，严禁绕行手段。
5. 401/凭据失效：任务级 token（tk_）短命，失效属正常机制——说明「凭据已失效」即可，不尝试替换/绕行。
6. token 不得写入任何文件/日志/评论。
7. **模板项目受 Apache-2.0 保护**：绝不删除/修改 LICENSE 与开源声明；二次开发必须保留。
8. **绝不破坏框架核心路径**（`agents/gateway/server/resources/config` 等）：领域能力一律走扩展层 + 领域前端模块新增。

# 领域 Swarm 二次开发实施（domain-coding v4.5）

## 环境变量表（平台注入，按 coding Agent 类型）

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
| 任务上下文 | `grape tasks current --json-out` + `grape issues detail` | 拿到 Spec payload（issue_body） | ISSUE 缺失 → 用 `grape git-repo issues get` 定位；定位不到 → STOP（不执行写操作） |
| 项目知识基线 | prompt 内联注入 + 本地 `jiuwenswarm` 基线仓库 | 返回基线摘要 | 「无基线」→ 降级到 references + 法务先例 README |
| 瞬时失败（网络/限流） | — | — | **重试**：自动重试 ≤3 次（退避 1s/2s/4s） |

> 本技能涉及 git push 建 PR（CLI 不覆盖 PR 流程的部分走 bash 调 git），其余 CLI 流程走 grape。

> **v4.3 变更（2026-09-23，account 实坑沉淀）**：「Agent 领域工具」从"可后置的可选项"升级为 **「Spec 开放
> 对话代办即必做」**——凡开放对话代办的每功能必须提供 `extensions/<domain>_platform/<domain>_gateway_tool.py`
> （@tool 包裹、进程内直调 `dispatch_<domain>_rpc`）并注册进 `interface_deep.py` `_get_tool_cards()`；
> **进程内直调工具无条件注册**（try/except 包裹，不依赖 `<domain>_gateway.enabled`）；收尾全量核对
> `extensions/*_platform/*_gateway_tool.py` ↔ `interface_deep.py` 注册块一一对应（缺 1 即未完成，qa 24x/24z 判 FAIL）。
> 症状：页面/WS RPC 全通但主对话"帮我登记一张发票"只回话术、SQLite 零写入。
>
> **v4.4 变更（2026-09-24，finance loaded_extension 实坑沉淀）**：**扩展模块（extension.py 及其内部模块）一律
> 绝对导入，禁止相对导入**——loader 以 `importlib.util.spec_from_file_location("jiuwenswarm.loaded_extension.<name>",
> entry)` 动态加载 `extension.py`，磁盘上并不存在 `jiuwenswarm.loaded_extension` 这个父包；
> 相对导入 `from .<domain>_backend import ...` 需解析父包 `jiuwenswarm.loaded_extension` →
> 报 `No module named 'jiuwenswarm.loaded_extension'` → 整个扩展加载被跳过 → 全部 `<domain>.*` RPC 未注册 →
> 前端所有功能页 `unknown method`（finance_platform 实坑：页面/WS 全报 unknown method，46 个 RPC 全丢）。
> 正确写法：`from jiuwenswarm.extensions.<domain>_platform.<module> import ...`（先例：`video_duplex`
> 扩展即用绝对导入，加载正常）。**切勿照抄旧指南说的"相对导入"**——旧写法在 loader 伪命名空间缺失时必挂。

## 定位

领域 Swarm 工厂流水线的**第三站（实施核心）**：

- **职责内**：按 `<spec>` 在基线仓库 develop 分支上改造 jiuwenswarm 的**后端与前端代码**
  （扩展+RPC 落库 → 前端功能页面 → 界面品牌适配 → Agent/技能 → 自检脚本就位 → 文档）→ 建 PR → A2A 交办 `domain-qa`（验收由其全量执行）。
- **职责外**：不产出质检结论（domain-qa）、不部署运行（domain-sre）。
- **核心心法**：本技能不是"写一套领域 SKILL/Agent 定义"就结束，而是**要把功能真真切切做进 jiuwenswarm 的界面对话框体系里**——
  `legal_platform` 是先例，照它的形状改。

## 评论前缀规范

所有 Coding Agent 评论 body 一律以 `[Domain Coding Agent]` 开头。

## 处理流程

### 场景路由（payload / 评论区判定 → 任务类型）

> ⚠️ **先判定再动手**：到达后先读 `grape tasks current --json-out` + 评论区 + `grape issues pipeline`，按下表判定本任务是「首次实施」还是「修复打回」——**判错就漏跑 A2A 链路，整条流水线断在 coding**。

| 触发信号（按优先级判定）| 场景 | 必走路径 |
|---------|------|---------|
| ① 评论区最近一条是 `[Domain QA Agent] REVISE` 或 `[Domain SRE Agent] REVISE` | **场景 B：修复打回** | B0→B1→B2→B3→B4（**必须 A2A qa 复检**）|
| ② A2A payload 显式 `recheck: true` | **场景 B：修复打回** | 同上 |
| ③ pipeline 含 `coding:a2a_event`（自身已发过 A2A coding）| **跳过实施** | 只发状态评论 → `grape tasks complete`（防自我循环）|
| ④ 其他（首次 issue 实施）| **场景 A：首次实施** | C1→C2→C3→C4→C5→C6→C7→A2A qa |

> ⚠️ **A2A 链路贯通硬约束（防 QA→Coding→QA→SRE 链断）**：
>
> 完整链 = `coding A 实施 → qa A 验收 →（PASS → sre / REVISE → coding B 修复）→ qa B 复检 →（PASS → sre / REVISE → coding C 修复…）`。
> - **场景 B 修复完成必须 A2A qa 复检**——qa 不会自动唤醒复检，只发评论 = 链路断在 coding；
> - **coding 不得越级直接 A2A sre**（跳过 qa 复检）—— sre 不会接受未通过 qa 复检的代码；
> - **未成功 A2A qa → 不得调用 `grape tasks complete`**（链路未贯通 = 任务未完成，必须重试 A2A 至贯通）。
>
> 任一 A2A 调用失败 → 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ `next_step` 标人工介入，**仍不得 complete**（任务进入待人工介入态）。

### 场景 A：接管 A2A（issue 交办实施）

#### C1 读取 Spec 与基线（必须先做）
- 从 A2A payload 读取 `issue_body`（含 `<spec>` 块：domain/品牌名/角色表/技能清单/**功能模块实施规格**/**品牌改造规格**/端口/验收）。
- **配套命令**：
  ```bash
  # 拉取最新 Spec（防 A2A payload 与远端 Issue 漂移）
  grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
  ```
- 读取本技能 references（全部）：`template-project-guide.md`（模板结构）、`secondary-dev-pattern-guide.md`（二次开发模式）、
  `extension-implementation-guide.md`（扩展/RPC 手册）、`domain-frontend-integration-guide.md`（前端模块+品牌定制）、
  `domain-skills-authoring-guide.md`（技能/Agent 规范）、`delivery-and-docs-guide.md`（交付物与文档）、`templates.md`。
- 先例对照（最高优先级）：通读基线仓库法务实现并**照抄其目录骨架与代码形状**：
  - 后端 `extensions/legal_platform/extension.py`（`bind_web_channel` 注册 `legal.*` RPC + `register_extensions` 入口）、
    `legal_backend.py`（`dispatch_legal_rpc` + SQLite 建表/写入）、`legal_gateway.py`、`legal_gateway_tool.py`；
  - 前端 `components/LegalWorkbenchPanel/`（每功能独立组件）、`services/legalApi.ts`（`webRequest('legal.xxx')` 直调）、
    `stores/legalStore.ts`、`utils/frontendPlatform.ts`（`SidebarNavKey`）、`SessionSidebar/index.tsx`（logo + 导航 items）、
    `public/legal-ai-logo.svg`、i18n。

#### C2 落地模式确认
- 落地模式**固定为模式 B（v2.4，无选项）**：基线模板仓库 `develop` 分支**只读**；当前开发分支 =
  从 develop 新建的 `issue-{N}` / `feat/issue-{N}`（由 spec §二 落地信息给出），二次开发增量全部落在
  当前开发分支；完成后 PR 合回 develop。**禁止**派生新仓库（模式 A 已废弃）、**禁止**直接在 develop 上提交。

#### C3 领域架构设计（实施前落定）
- 结合 `<spec>` 功能模块规格 + 角色表复述划功能/拆角色/定流程/配信号（详见
  `../domain-issue/references/domain-architecture-guide.md`），在 PR 描述/评论给出设计摘要供 QA 核查。

#### C4 领域功能与扩展实施（核心改动）
按顺序实施（详细命令与模板见 `references/extension-implementation-guide.md` +
`references/domain-frontend-integration-guide.md` + `references/templates.md`）。

> ⚠️ **编码期「一次写对」清单——自检正则约束（gov 实坑：写法不匹配自检正则 → 跑自检 → 失败 → 现场修 → 重跑，来回 6+ 分钟）**
> 自检脚本 `validate_domain_project.py` 用正则核对一致性，以下写法会在自检时被**误判或必挂**，
> 编码时严格按"写一次就对"处理（对应正则见脚本 4.5/5.5/页签排序段）：
> 1. **前端 Api.ts 禁止泛型**：一律 `webRequest('<domain>.xxx', params)` **无泛型**；
>    ❌ `webRequest<T>(...)` 泛型写法不被自检正则 `webRequest\([...]{0,120}?['"]` 匹配 → 判"未发现 RPC 调用"；
> 2. **技能 SKILL.md 的 RPC 引用写精确方法名**（如 `gov.policy.search`）；
>    ❌ 占位/通配 `<domain>.xxx.yyy`、`gov.xxx`、`gov.complaint.*` 会被"RPC 点名一致"检查当成已引用名
>    去比对注册表 → 必判 FAIL（日志实测 5 个技能逐个改是最大返工源）；
> 3. **协调技能目录名必须 `<domain>-swarm-coordination`**（自检 4.5(a) 固定探测该名）；
>    ❌ 写成 `<domain>swarm-coordination`（少连字符）等变体 → 判"未发现协调技能"；
> 4. **注释/文档/示例不得出现拼接字面量**：❌ 注释里写 `[...mainNavItems, ...applicationPluginItems]`
>    会被"页签排序"正则误匹配判 FAIL；写 `webRequest('gov.xxx')` 会被"可执行通道/前端挂载"正则误判；
>    需要解释时改述为"直接拼接"等**不带字面量**的话；
> 5. **Python 按 Py3.9 兼容编写**：自检/交付脚本一律避免 `str | None` 等 PEP 604 注解
>    （权威脚本头部已带 `from __future__ import annotations`，**交付副本不得现场删/改**）。
> 6. **Agent 领域工具"建必注册"（v4.3 account 实坑：页面/WS 全通但主对话代办只聊不做）**：只要建了
>    `extensions/*_platform/*_gateway_tool.py`，就必须同步在 `server/runtime/agent_adapter/interface_deep.py`
>    `_get_tool_cards()` 加注册块（import → `self._register_shared_tool(...)` → `tool_cards.append(...card)` →
>    logger 日志）；**进程内直调工具必须无条件注册**（try/except 包裹，默认不因 enabled 关闭）；
>    收尾 grep 全量核对：`grep -cl "gateway_tool" extensions/*_platform/*.py` 里的每个域，都要在
>    `interface_deep.py` 找到一个对应 `_register_shared_tool` 注册块（缺 1 = 验收 24x/24z 必 FAIL）。
> **超时护栏**：以上清单在编码期遵守，自检 7.1 只确认交付脚本"无 ImportError/语法错误"（≤1min）；
> 若运行发现失败项，**只允许 1 轮修复（≤2min）**，仍不过 → 把失败明细完整写进 PR/A2A 交 domain-qa 复核，
> **禁止反复"跑→修→重跑"循环**（日志实测这是 30 分钟超时的最大耗时源）。

**阶段 A：后端领域能力（domain 可被调用、可落库）**
0. **前后端设计落地对照（新步骤，先从 Spec 七·一转成实现清单，勿自由发挥）**：对 Spec 里每个功能的
   「段 1 产品设计 + 段 2 交互闭环四件套」建立实施对照表，编码时逐项打勾：
   - 段 1 产品设计 → 表单字段/校验规则/空态/错误态/loading/删除确认/分页全部落到 `<Domain><Feature>Panel`
     组件实现（见下"产品设计可用性铁律"），**禁止"能看不能用的壳子"**（无校验/无空态/无 loading/失败不提示）；
   - 数据模型 → `<domain>_backend.py` 的建表函数 + `init_db()`；
   - RPC 规格 → 对应的 `dispatch_<domain>_rpc` 分支 + `extension.py` 注册名 + `<domain>Api.ts` 封装，三处同名一致；
   - 页面规格 → 对应 `<Domain><Feature>Panel/index.tsx` 的列表列/表单字段，与 RPC 入参、表字段同名映射；
   - 用户操作闭环 → 每个按钮对应一次 RPC 调用 + 成功后 `refresh()` 刷新列表；**禁止"只建页面不接数据的空按钮"**；
   - ⚠️ **产品设计可用性铁律（gov 实坑，验收 24r 判据）**：有表单必须有**必填/格式/唯一性校验**（拦截并红字提示）；
     列表有空态文案+引导；拉取/提交有 **loading**（按钮禁用或 spin）；删除走**二次确认**；`ok:false` **红字提示不静默**；
     >page_size 有**分页**. 缺任一项视为功能未完成。
1. `resources/config/config.example.yaml` **和** `resources/config/config.yaml`（运行时生效）**两份都**新增
   `<domain>_gateway` 段（host/port 192xx/enabled: true/api_key/cors）。只写 example 会导致默认启动时
   （读 config.yaml）REST 网关不加载、后端不可用——两份必须同步（见 extension-implementation-guide.md）。
2. 新建 `extensions/<domain>_platform/extension.yaml`（`id: <domain>_platform`）。
3. 新建 `extensions/<domain>_platform/extension.py`（照抄**已验证可用的 finance 先例形状**：
   `ApplicationPluginExtension` 子类 + `bind_web_channel(self, channel, services)` for 循环
   `channel.register_method("<domain>.<name>", _make_handler(channel, name))` +
   **`async def register_extensions(registry)`**（必须 async，loader 以 await 调用）返回插件实例；
   内部模块引用**一律绝对导入**（v4.4 铁律，finance 实坑）：`from jiuwenswarm.extensions.<domain>_platform.<domain>_backend import ...`，
   **❌ 禁止相对导入 `from .<domain>_backend import ...`**（loader 动态模块名 `jiuwenswarm.loaded_extension.<name>`
   下父包 `jiuwenswarm.loaded_extension` 不存在 → `No module named 'jiuwenswarm.loaded_extension'` →
   整个扩展加载失败、全部 `<domain>.*` RPC 未注册、前端全功能 `unknown method`，见 v4.4）；
   `health` 必须注册）。
4. 新建 `<domain>_backend.py`（业务函数 + `dispatch_<domain>_rpc` 统一分发 + SQLite 建表落库）。
5. 新建 `<domain>_gateway.py`（REST `/api/<domain>/*`，含 `/api/<domain>/health`）。
6. 新建 `<domain>_gateway_tool.py`（**如提供：必须同时完成阶段 C 第 5 条的工具注册 + 第 6 条的身份注入，
   只建文件不注册 = 模型看不到**；工具实现优先进程内 `dispatch_<domain>_rpc`（AgentServer 进程已加载扩展，
   同步直查 SQLite，不依赖 REST 端口），失败才回退 REST 网关——规避领域网关端口与主 gateway 冲突）。
- 实施完成标志：每个 Spec 功能点都有 RPC；写操作 SQLite 落库；对照表逐项打勾完成。
- ⚠️ **后端可用性铁律（编码时遵守，运行级验收统一由 domain-qa 一次性完成）**：
  - 入口 `register_extensions` **必须 `async def`**（`ExtensionLoader` 以 await 调用，写 `def` 扩展注册不上、功能不可用）；
  - **RPC handler 必须 `async def h(ws, req_id, params, session_id)` 且自行 `await channel.send_response(ws, req_id, ok=..., payload=...)`**
    ——这是 `channel.register_method` 的硬契约（`_ApplicationPluginChannel` 按 4 参调用并等待 handler 自行回包）；
    ❌ `lambda p: dispatch(...)` / 同步返回 dict 的 handler 会 `TypeError`、前端永远无响应，功能不可用；
  - **WS 成功回包 `payload` 必须是业务数据本体（`result.get("data")`），不许整包下发 `payload=result or {}`**——
    `dispatch_<domain>_rpc` 返回 `{ok, data}` 双层包裹；前端 `webRequest` 的 resolve 值恰是 WS `payload`，组件直接取
    `res.items` 等业务字段。若整包下发 `{ok, data}`，数据库已落库但前端取到空（页面显示"暂无资产"，finance 实坑）；
    必须与 REST 网关同口径：`payload = result.get("data") if isinstance(result, dict) else {}`;
  - **扩展读自身配置段必须 `from jiuwenswarm.common.config import get_config()`**——框架注入的
    `registry.config` 是空 `{}`（`ExtensionConfig(config={})`），依赖它判断 `<domain>_gateway.enabled`
    会永远不走网关启动分支；
  - 扩展内模块引用**绝对导入**（v4.4 finance 实坑）：一律 `from jiuwenswarm.extensions.<domain>_platform.<module> import ...`；
    ❌ **禁止相对导入 `from .<module> import ...`**——loader 以动态模块名 `jiuwenswarm.loaded_extension.<name>`
    加载 `extension.py`，磁盘无 `jiuwenswarm.loaded_extension` 父包，相对导入报
    `No module named 'jiuwenswarm.loaded_extension'` → 扩展整体加载失败、全域 `<domain>.*` RPC `unknown method`（finance 实坑）；
  - `<domain>_gateway` 段**必须同时写入实际生效的 `resources/config.yaml` 与 `config.example.yaml`** 且 `enabled: true`；
  - **通用 `_build_where` 日期边界两条铁律（v4.2 gov 实坑，凡 list/search 带日期筛选必踩）**：
    ① `_to` 后缀列名截取 = `col[:-3]`（删 `"_to"` 3 个字符）；❌ `col[:-2]` 会生成 `created_at_` →
    报 `no such column`，**所有 `date_to` 查询必挂**（`_from` 是 `col[:-5]` 删 5 字符，无此问题）；
    ② 纯日期 `YYYY-MM-DD` 边界作字符串比较会**漏掉当天整批记录**（`'2026-09-21 10:07:26' <= '2026-09-21'`
    为 False）——`_from` 值必须补 `" 00:00:00"`、`_to` 值补 `" 23:59:59"`，带时间的值保持原样
    （抽 `_normalize_date_bound(val, end: bool)` 辅助函数统一处理）；
  - ⏱ **不要边写边启动冒烟**（避免多次启动）：启动 + `/health` + 写 RPC 抽查统一由 **domain-qa 一次完成**。

**阶段 B：前端功能模块 + 界面改造（本次的核心，功能必须在界面可见可点可操作）**
> ⚠️ **导航形态硬规则（多入口直挂）**：Spec 功能清单中**每个功能模块 = 左侧导航 1 个独立入口 + 1 个独立页面组件**，
> 禁止打包成单个"XX 工作台"入口再在页面里分 tab 切换。可选额外提供 `<Domain>WorkbenchPanel` 聚合首页（快捷卡片），
> 但**不得替代**各功能独立入口与组件。
> ⚠️ **导航滚动硬规则（页签过多带滑轮）**：导航列表渲染处用 `<div className="icon-rail-nav-list">` 包裹全部 items，
> `SessionSidebar.css` 为 `.icon-rail-nav-list` 设置 `flex:1 1 auto; min-height:0; overflow-y:auto; overflow-x:hidden;
> scrollbar-width:thin` + `::-webkit-scrollbar{width:4px}` 滚动样式；任意数量页签都能**滚动到、点得到、可见**，
> 禁止因页签过多导致尾部入口不可达。
> ⚠️ **面板占位分配铁律（finance 排版实坑）**：每个领域页面组件/卡片的面板样式**必须同时声明
> 「自身在宿主容器中的占位分配」**，禁止只定义内部布局（`flex-direction`/`height:100%`）不管外部摆放：
> - **多面板等宽平铺**（工作台/概览/并列报表等多面板同屏）：子面板样式加 `flex: 1 1 0%;` + `width: 100%;`
>   （宿主为 flex 容器时）或 `grid-template-columns: repeat(auto-fit, minmax(<最小宽>, 1fr))`（宿主为 grid）；
>   ❌ 只写 `display:flex; flex-direction:column; height:100%` 不写外部占位 → 面板按内容宽度排列、
>   无法等宽/堆叠/溢出（finance 实坑：记账凭证/资金池/资产负债/利润四面板在 flex 容器中排布错乱，
>   补 `flex:1 1 0%` + `width:100%` 两行即恢复等宽平铺——用户手动修才定位到根因）；
> - **单面板整页**：面板自身 `width:100%`/`max-width` 自适应容器宽度，不撑出横向滚动；
> - **「写一次对」布局自检（静态交付义务内，不做浏览器运行验收）**：`npm run build` 后浏览器打开
>   每个新增页签/面板一次，确认**等宽平铺、无堆叠、无横向溢出、内容区可滚动**；发现问题当场改 CSS
>   再 build 复看 1 次，仍不行 → 把问题写进 PR/交 domain-qa 复核（布局 bug 属前端可见性问题，qa 24aa 会验）。
> 附 CSS 形状（对照 finance-panel.css 先例）：
> ```css
> .<domain>-panel {                              /* 子面板：内部布局 + 外部占位 缺一不可 */
>   display: flex; flex-direction: column;       /* 内部：标题区+内容区分列 */
>   flex: 1 1 0%;                                /* 外部：在宿主 flex 中等分剩余空间（等宽平铺关键）*/
>   width: 100%;                                 /* 外部：随容器宽度自适应，不横向溢出 */
>   height: 100%; min-height: 0; overflow: hidden;   /* 内部：超高内容由子区滚动 */
> }
> .<domain>-panel__body { flex: 1 1 auto; min-height: 0; overflow-y: auto; }
> ```
7. 新建页面组件：**每个 Spec 功能 = 一个独立组件** `frontend/src/components/<Domain><Feature>Panel/index.tsx`（+ css），
   按 spec 功能清单逐个建；可选聚合首页 `<Domain>WorkbenchPanel/index.tsx`（非必须，不替代独立组件）。
   ⚠️⚠️ **CSS 主题变量契约（gov 实坑：未定义变量 → 弹窗透明）**——页面/弹窗/表单样式**禁止使用
   `--color-bg` / `--color-text` / `--color-accent` 等"看起来有、实际未定义"的占位变量**（gov 面板
   `.gov-modal__content` 写 `background: var(--color-bg)`，该变量在主题中从未定义 → 解析为透明 → 弹窗
   整块透明、文字/按钮随内容底色渲染）。硬规则：
   - **只使用主题真实存在的变量**（构建产物 `dist/assets/index-*.css` 中 `:root` 实际定义过的，如
     `--color-surface-page`/`--color-surface-elevated`（弹窗卡背景）/`--color-text-primary`/
     `--color-border-default`/`--color-action-primary` 等）；拿不准就先 grep 主题 `:root`
     确认存在再引用（dist 是运行时真相，src 里搜不到定义的变量一律视为不存在）；
   - **每个 `var(--x)` 必须带兜底色值**：`background: var(--color-surface-elevated, #ffffff)`——
     即使后续变量名改版，界面也回退到明确底色，绝不透明；
   - **弹窗/浮层内容必须有实色背景**（白色卡片或 `--color-surface-elevated` + 圆角 + 阴影 + 1px 边框），
     禁止让弹窗内容层复用页面级背景变量而透明；
   - **每个 Panel 目录必须自带 `index.css` 并在组件顶部 `import './index.css'`**——禁止依赖别的
     面板组件的全局 CSS 生效（gov 实坑：Policy/Petition 面板没 import 自己的样式，全靠
     Document 面板的 css 才"偶尔"成形，一改就错）；同一套领域 CSS 若需复用可统一放公共 css 再各自 import。
   完成后对每个新组件 `grep -n "var(--" <Panel>/index.css` 逐一核对兜底，杜绝裸引用。
8. 新建 `frontend/src/services/<domain>Api.ts`（照抄 `legalApi.ts`：每个功能一个函数封装
   `webRequest('<domain>.xxx', params)`，RPC 名与后端一致）。
9. 新建 `frontend/src/stores/<domain>Store.ts`（领域状态 + loading/error + 成功后刷新列表）。
10. `frontend/src/utils/frontendPlatform.ts`：`SidebarNavKey`（字符串字面量 type 联合，非 enum）追加 `<domain>-*` key，
    **每个功能一个 key**，数量 = Spec 功能数（不强制 `<domain>-workbench` 聚合 key）。
11. `frontend/src/components/SessionSidebar/index.tsx`：**四条改造**
    - 顶部 logo 引用改为 `import logoIcon from '/<domain>-ai-logo.svg'`（左上角按领域更换，法务=天平）；
    - **新增 `domainFeatureNavItems` 常量数组**（每功能一项 `{ key: '<domain>-case', labelKey: 'nav.<domain>Case', icon: ... }`），
      ⚠️⚠️ **页签排序铁律-双路径（gov 实坑：`[...mainNavItems, ...applicationPluginItems]` 导致领域页签排末尾）**——
      领域页签可能走**两条路径，两条都必须插在「任务」(chat) 之后、`skills` 之前**：
      ① **静态数组路径**：`mainNavItems` 中 `chat` 项之后紧接 `...domainFeatureNavItems`（chat 与 skills 之间）；
      ② **应用插件动态页签路径**：`visibleMainNavItems` 组装时仍以 `chat` → `domainFeatureNavItems` →
         `applicationPluginItems`（按 position 排序）→ `skills` 的顺序拼接，**❌ 禁止 `[...mainNavItems,
         ...applicationPluginItems]` append 末尾**（否则领域页签排在"更新"等平台页签之后，验收 24o 判 FAIL）；
    - **导航列表外包 `<div className="icon-rail-nav-list">` 滚动容器**，并同步在 `SessionSidebar.css` 增加滚动样式，
      插到 chat 之下后数量变多同样靠滚动容器保证全部可达；
12. `frontend/src/App.tsx`：侧栏选中项 switch 支持新 key，**每个 key 渲染对应独立页面组件**
    （每 key 独立渲染分支，不用 mode 参数共用组件）。
13. `frontend/src/i18n/locales/{zh,en}.json`：`nav.<domain>*` 文案（每功能一个）+ 欢迎语
    （`welcomeHeading/welcomeBubbleText/welcomeSuggestions`）+ 页面文案；zh/en 成对。
- 实施完成标志：每功能已有独立入口 + 独立组件；logo 引用已切换；滚动容器已包。
  （可点/落库/可滚动等运行验收统一由 domain-qa 完成，**阶段内不做逐功能浏览器手检**，防重复耗时。）

**阶段 C：Agent/技能/品牌/自检/文档**
> ⚠️ **任务对话可识别 + 可执行硬规则（每个新功能都要能被模型识别并真的执行）**：用户在主对话说
> "生成一个财务报告/登记一笔资产/审查一份合同/帮我查一下 XX 政策"时，模型必须识别功能、
> **真实发起**对应 RPC（不能只回文本"好的，已为您查询"却不实际调用）、落库，
> 结果自动出现在对应前端页签。**六件事缺一不可**（v4.2 起：新增「Agent 工具注册」「主对话身份注入」两条）：
> 1. **协调技能委派映射**：`*-swarm-coordination/SKILL.md` 必须有「委派映射」表，每功能触发关键词
>    （报表/汇总 → 财务分析专员；查政策/录入政策 → 政策研究员）写得让 LEADER 一看就能派对人；
> 2. **功能技能 SKILL.md 写清触发场景 + 调用 RPC**：「适用场景」写"用户要生成报表/查询…"，
>    「操作要点」写**「调用 `<domain>.<x>.<y>`，参数 …」**（如 `finance.report.generate` + report_type/period；
>    `gov.policy.search` + keyword；`gov.policy.import` + title/doc_no/body）；
> 3. **Agent persona 明确枚举功能**：LEADER/worker「能做啥」显式列出领域功能，与 `*skil.list`/`*team.list` 同口径；
> 4. **RPC 名四处一致**：`extension.py` 注册名、`<domain>Api.ts`、`dispatch_<domain>_rpc` 分支、技能 SKILL.md 引用名；
> 5. **（新增 v3.6）功能技能必写「可执行通道段」**：除「触发场景+调用 RPC」外，每个功能技能 SKILL.md 必须写清
>    **Agent 如何真实发起该调用**，二选一（按 spec 段 2·补⑥ 执行通道）：
>    - **领域 REST 网关通道**：`POST /api/<domain>/<action>`（网关端口 192xx）+ 鉴权头 `X-API-Key: <api_key>`
>      （api_key 从 `config.yaml` 的 `<domain>_gateway` 段读取，**禁止硬编码**）+ 参数 JSON 契约（与 RPC params 同名同型）；
>    - **Agent 可直接调用的领域工具**：注册 `<domain>_gateway_tool.py` 为 Agent 工具（工具名 + 入参 schema），
>      或把领域 RPC 暴露给模型白名单，让模型在对话中直接 `webRequest('<domain>.xxx')` 等效调用；
>    - ⚠️ **"只定义工具 ≠ 模型能看到"（v4.2 gov 实坑，注册步骤必做）**：`<domain>_gateway_tool.py` 用 `@tool`
>      装饰器定义工具后，**必须注册进主对话 Agent 工具链**——在 `server/runtime/agent_adapter/interface_deep.py`
>      `_get_tool_cards()` 中执行 `self._register_shared_tool(<domain>_gateway_call)` +
>      `tool_cards.append(<domain>_gateway_call.card)`，受 `config_base.get("<domain>_gateway", {}).get("enabled")`
>      控制并打 `"<Domain>Swarm <domain>_gateway_call tool registered"` 日志。**只写工具文件不注册 → 模型工具链里
>      根本没有它**，所有"可执行通道段"文档形同虚设（gov 实坑：`gov_gateway_tool.py` 定义后从未注册，问"你能做啥"
>      主对话完全不提公文管理/政策法规）。enabled 判定以**实际生效配置**为准（用户目录 `~/.jiuwenswarm/config/config.yaml`
>      覆盖仓库 `resources/config.yaml`）；
>    - **（v4.3 account 实坑，"可后置"必须升级为"必做"）**：`<domain>_gateway_tool.py` **不是"第一版可直接用
>      RPC 协议、此文件后置"的可选项**——只要 Spec 段 2 ⑤⑥ 开放了任一功能对话代办，就必须提供
>      Agent 直接可调领域工具并注册（account 实测：发票/凭证/资金/报表功能页面齐全、WS RPC 全部通，
>      但**没建 `<domain>_gateway_tool.py`、`interface_deep.py` 也没有注册块**，主对话"帮我登记一张发票"
>      只会回软话术"好的已登记"、SQLite 零写入，功能名存实亡——与 24t "只聊不做"同症状）。
>      且**进程内直调工具必须无条件注册**（import/注册包 try/except，**不依赖 `<domain>_gateway.enabled` 开关**）：
>      进程内调用不经 REST 端口，网关 enabled 缺省/关闭不应让工具从模型工具链消失；仅需走 REST 网关的
>      调用兜底才用 enabled 控制。收尾强制全量核对：`grep -cl "gateway_tool" extensions/*_platform/*.py`
>      列出的每个域，都必须能在 `interface_deep.py` `_get_tool_cards()` 找到对应 `_register_shared_tool`
>      注册块（缺 1 即阶段 C 未完成，QA 24x/24z 判 FAIL）。
>    - 判据：模型拿到技能文档后**能写出真实可发起的 curl/webRequest 调用**，而非"依赖 Agent 自己发挥"。
>      缺「可执行通道段」= 技能只聊不做，验收 24t 判 FAIL。
> 6. **（新增 v4.2）主对话身份系统提示词领域化——"问'你能做啥'能答出领域功能"的直接机制**：
>    改 `agents/harness/common/prompt/prompt_builder.py` 的 `_identity_prompt()`（zh/en 两份）：
>    - 「# 身份」写"你是 `<Brand>`（`<平台名>`）提供能力的 `<领域>` AI 助手"；
>    - 「## 你是谁」写"是 `<平台名>` 内置 AI 助手，不是通用聊天机器人"；
>    - 「## 你能做什么」**三段式**：平台原生能力 + **领域能力逐条枚举**（与左侧页签/RPC 同口径）+ 引导例句；
>    - 「【强制·问候回复】」写"用户发你好/你是谁/你能做什么/怎么使用时，第一条回复必须完整输出领域
>      自我介绍 + 领域能力概览，不得省略，也不得自称通用助手"。
>    仅靠 extension hook / Agent persona 不够（gov 实坑：这两处已领域化但 `_identity_prompt` 仍是通用版 → 主对话
>    回答"我是通用 AI 助手"、不提领域功能）；eduSwarm 先例即改 `_identity_prompt` 内嵌【自我介绍硬性要求】+示例话术。
> 先例：基线 `finance-swarm-coordination/SKILL.md`、`financial-report-analysis/SKILL.md`、`finance_report_analyst.json`。
14. 新建 `resources/agent/<domain>_agent_configs/*.json`（LEADER + N worker；persona「能做啥」=
    平台能力 + 领域能力二段式，**领域能力必须逐条枚举本领域功能**，与 `*team.list`/`*skil.list` 同口径）。
15. 领域技能 + 品牌收尾 + 自检 + 文档：
    - 领域技能 `resources/agent/workspace/skills/<技能>/*.md`（按 `domain-skills-authoring-guide.md` 规范，
      frontmatter 完整）+ **「技能→我的技能」安装通道（v2.4 新交付物）**：在 `<Domain>Swarm快速部署指南.md`
      写明 `skills.install <技能名>` 安装命令（内置技能拷贝到用户技能目录、source 变 local）——
      否则技能仅内置目录 `source='builtin'`，UI「技能→我的技能」不可见（gov 实测），验收 24s 判 FAIL；
    - **协调技能必须含「委派映射」表**（每 Spec 功能至少一行：触发关键词 → 专员 id）；
    - **每个功能技能必须写「触发场景」+「调用 <domain>.<x>.<y>」**；
    - **品牌收尾五触点（全部要做，扫描无残留才算完成）**：
      - ① **浏览器页签 title**：`frontend/index.html` 的 `<title>` 改为领域品牌名（如 `<title>LegalSwarm</title>`），
        i18n `app.title` 同步领域化；
      - ② **任务对话窗口欢迎语**：`ChatPanel/index.tsx` 等对话组件内**硬编码的中英文品牌名与标语**
        （如 `WorkSwarm 轻松解决工作每个问题！` / `makes work easier!`，**不在 i18n 里**）全文替换为领域版
        （如 `LegalSwarm 让法律工作更轻松高效！` / `making legal work easier!`）；输入框 placeholder、空态文案同改；
      - ③ **分享/导出图片品牌名**：`shareImageExport.tsx` 等导出卡片的 masthead 品牌 + AIGC `producer` 标签同步替换；
      - ④ `public/<domain>-ai-logo.svg`（领域图标，左侧栏已引用）；
      - ⑤ Agent「能做啥」回答 = 平台能力 + 领域能力（参考 `legal.skills.list`/`legal.team.list` 数据驱动）；
      - **收尾必做全仓清零**：`git grep -n "<旧品牌名>"`（如 WorkSwarm）在前端 src 与 i18n 全量扫描逐条替换
        （i18n `connectionDescription`/SkillNet `usageNotice*`/定时任务 `viaChatPrompt`/成员 `instructionHint`
        等散落文案一个都不能漏），zh/en 成对提交；
    - 自检脚本 `references/scripts/validate_domain_project.py`（携带 `<domain>` 参数）复制到落地仓库 `scripts/`；交付文档四件套（README/部署指南/架构图/经验分享）。
- 实施完成标志：委派映射覆盖全部功能；每个功能技能有触发场景 + RPC 调用；
  编码阶段只做静态三查（≤2min），**运行级验收（含后端/前端/对话冒烟）统一由 domain-qa 全量执行**（见
  `../domain-qa/SKILL.md` C7 验收），coding 不做重复的动态运行校验。

#### C5 领域技能与 Agent 配置编写（含静态三查，≤2min）
- 按 `references/domain-skills-authoring-guide.md`：skill_name 唯一、SKILL.md frontmatter 完整、
  Agent JSON 关键字段齐全；**每个 Agent persona 的「能做啥」回复须含平台能力 + 领域能力清单（逐条枚举）**。
- ⚠️ **对话可识别 + 可执行四查（静态自查，写入时顺手完成，不做对话冒烟）**：协调技能有**委派映射表**覆盖全部功能
  触发词；每个功能技能 SKILL.md 有「触发场景 + 调用 `<domain>.<x>.<y>`（参数）」；技能引用的 RPC 名与
  `extension.py` / `<domain>Api.ts` / `dispatch_<domain>_rpc` **四处一致**；**每个功能技能 SKILL.md 有「可执行通道段」**
  （REST 网关地址/方法/鉴权头/参数契约，或已注册的 Agent 领域工具——grep 一遍确认即停，**动态验证由 domain-qa 全量执行**）。
- ⏱ **四查失败只修 1 轮（≤2min）**：若发现 RPC 名/目录名/字面量等不一致，按 C4「一次写对」清单修 1 轮；
  仍不过 → 把失败明细完整写进 PR/A2A 交 domain-qa 复核，**禁止反复"查→改→重查"**。

#### C6 文档与部署脚本
- 按 `references/delivery-and-docs-guide.md`：README 品牌化、`<Domain>Swarm快速部署指南.md`、
  `<Domain>Swarm架构图.svg`、`<Domain>Swarm经验分享.md`、启动脚本对齐。

#### C7 验收已移交 domain-qa（coding 不再做运行级验收）
- 运行级验收（静态自检 7.1、后端 1 次启动 + `/health` + WS 黑盒 7.2、前端编译 + 品牌冒烟 7.3、
  对话识别 + 对话代办冒烟 7.4、超时降级 7.5）**已整体移交 `domain-qa` 全量执行**，见
  `../domain-qa/SKILL.md` Q2/C7 与 `../domain-qa/references/qa-checklist.md`。
- coding 侧只保留**静态交付**义务：
  - 自检脚本：将 `references/scripts/validate_domain_project.py`（权威版，与 domain-qa 保持一致）
    复制到落地仓库 `scripts/`，运行确认无导入/语法错误即可（运行级判责在 qa）；
  - 前端编译、后端启动、WS 黑盒、对话代办等运行级动作**一律不再在 coding 阶段执行**，
    避免与 qa 重复耗时（qa 会按同套脚本与 `ws_smoke.py` 一次性完成）。
- ⏱ **自检失败只修 1 轮（≤2min）**：脚本运行发现失败项时按 C4「一次写对」清单修 1 轮，
  仍不过 → 立即停，把失败明细完整写进 PR/A2A 交 domain-qa 复核；**禁止反复"跑自检→修→重跑"循环**
  （日志实测 30 分钟超时主因即此，多轮迭代不产出新增交付物）。

#### C8 PR + A2A 交办 domain-qa
- 建 PR：标题 `<Domain>Swarm 领域二次开发实施`；描述直接**引用 C3 已产出的设计摘要**（功能模块实现对照表 + 品牌改造前后对照，不重复生成）+ 交付物清单（含 `scripts/validate_domain_project.py` 已就位）；关联 Issue `#<issue_id>`。
- **提交推送 + grape CLI 显式建 PR（命令与 `references/grape-cli-reference.md` PR 管理节一致）**：
  ```bash
  # ① 提交并推送当前开发分支（spec §二落地分支：issue-{N} / feat/issue-{N}）
  git add -A
  git commit -m "feat(<domain>): <Domain>Swarm 领域二次开发实施\n\nCloses #$ISSUE_NUMBER"
  git push origin <spec 二落地分支名>
  # ② grape CLI 建 PR（base 固定 develop——C2 铁律：PR 合回只读基线，禁止派生子仓库）
  grape git-repo pulls create --owner "$REPO_OWNER" --repo "$REPO_NAME" \
    --head <spec 二落地分支名> --base develop \
    --json '{"title":"<Domain>Swarm 领域二次开发实施","description":"<引用 C3 设计摘要 + 交付物清单>","close_related_issue":true}'
  # 建成功 → 记录 pr_number 供评论/A2A 引用；失败重试 ≤3 次
  ```
- ⚠️ **重复 A2A 检查**：若 pipeline 已含 `qa:a2a_event`，不重复 A2A，只评论。
- **A2A 交办 domain-qa**：
```bash
# 防重复检查
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 已含 qa:a2a_event → 不重复，只发评论；否则执行 a2a handoff
grape a2a handoff --json '{"agent":"qa","payload":{"repository":"$REPO_FULL_NAME","account":"$ACCOUNT","issue_number":'$ISSUE_NUMBER',"pr_url":"<pr_url>","domain":"<domain>","product_brand":"<Domain>Swarm","changes_summary":"<C3 设计摘要>","deliverables":["scripts/validate_domain_project.py","docs/..."],"allowed_agents":["qa","sre"],"context":"Coding 已完成 jiuwenswarm 改造 + 建 PR + scripts 已就位，请按 qa-checklist 验收"}}'
# 失败 → 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入
```

### 场景 B：修改请求（qa/sre 打回）

> ⚠️ **触发条件**：评论区最近一条是 `[Domain QA Agent] REVISE` 或 `[Domain SRE Agent] REVISE`，**或** A2A payload 含 `recheck: true`（参见「场景路由表」）。判错场景 = 漏跑 A2A 链路 = 流水线断在 coding。

**流程总览（一行）**：

> ⓪ 读打回评论（B0）→ ① 定位 REVISE 项 + 修复（B1）→ ② 发修复摘要评论（B2）→ ③ 防重复检查（B3）→ ④ **A2A qa 复检（硬性必经节点，未成功不得 complete）**（B4）→ 收尾

**执行规则**：
- 场景 B 全部修复完成**必须 A2A qa 复检**——qa 不会自动唤醒复检，"只评论不 A2A" = 链路断在 coding（qa 永远不会复检 → sre 永远不会收到）；
- 不得越级直接 A2A sre（sre 拒绝未通过 qa 复检的代码）；
- 修复后**不重复运行动态验收**（运行级复验由 domain-qa 统一执行），coding 只保证修复代码就位、`scripts/validate_domain_project.py` 静态无导入错误。

**执行命令**：

```bash
# B0 读打回评论（含 REVISE 项）
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# B1 修复对应文件（按 REVISE 项逐条修复，不在范围内不动）
# B2 发修复摘要评论（含每项的修复点 + 复查入口）
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Domain Coding Agent] REVISE 修复摘要：\n- {REVISE 1}：{修复点}（文件:路径）\n- ...\n复查入口：{grep/regex 命令或 commit hash}"}'
# B3 防重复检查
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# B4 必做：A2A qa 复检（除非已含 qa:a2a_event 才跳过——防重复交办）
grape a2a handoff --json '{"agent":"qa","payload":{"repository":"$REPO_FULL_NAME","account":"$ACCOUNT","issue_number":'$ISSUE_NUMBER',"pr_url":"<pr_url>","recheck":true,"allowed_agents":["qa","sre"],"context":"Coding 已按 REVISE 修复，请按 qa-checklist 复检"}}'
# 失败 → 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 标人工介入
# ⚠️ B4 失败或未执行 → 不得调用 grape tasks complete（链路未贯通 = 任务未完成）
```

前端**16 处改动**的实施判据内联在 C4 各阶段 + 硬约束 5/6/7/11/12/13；**运行级验收统一由 domain-qa 全量执行**
（静态自检 + 1 次启动抽查 + WS 黑盒 + 前端编译 + 代表指令对话冒烟 + 24p/24t 全量闭环），coding 不重复。

## 前端改造真实代码形状（对照法务先例，照此形状写）

后端 `extension.py` 骨架（**handler 必须 `async def (ws, req_id, params, session_id)` 并自行 send_response**）：
```python
def _make_handler(channel, sub):
    async def _h(ws, req_id, params, session_id):          # ← 框架 register_method 硬契约：4 参
        try:
            result = dispatch_<domain>_rpc(sub, params or {})
        except Exception as exc:
            await channel.send_response(ws, req_id, ok=False, error=str(exc), code="<DOMAIN>_RPC_EXCEPTION")
            return
        if isinstance(result, dict) and result.get("ok") is False:
            await channel.send_response(ws, req_id, ok=False, error=result.get("error") or "failed", code="<DOMAIN>_RPC_ERROR")
            return
        # payload 必须解出业务数据本体（dispatch 返回 {ok,data} 双层包裹）；整包下发会让前端
        # res.items 取到空 → 页面"暂无资产"（finance 实坑）。与 REST 网关 result.get("data") 同口径。
        data = result.get("data") if isinstance(result, dict) else {}
        await channel.send_response(ws, req_id, ok=True, payload=data or {})   # ← 必须自行回包
    return _h

class <Domain>PlatformExtension(ApplicationPluginExtension):
    plugin_id = "<domain>_platform"
    def bind_web_channel(self, channel, services):         # ← 基类契约（不是 initialize(binding_web_channel)）
        for sub in _<DOMAIN>_RPC_METHODS:                  # ("health", "case.list", "case.create", ...)
            channel.register_method(f"<domain>.{sub}", _make_handler(channel, sub))

async def register_extensions(registry, *args):
    plugin = <Domain>PlatformExtension()
    registry.register_application_plugin(plugin)           # 必须登记，否则 WS 方法不绑定
    cfg = get_config() or {}
    if (cfg.get("<domain>_gateway") or {}).get("enabled"): # ← 配置必须经 get_config() 读取，registry.config 是空 {}
        start_<domain>_gateway(...)
    return [plugin]
```
前端 `services/<domain>Api.ts` 骨架：
```ts
import { webRequest } from './webClient';
export async function <domain>CaseList(keyword?: string) {
  return ok(await webRequest<...>('<domain>.case.list', { keyword: keyword || '' }));
}
```
`SessionSidebar/index.tsx`（**导航 items 外包滚动容器**）：
```tsx
import logoIcon from '/<domain>-ai-logo.svg';         // 左上角图标按领域更换
{ key: '<domain>Case', labelKey: 'nav.<domain>Case', icon: <领域图标/> }   // 每功能一项
<div className="icon-rail-nav-list">                  // 页签过多时可滑轮
  {visibleMainNavItems.map((item) => (
    <button key={item.key} className="icon-rail-nav-item" ...>
      <span className="icon-rail-nav-item__icon">{item.icon}</span>
      <span className="icon-rail-nav-item__label">{...}</span>
    </button>
  ))}
</div>
```
`SessionSidebar.css`（与 `.icon-rail-nav-item` 同级新增）：
```css
.icon-rail-nav-list {
  display: flex; flex-direction: column; align-items: center;
  flex: 1 1 auto; min-height: 0; width: 100%;   /* min-height:0 配合 flex 才可收缩滚动 */
  overflow-y: auto; overflow-x: hidden; scrollbar-width: thin;
}
.icon-rail-nav-list::-webkit-scrollbar { width: 4px; }
.icon-rail-nav-list::-webkit-scrollbar-thumb { background: var(--color-border-default); border-radius: 2px; }
```
> ⚠️ **RPC 三名一致铁律**：`extension.py` 注册名、`<domain>Api.ts` 的 `webRequest('<domain>.xxx')`、
> `dispatch_<domain>_rpc` 分支三处一致，改名需三处同步。

## 操作边界

| 行为 | 态度 |
|------|------|
| 全程读写模板仓库文件 | ✅ **可以做** |
| 按 spec 改造扩展/前端功能模块/品牌/Agent/技能/文档 | ✅ **必须做** |
| 运行 Python 自检脚本（仅确认静态无导入/语法错误） | ✅ **可以做** |
| git 状态/差异查看 | ✅ **可以做** |
| git push 建 PR | ✅ **必须做**（推送前交付物齐全） |
| 删除/修改框架核心或 LICENSE/开源声明 | ❌ **禁止** |
| 跳过交付物完整性检查直接交办 | ❌ **禁止** |
| 在 coding 阶段重复做运行级验收（后端启动/tsc/WS 黑盒/对话冒烟） | ❌ **禁止**（已移交 domain-qa） |
| 回复 Token/密码 | ❌ **禁止** |

## 硬约束

1. **必须先读全 references + 法务先例再做改动**（C1 与 C4 次序不得颠倒）。
2. **交付物齐全是交办前提**：功能三件套（页签/RPC/落库）、品牌五触点、Agent/技能、文档四件套、
   `scripts/validate_domain_project.py` 静态无导入错误——缺一不得 A2A；**运行级验收（含退出码 0 判定）由 domain-qa 全量执行，coding 不预跑冒烟**。
3. **框架守约**：领域能力只入扩展目录、领域配置/技能目录与领域前端模块目录，框架核心不动。
4. **开源合规**：保留 LICENSE 与开源声明。
5. **功能三件套**：每个 Spec 功能点必须「前端页签 + 后端 RPC + 落库」齐备，缺一即未完成。
6. **导航形态（多入口直挂）**：每功能一独立 `SidebarNavKey` + 一导航项 + 一独立页面组件（App.tsx 每 key 独立渲染分支）；
   **禁止打包进单个工作台入口再分 tab/mode 切换**；可选 `<Domain>WorkbenchPanel` 不得替代。
7. **品牌改造必做（五触点，缺一即未完成）**：左上角 logo、**浏览器页签 title**（`index.html` `<title>` + `app.title`）、
   **任务对话窗口硬编码中英文欢迎语/标语**（不只 i18n）、「能做啥」（平台+领域能力；分享图品牌名同改）、
   **全仓 `git grep -n "<旧品牌名>"` 清零**（含 i18n 散落文案、分享图 producer 标签）。
8. **PR 必带**：关联 Issue，描述含设计摘要（功能模块实现对照表）+ 交付物清单（含 `scripts/validate_domain_project.py`）。
9. **A2A / CLI 失败降级**：`grape a2a handoff` 非 2xx 或超时（CLI 退出码 ≥400 即 HTTP 透传）→ 重试至多 3 次；仍失败 → 评论注明，标记人工介入。
   其他 CLI 命令（`issues detail` / `pipeline` / `comments create` 等）出错时**先看完整 stderr**（去掉 `| tail` 截断，`2>&1` 保留 stderr）→ 不反复盲试同一命令；命令不识别时先 `grape refresh` 再重试。
10. **一条流水线只跑一次实施**：确认 payload 无 `coding:a2a_event` 才执行核心改动。
11. **前后端必须真正可用（不只是文件就绪）**：`async def register_extensions` + **RPC handler 4 参契约
    （`async def h(ws, req_id, params, session_id)` + `send_response`）** + **WS 成功回包 `payload` 必须是业务数据本体
    （`result.get("data")`），禁止整包下发 `payload=result or {}`（否则前端 `res.items` 取空、页面"暂无资产"，
    finance 实坑）** + 配置经 `get_config()` 读取 + **扩展模块绝对导入（❌ 禁相对导入，finance 实坑：
    相对导入报 `No module named 'jiuwenswarm.loaded_extension'` → 扩展整体加载失败、全域 RPC `unknown method`，见 v4.4）**
    + 双配置生效且 `enabled: true`；
    **运行级验收统一由 domain-qa 全量执行**（后端 1 次启动 + `/health` +
    **WS 黑盒（现成 `ws_smoke.py`，禁止手写脚本）**、前端可编译、代表指令对话冒烟、
    **六步完整闭环 create→list→…→delete 与逐功能对话代办 24p/24t 均由 domain-qa 执行**），coding 只保证硬件约束在代码中落实。
12. **导航滚动容器 + 页签排序-双路径必做**：items 渲染处必须用 `<div className="icon-rail-nav-list">` 包裹 +
    css `overflow-y:auto`（**禁止**因导航过多导致底部页签不可达/不可点）；
    **新增领域/插件页签必须固定插在「任务」(chat) 之下**（`chat` 与 `skills` 之间）——静态数组
    `domainFeatureNavItems` 与 `visibleMainNavItems` 组装处的应用插件动态页签 `applicationPluginItems`
    都遵循 `[chat, ...domainFeatureNavItems, ...applicationPluginItems(按 position 排序), ...rest]`；
    **❌ 禁止 `[...mainNavItems, ...applicationPluginItems]` append 末尾**（gov 实坑：领域页签排到"更新"等平台页签后）。
13. **任务对话可识别 + 可执行（不只是前端页签可用，也不可"只聊不做"）**：五要件缺一即未完成——
    (a) 协调技能委派映射表覆盖每功能触发词；
    (b) 每功能技能写「适用场景」+「调用 `<domain>.<x>.<y>` + 参数」；
    (c) persona「能做啥」逐条枚举领域功能；
    (d) 技能引用的 RPC 名与 `extension.py`/`<domain>Api.ts`/`dispatch_<domain>_rpc` **四处一致**；
    (e) **每功能技能必含「可执行通道段」**（写清 REST 网关地址/方法/鉴权头（api_key 来自 config）/参数 JSON 契约，
    或注册为 Agent 可直接调用的领域工具 `<domain>_gateway_tool.py`）——模型拿到技能文档即可真实发起调用；
    (f) **Agent 领域工具全量注册（v4.3 新增，account 实坑）**：凡 Spec 开放对话代办的功能必须提供
        `<domain>_gateway_tool.py`（**进程内直调 `dispatch_<domain>_rpc`**，返回体摘要化防撑爆上下文，
        失败才回退 REST）并注册进 `interface_deep.py` `_get_tool_cards()`（import → `_register_shared_tool` →
        `tool_cards.append(card)` → 日志）；**进程内工具无条件注册**（try/except 包裹，不受
        `<domain>_gateway.enabled` 关闭）。收尾全量核对 `extensions/*_platform/*_gateway_tool.py` ↔
        `interface_deep.py` 注册块**一一对应**，漏一个即未完成；
    运行级验证（识别→真实 RPC（看日志/落库，非只看回复文本）→落库/数据变化→页签可见）**由 domain-qa 全量执行**
    （24l/24t 逐功能），coding 只在 C5 静态四查保证五要件在配置中写全，不预跑对话冒烟。
14. **A2A 链路贯通（v3.6 新增，最高优先，防 QA→Coding→QA→SRE 链断）**：
    - 完整链 = `coding A 实施 → qa A 验收 →（PASS → sre / REVISE → coding B 修复）→ qa B 复检 →（PASS → sre / REVISE → coding C 修复…）`；
    - **场景 B 修复完成必须 A2A qa 复检**——qa 不会自动唤醒复检，"只发修复摘要评论而不 A2A" = 链路断在 coding
      （qa 永远不会复检 → sre 永远不会收到，pipeline 永远卡在 QA/Coding 循环外）；
    - **coding 不得越级直接 A2A sre**（跳过 qa 复检）——sre 拒绝未通过 qa 复检的代码；
    - **未成功 A2A → 不得调用 `grape tasks complete`**（链路未贯通 = 任务未完成）：
      * A2A handoff 非 2xx / 超时 → 重试 ≤3 次；
      * 仍失败 → 评论说明「A2A 服务不可达，待恢复后重试」+ `next_step` 标人工介入；
      * 即便 A2A 失败也**不得 complete**（任务进入待人工介入态，等恢复后人工补 A2A qa 复检）。

## 输出格式与任务收尾（必做）

业务动作完成后，先输出人类可读摘要（功能实施数/品牌五触点/交付物清单/PR URL），再调用。

**任务收尾的 A2A 链路贯通前置检查（必做，未贯通不得 complete）**：

| 场景 | A2A 调用 | actions 字段 | next_step 字段 |
|------|---------|-------------|---------------|
| 场景 A（首次实施）| A2A qa（首次验收）| `"A2A: qa(首次验收, status=ok/降级)"` | `"a2a_qa(首次验收) 或 等待 qa 验收"` |
| 场景 B（修复打回）| A2A qa（**复检，硬性**）| `"A2A: qa(复检, status=ok/降级)"` | `"a2a_qa(复检) 或 等待 qa 复检"` |
| A2A 调用失败 | — | `"A2A: {agent}, status=失败(重试3次仍失败)"` | `"A2A 服务不可达，待恢复后人工补 A2A qa 复检（链路未贯通 = 任务未完成）"` |

> ⚠️ **A2A 失败 / 跳过 = 链路未贯通 = 不得 complete**（参见硬约束 #14）。

**场景 A 示例（首次实施）**：

```bash
grape tasks complete --json '{
  "result_text":  "Coding 处理完毕（结论：{Domain}Swarm 实施 + PR 已建，移交 qa 验收）",
  "actions":      ["读取 Spec v{N}", "后端: 扩展/网关/gateway_tool 三件套", "前端: {功能数} Panel/Api/Store/导航/品牌五触点", "Agent: {LEADER}+{N} worker", "技能: {M} 项 + 委派映射", "git push: <branch> → <pr_url>", "A2A: qa(首次验收, status=ok/降级)"],
  "conclusion":   "实施完毕 + PR 已建 + A2A qa 首次验收",
  "artifacts":    ["scripts/validate_domain_project.py（已就位）", "docs/{README,部署指南,架构图,经验分享}", "PR #<n>: <pr_url>", "A2A handoff: {agent=qa, status=ok/降级}"],
  "issue_summary":"{Domain}Swarm 实施摘要（{功能数} 功能 / {RPC 数} RPC / port={192xx}）",
  "next_step":    "a2a_qa(首次验收) 或 等待 qa 验收"
}'
```

**场景 B 示例（修复打回）**：

```bash
grape tasks complete --json '{
  "result_text":  "Coding 处理完毕（结论：按 qa/sre REVISE 修复完成，移交 qa 复检）",
  "actions":      ["B0 读打回评论", "B1 修复 {N} 项（{REVISE 1/2/...}）", "B2 发修复摘要评论", "B3 防重复检查", "A2A: qa(复检, status=ok/降级)"],
  "conclusion":   "修复完毕 + A2A qa 复检（硬性）",
  "artifacts":    ["修复摘要评论: {位置}", "A2A handoff: {agent=qa, status=ok/降级}"],
  "issue_summary":"按 REVISE 修复 {N} 项，移交 qa 复检",
  "next_step":    "a2a_qa(复检) 或 等待 qa 复检"
}'

# ⚠️ 场景 B 若 A2A qa 失败 / 未执行 → 不得 complete（链路未贯通 = 任务未完成），改为：
grape tasks complete --json '{
  "result_text":  "Coding 处理修复中（结论：修复完成但 A2A qa 复检未贯通，待恢复后人工补）",
  "actions":      ["B0-B2 完成（修复 + 评论）", "A2A qa 复检: status=失败(重试3次仍失败)"],
  "conclusion":   "修复完成 + A2A 链路未贯通（待人工补 A2A qa 复检）",
  "artifacts":    ["修复摘要评论: {位置}", "A2A handoff: 失败（待恢复）"],
  "issue_summary":"修复完成但 A2A 链路未贯通",
  "next_step":    "A2A 服务不可达，待恢复后人工补 A2A qa 复检（链路未贯通 = 任务未完成）"
}'
```

始终输出实施摘要 JSON（人类可读）：

```json
{
  "skill": "domain-coding",
  "summary": {
    "domain": "legal", "changes_done": 16, "features_implemented": 7,
    "brand_customized": {
      "logo": "已替换领域图标", "browser_tab": "index.html <title>+app.title 已改品牌名",
      "chat_welcome": "ChatPanel 硬编码欢迎语/标语已领域化（中英）", "welcome": "welcomeHeading 已领域化",
      "share_export": "shareImageExport 品牌 + producer 已替换", "howto": "能做啥=平台+领域",
      "old_brand_zero": "git grep WorkSwarm 无残留"
    },
    "skills_created": 7, "agent_configs": 7,
    "deliverables_ready": {
      "features_triplet_complete": true, "brand_5_touchpoints": true,
      "validate_script_placed_in_repo": true, "docs_4_suite": true
    },
    "runtime_acceptance_deferred_to_qa": {
      "static_self_check_exit_0": "domain-qa 执行", "backend_smoke_1startup_health_ws": "domain-qa 执行",
      "frontend_tsc_brand_zero": "domain-qa 执行", "chat_delegation_smoke_24t": "domain-qa 执行"
    },
    "conversation_recognizable": {
      "delegation_mapping_covers_all_features": true, "skills_document_rpc_per_feature": true,
      "persona_enumerates_features": true, "rpc_names_compatible_4_places": true,
      "skills_have_executable_channel": true,
      "dialogue_delegation_real": ["帮我查安全生产政策->policy.search实际返回结果", "帮我录入政策->policy.import落库行数+1可见"]
    },
    "pr_url": "https://.../pull/84"
  },
  "next_step": "A2A 已交办 domain-qa 验收。"
}
```

## 参考

- `references/template-project-guide.md` / `references/secondary-dev-pattern-guide.md`
- `references/extension-implementation-guide.md` / `references/domain-frontend-integration-guide.md`
- CLI 命令面与契约：`references/grape-cli-reference.md` / 安装与自愈：`references/grape-cli-installation.md`
- `references/domain-skills-authoring-guide.md` / `references/delivery-and-docs-guide.md`
- 架构设计：`../domain-issue/references/domain-architecture-guide.md`
- 模板资源：`references/templates.md` / 自检脚本交付副本：`references/scripts/validate_domain_project.py`
  （**权威版在 `../domain-qa/references/scripts/`，两侧保持一致，勿分叉**）
- 运行级验收（WS 冒烟 `ws_smoke.py` / 前端编译 / 对话代办 24t）统一由 domain-qa 执行，脚本见
  `../domain-qa/references/scripts/`
- **第一先例（照抄）**：基线仓库 `extensions/legal_platform/` + 前端 `LegalWorkbenchPanel/legalApi.ts/legalStore.ts/frontendPlatform.ts/SessionSidebar/legal-ai-logo.svg/i18n`

> ⚠️ **任务结束**：完成所有业务动作后，输出最终 JSON 块并**结束任务**，不要继续思考或等待输入。