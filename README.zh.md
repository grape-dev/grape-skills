<h1 align="center">Grape Skills</h1>

<p align="center"><a href="README.md">English</a> | 中文</p>

<p align="center">Grape 官方技能仓库</p>

<p align="center">
  <a href="#简介">简介</a> ·
  <a href="#仓库结构">仓库结构</a> ·
  <a href="#技能">技能</a> ·
  <a href="#场景">场景</a> ·
  <a href="#交互规范grape-cli">交互规范（grape CLI）</a> ·
  <a href="#贡献">贡献</a>
</p>

---

## 简介

Grape Skills 围绕 DevOps 的全生命周期，为 Agent 提供各类最佳场景的实践。在 AI Native 的 DevOps 下，这些实践包含了个人与 Agent、组织与 Agent 之间的运行规则和方法论，让 AI Native 的最佳实践可以更方便地应用到各种项目中去。

Grape Skills 是 Grape 的官方技能仓库，维护两类由 Grape 平台在构建/部署时拉取的内容：

- **技能（skills/）**：按 `agent_type / sub_scene / skill` 三层目录存放，构建期通过 clone / 卷挂载拉取。
- **场景（scenes/）**：每个场景一个子目录，`scene.json` 定义工作流（挂载已注册技能），是同步到前端场景市场的**唯一数据源**。

## 仓库结构

```
grape-skills/
├── skill-description.json   # 技能注册清单（key → name/agent_type/sub_scene/path/description）
├── pipelines.json           # 历史遗留场景快照——请勿改动
├── scenes/<scene>/          # 场景定义（场景同步唯一数据源）
│   ├── scene.json           # 工作流节点（挂载已注册技能）
│   └── README.md
└── skills/
    ├── <agent_type>/        # vod | issue | coding | qa | sre | chat
    │   └── <sub_scene>/     # 如 feedback-loop / scaffolding / auto-testing
    │       └── <skill>/     # SKILL.md + 可选 references/ | scripts/ | templates/
    └── _template/           # 新技能脚手架模板
```

## 技能

### 技能格式

每个技能是一个独立目录，含 `SKILL.md`（frontmatter：`name` / `description` / `version`）及可选的 `references/`、`scripts/`、`templates/`。

### 技能分类

`agent_type` 为 `vod | issue | coding | qa | sre | chat` 之一，各对应开发工作流中的
一个环节：声音收集 → 需求 → 实现 → 审查 → 部署运维：

| agent_type | 主要职责 |
|---|---|
| vod | 收集开发者反馈、聚类共性、引导并创建 Issue |
| issue | Issue 全生命周期运营（分类、标签、指派、触发开发） |
| coding | AI 代码实现、PR 创建、发布内容生成 |
| qa | PR 审查、自动化测试、安全扫描 |
| sre | 构建部署、发布管理、运维诊断 |
| chat | IM 对话 / 通知 |

技能再按 `sub_scene` 二级归类：

| sub_scene | 职责范围 | agent_type |
|---|---|---|
| feedback-loop | 需求收集/引导、Issue 运营 | vod、issue |
| ai-coding-review | AI 代码实现与 PR 创建 | coding |
| scaffolding | 技能脚手架/生成器 | coding |
| app-release | 构建部署/发布/内容生成 | coding、sre |
| code-quality | 代码/PR 质量审查 | qa |
| auto-testing | 自动化测试验证 | qa |
| ci | 构建调试 | sre |
| observability | 可观测性/事件分诊 | sre |
| container-deploy | 容器运行时安装 | sre |
| log-diagnostics | 日志诊断 | sre |
| im | IM 对话/通知 | chat |
| meeting / other / code-hosting / browser-verify | 预留（暂无技能） | — |

> 标记「预留」的子场景为受 git 跟踪的空占位目录，为该子场景新增的第一个技能直接放入即可。

### 技能注册

每个技能**必须**注册到 `skill-description.json`，且 `path` 与三层目录一致：

```json
{
  "<skill-name>": {
    "name": "技能显示名",
    "agent_type": "coding",
    "sub_scene": "scaffolding",
    "path": "coding/scaffolding/<skill-name>",
    "description": "一句话说明职责与调用方式"
  }
}
```

> 已注册技能的完整列表（name/agent_type/sub_scene/path/description）以 `skill-description.json` 为准，不在此处维护。

## 场景

- 场景同步**只认** `scenes/<场景>/scene.json`（唯一数据源；`pipelines.json` 为历史遗留）。
- 工作流节点通过 `skill` 字段挂载已注册技能。
- 引用未注册技能，必须**同 PR 注册**（「注册与引用同 PR 上线」）。

## 交互规范（grape CLI）

涉及 Grape 平台交互（GitCode / Issue / 任务 / Skills / A2A）的技能**必须通过 `grape` CLI**，禁止 `curl` 直连 API：

- 一律走 `grape <group> <verb> [--参数]`；命令以 `grape commands`、`grape <group> --help` 为准。
- token 由 CLI 自动注入——不进命令行、不落盘、不写入文件/日志/评论。
- 平台 git 操作用 `grape git`（凭据经 `GIT_CONFIG` 进程内注入，零暴露）。
- 使用配方可参考 `grape-cli-guidance`；纯本地/对接第三方服务的技能不受此限。

本地 agent 安装：

```bash
pip install git+https://gitcode.com/grape-dev/grape-cli.git
```

## 贡献

1. 为新增/修改技能规划三层目录（`<agent_type>/<sub_scene>/<skill>`）。
2. 新增技能 → 在 `skill-description.json` 注册。
3. 平台交互类技能 → 遵循「交互规范（grape CLI）」。
4. 新增/修改场景 → 挂载已注册技能（引用未注册则同 PR 注册）。
5. 提交 PR → 维护者审核合入。

## 版本管理

- 默认分支 `main`；
- 版本 tag 语义化（如 `v1.0.0`），破坏性变更升主版本；Grape 发布物锁定 `tag` 或 `commit`。

## 使用

Grape 系统会定期同步该仓库的技能，开发者在 Grape 通过选择对应的场景和技能到项目的场景中便可运行。