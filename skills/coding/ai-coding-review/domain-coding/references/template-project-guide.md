# 模板项目结构解析（JiuwenSwarm / WorkSwarm）

> 配套 `skills/domain-coding/SKILL.md` 与 `skills/domain-issue/SKILL.md`。本指南讲清模板项目的目录、运行方式与「可定制点」，是领域化改造的地图。

## 一、项目定位

JiuwenSwarm（`workswarm` 包名）是一个通用多智能体协作平台，关键能力：
- 多 Agent 协作：Leader 自动拆解任务、组建团队，Agent 专业分工
- Skill 自演进 / Skill Hub：能力资产以 SKILL.md 组织，可安装/搜索/组合
- Swarmflow / Auto Harness：确定性编排与评测驱动优化
- 多端接入：Web / 飞书 / 钉钉 / 微信等渠道网关
- 扩展机制：`extensions/` 支持以插件方式挂载领域能力

二次开发无需理解全部内部实现，只需掌握「定位入口 → 加扩展 → 配领域资产」三条主线。

## 二、顶层目录全景

```
<template>/
├── pyproject.toml                 # 包定义：name/version/scripts/package-data（领域化必改 #1）
├── jiuwenswarm/                   # 主平台包
│   ├── start_services.py          # 一键启动全部服务
│   ├── init_workspace.py          # 首次初始化（JIUWENSWARM_DATA_DIR）
│   ├── app.py / debug_launcher.py
│   ├── agents/                    # 多智能体运行时：harness/ + swarm/
│   ├── channels/                  # 渠道：web/frontend（React+Vite）、feishu、telegram、discord 等
│   ├── extensions/                # ★ 扩展层：领域化改造的主战场（见三）
│   ├── gateway/                   # 消息网关（WebSocket）
│   ├── server/                    # AgentServer（18092）
│   ├── symphony/                  # Swarmflow 自动编排
│   ├── resources/                 # ★ 运行时资源：config + agent 配置 + 技能
│   │   ├── config/config.example.yaml   # 配置模板（入库），config.yaml（本地，不入库）
│   │   ├── config/config.yaml           # 实际配置
│   │   └── agent/
│   │       ├── <domain>_agent_configs/  # ★ 领域 Agent 配置 JSON（可选）
│   │       └── workspace/skills/        # ★ 技能库：<skill-name>/SKILL.md
│   ├── cli/  common/  runtime/  acp/  instance_manager/  observability/
│   └── package.json / package-lock.json
├── jiuwenbox/                     # 沙箱执行环境（Python 子包 jiuwenbox）
├── docs/                          # 框架文档（zh/en + assets 配图）
├── scripts/  packages/  deploy/  docker/  tests/
├── LICENSE                        # Apache-2.0，二次开发必须保留
├── OPEN_SOURCE_SOFTWARE_NOTICE.md # 开源声明
└── README_CN.md / README.md
```

## 三、扩展机制（最关键的可定制点）

扩展是领域化改造的核心载体。参考 `jiuwenswarm/extensions/edu_platform/`：

```
extensions/<domain>_platform/
├── extension.yaml        # 声明：id / name / version / description / author / min_jiuwenswarm_version
├── extension.py          # 入口：register_extensions(registry) 注册 RPC + hook + 启动网关
├── <domain>_backend.py   # 领域业务逻辑（纯标准库/轻依赖），被 RPC handler 调用
├── <domain>_gateway.py   # 可选：领域 REST 网关（http.server 独立端口）
└── <domain>_gateway_tool.py  # 可选：给 Agent 用的「网关调用」工具
```

加载方式：扩展目录必须含 `extension.yaml`；`extension.py` 暴露 `register_extensions(registry, *args)`。
`registry` 提供：
- `registry.register_rpc_handler("domain.xxx.yyy", handler)` —— 注册 RPC，前端/Agent 通过 WebSocket 协议调用
- `registry.register("before_system_prompt_build", hook, priority=50)` —— 系统提示词构建前注入领域上下文
- 注意：registry **不提供原生 HTTP 路由注册**，需要 REST 接口时用独立 `http.server` 网关（见 extension-implementation-guide.md）

## 四、配置体系

- `resources/config/config.yaml`：实际运行配置（`config.yaml` 在 .gitignore，禁止提交）；`config.example.yaml` 是可入库模板。
- 领域化必看的配置段：
  | 配置段 | 作用 | 领域化动作 |
  |--------|------|-----------|
  | `agents.agent_leader.system_prompt` | 集群模式 LEADER 提示词 | 改写为领域话术（角色/能力/示例话术） |
  | `agents.agent_teammate.system_prompt` | 团队成员提示词 | 改写为领域协作话术 |
  | `agents.<role>.skills` | 成员技能挂载（MEMBER_SKILL_TOOLKIT） | 挂载领域技能 |
  | `team` | 组队成员定义（member_name/name/desc/prompt） | 改写为领域团队 |
  | `<domain>_gateway` | 领域 REST 网关配置（host/port/api_key/ws_url） | 新增 |
  | `port / port_xxx` 相关 | 各服务端口 | 规划端口不冲突 |

## 五、技能体系（领域资产的另一主阵地）

技能目录惯例：`resources/agent/workspace/skills/<skill-name>/`，每个技能目录包含：
```
<skill-name>/
├── SKILL.md        # 主定义：frontmatter(name/description/steps) + 指令内容
├── README.md       # 技能说明
├── references/     # 参考文档
├── scripts/        # 可执行脚本
├── assets/         # 静态资源
└── resources/      # 模板/素材
```

技能来源：内置技能、Edu Skill Hub 类市场、二次开发自建。领域化时新增技能放在同一目录，命名用小写连字符。

## 六、运行方式（用于本地/CI 自检）

```bash
# 数据目录必须指向仓库资源，避免落到 ~/.jiuwenswarm
export JIUWENSWARM_DATA_DIR=/path/to/<domain>swarm/jiuwenswarm/resources
# 生成配置
cp jiuwenswarm/resources/config/config.example.yaml jiuwenswarm/resources/config/config.yaml
# 安装依赖（框架已 vendor 在 openjiuwen_src 时用 -e ./openjiuwen_src）
uv pip install -e .
# 启动全部服务
python -m jiuwenswarm.start_services
```

端口惯例：5173 Web / 18092 AgentServer / 19000-19001 Gateway / 19200（edu REST 网关）。领域网关用偏移端口避免跨域实例冲突。

## 七、常见误区

1. **误把 webpack/node_modules 当业务代码**：`channels/web/frontend/node_modules` 不应改动/入库。
2. **直接改框架核心**导致无法跟随上游：领域能力一律走 `extensions/`，不要改 `agents/ server/ gateway/` 核心流程。
3. **忘记保留开源声明**：删除 LICENSE 会导致合规问题，二次开发明确禁止。
4. **把运行时数据当配置提交**：`config.yaml`、`skills_state.json`、`projects.json.lock` 等运行时产物不提交。