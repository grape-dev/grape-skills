# 领域工程模板合集

> 配套 `skills/domain-coding/SKILL.md`。以下模板用于领域工厂生成目标仓库文件，使用时整段复制并全局替换占位符。

## 1. 领域扩展声明 extension.yaml

复制到 `jiuwenswarm/extensions/<domain>_platform/extension.yaml`，替换占位符：

- `<Domain>` → 领域名（首字母大写，如 `Legal`）
- `<domain>` → 领域名（全小写，如 `legal`）
- `<DomainSwarm>` → 产品名（如 `LegalSwarm`）
- `<中文品牌名>` → 中文产品名（如 `法务智能工作台`）

```yaml
id: <domain>_platform
name: <domain>_platform
version: 0.1.0
description: <DomainSwarm>核心扩展：<领域>能力 RPC/REST 网关、<领域>角色 Agent 配置、<领域>上下文 hook 注入。
author: <DomainSwarm>-team
min_jiuwenswarm_version: "0.2.0"
```

要点：`id` 全局唯一；`description` 写清扩展职责；`min_jiuwenswarm_version` 对齐框架版本（参考 `pyproject.toml`/`__init__.py`）。

## 2. 领域扩展入口 extension.py

复制为 `jiuwenswarm/extensions/<domain>_platform/extension.py`，替换占位符（仅出现在字符串中，标识符无需改名），在 `<domain>_backend.py` 中实现业务函数（入参出参均为 dict），并同步修改下方 RPC 注册表与 REST 路由表：

```python
# -*- coding: utf-8 -*-
import asyncio
import importlib
import json
import logging
import threading

logger = logging.getLogger(__name__)


# 动态导入领域 backend（模块名含占位符时仍是合法字符串，替换 <domain> 后生效）
try:
    _backend = importlib.import_module("<domain>_backend")
except Exception as exc:  # noqa: BLE001
    logger.exception("[<domain>_platform] 导入 <domain>_backend 失败: %s", exc)
    _backend = None


def _bn(name: str):
    """从 backend 取函数，缺失时返回 None（同一 backend 包装，幂等）。"""
    if _backend is None:
        return None
    return getattr(_backend, name, None)


# ======================================================================
# 一、领域 RPC 注册
# ======================================================================
async def _register_platform_rpc(registry):
    """注册 <domain>.* 命名空间 RPC（与 REST 网关路由表一一对应）。"""
    fns = {
        "<domain>.health": _bn("<domain>_health"),
        # 按 backend 实现补充：
        # "<domain>.contract.review":  _bn("contract_review"),
        # "<domain>.research.search":  _bn("research_search"),
        # "<domain>.draft.generate":   _bn("draft_generate"),
        # "<domain>.case.create":      _bn("case_create"),
        # "<domain>.compliance.check": _bn("compliance_check"),
    }
    for rpc, fn in fns.items():
        if fn is None:
            logger.warning("[<domain>_platform] RPC %s 的 backend 函数缺失，跳过注册", rpc)
            continue
        registry.register_rpc_handler(rpc, lambda p, _fn=fn: _fn(p))
    logger.info("[<domain>_platform] 已注册 %d 个 <domain>.* RPC", len([r for r in fns if fns[r] is not None]))


# ======================================================================
# 二、领域上下文 hook（before_system_prompt_build）
# ======================================================================
_ROLE_CONTEXT = {
    # 按领域成员补充（key 为 team member_name，如 legal_contract_reviewer）
    "<角色前缀>leader": "你是<领域>主管 LEADER，统筹任务拆解与团队协调，不亲自处理具体业务。",
    "<角色前缀>worker": "你是<领域>专职成员，负责具体任务生产，产出必须落库并返回 CONTROL_RETURN。",
}
_DEFAULT_CONTEXT = (
    "当前运行于 <DomainSwarm>（<中文品牌名>）。"
    "可用领域能力 RPC：<domain>.health（健康检查）等。"
    "示例话术：「用我的<领域>团队处理这个任务」\n"
    "【强制·问候回复模板】当用户只发送问候时，输出<领域>自我介绍："
    "我是<领域>主管 LEADER，我的团队已就位：<角色名单>。需要我处理什么任务？"
)
_CTX_FLAG = "has_<domain>_context"


def _make_platform_hook():
    """返回 before_system_prompt_build 钩子（同步回调，兼容 dict/对象 context，失败静默降级）。"""

    def capture(self, params, *args, **kwargs) -> None:
        try:
            state = getattr(self, "state", None)
            multimodal_state = getattr(self, "multimodal_state", None)
            if state is None:
                return
            replied = getattr(multimodal_state, "replied", False) if multimodal_state else False
            member_params = getattr(state, "team_member_params", None)

            builder = None
            if multimodal_state is not None:
                builder = getattr(multimodal_state, "system_prompt_builder", None)
            if builder is None:
                builder = getattr(state, "system_prompt_builder_service", None)
            if builder is None:
                return

            member_name = ""
            if member_params:
                member_name = member_params.get("member_name") or member_params.get("name") or ""
            role_context = _ROLE_CONTEXT.get(member_name) if member_name else None
            if not role_context and not replied:
                role_context = _DEFAULT_CONTEXT

            # 当前会话已注入过则跳过，避免重复
            existing = getattr(state, "swarm_chat_context", "{}") or "{}"
            try:
                existing_obj = json.loads(existing) if isinstance(existing, str) else (existing or {})
            except Exception:  # noqa: BLE001
                existing_obj = {}
            if existing_obj.get(_CTX_FLAG):
                return

            extra_text = ""
            if role_context:
                extra_text += "\n\n[<领域>上下文-" + (member_name or "默认") + "]\n" + role_context
            if not replied:
                extra_text += "\n\n[<领域>平台服务提示]\n当用户向你发送问候时，务必按【强制·问候回复模板】输出<领域>自我介绍。"
            getattr(builder, "append_text")(extra_text)

            existing_obj[_CTX_FLAG] = True
            try:
                state.swarm_chat_context = json.dumps(existing_obj, ensure_ascii=False)
            except Exception:  # noqa: BLE001
                pass

        except Exception as exc:  # noqa: BLE001
            logger.warning("[<domain>_platform] hook 注入失败（降级）: %s", exc)

    return capture


# ======================================================================
# 三、领域 REST 网关（http.server，独立端口，默认 19210，见 config.yaml <domain>_gateway.port）
# ======================================================================
def start_platform_gateway(host: str, port: int, api_key: str, cors_origins, ws_url: str = "") -> threading.Thread:
    """启动领域 REST 网关（后台线程）。路由表与 RPC 注册保持一致。"""
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    class PlatformHandler(BaseHTTPRequestHandler):
        def _send_json(self, code: int, payload: dict) -> None:
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _authorized(self) -> bool:
            if not api_key:
                return True
            h = self.headers.get("X-<DomainSwarm>-Key") or self.headers.get("Authorization", "").replace("Bearer ", "")
            return h == api_key

        def do_GET(self):  # noqa: N802
            path = self.path.split("?")[0]
            if path == "/api/<domain>/health":
                fn = _bn("<domain>_health")
                data = fn({}) if fn else {"status": "unknown"}
                self._send_json(200, {"success": True, "data": data})
            else:
                self._send_json(404, {"success": False, "error": "not found"})

        def do_POST(self):  # noqa: N802
            if not self._authorized():
                self._send_json(401, {"success": False, "error": "unauthorized"})
                return
            # 路由 /api/<domain>/<resource>/<action>：在业务落地后实现
            self._send_json(501, {"success": False, "error": "未实现路由"})

        def log_message(self, fmt, *args):  # 关闭默认访问日志
            pass

    server = ThreadingHTTPServer((host, int(port)), PlatformHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True, name="<domain>-gateway")
    thread.start()
    logger.info("[<domain>_platform] REST 网关已启动: http://%s:%s/api/<domain>/health", host, port)
    return thread


# ======================================================================
# 四、扩展入口
# ======================================================================
async def register_extensions(registry, *args):  # noqa: A003
    try:
        await _register_platform_rpc(registry)
        registry.register("before_system_prompt_build", _make_platform_hook(), priority=50)

        # 读取 config 中的 <domain>_gateway 段（registry.config 为 dict 或缺失时降级默认）
        config = getattr(registry, "config", None) or {}
        gw_cfg = (config or {}).get("<domain>_gateway") or {}
        if gw_cfg.get("enabled", False):
            start_platform_gateway(
                host=gw_cfg.get("host", "0.0.0.0"),
                port=int(gw_cfg.get("port", 19210)),
                api_key=gw_cfg.get("api_key", ""),
                cors_origins=gw_cfg.get("cors_origins", ["*"]),
                ws_url=gw_cfg.get("ws_url", ""),
            )
        return True
    except Exception as exc:  # noqa: BLE001
        logger.exception("[<domain>_platform] 扩展注册失败: %s", exc)
        return None
```

扩展三职责：RPC 注册（`register_extensions` 内 `_register_platform_rpc`）、上下文 hook 注入（`before_system_prompt_build`）、REST 网关（`start_platform_gateway`）。后台异步任务要跨线程回投事件循环广播完成事件（`loop.call_soon_threadsafe`）。

## 3. 领域 Agent 配置 agent_config.json

复制到 `resources/agent/<domain>_agent_configs/*.json`，替换占位符：

- `<role_id>` → 角色 ID（如 `legal_contract_reviewer`）
- `<角色中文名>` → 角色中文名
- `<领域>` / `<角色名单>` → 领域名、团队角色名单
- `<leader-skill-name>` → LEADER 挂载的技能名
- `<YYYY-MM-DD>` → 更新日期

```json
{
  "id": "<role_id>",
  "agent_id": "<role_id>",
  "name": "<角色中文名>",
  "persona": "你是<领域>主管 LEADER，统筹<领域>任务拆解与团队协调，不舍得亲自干活。你的团队：<角色名单>。\n调度规则：\n1. 先判断任务复杂度：简单任务（单次单产出）直接调用领域 RPC 解决，不组队；复杂任务（多环节依赖/需迭代）才组队，并向用户亮出团队名单。\n2. 单发言人：只有你直接对用户说话，成员只向你汇报。\n3. 一次只激活一个成员，等成员返回 CONTROL_RETURN（含产出摘要 + 产出ID/路径）再切换。\n4. 严禁嵌套组队；成员交付必须落地入库，禁止只输出文本。\n5. 成员失败 → 你兜底直调该成员能力，不让流程卡死。\n示例话术：\n- 简单：“审一下这份 NDA，标出风险条款”\n- 复杂：“为 XX 项目出一套<领域>文件…”\n- 长周期：“接手这个案件，管理立案到结案全流程”",
  "skills": ["<leader-skill-name>"],
  "knowledge_base": {},
  "source": "custom",
  "max_iterations": 200,
  "model": {
    "model_source": "default",
    "provider": "azure",
    "model": "gpt-4o",
    "temperature": 0
  },
  "updated_at": "<YYYY-MM-DD>"
}
```

字段约束：`id`/`agent_id` 统一 `<domain>_<role>` 小写；`persona` 必须含 5 段（定位与唯一职责 / 不做什么 / 可调用领域 RPC 能力清单 / 交付规范 / 示例领域话术）；`skills` 引用 `workspace/skills/` 真实存在的技能目录名。

## 4. 领域技能定义 SKILL.md

复制到 `resources/agent/workspace/skills/<skill-name>/SKILL.md`，替换占位符：

- `<skill-name>` → 技能名（kebab-case，如 `contract-review`）
- `<一句话说明…>` → 技能说明（含触发场景）
- `<domain>.xxx.yyy` 等 → 对接的领域 RPC：**必须替换为精确方法名**（如 `gov.policy.search`）。
  ❌ **禁止留占位符/通配**（`<domain>.xxx.yyy`、`gov.xxx`、`gov.complaint.*`）——自检"RPC 点名一致"
  正则 `({domain})\.([\w.]+)` 会把占位/通配形式也提取成"已引用 RPC"去比对注册表 → 必判 FAIL
  （gov 实测 5 个技能逐个改，是超时最大返工源）。RPC 名必须与 `extension.py` 注册名 / `<domain>Api.ts` /
  `dispatch_<domain>_rpc` 分支三处完全一致。

```markdown
---
name: <skill-name>
description: <一句话说明技能解决什么领域问题>。
steps:
  1. <第一步：获取输入/output：…>
  2. <第二步：调用领域能力 output: …>
  3. <第三步：产出落库并输出交付物 output: …; save_to_db: true>
---

# <技能中文名>

## 主要步骤
1. <获取输入> → `<domain>.xxx.yyy` 能力
2. <处理规则/核查要点列表>
3. 输出交付物并落库（产出ID/路径）

## 注意事项
- <关键规则，如"金额/违约条款必须明确提示">
- <输出格式要求，如"意见书格式：风险等级/条款位置/问题描述/修改建议">

## 边界
- <不做的事，如"不代签最终法律意见">
- <数据来源要求，如"检索结果必须带来源，不杜撰法条">
```

## 5. 领域扩展入口 extension.py（ApplicationPlugin 模式，基线仓库法务先例，v2 推荐）

`extensions/<domain>_platform/extension.py` 采用 `ApplicationPluginExtension`（框架当前实现方式），
通过 `bind_web_channel` 把 `<domain>.*` RPC 挂到 WebChannel，浏览器 `webRequest('<domain>.xxx')` 直调：

```python
# -*- coding: utf-8 -*-
import json
import logging
import re
import sqlite3
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

logger = logging.getLogger(__name__)
_DB_PATH = "<repo>/jiuwenswarm/resources/data/<domain>_platform.db"  # 按实际落位调整


def _db() -> sqlite3.Connection:
    conn = sqlite3.connect(_DB_PATH, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db():
    with _db() as conn:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS cases (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL, party TEXT DEFAULT '',
                stage TEXT DEFAULT 'open', assignee TEXT DEFAULT '',
                detail TEXT DEFAULT '', created_at TEXT DEFAULT (datetime('now','localtime')));
        """)


def dispatch_<domain>_rpc(method: str, p: dict):
    """统一分发：method 形如 'case.create'，前端 webRequest('<domain>.case.create', p) 入口。"""
    fn = _HANDLERS.get(method)
    if not fn:
        return {"ok": False, "error": f"未知方法 {method}"}
    try:
        return {"ok": True, "data": fn(p)}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc)}


def _case_list(p):
    with _db() as conn:
        rows = conn.execute("SELECT * FROM cases ORDER BY id DESC LIMIT 100").fetchall()
        return [dict(r) for r in rows]


def _case_create(p):
    with _db() as conn:
        cur = conn.execute("INSERT INTO cases(title, party, ...) VALUES(?,?,?)", (p.get("title"), p.get("party"), ...))
        return {"id": cur.lastrowid}


def _get_<domain>_skills(p=None):
    """能力清单：前端「团队成员」页 + Agent「能做啥」回答共用。"""
    return [{"name": "案件管理", "rpc": "<domain>.case.list", "desc": "案件建档/列表/详情"},
            {"name": "文书起草", "rpc": "<domain>.document.draft", "desc": "选模板生成初稿"},
            {"name": "合同审查", "rpc": "<domain>.contract.review", "desc": "风险点分级+意见书"},
            {"name": "法规检索", "rpc": "<domain>.search_law", "desc": "带来源检索报告"},
            {"name": "合规检查", "rpc": "<domain>.compliance.check", "desc": "对照清单出评估"}]


def _get_<domain>_team(p=None):
    return [{"name": "<角色1>", "persona": "负责…"}, {"name": "<角色2>", "persona": "负责…"}]


_HANDLERS = {
    "health": lambda p: {"status": "success", "service": "<DomainSwarm>-<domain>-platform"},
    "case.list": _case_list,
    "case.create": _case_create,
    "skills.list": _get_<domain>_skills,
    "team.list": _get_<domain>_team,
    # 继续补齐 Spec 功能清单的每个功能点…
}


class <Domain>PlatformExtension(ApplicationPluginExtension):
    """法务先例结构：RPC 注册 + REST 网关 + 领域上下文注入。"""

    def initialize(self, binding_web_channel) -> None:
        init_db()
        channel = binding_web_channel
        for sub in ("health", "case.list", "case.create", "skills.list", "team.list", "..."):
            channel.register_method(f"<domain>.{sub}", _mk(sub))

    def initialize_web(self, binding_web_channel) -> None:
        # 网关：<domain>GatewayHttpHandler 内置；路由 /api/<domain>/<resource> 转 dispatch
        binding_web_channel.http_server.register_handler("/api/<domain>/*", <Domain>GatewayHandler)

    def initialize_agent_hook(self, binding_agent_hook) -> None:
        binding_agent_hook.before_system_prompt_build.append(_make_hook())  # 领域上下文（二段式能力回答见 §7）


def _mk(sub):
    def _h(p):
        return dispatch_<domain>_rpc(sub, p or {})
    return _h


def _make_hook():
    def capture(self, params, *args, **kwargs) -> None:
        try:
            ctx = (
                "[<领域>上下文]\n当前运行于 <DomainSwarm>（<中文品牌名>）。"
                "可用领域能力：<逐条功能清单>。\n"
                "【强制·能做啥回答】用户问你能做什么时：一、平台原生能力…；二、本领域能力（逐条）…；三、引导句…。\n"
                "【强制·问候回复模板】只发问候时输出<领域>自我介绍。"
            )
            builder = ...  # 取 state/multimodal_state 的 system_prompt_builder，append_text(ctx)
        except Exception as exc:  # noqa: BLE001
            logger.warning("[<domain>_platform] hook 注入失败（降级）: %s", exc)
    return capture
```

要点：`channel.register_method(<domain>.<sub>, ...)` 的 `<sub>` 与 `<domain>Api.ts`、`dispatch_<domain>_rpc` 三者严格同名。

## 6. 前端功能模块模板（v2 必做，参考基线仓库 LegalWorkbenchPanel/legalApi.ts/legalStore.ts/frontendPlatform.ts）

### 6.1 侧栏导航 key（`src/utils/frontendPlatform.ts`）

> 导航形态硬规则：**每个 Spec 功能一个 key**，SessionSidebar 逐项挂载、App.tsx 每 key 独立渲染，
> 禁止把多个功能打包成一个工作台入口再分 tab/mode。首个 key 为可选聚合首页，非必需。

```ts
export type SidebarNavKey =
  | 'chat'                                       // ... 平台既有 key
  | '<domain>-case'                              // 每个功能一个 key（数量 = Spec 功能数）
  | '<domain>-document'
  | '<domain>-contract'
  | '<domain>-search'
  | '<domain>-compliance'
  | '<domain>-team';
  // | '<domain>-workbench'                      // 可选：仅当需要聚合首页（功能快捷卡片）时加
```

### 6.2 API 封装（`src/services/<domain>Api.ts`）

```ts
import { webRequest } from '../utils/webRequest';   // 沿用平台封装，无则按模板 store 的调用方式
export const <domain>Api = {
  caseList: ()    => webRequest('<domain>.case.list'),
  caseCreate: (p) => webRequest('<domain>.case.create', p),
  contractReview: (p) => webRequest('<domain>.contract.review', p),
  documentDraft: (p) => webRequest('<domain>.document.draft', p),
  searchLaw: (p)  => webRequest('<domain>.search_law', p),
  skillsList: ()  => webRequest('<domain>.skills.list'),
  teamList: ()    => webRequest('<domain>.team.list'),
};
```

> ⚠️ **禁止泛型调用（gov 实坑）**：`webRequest('<domain>.xxx', params)` 一律**无泛型**；
> ❌ `webRequest<T>(...)` 带 `<T>` 泛型的写法不被自检正则 `webRequest\([^)]{0,120}?['"]` 匹配
> → 判"未发现 RPC 调用"。API 层只用**无泛型直调**写法。

### 6.3 i18n（`src/i18n/locales/zh.json` 与 en.json 成对）

```jsonc
"nav": {
  "<domain>Case": "案件管理",        // 每个功能一个 key（数量 = 功能数）
  "<domain>Document": "文书起草",
  "<domain>Contract": "合同审查",
  "<domain>Search": "法规检索",
  "<domain>Compliance": "合规检查",
  "<domain>Team": "法务团队"
  // "<domain>Workbench": "工作台首页",  // 可选聚合首页时才需要
},
"welcomeHeading": "你好，我是 <中文品牌名>，很高兴认识你！",
"welcomeBubbleText": "我是<领域>智能工作台。我可以做…（逐条领域能力）。",
"welcomeSuggestions": ["<领域>任务例句1", "<领域>任务例句2", "<领域>任务例句3"]
```

### 6.4 页面组件骨架（**每功能一个独立组件** `src/components/<Domain><Feature>Panel/index.tsx`）

每个功能组件 = 表单/列表/明细 + `<domain>Api` 调用 + 落库后刷新。App.tsx 每个 nav key 独立渲染对应组件：

```tsx
case '<domain>-case':     return <Domain>CasePanel />;      // 每 key 一个独立渲染分支
case '<domain>-document': return <Domain>DocumentPanel />;
```

（可选聚合首页 `components/<Domain>WorkbenchPanel/index.tsx` 为功能快捷卡片页，仅补充入口，不替代各功能独立组件。）

### 6.5 左上角 logo

`src/public/<domain>-ai-logo.svg`；`SessionSidebar/index.tsx` 顶部 `logoIcon = '/<domain>-ai-logo.svg'`。

## 7. 「能做啥」回答模板（persona / 领域上下文追加段，v2 必做）

Agent 被问「你能做什么/能做啥」时必须**同时**给出平台能力与领域能力（禁止只讲其一）：

```markdown
当用户询问你能做什么时，请按以下固定结构回答：
一、平台原生能力：多 Agent 团队协作、上下文对话、文件与图片处理、联网检索、任务编排等（沿用平台口径）。
二、本领域能力（<DomainSwarm> 已实现）：<逐条功能清单，如案件管理/文书起草/合同审查/法规检索/合规检查/团队>。
三、引导句：例如「你可以说：审一下这份采购合同」。
```

- 数据源一致性：persona 中的能力描述 = `skills.list / team.list` RPC 返回值 = 前端「法务团队」页展示，三处同口径。