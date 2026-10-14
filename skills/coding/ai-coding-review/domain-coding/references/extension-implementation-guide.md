# 领域扩展层实现手册

> 配套 `skills/domain-coding/SKILL.md`。
> **第一参考先例 = 基线仓库 `jiuwenswarm`（develop 分支）的 `extensions/legal_platform/` 实际实现**
> （其 `extension.py` 用 ApplicationPlugin + `bind_web_channel` 注册 `legal.*` RPC，附带 REST 网关）；
> EduSwarm `extensions/edu_platform/` 作为第二先例。
> 所有代码骨架可从 `templates.md` 直接复制改造。

## 一、扩展目录骨架

```
extensions/<domain>_platform/
├── extension.yaml              # 扩展声明
├── extension.py               # 注册 <domain>.* RPC + hook + 启动网关
├── <domain>_backend.py        # 领域业务逻辑（纯标准库，函数式，入参出参 dict）+ dispatch_<domain>_rpc 分发
├── <domain>_gateway.py        # 可选：REST 网关（http.server + threading）
└── <domain>_gateway_tool.py   # 可选：Agent 侧「网关调用」工具（domain_gateway_call）
```

命名约定：`<domain>` 用小写单词，如 `edu`、`legal`、`medical`。

> 前端功能模块（页面/API/store/左侧导航/品牌）见配套
> **`references/domain-frontend-integration-guide.md`**——领域 Swarm 若没有前端可点页面，不算完成。

## 〇、扩展可用性前提（当前基线 loader/框架契约，编码前必读）

基线 `jiuwenswarm/extensions/loader.py` 与 `extensions/registry.py` 的加载/绑定方式决定了后端「可用性」的
硬约束，编码时逐条遵守，否则功能即便写完也跑不起来（以下均为实战踩坑后的结论）：

1. **入口 `register_extensions` 必须是 `async def`**：loader 以 `await module.register_extensions(registry)`
   调用（`loader.py load_extension` 中 `registered = await module.register_extensions(self.registry)`）。
   写成同步 `def` 会导致协程未 await，扩展注册失败、RPC 绑定不上。
   ```python
   async def register_extensions(registry): ...   # ✅ 与 loader 契约一致（finance 先例）
   def register_extensions(registry): ...         # ❌ 加载后不会执行，功能不可用
   ```
2. **⚠️ 扩展内模块引用必须用绝对导入**（`from jiuwenswarm.extensions.<domain>_platform.<module> import ...`）：
   loader 的 `_import_module` 用 `importlib.util.spec_from_file_location("jiuwenswarm.loaded_extension.<name>", entry)`
   动态加载 `extension.py`，**磁盘上不存在 `jiuwenswarm.loaded_extension` 父包**。
   ❌ **禁止相对导入 `from .<domain>_backend import ...`**：相对导入需解析父包 `jiuwenswarm.loaded_extension`
   → 报 `No module named 'jiuwenswarm.loaded_extension'` → 整个扩展加载被跳过、全部 `<domain>.*` RPC 未注册、
   前端所有功能页 `unknown method`（**finance_platform 实坑，46 个 RPC 全丢，已修复**；对照先例 `video_duplex`
   即用绝对导入，加载正常）。
   绝对导入正确形状（与 `video_duplex/extension.py` 一致）：
   ```python
   # extension.py
   from jiuwenswarm.extensions.finance_platform.finance_backend import (
       dispatch_finance_rpc,
       init_db,
   )
   ```
   **不要用 `import <domain>_backend` 直接顶层导入**（会把内部模块加载成独立副本，与 extension.py 的依赖关系
   脱离包上下文）；一律 `from jiuwenswarm.extensions.<domain>_platform.<module> import ...`。
   若收到 `No module named 'jiuwenswarm.loaded_extension'` → 立即检查 extension.py 及扩展内其他模块（如
   `<domain>_gateway.py`）是否残留相对导入（`from .xxx import`），逐一改为绝对导入。
3. **⚠️ 扩展读自身配置段必须走 `from jiuwenswarm.common.config import get_config()`（⚠️ 不要读 `.config`）**：
   框架 `ExtensionRegistry` 构造时以 `config={}` 创建 `ExtensionConfig`，**`registry.config.config` 恒为空
   `{}`**——旧指南的 `getattr(config, "config", None) or (config if isinstance(config, dict) else {})`
   在这里取出来是空 dict，`<domain>_gateway` 段永远不存在 → `enabled=False` → **网关永不启动、功能不可用**
   （finance 首版即栽在此坑）。正确写法（与 `agent_client`/`agentos` 等既有扩展一致）：
   ```python
   from jiuwenswarm.common.config import get_config
   config = get_config() or {}                   # 读全局运行时配置（resources/config/config.yaml）
   gw = (config.get("<domain>_gateway") or {})
   if gw.get("enabled", False):
       _start_<domain>_gateway(gw.get("host","0.0.0.0"), int(gw.get("port",19211)), ...)
   ```
4. **RPC handler 必须是 `async def handler(ws, req_id, params, session_id)` 并自行 send_response**：
   `registry._ApplicationPluginChannel.register_method` 会把 handler 包装成 4 参调用且**等待 handler 自行回包**。
   写 `lambda p: dispatch(...)`（1 参）会 `TypeError`；同步返回 dict 不回包则前端永远 pending。
   唯一正确形状（finance 已验证）：
   ```python
   def _make_handler(channel, sub):
       async def _h(ws, req_id, params, session_id):
           result = dispatch_<domain>_rpc(sub, params or {})      # 异常 / ok:false 也要回包
           data = result.get("data") if isinstance(result, dict) else {}   # ⚠️ 必须解出业务数据本体再下发
           await channel.send_response(ws, req_id, ok=True, payload=data or {})
       return _h
   ```
   `bind_web_channel(self, channel, services)` 中 `channel.register_method("<domain>."+sub, _make_handler(channel, sub))`。
   **⚠️ WS 成功回包 `payload` 必须是业务数据本体（<domain>_backend 的 `dispatch_<domain>_rpc` 返回 `{ok, data}` 双层包裹，
   与 WS/REST 同源）。前端 `webRequest` 的 resolve 值恰是当前 payload，组件直接取 `res.items`/`res.total` 等业务字段。
   若整包下发 `payload=result or {}`，前端会拿到 `{ok, data}` 双层结构 → `res.items` 为 undefined → 页面显示
   "暂无资产"（finance 实坑：数据库已落库但前端列表空白）。必须与 REST 网关同口径（网关侧本就用
   `result.get("data")`）。**
5. **健康检查必须注册**：`<domain>.health` RPC 与 `/api/<domain>/health` REST 是 QA 冒烟与 sre 部署验证的入口，缺一不可。

## 二、extension.yaml（模板见 templates.md「1. 领域扩展声明 extension.yaml」）

```yaml
id: legal_platform
name: legal_platform
version: 0.1.0
description: 法务智能工作台核心扩展：法务能力 RPC/REST、法务角色 Agent 配置、法务上下文 hook 注入。
author: legalswarm
min_jiuwenswarm_version: "0.2.0"
```

要点：`id` 全局唯一；`description` 写清扩展职责；`min_jiuwenswarm_version` 对齐模板版本（参考 `pyproject.toml`/`__init__.py`）。

## 三、extension.py（模板见 templates.md「2. 领域扩展入口 extension.py」）

两种注册模式，二选一：

- **A. ApplicationPlugin 模式（当前项目 finance 先例已验证，推荐**：`bind_web_channel` 更适合浏览器端
  `webRequest('<domain>.xxx')` 直调，前端功能页面不依赖 LLM 即可用）
  ```python
  # ⚠️ 基类契约是 bind_web_channel(self, channel, services)，不是 initialize(binding_web_channel)
  # ⚠️ handler 必须是 async def (ws, req_id, params, session_id) 且自行 send_response（见 §〇.4）
  def _make_handler(channel, sub):
      async def _h(ws, req_id, params, session_id):
          try:
              result = dispatch_legal_rpc(sub, params or {})
          except Exception as exc:
              await channel.send_response(ws, req_id, ok=False, error=str(exc), code="LEGAL_RPC_EXCEPTION")
              return
          if isinstance(result, dict) and result.get("ok") is False:
              await channel.send_response(ws, req_id, ok=False, error=result.get("error") or "failed", code="LEGAL_RPC_ERROR")
              return
          # ⚠️ payload 解出 data 业务本体，禁止整包下发（见 §〇.4）：否则前端 res.items 取空、页面"暂无资产"
          data = result.get("data") if isinstance(result, dict) else {}
          await channel.send_response(ws, req_id, ok=True, payload=data or {})
      return _h

  class LegalPlatformExtension(ApplicationPluginExtension):
      plugin_id = "legal_platform"
      def bind_web_channel(self, channel, services):
          for sub in LEGAL_RPC_METHODS:                       # ("health", "case.list", "case.create", ...)
              channel.register_method("legal." + sub, _make_handler(channel, sub))

  async def register_extensions(registry, *args):
      plugin = LegalPlatformExtension()
      registry.register_application_plugin(plugin)            # 必须登记，否则 WS 方法不绑定
      cfg = get_config() or {}                                 # 配置读取走 get_config()（见 §〇.3）
      if (cfg.get("legal_gateway") or {}).get("enabled", False):
          start_legal_gateway(...)
      return [plugin]
  ```
- **B. registry 模式（EduSwarm 先例**：`registry.register_rpc_handler("<domain>.xxx", lambda p: handler(p))` + `registry.register("before_system_prompt_build", hook)`）

### 3.1 注册领域 RPC

```python
# 骨架：handler 包装为「接收 dict 参数」形式，统一签名；实现放 <domain>_backend，RPC 只做转发。
registry.register_rpc_handler("legal.contract.review", lambda p: contract_review(p))
registry.register_rpc_handler("legal.case.create",     lambda p: case_create(p))
registry.register_rpc_handler("legal.skills.list",     lambda p: get_legal_skills())
registry.register_rpc_handler("legal.team.list",       lambda p: team_list())
# 注册 before_system_prompt_build hook 注入领域上下文
registry.register("before_system_prompt_build", _make_sync_hook(), priority=50)
# 启动 REST 网关（独立线程独立端口）
_start_domain_gateway_from_registry(registry)
```

要点：
- 所有 handler 包装为「接收 dict 参数」形式，统一签名。
- 一个领域能力的实现函数放在 backend，RPC 只做转发。
- **能力清单 RPC 必建**：`<domain>.skills.list` / `<domain>.team.list`，返回领域能力/团队清单——
  前端「团队成员」页与 Agent「能做啥」回答共用同一数据源，避免口径漂移。
- 异步后台任务（如生成报告）要跨线程回投事件循环广播完成事件（`loop.call_soon_threadsafe`）。

### 3.2 领域上下文注入 hook

为每个领域角色写一段 role context，注入到 system prompt。**「能做啥」回答必须二段式**：

```python
_DOMAIN_ROLE_CONTEXT = {
    "legal_leader": "你是法务主管（LEADER），统筹案件/合同任务拆解与团队协调……",
    "legal_contract_reviewer": "你是合同审查师。用 legal.contract.review 审查合同并输出审查意见书……",
    ...
}
_DEFAULT_DOMAIN_CONTEXT = (
    "当前运行于 LegalSwarm 法务智能工作台……"
    "可用法务能力 RPC：legal.contract.review（合同审查）、legal.search_law（法规检索）、"
    "legal.document.draft（文书起草）、legal.case.*（案件管理）、legal.compliance.check（合规检查）、"
    "legal.team.list（法务团队）。\n"
    "【强制·「能做啥」回答模板】当用户问你能做什么时，必须分三部分：\n"
    "  一、平台原生能力：多 Agent 协作、对话、文件/图片处理、联网检索、任务编排……（沿用模板口径）\n"
    "  二、本领域能力（LegalSwarm 已实现）：逐条列出功能清单（案件管理/文书起草/合同审查/法规检索/合规检查/团队）\n"
    "  三、引导用户直接提需求的例句（如「你可以说：审一下这份采购合同」）\n"
    "【强制·问候回复模板】当用户只发问候时，输出领域自我介绍 + 领域能力概览……"
)
```

hook handler 写法（同步回调，兼容 dict/对象 context、失败静默降级）见 `templates.md`「2. 领域扩展入口 extension.py」中 `_make_platform_hook` 实现。

### 3.3 领域 REST 网关

`registry` 无原生 HTTP 路由能力，REST 走独立 `http.server`：

```python
# <domain>_gateway.py
# 路由表：(http_method, path_pattern, handler)
ROUTES = [
    ("GET",  "/api/legal/health",                 lambda p: {"status": "ok"}),
    ("POST", "/api/legal/contract/review",        contract_review),
    ("POST", "/api/legal/research/search",        legal_research),
    ("POST", "/api/legal/draft/generate",         legal_draft_generate),
    ("POST", "/api/legal/case/create",            case_create),
    ("POST", "/api/legal/compliance/check",       compliance_check),
]
# 统一响应 {success, data?, error?}；支持 JSON body / query string；
# 鉴权 X-LegalSwarm-Key header 或 Authorization: Bearer；CORS；健康检查。
# 端口：config.yaml 的 <domain>_gateway.port（默认 19210 等偏移端口）
```

启动/停止：`start_domain_gateway(config)` 后台线程启动、`stop_domain_gateway()` 优雅停止，异常时降级不打崩主流程。

### 3.4 Agent 工具（**提供则必须完成"定义 + 注册"双步，否则模型看不到**）

`<domain>_gateway_tool.py` 暴露给 Agent 在对话中直接调领域能力（类似 edu 的 `edu_gateway_tool.py` 提供
`edu_gateway_call`、gov 的 `gov_gateway_call`），适用于需要让 Agent 通过工具而非 RPC 协议触达领域能力的场景。
**v4.3 account 实坑（2026-09）：此文件不再是"可后置"的可选项**——只要 Spec 段 2 ⑤⑥ 开放了任一功能
对话代办，就必须提供：account 域发票/凭证等页面齐全、WS RPC 全通，但**从未建 gateway_tool、也从未在
interface_deep.py 注册**，主对话"帮我登记一张发票"只会回软话术、SQLite 零写入（24t"只聊不做"同症状）。
一旦提供，必须按以下完整模式落地（**定义 + 注册双步，只定义不注册 = 模型看不到**）。

```python
# <domain>_gateway_tool.py —— 完整模式（gov 实坑修复后的最终形态）
from typing import Any, Dict
from openjiuwen.core.foundation.tool import tool

# ① 白名单方法集合（与 extension.py 注册的 <domain>.* 方法同名）
_DOMAIN_RPC_METHODS = {
    "document.list", "document.create", "document.get",
    "policy.search", "petition.search", "report.summary", "disclosure.search",
    ...
}

def _call_in_process(method: str, params: dict) -> dict:
    """② 优先进程内直调 dispatch（AgentServer 进程已加载扩展，可同步直查 SQLite）。"""
    from jiuwenswarm.extensions.<domain>_platform.<domain>_backend import dispatch_<domain>_rpc
    return dispatch_<domain>_rpc(method, params or {})

def _call_http_gateway(method: str, params: dict) -> dict:
    """③ 兜底：经 REST 网关 HTTP 调用（端口从 env/config 读，禁止硬编码）。"""
    ...  # POST http://<host>:<port>/api/<domain>/<method 的 / 分隔>，X-API-Key 鉴权

@tool(
    name="<domain>_gateway_call",
    description=("调用 <Domain>Swarm 领域能力…支持的方法：method 取别名…params 与 webRequest('gov.<method>', params) 同名同型"),
)
def <domain>_gateway_call(method: str, params: Dict[str, Any] | None = None) -> dict:
    sub = method[len("<domain>."):] if method.startswith("<domain>.") else method
    if sub not in _DOMAIN_RPC_METHODS:
        return {"success": False, "error": f"未知方法 {sub}，可选: {sorted(_DOMAIN_RPC_METHODS)}"}
    try:
        return _call_in_process(sub, params or {})   # ② 进程内优先：规避 REST 端口冲突
    except Exception as exc:
        return _call_http_gateway(sub, params or {})  # ③ 失败才回退 HTTP
```

**④ 注册进主对话 Agent 工具链（只写定义不注册 = 模型看不到，gov 实坑）**——在
`server/runtime/agent_adapter/interface_deep.py` 的 `_get_tool_cards()` 中（品牌工具块后、SkillToolkit 块前）加：

```python
config_base = get_config()  # 注意：以实际生效配置为准（用户目录 ~/.jiuwenswarm/config/config.yaml 覆盖仓库 config）
try:
    cfg = config_base.get("<domain>_gateway", {}) or {}
    if cfg.get("enabled", False):
        from jiuwenswarm.extensions.<domain>_platform.<domain>_gateway_tool import <domain>_gateway_call
        self._register_shared_tool(<domain>_gateway_call)      # 进程级共享注册（幂等）
        tool_cards.append(<domain>_gateway_call.card)          # 工具卡片挂进 Agent 工具链
        logger.info("[JiuWenSwarmDeepAdapter] <Domain>Swarm <domain>_gateway_call tool registered")
    else:
        logger.info("[JiuWenSwarmDeepAdapter] <Domain>Swarm <domain>_gateway_call tool skipped: disabled")
except Exception as exc:
    logger.warning("[JiuWenSwarmDeepAdapter] <domain> gateway tool registration failed: %s", exc)
```

**v4.3 注册形态二选一（account 实坑：进程内工具被 enabled 误关 = 主对话代办消失 / 从未注册 = 只聊不做）**：
- **进程内直调工具（推荐，无 REST 端口依赖）**：**无条件注册**——去掉 `if cfg.get("enabled")` 分支，
  直接 `from ...<domain>_gateway_tool import <domain>_gateway_call` + `self._register_shared_tool(...)` +
  `tool_cards.append(...card)`，整体 try/except 包裹（失败打 warning 不崩主流程）。进程内调用不经 REST 端口，
  网关 enabled 缺省/关闭不应让工具从模型工具链消失（account 实坑：只因依赖 enabled 判定/gateway 段缺失，
  发票、凭证登记在对话中凭空消失）；
- **REST 网关型工具（依赖 `<domain>_gateway` 端口）**：保留 enabled 控制（如上示例），且 config 双份 +
  enabled 判定按实际生效配置（用户目录 `~/.jiuwenswarm/config/config.yaml` 覆盖仓库 `resources/config.yaml`）。
- **收尾全量核对（必做）**：`grep -cl "gateway_tool" extensions/*_platform/*.py` 列出的每个域，在
  `interface_deep.py` `_get_tool_cards()` 逐一找对应 `_register_shared_tool(<domain>_gateway_call)`
  注册块，缺 1 = 未完成（该域主对话代办"只聊不做"，qa 24x/24z 判 FAIL）。

**调用契约**：`LocalFunction` 的 `.invoke(inputs_dict)` 首参是**单个结构化 dict**（`{"method": ..., "params": ...}`），
不是关键字参数——❌ `.invoke(method=..., params=...)` 会让 `inputs=None` 且异常被吞（gov 实坑）；
Agent 侧看到的是工具卡片（model-function calling 按 schema 传 `{"method","params"}`）。
**返回体必须摘要化**：长文本/大列表 key（content/detail/html/items 等）截断或折叠（如列表截前 20 条 +
"…共 N 项"），防止撑爆 LLM 上下文（account_gateway_tool 实现同款 `_compact` 辅助）。

## 四、backed 业务实现要点

- **纯标准库优先**：EduSwarm `edu_backend.py` 是 1.1MB 单文件纯标准库（sqlite3/json/http.client），避免引入与框架冲突的第三方依赖。
- **数据目录**：统一 `data/<domain>/` 下建 SQLite 库与导出文件。
- **函数风格**：`def contract_review(params: dict) -> dict`，内部做参数校验、调用 LLM（通过注入的 agent 调用或 REST 网关直连）、落库、返回 `{status, data}`。
- **LLM 调用注意**（EduSwarm 最重要坑）：reasoning 模型 `content` 与 `reasoning_content` 共享 max_tokens，内容生成类任务要么关思考（`thinking: {"type": "disabled"}`）要么加大 max_tokens（≥8000），并把「content 为空」当异常重试。

## 五、config.yaml 领域段（**双份配置，必做**）

> ⚠️ **运行可用前提（实践教训）**：`<domain>_gateway` 段必须**同时**写入两份配置，缺一不可：
> - `jiuwenswarm/resources/config/config.example.yaml` —— 配置样例（自检检查）；
> - `jiuwenswarm/resources/config/config.yaml` —— **运行时实际生效的配置**。若只写 example，
>   默认启动使用 `config.yaml` 时 `<domain>_gateway` 段不存在 → `enabled=false` → **REST 网关不加载、
>   `/api/<domain>/health` 直接不可用**（本次实践中 legal 就是这样补上的）。

```yaml
legal_gateway:
  enabled: true
  host: 0.0.0.0                # example 可 0.0.0.0；config.yaml 可收敛为 127.0.0.1（按部署安全要求）
  port: 19210                 # 领域偏移端口，避开 5173/18092/19000/19001/19200
  api_key: change-me-in-production
  cors:
    allow_origins:
      - "*"
  # 以下为可选扩展字段（按需提供）：
  # frontend_url: ''           # 局域网前端地址，如 http://192.168.x.x:5173
  # backend_url: ''            # 局域网后端地址，如 http://192.168.x.x:19210
  # ws_url: ws://localhost:18092
```

同时覆盖 `agents.agent_leader.system_prompt`（法务主管话术）、`team` 段（法务团队成员）。
> 若扩展默认启用 WebSocket RPC（如法务先例 `bind_web_channel` 直绑 channel）说明"无需配置即启用"，
> 而 REST 网关必须显式 `enabled: true` —— 两份配置都要体现。

## 六、前端接入（**必须做，v2 核心**）

> 本手册只讲后端；前端完整实施见 **`references/domain-frontend-integration-guide.md`**。
> 原则：**Spec 功能清单每个功能点都要做成"左侧导航可点页面 → webRequest 直调 RPC → 落库**，
> 用户不依赖对话也能操作**。

1. **品牌**：`public/<domain>-ai-logo.svg` 替换左侧栏左上角图标；`index.html` 标题、语言包 domain 化。
2. **侧边栏入口**：`utils/frontendPlatform.ts` 的 `SidebarNavKey` 追加 `<domain>*` key；
   `SessionSidebar` 导航数组加对应 items（i18n `nav.<domain>*`）。
3. **领域页面**：**每个 Spec 功能一个独立页面组件** `components/<Domain><Feature>Panel/`（数量=功能数，
   App.tsx 每 key 独立渲染；可选聚合首页 `<Domain>WorkbenchPanel/` 仅作补充入口，不替代各功能入口）
   + `services/<domain>Api.ts`（webRequest 直调）+ `stores/<domain>Store.ts`。
4. **欢迎语**：i18n `welcomeHeading/welcomeBubbleText/welcomeSuggestions` 领域化。
5. **「能做啥」**：Agent 上下文二段式回答（平台能力 + 领域能力），见 §3.2。
6. 不要重写前端工程结构。

## 七、自检：扩展加载验证（可用性冒烟）

```bash
# 1) 语法与关键契约静态验证
python -c "import ast; ast.parse(open('jiuwenswarm/extensions/<domain>_platform/extension.py', encoding='utf-8').read()); print('extension.py OK')"
# 2) 确认 register_extensions 为 async def（loader 以 await 调用，写成 def 会注册失败）
python -c "import ast,re; s=open('jiuwenswarm/extensions/<domain>_platform/extension.py',encoding='utf-8').read(); assert 'async def register_extensions' in s, 'register_extensions 必须为 async def'; print('async register_extensions OK')"
# 3) 扩展入口加载验证（v4.4：必须绝对导入。❌ 相对导入在 loader 动态模块名 jiuwenswarm.loaded_extension.<name>
#    下会报 No module named 'jiuwenswarm.loaded_extension' → 扩展加载失败、全域 RPC unknown method（finance 实坑）。
#    以下两查：a) extension.py 及其内部模块无 "from ." 相对导入残留；b) 模拟 loader 动态加载成功）
python -c "import pathlib; files=[p for p in pathlib.Path('jiuwenswarm/extensions/<domain>_platform').glob('*.py')]; bad=[str(f) for f in files if any('from .' in x.split('#')[0] for x in f.read_text(encoding='utf-8').splitlines())]; assert not bad, f'相对导入残留: {bad}'; print('无相对导入残留 OK')"
python -c "import importlib.util,sys,pathlib; p=pathlib.Path('jiuwenswarm/extensions/<domain>_platform'); spec=importlib.util.spec_from_file_location('jiuwenswarm.loaded_extension.'+p.name, p/'extension.py'); m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m); print('extension.py 可加载 OK')"
# 4) RPC handler 契约：必须 4 参 async + 自行 send_response（否则前端永远无响应）
python -c "import ast; s=open('jiuwenswarm/extensions/<domain>_platform/extension.py',encoding='utf-8').read(); assert 'async def _h(ws, req_id, params, session_id)' in s or 'send_response' in s, 'handler 必须 async 4 参并 send_response'; print('rpc handler contract OK')"
# 5) 两份配置都必须含领域段且 enabled: true（只写 example 则 REST 网关默认不启动）
python -c "import yaml; [print(f, 'OK') if (yaml.safe_load(open(f,encoding='utf-8')).get('<domain>_gateway', {}).get('enabled')) else print(f, 'FAIL: 缺少 <domain>_gateway.enabled=true') for f in ['jiuwenswarm/resources/config/config.example.yaml','jiuwenswarm/resources/config/config.yaml']]"
# 6) 启动冒烟（起服务确认扩展被加载、RPC 注册无异常，随后停掉）
JIUWENSWARM_DATA_DIR=$PWD/jiuwenswarm/resources python -m jiuwenswarm.start_services --foreground &
# 7) REST 网关健康检查
curl -s http://127.0.0.1:<port>/api/<domain>/health   # 期望 {"success": true, ...}
# 8) WS 黑盒闭环（必测）：前端 webRequest 走 Gateway WebChannel WS（Vite 代理 /ws → 19000，非 18092）
#    写一个 asyncio 脚本连 ws://127.0.0.1:19000/ws，发 {"method":"<domain>.asset.create","params":{...},"request_id":1}
#    → 断言收到 {"ok":true,...}；再 list 确认可见，跑完每个功能的 create→list→get→update→delete 闭环。
```

启动后检查日志包含领域扩展注册成功的输出、无 `ImportError`/`TypeError`，并测试 `GET /api/<domain>/health` 返回 success；
**WS 黑盒拿到 `ok:true` 回包才算 RPC 真正可用**（静态注册存在不代表前端能调到）。