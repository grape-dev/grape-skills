# 贡献指南（CONTRIBUTING）

感谢你为 **Grape Skills** 官方内容仓库贡献。本仓库维护 Grape 平台使用的两类内容：

- **技能（skills/）**：按 `agent_type / sub_scene / skill` 三层目录存放。
- **场景（scenes/）**：每个场景一个子目录，含 `scene.json` 工作流定义。

开始前请先阅读 [README](README.zh.md)，了解完整的分类体系、注册规则与场景语义。

## 快速开始

1. Fork 本仓库并创建特性分支：`feat/xxx`、`fix/xxx`、`docs/xxx`、`chore/xxx`。
2. 按照下述规则进行修改。
3. 本地验证（JSON 合法性、节点引用完整性）后，向 `main` 提交 PR。

## 新增 / 修改技能

技能存放于 `skills/<agent_type>/<sub_scene>/<skill>/`：

```
<skill>/
├── SKILL.md           # frontmatter：name / description / version
├── references/        # 可选参考资料
├── scripts/           # 可选辅助脚本
└── templates/         # 可选模板
```

- 选择正确的 `agent_type`（`vod/issue/coding/qa/sre/chat`）与 `sub_scene`；若无合适子场景，先与维护者确认再新建。
- **在 `skill-description.json` 中注册技能**，且 `path` 必须与实际三层目录一致。
- 涉及 Grape 平台交互（GitCode / Issue / 任务 / Skills / A2A）的技能**必须使用 `grape` CLI**，禁止直接 `curl` 平台 API，禁止提交 token。

## 新增 / 修改场景

- 每个场景为 `scenes/` 下一个子目录，含 `scene.json` + `README.md`。
- 工作流节点通过 `skill` 字段挂载**已注册**技能；引用未注册技能必须在**同一 PR** 内注册。
- **只改 `scenes/<场景>/scene.json`**——它是场景市场同步的唯一数据源。
- `next` 必须指向存在的节点 id，`handoff` 为合法枚举（`a2a`/`complete`），不得有悬空引用。

## 提交信息

统一使用**英文**并遵循 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/)：

```
<type>(<scope>): <short subject>
```

| type | 用途 |
|------|------|
| `feat` | 新技能 / 场景 / 功能 |
| `fix` | 缺陷修复 |
| `docs` | 文档 |
| `refactor` | 不改变行为的重构 |
| `chore` | 维护、工具链 |

## Pull Requests

- 说明改了什么、为什么、如何验证。
- 保持 PR 聚焦单一改动。
- 不得引入任何密钥或内部信息（见 [SECURITY](SECURITY.md)）。

## 版本管理

- 默认分支 `main`；
- 版本 tag 语义化（`v1.0.0`），破坏性变更升主版本号。

## 行为准则

请阅读并遵守我们的 [行为准则（CODE_OF_CONDUCT）](CODE_OF_CONDUCT.md)。