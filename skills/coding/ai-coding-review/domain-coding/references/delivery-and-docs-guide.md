# 交付物清单与验收标准

> 配套 `skills/domain-coding/SKILL.md` 与 `skills/domain-qa/SKILL.md`。定义领域化项目的交付物清单、文档范式与验收标准（QA 按此审查）。

## 一、交付物总览（MVP 版本）

| # | 交付物 | 位置 | 必/选 |
|---|--------|------|-------|
| 1 | 主 README（领域品牌） | 根 `README_CN.md`（如暂无则新建，保留英文版） | 必 |
| 2 | 领域扩展 | `extensions/<domain>_platform/`（5 文件） | 必 |
| 3 | 配置示例（领域段 + 话术） | `resources/config/config.example.yaml` | 必 |
| 4 | 领域 Agent 配置 | `resources/agent/<domain>_agent_configs/*.json` | 必 |
| 5 | 领域技能 | `resources/agent/workspace/skills/<skill>/*` | 必 |
| 6 | 团队配置 | `config.yaml` `team` 段 + `agents.*` system_prompt | 必 |
| 7 | **前端功能模块**（v2 必做）| `frontend/src/components/<Domain><Feature>Panel/`（**每功能一个独立组件，数量=功能数**；可选聚合首页 `<Domain>WorkbenchPanel/` 仅补充入口）+ `services/<domain>Api.ts` + `stores/<domain>Store.ts` + `utils/frontendPlatform.ts`（SidebarNavKey 每功能一个）| 必 |
| 8 | **品牌定制**（v2 必做）| `frontend/src/public/<domain>-ai-logo.svg`、i18n 欢迎语（`welcomeHeading/welcomeBubbleText/welcomeSuggestions`）、Agent「能做啥」=平台+领域能力 | 必 |
| 9 | 一键启动脚本 | `start-backend.bat`（Windows）、`start.sh`（macOS/Linux） | 必 |
| 10 | Docker 部署 | `Dockerfile` + `docker-compose.yml`（可选）；文档中给出手工 docker 命令 | 选 |
| 11 | 快速部署指南 | 根 `<Domain>Swarm快速部署指南.md` | 必 |
| 12 | 架构图 | 根 `<Domain>Swarm架构图.svg` | 必 |
| 13 | 经验分享 | 根 `<Domain>Swarm经验分享.md` | 必 |
| 14 | 全景流程 | 根 `<Domain>Swarm全景流程图.html`（可选） | 选 |
| 15 | 领域语料样本 | 根 `教案_*.md` 等价物（如 `法务案例_*.md`），作为领域能力输入样例 | 选 |
| 16 | 交付物清单 | PR 描述列出交付物（含 `scripts/validate_domain_project.py` 副本已就位）；运行级验收由 domain-qa 执行 | 必 |

## 二、README_CN.md 结构范式

```
# <Domain>Swarm · <中文品牌名>

> 一句话定位（谁 + 解决什么问题）。
> 支持多种部署方式（Web / Docker / 桌面端），示例见快速部署指南。

## 目录
## 产品简介（含领域能力范围表）
## 团队与分工（角色表 table：角色名 / 职责 / 对应技能）
## 领域功能模块（左侧导航页签表：页面 / 能力描述 / 后端 RPC / 数据落库，与 Spec 功能清单对照）
## 快速开始（耗时几分钟，命令可直接复制）
## 能力示例（演示场景 3 个：简单/复杂/长周期 + 页面路径）
## 部署指南入口（指向快速部署指南）
## <Domain>Swarm 二次开发说明（基于模板 + 新增内容清单 + 保留上游同步策略）
## 社区与获取帮助（可选）
## 开源协议（Apache-2.0 + 声明文件，不可删除）
```

## 三、快速部署指南结构范式

```
1. 环境要求（Python 3.11+/Node/uv 或 pip；端口清单）
2. 一键脚本部署（Windows：start-backend.bat；macOS/Linux：start.sh）
3. 手动部署（git clone → 配置数据目录 → 安装依赖 → 生成配置 → 启动服务 → 打开页面）
4. Docker 部署（docker build/run 或 compose up；端口映射表）
5. 验证清单（访问 5173、AgentServer 18092、领域网关 192xx 健康检查）
6. 常见问题（端口占用/依赖缺失/密钥配置/局域网访问）
```

## 四、架构图（SVG）内容要素

- 从左到右：用户层（Web/桌面/移动/第三方系统）→ 网关层（WebSocket 消息网关 + <domain> REST 网关）→ Agent 层（LEADER + 领域专职 Agent + 技能库）→ 领域能力层（<domain>_platform 扩展 RPC）→ 数据层（SQLite / 文件库）
- 标注链路：对话 → 领域上下文注入(hook) → LEADER 调度 → 组队/直调 → 能力落库 → 汇总交付

## 五、经验分享文档结构范式（每个领域都该沉淀）

1. 一句话方法论（本领域最核心的自研点）
2. 领域 Agent 团队设计（角色表 + 为什么这样拆）
3. 领域技能体系（技能清单 + 设计取舍）
4. 关键技术点 / 踩坑（参考 EduSwarm 的 6 条：产出入库、单发言人、一次一成员、组队决策、content 空、禁嵌套）
5. 与模板框架的协同方式（增量扩展、跟随上游、开源合规）
6. 部署与运维经验（端口/数据目录/升级）

## 六、端口规划（防冲突约定）

| 服务 | 端口 | 备注 |
|------|------|------|
| Web 前端 | 5173 | 固定 |
| AgentServer | 18092 | 固定 |
| 消息网关 | 19000-19001 | 固定 |
| Edu 领域网关（参考先例） | 19200 | 已被占用 |
| **新领域网关** | **19210+（每领域 +10）** | 法务 19210，医疗 19220，金融 19230… |

## 七、Spec 模板（Issue Agent 产出，写入 Issue body）

```markdown
## 领域画像
- 目标用户：…
- 领域任务：…
- 交付形态：…
- 验收标准：…

## 落地信息
- 产品命名：<Domain>Swarm · …
- 落地模式：B 当前仓库 develop 分支增量（默认）/ A 新仓库
- 目标仓库：<owner>/<domain>swarm
- 扩展 id：<domain>_platform；RPC 前缀 <domain>.*
- 领域网关端口：1921x

## 领域团队（角色表）
| 角色 id | 中文名 | 职责 | 不做什么 | 技能 | 能力 RPC |

## 领域技能清单
| 技能名 | 服务角色 | 依赖能力 |

## 领域功能清单（前端页签 + 后端 RPC 落库 + 任务对话可识别，四件套）
| 功能名 | 前端导航 key | 页面组件 | 后端 RPC | REST 路由 | 落库表 | **对话触发词（委派映射行）** | **对应技能 SKILL.md（含触发场景+调用 RPC）** |

## 品牌定制
- 左上角 logo：public/<domain>-ai-logo.svg
- 任务欢迎语：i18n welcomeHeading/welcomeBubbleText/welcomeSuggestions
- 「能做啥」回答：平台能力 + 领域能力（skills.list/team.list 数据驱动）

## 数据对象
| 对象 | 字段要点 | 存储位置 |

## 交付物清单（对应「一、交付物总览」编号）
## 验收标准（引用 validate_domain_project.py 校验项 + 功能模块/品牌项 + 冒烟命令）
```

## 八、验收标准（QA Agent 检查项）

1. **开源合规**：`LICENSE` 与开源声明文件存在、未被修改。
2. **框架守约**：`git diff --stat` 显示改动集中于 `extensions/<domain>_platform/`、`resources/`、`channels/web/frontend/src/` 领域模块、根目录文档/脚本；未大改 `agents/ server/ gateway/` 核心。
3. **配置可解析**：config.example.yaml YAML 合法且含 `<domain>_gateway` 段；Agent JSON 合法。
4. **技能可加载**：Agent 配置 `skills` 引用的每个 `<skill-name>` 目录存在，且 `SKILL.md` frontmatter 合法、引用 RPC 与 extension.py 注册一致。
5. **端口无冲突**：领域网关端口不在 {5173, 1793, 18092, 19000, 19001, 19200} 内。
6. **自检通过**：`python ../scripts/validate_domain_project.py <repo_path> --domain <domain>` exit 0（前端功能模块项 + 品牌项包含在内；**由 domain-qa 于验收阶段执行**）。
7. **功能模块验收（v2）**：`SidebarNavKey` 的 `<domain>*` key 数量 = Spec 功能数（**每功能一个独立入口**）；
   `SessionSidebar` 导航项与 key 一一对应；`App.tsx` 每 key 独立渲染对应独立页面组件
   （**禁止单工作台入口 + mode 参数打包多个功能**，可选聚合首页不替代独立入口）；
   每个功能「前端页签 + RPC + 落库」三件套齐备；浏览器可打开页面完成一次"增/查"并刷新存续。
8. **品牌验收（v2）**：左侧栏左上角为 `<domain>-ai-logo.svg`；i18n `welcomeHeading/welcomeBubbleText/welcomeSuggestions` 已领域化（zh+en）；Agent 被问「能做啥」的回答包含 **平台能力 + 领域能力** 两部分。
9. **冒烟验证**（**运行级验收已整体移交 domain-qa 全量执行**，见 `../../domain-qa/SKILL.md` Q2/C7：静态自检 → 后端 1 次启动 + `/health` + WS 黑盒写 RPC 抽查 → 前端编译 + 品牌清零 → 单条批量对话冒烟 → 24p/24t 全量闭环）。coding 侧只保证交付物完整与脚本静态可用。识别不到 = 技能缺触发场景/RPC 引用 或 协调技能缺委派映射行，按 REVISE 修复后交 domain-qa 复检。
10. **文档齐备**：README / 快速部署 / 架构图 / 经验分享四件套存在，端口、命名与实现一致。

## 九、验收返回格式（QA 报告）

```markdown
# QA 验收报告：<repo> / PR <#>
✅ 开源合规 / ❌ …
✅ 配置可解析 / …
✅ 技能可加载 / …
✅ 端口无冲突 / 校验项 N/M 通过
自检脚本：exit <code>（<输出摘要>）
冒烟验证：<结果/待验证说明>
遗留风险：<列表>
结论：通过 ✅ / 需返工 ❌（附问题清单）
```