# Grape Skills

Grape 官方内容仓库，维护 Grape 的**技能**与**场景**两类内容：

- **技能（skills/）**：按 `agent_type / sub_scene / skill` 三层目录分组存放，
  供 Grape 系统在构建/部署时拉取使用（方案：构建期 clone / 卷挂载，见 grape
  仓库 `docs/new-version2/skills-standalone-repo-build-time-pull.md`）；
- **场景（scenes/）**：每个场景一个子目录，以 `scene.json` 定义工作流节点
  （挂载已注册技能），是前端场景市场的同步数据源。

## 仓库结构

```
grape-skills/
├── skill-description.json     # 官方技能注册清单（name/agent_type/sub_scene/path/description）
├── scenes/                    # 场景定义（每个场景一个子目录，含 scene.json；场景同步唯一数据源）
│   └── <scene-name>/
│       ├── scene.json         # 场景工作流节点（挂载已注册技能）
│       └── README.md
├── skills/
│   ├── <agent_type>/          # 一级：agent_type（vod/issue/coding/qa/sre/chat）
│   │   └── <sub_scene>/       # 二级：子场景（scaffolding/auto-testing/ci/...）
│   │       └── <skill>/       # 三级：技能本体
│   │           ├── SKILL.md
│   │           ├── references/   # 可选参考资料
│   │           ├── scripts/      # 可选辅助脚本
│   │           └── templates/    # 可选模板
│   └── _template/             # 技能模板（上传/创建的脚手架）
```

## 技能与场景

- **agent_type（一级）**：vod、issue、coding、qa、sre、chat。
- **sub_scene（二级）**：子场景分类，用于技能归类。
  技能必须归到某个子场景，可选子场景如下，按职责就近归类，无法归入时先
  与维护者确认是否新建子场景：

  | sub_scene | 职责范围 | 现有技能示例 |
  |---|---|---|
  | feedback-loop | 需求收集/分析/引导、Issue 全生命周期运营 | vod、issue-advance、skill-issue |
  | ai-coding-review | AI 辅助代码实现与 PR 创建 | implementation、iac-coding |
  | scaffolding | 技能脚手架/生成器 | skill-creator、common-skill-creator |
  | code-quality | 代码/PR 质量审查 | pr、qa、impact-analysis、skill-pr |
  | auto-testing | 自动化测试验证 | skill-tester、common-skill-tester |
  | app-release | 构建部署/发布运维/发布相关生成 | cloud-deploy、skill-publish、ai-blog-generation |
  | ci | 构建调试 | build-debug |
  | observability | 可观测性/事件分诊 | incident-triage |
  | container-deploy | 容器运行时安装 | runtime-install |
  | log-diagnostics | 日志诊断 | os-disk-list |
  | im | IM 对话/通知 | chat、im-notify |
  | meeting | 会议相关 | （暂无，待新增） |
  | other | 其他 | （暂无，待新增） |
  | code-hosting | 代码托管 | （暂无，待新增） |
  | browser-verify | 浏览器验证 | （暂无，待新增） |

  > 表格含当前全部子场景；标注「待新增」的子场景尚无技能归入，为其新增的
  > 第一个技能即在该子场景下按三层目录放置即可。

- **技能注册**：每个技能必须注册到 `skill-description.json`，字段如下，
  且 `path` 必须与三层目录一致（`<agent_type>/<sub_scene>/<skill>`）：

  ```json
  {
    "<skill-name>": {
      "name": "技能显示名",
      "agent_type": "coding",
      "sub_scene": "scaffolding",
      "path": "coding/scaffolding/<skill-name>",
      "description": "一句话说明该技能的职责与调用方式"
    }
  }
  ```

- **场景（scenes/）**：场景定义工作流节点，节点通过 `skill` 字段挂载
  技能。**场景同步只认 `scenes/<场景>/scene.json`**（实时同步通道，
  前端场景市场的唯一数据源）；场景可引用已注册技能，若引用未注册技能，
  必须将技能一同注册并在同一个 PR 中同步上线（即"注册与引用同 PR 上线"）。

## 技能格式

每个技能是一个独立目录，含 `SKILL.md`（frontmatter 含 `name`/`description`/`version`
等元信息），以及可选的 `references/`、`scripts/`、`templates/`：

```
skills/<agent_type>/<sub_scene>/<skill>/
├── SKILL.md
├── references/        # 可选的参考资料
├── scripts/           # 可选的辅助脚本
└── templates/         # 可选的模板
```

新增技能时：在对应 `<agent_type>/<sub_scene>` 下建目录，并同步更新
`skill-description.json`（path = `<agent_type>/<sub_scene>/<skill>`，
详见「技能与场景」的**技能注册**）。

## 技能清单

| agent_type | 技能 |
|---|---|
| vod | vod、vod-cli、vod-strict、repo-onboarding、event-dialogue、blog-vod、iac-vod |
| issue | issue、issue-advance、issue-multitask、issue-cli、skill-issue、blog-issue、iac-issue |
| coding | implementation、coding-cli、skill-creator、common-skill-creator、rest-api-skill-creator、iac-coding、wan-video-generation、qwen-image-generation、ai-blog-generation |
| qa | qa、qa-cli、impact-analysis、pr、skill-pr、skill-tester、common-skill-tester、rest-api-skill-tester、iac-qa |
| sre | cloud-deploy、deploy-cli、devbridge-deploy、build-debug、deploy-guard、changelog-gen、incident-triage、skill-publish、huawei-cloud、runtime-install、blog-publish、blog-manager、iac-sre、os-disk-list |
| chat | chat、chat-cli、im-notify |

> 完整字段（name/agent_type/sub_scene/path/description）以 `skill-description.json` 为准。

## 交互方式规范（grape CLI）

涉及 Grape 平台交互（GitCode 仓库 / Issue / 任务 / Skills / A2A 等）的技能，
**必须通过 `grape` CLI 交互**，禁止 `curl` 直连 API：

- 平台交互一律走 `grape <group> <verb> [--参数]`，命令以 `grape commands`
  实际输出为准，不确定先 `grape <group> --help` / `grape <group> <verb> --help` 发现；
- token 由 CLI 自动注入（`GRAPE_SESSION_TOKEN` / `GRAPE_API_TOKEN` /
  `~/.grape/config.json`），**不进命令行、不落盘、不写进文件/日志/评论**；
- 平台 git 操作用 `grape git`（凭据经 `GIT_CONFIG` 进程内注入，零暴露）；
- `grape-cli-guidance` 为 CLI 使用指南技能（命令发现 / token 作用域 / 常见配方 /
  错误排查），可参考；命令树以服务端契约为准。

**不需要与 grape 对话的 skill**（纯本地工具、对接第三方平台/服务的技能），
直接按自身工具或第三方接口执行即可，不要求经 grape CLI。

### grape CLI 安装（本地 agent）

```bash
pip install git+https://gitcode.com/grape-dev/grape-cli.git
grape --version
# 详细用法见 https://gitcode.com/grape-dev/grape-cli
```

## Skill 检测

纳入本仓的每个技能必须通过 **Skill 检测**（Lint 规范检查 + 功能测试 + 安全审计），
**贡献者须在本地 agent 安装检测技能后自行检测**，提交 PR 时**必须附上 skill
检测报告**，是否合入由维护者结合报告人工判断。

- Lint 规范检查：SKILL.md frontmatter/文件结构是否符合技能规范。
- 功能测试：运行技能验证其功能正确性。
- 安全审计：恶意代码/密钥泄露/CWE 漏洞扫描。

Critical/P0/CRITICAL 级别问题一票否决（不得合入）；无否决项时按技能自身检测
结果展示，合入由维护者人工判断。

### 检测技能安装（本地 agent）

检测由 **`common-skill-tester`** 一个技能完成（覆盖 Lint 规范检查 / 功能测试 /
安全审计），只需安装这一个。官方发布在
`developer-skill/skills-group-contribution` 仓库（`members-contribution` 分支）。
在本地 agent 机器上执行：

```bash
# 1) 克隆官方技能工具仓
git clone --depth 1 -b members-contribution \
    https://gitcode.com/developer-skill/skills-group-contribution.git

# 2) 安装检测技能（opencode 会自动扫描 ~/.agents/skills）
cp -r skills-group-contribution/skills/common-skill-tester ~/.agents/skills/common-skill-tester
```

### 自测与报告

在本地 agent 对话中触发检测：

```
用 common-skill-tester 检查+测试+审计 <本技能目录绝对路径>
```

执行后会在被测技能父目录生成组合报告文件
`{skill-name}-tester-report-{YYYYMMDD-HHmmss}.md`
（含 Lint / Test / Audit 三章子报告 + 综合判定）。

**提交 PR 时必须将检测报告（内容或文件）一并附上**，供仓库运营方判断是否合入。

## 场景检测

新增/修改场景（`scenes/`）同样纳入检测范围，提交 PR 时须满足：

- **结构合规**：每个场景一个子目录，含 `scene.json` + `README.md`；`scene.json`
  字段（name/version/display_name/description/category/nodes/onboarding 等）完整合法；
- **技能挂载**：nodes 节点中 `skill` 及 `onboarding` 引用的技能**必须已注册**
  （参考 `skill-description.json`）；引用未注册技能时必须连同注册同 PR 上线；
- **同步数据源正确**：场景同步只认 `scenes/<场景>/scene.json`，改场景只改该文件；
- **节点链路**：`next` 指向存在的节点 id，`handoff` 取值为合法枚举（a2a/complete 等），
  无悬空引用。

场景检测结果随 PR 一并展示（可复用本地 agent 校验场景结构或人工核对），由仓库运营方
参考上述检查项判断是否合入。

## 提交 PR 流程

1. 新增/修改技能 → 按三层目录规划位置（`<agent_type>/<sub_scene>/<skill>`）。
2. 新增技能 → 同步在 `skill-description.json` 注册该技能。
3. 平台交互类技能 → 交互必须满足「交互方式规范（grape CLI）」。
4. 新增/修改场景 → 挂载已注册技能；引用未注册技能则连同注册一起提交
   （见「场景检测」）。注意：场景同步只认 `scenes/<场景>/scene.json`。
5. 本地安装检测技能并自测（见「Skill 检测」），生成检测报告。
6. 提交 PR → **附上 skill 检测报告 + 场景检测自查结果** → 维护者结合报告
   人工判断是否合入。

## 版本管理

- `main` 为默认分支；
- 版本 tag 语义化（如 `v1.0.0`）；向后不兼容变更升主版本号，Grape 发布物锁定
  `tag` 或 `commit`。

## 运行时目录说明

`skills/custom/`（用户上传技能）与 `skills/repo/`（仓库技能）是 Grape 运行时
动态产生的目录，**不属于本仓库**，勿提交。

## 使用

本仓库不直接运行；由 Grape 系统在构建/部署时拉取并铺入其部署根 `skills/`：

```bash
# 预览
git clone https://gitcode.com/grape-dev/grape-skills.git
# 部署侧（Grape 维护的 sync 脚本）
# git clone --depth 1 --branch <SKILLS_REF> <SKILLS_REPO> <stage>
# cp -a <stage>/skills/<agent> <deploy-root>/skills/<agent>