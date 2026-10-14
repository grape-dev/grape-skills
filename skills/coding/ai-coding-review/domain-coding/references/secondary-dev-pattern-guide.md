# 参考项目二次开发模式剖析（EduSwarm）

> 配套 `skills/domain-issue/SKILL.md` 与 `skills/domain-coding/SKILL.md`。EduSwarm（AI 智慧课堂工作台）是「在 JiuwenSwarm 模板上做教育领域化」的成熟范本，本指南逐层拆解它做了什么、为什么这样做，形成可复制的差异点清单。

## 一、EduSwarm 是什么

基于 JiuwenSwarm 框架构建的 AI 教师团队协作平台：把备课、上课、作业、批改、学情等教学环节交给多位专职 AI Agent（课件师、出题官、批改师、学情分析师等）协作完成。教师从「亲力亲为」变成「做决策」。

产品形态：品牌独立（EduSwarm）、定位清晰（AI智慧课堂工作台）、领域纵深（教学闭环）、可部署（Web/Docker/桌面端）。

## 二、它与模板项目的差异（diff-jiuwenswarm-to-eduswarm）

### 2.1 层—1：包与品牌

| 项 | 模板 | EduSwarm | 说明 |
|----|------|----------|------|
| pyproject 包名 | `workswarm`（模板） / `jiuwenswarm` | `jiuwenswarm`（保留框架包名，name 字段保持平台侧） | edu 用 `jiuwenswarm`，领域化的最小改动是改 description/README，不强制改包名（包名改动影响安装与导入路径，风险高） |
| 项目 README | 框架通用 | `EduSwarm · AI智慧课堂工作台` + 领域能力表/团队表/部署 | README 是项目的脸，必改 |

> 经验：**包名尽量不动**，用"保留框架包名 + 文档/Script/前端品牌独立"实现品牌区隔，风险最低。

### 2.2 层—2：新增 openjiuwen_src（框架源码 vendor）

```
openjiuwen_src/   # openjiuwen 框架源码（多智能体运行时 / SDK），6356 文件
```
- 目的：让仓库自包含、可离线安装（`uv pip install -e ./openjiuwen_src`，不那么依赖 git+ 远程 sha）。
- 模板中 openjiuwen 以 `git+https://...agent-core.git@<sha>` 依赖引入。
- 领域化建议：**拷贝工具能拿到源码时做 vendor**，拿不到就保留原依赖方式（在 README 写明），不要强行内嵌。

### 2.3 层—3：领域扩展（核心差异）

| 模板 | EduSwarm | 差异本质 |
|------|----------|---------|
| `extensions/` 仅基础扩展（agentos/sdk/agent_client） | 新增 `extensions/edu_platform/`（5 文件：extension.yaml/extension.py/edu_backend.py/edu_gateway.py/edu_gateway_tool.py） | 领域能力统一走扩展层 |
| 无教育 RPC | 注册 **109 个 `edu.*` RPC**（备课/出题/批改/学情/课堂/课件/班级/学生/统计…） | RPC 命名空间 `<domain>.` |
| 无领域 REST | 独立 `edu_gateway.py`：`/api/edu/*`，端口 19200，Key 鉴权（X-EduSwarm-Key），CORS | 第三方系统可调 Agent 能力 |
| 无领域上下文注入 | `before_system_prompt_build` hook 注入 `[教学上下文]`（角色/能力/示例话术/问候模板） | 每个 Agent 感知领域职责 |
| backend 体量 | `edu_backend.py` ≈ 1.1MB 单文件纯标准库 | 领域逻辑用标准库单文件即可起步 |

### 2.4 层—4：领域 Agent 团队

| 项 | EduSwarm | 说明 |
|----|----------|------|
| Agent 配置目录 | `resources/agent/edu_agent_configs/*.json`（9 个：leader/lecturer/quiz_maker/grader/tutor/analyst/courseware_maker/discussion_guide/kg_builder…） | 一个角色一个 JSON |
| 字段 | `id/agent_id/name/persona/skills/knowledge_base/source/max_iterations/model` | persona 写清「职责+不做什么+调用哪些能力+交付规范」 |
| 团队体系 | LEADER 教研组长 + 8 专职 + 1 待开发（知识图谱师不进团队） | 「拆角色→定流程→配信号」三步法 |
| 技能挂载 | `skills: ["lesson-planner","courseware-maker","quiz-generator",...]` | 指到 workspace/skills 下目录 |
| 模型 | `model_source: default` 跟随平台主模型，可单独覆盖 | 避免每个 Agent 各自配 key |

### 2.5 层—5：领域技能库

```
resources/agent/workspace/skills/
├── lesson-planner/  courseware-maker/  quiz-generator/  homework-assigner/
├── grading-assistant/  analyst-diagnosis/  peer-discussion/  tutor-agent/
├── eduswarm-leader-orchestrator/  learning-path/  exercise-recommend/
└── 内置 17 个教学 Skill + 教育市场（Hermes 中文教育库 170+）
```
每个技能目录 `SKILL.md + README.md + references/ + scripts/ + assets/`，与 vod 技能同构。Edu Skill Hub 通过 `edu.skill.market.index/import` RPC 提供市场安装能力（首次克隆 Hermes 教育库、增量更新）。

### 2.6 层—6：配置与团队定义

- `config.yaml` 增加 `edu_gateway` 段：`enabled/host/port(19200)/frontend_url/backend_url/api_key/cors_origins/ws_url/notify/jwt/cron`。
- `agents.agent_leader.system_prompt` → 教研组长话术；`agent_teammate` → 教学团队成员话术。
- `team` 段定义 8 个成员：`member_name/name/desc/prompt`，prompt 含「调用 edu_gateway_call 调能力 + 完成后返回 CONTROL_RETURN + 产出ID」。

### 2.7 层—7：前端定制

- 教师端/学生端双视角（学生凭课堂码加入）。
- `features/eduTour` 引导、侧边栏导航顺序（`edu.sidebar.nav_order` RPC 持久化）。
- 品牌 logo/文案、启动页 `desktop_splash.html`。
- 消息流不塞本地合成 UI（前端渲染派生代替），仅记一条：**前端定制的原则是"复用模板 + 领域增量"**，不要重写。

### 2.8 层—8：部署与文档

| 模板 | EduSwarm 新增 | 说明 |
|------|--------------|------|
| deploy/ docker/ | `start-backend.bat / start.sh`（依赖自检+国内镜像+.venv+自动开浏览器） | 一键启动 |
| — | `install-desktop.bat / uninstall-desktop.bat / desktop_app.py / desktop_splash.html` | 桌面端（仅 Windows） |
| — | `Dockerfile / docker-compose.yml`（镜像 `swr.../eduswarm:latest`，端口 5173/18092/19000/19001/19200） | 云部署 |
| — | `requirements-offline.txt` + `offline_wheels/` | 离线安装 |
| docs/ | `EduSwarm快速部署指南.md`、`EduSwarm架构图.svg`、`EduSwarm经验分享.md`、`EduSwarm全景流程图.html` | 领域文档 |
| — | `教案_*.md` 示例（4 份，作为课件生成的输入样例） | 领域语料 |

## 三、可复制的「差异点清单」（领域化必改/可选矩阵）

| 改动点 | 必改 | 可选 | 改动对象 |
|--------|:---:|:---:|---------|
| README / 品牌 | ✅ | | 根目录 README_CN.md |
| 领域扩展（RPC+hook+网关） | ✅ | | `extensions/<domain>_platform/` |
| config 领域段 + Agent/团队话术 | ✅ | | `resources/config/config.example.yaml` |
| Agent 配置 | ✅ | | `resources/agent/<domain>_agent_configs/` |
| 领域技能 | ✅ | | `resources/agent/workspace/skills/` |
| 启动/部署脚本 | ✅ | | `start-backend.bat` 等 |
| 领域文档/经验分享 | ✅ | | 根目录 `*.md / *.svg` |
| 前端领域页面/引导 | | ✅ | `channels/web/frontend/src/features/` |
| openjiuwen_src vendor | | ✅ | `openjiuwen_src/` |
| 桌面端 | | ✅ | `install-desktop.bat` 等 |
| 离线包 | | ✅ | `offline_wheels/` |

## 四、从 EduSwarm 提炼的「领域化工作流角色」参考模板

| 域样板角色 | 对应 EduSwarm 角色 | 生产步骤 |
|-----------|-------------------|----------|
| LEADER 调度 | 教研组长 | 理解需求→判断复杂度→组队/直调→汇总审核 |
| 主生产 Agent | 课件师/出题官 | 针对用户主任务链的单步骤专业 Agent |
| 质检 Agent | 批改师 | 对生产结果做校验/评分/报告 |
| 分析 Agent | 学情分析师 | 对过程数据做分析，回流指导下一轮 |
| 答疑/客服 Agent | 答疑教师/辅导员 | 面向终端用户的一对一交互 |

## 五、关键教训（写进任何领域项目的经验分享文档）

1. **产出必须落地**：Agent 交付 = 平台里的产出（ID + 路径），禁止只输出文本。
2. **单发言人**：只有 LEADER 对用户说话，成员只向组长汇报。
3. **一次一个成员 + 结构化信号**（CONTROL_RETURN），不并发插话。
4. **该不该组队是 LEADER 的核心智能**：简单任务直调、复杂任务组队，避免形式主义。
5. **reasoning 模型 content 为空的坑**：内容生成类任务关闭思考或加大 max_tokens，永远把“content 为空”当异常重试。
6. **禁止嵌套组队**。

> 详见 EduSwarm 经验分享（项目根目录 `EduSwarm经验分享.md`），领域化时应为每个领域沉淀类似的经验文档。