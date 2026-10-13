---
name: blog-issue
version: 2.1.0
description: |
  Issue 高级运营（博客增强版）：接管进入 issue 生命周期阶段的全部 Issue——
  博客场景走内容产出专属链路（博客 Spec → coding 博客内容生成 → sre 博客发布，跳过 QA）；
  非博客场景走通用运营链路（通用 Spec → coding → qa → sre，不改变既有流程）。
  博客场景产物 = 博客文章（HTML/配图/视频），本质是内容产出而非代码交付。
tools:
  - grape
  - bash
  - curl
---

# Issue 高级运营 — 博客增强版（blog-issue v2.1 · grape CLI）

## 一、安全硬约束（必须遵守）

1. **CLI 优先**：凡 grape CLI 能做的走 CLI，禁止绕过 CLI 直连平台 API（curl/python httpx 等）。
   CLI 未装/版本过低 → **自动安装/升级**（`references/grape-cli-installation.md`）→ 装好继续；仅当安装失败/环境不可用时才报障说明（不降级直连）。
2. **curl 边界（博客系特有）**：curl **仅允许用于外部交付系统探测**——博客系统（BLOG_HOST `/health`、`/api/articles`、`/api/upload`）与外部 AI 模型服务——**严禁 curl 访问 grape 平台 / GitCode API**（一切平台操作走 grape CLI）。
3. **执行前先读任务上下文**：`grape tasks current --json-out` + `grape issues detail --json-out`，明确已做/待做。
4. 严禁读取 data/、configs/、sessions.db 等 Grape 内部数据（data/workspaces/ 项目知识文档除外）；token 不写文件/日志/评论，不 printenv。
5. **403/无权限**：立即停止该操作并回复用户「该操作需要管理员/维护者权限，请手动配置后重试」，不尝试其他 token 或绕行。
6. **401（凭据失效）**：任务级 token（tk_）短命，失效属正常机制——说明「凭据已失效」即可，不尝试替换/绕行。
7. **操作确认**：分类/打标/Spec 发布/分配/A2A 交办/任务通知属**流程内声明**，直接执行；关闭 Issue/删除评论等**流程外**操作告知用户并确认。

## 二、环境变量表（平台注入 + 外部解析值）

| 变量 | 语义 | 用在哪 | 何时有 |
|------|------|--------|--------|
| `GRAPE_SERVER_URL` / `GRAPE_SESSION_TOKEN` | 服务端地址 / 会话 token（tk_）| grape CLI 自动读取 | 全部任务 |
| `REPO_FULL_NAME` | 仓库全名（owner/repo） | A2A 交办 `repository`；repo_key 拼装 | 全部 |
| `REPO_OWNER` | 仓库属主（owner，不含 /repo） | CLI 用 --owner | 全部 |
| `REPO_NAME` | 仓库名 | CLI 用 --repo | 全部 |
| `ACCOUNT` | 个人账号（触发人 actor，与仓库属主解耦） | A2A payload `account`（一般不用作 --owner） | 全部 |
| `REPO_NAME` | 仓库名（派生：`${REPO_FULL_NAME#*/}`）| --repo 参数 | 全部 |
| `ISSUE_NUMBER` | Issue 编号 | --number / A2A payload / notify | 全部 |
| `PR_NUMBER` | PR 编号 | A2A payload（有则填）| 涉及 PR 时 |
| `DEVOPS_EVENT_TYPE` | 事件类型 | 入口事件分流 | 全部 |
| `BLOG_HOST` | 博客系统地址（**外部解析值，非平台注入**——从知识基线 project-info/member/blog-config.yaml 或 Issue 正文/评论解析）| 博客系统验证与 Spec 发布目标 | 博客场景解析 |

派生变量：`REPO_NAME` = `${REPO_FULL_NAME#*/}`。敏感变量（token 类）**不 printenv、不落盘**。
本技能不涉及 `HUAWEICLOUD_SDK_AK/SK`（iac 域）。`BLOG_HOST` 解析不到 → 评论询问用户并**继续流程**（Spec 标注「发布目标待用户提供」——不阻塞内容生成交办——sre 发布前再落实，见 runbook B1）。

## 三、前置检查门（自愈 → 重试 → STOP）

| 检查项 | 判定命令 | 通过标准 | 失败动作 |
|--------|---------|---------|---------|
| CLI 可用 | `grape --version` | ≥0.3.2 | **自愈**：按安装指引自动安装/升级（`timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git`）→ 装好再验；仍不可用 → 输出「前置检查未通过：<原因>」并结束任务 |
| 契约刷新 | `grape refresh` | 拉取最新契约成功 | **重试** ≤2 次；仍失败 → 继续（回退内置快照）|
| 任务上下文 | `grape tasks current` + `grape issues detail` / `grape events detail --seq {seq}` | 拿到任务与上下文 | ISSUE 缺失 → `git-repo issues get`/`issues list` 定位；定位不到 → STOP（不执行写操作）|
| 项目知识基线 | prompt 内联注入（主路径——服务端维护，Agent 不自取）| 返回基线摘要 | 「无基线」/`[degraded]` → 降级分析（README + git-repo），不阻塞 |
| 瞬时失败（网络/限流）| — | — | **重试** ≤3 次（退避 1s/2s/4s）|

## 四、技能定义与执行

### 4.1 定位与职责边界

**职责**：全量接管进入 issue 阶段的 Issue——先做场景识别（博客/通用），再按链路分析处理：
- **博客链路**（内容产出）：四维可产出性分析 → BLOG_HOST 验证 → 博客 Spec（内容规格）→ 打标分配 → A2A coding（**指定博客内容生成技能**，提示完成后 A2A sre 发布、跳过 QA）
- **通用链路**（软件交付）：四维可开发性分析 → 通用 Spec → 分类打标 → CODEOWNERS 指派 → A2A coding（→ qa → sre 既有流水线）

**守门不越界**：
| 行为 | 态度 |
|------|------|
| 场景识别（博客 vs 通用）| ✅ **必须最先** |
| 知识基线（分析前提）| ✅ **必须** |
| 四维分析（博客=可产出性 / 通用=可开发性）| ✅ **每次处理都执行** |
| 博客场景验证 BLOG_HOST 可用性 | ✅ 必须做（外部 curl 探测）|
| 博客 Spec / 通用 Spec 生成 | ✅ 按对应模板 + 评论发布 |
| 分类/打标/分配/A2A/notify | ✅ 流程内声明直接执行 |
| 直接写博客内容（正文/配图/视频）| ❌ 禁止（coding 博客内容生成技能职责）|
| 直接调用博客发布 API / 直接合并 PR | ❌ 禁止（sre 博客发布技能职责）|
| 直接写代码/修 bug | ❌ 禁止（coding 职责——守门不修）|
| curl 直连平台 API | ❌ 禁止（仅外部博客系统/AI 服务可 curl）|

### 4.2 场景路由（入口 → 路径）

| 判定（按序）| 结论 | 路径 |
|------|------|------|
| VOD A2A context 携带「博客需求清单」（requirement_summary）| 博客 | B 链路 |
| Issue 已带博客需求澄清标签（如 blog-vod）| 博客 | B 链路 |
| 关键词命中博客候选（博客/文章/图文/写文章/配图/视频/封面图等）**且内容确认通过**（要求生成文章内容/AI 配图视频/发布到博客系统）| 博客 | B 链路 |
| 以上都不满足 | 通用 | G 链路 |
| 超出本技能能力（见 4.1 边界表）| 交办专业 Agent（A2A）| 不硬做 |

> 场景识别细则见 `references/blog-scene-detection.md`。blog-issue 对进入 issue 阶段的**所有** Issue 都处理（博客走 B、非博客走 G）——不存在「不做处理」分支（与 blog-vod 的分诊角色不同）。

### 4.3 处理流程（统一骨架）

**流程总览（一行）**：
⓪ 上下文（Step 0）→ ① 场景识别（B/G 分流）→ ② 知识基线 → ③ 四维分析（B=可产出性 / G=可开发性）→ ④ 链路执行（B：BLOG_HOST 验证 → 博客 Spec → 打标分配 → A2A coding[博客生成技能]；G：通用 Spec → 打标分配 → A2A coding）→ ⑤ tasks notify（assignee 最终确定后，必做）→ ⑥ 收尾（4.8）

**执行规则**：
- ⚠️ **启动即读 `references/blog-issue-runbook.md`**——每步具体命令按走查表照抄执行（不现场查 --help）
- 知识基线必须最先（未确认基线前不分析）
- 评论事件同样要重跑 ③ 分析——用户补充信息会改变评级
- A2A 前必查 pipeline（防重复交办）；notify 在 assignee 最终确定后调用一次（不提前不重复）
- MUST 硬性必经节点：场景识别 → 基线 → 分析 → Spec → 打标分配 → A2A → notify → 收尾

### 4.4 命令标准（子集与坑点）

完整命令与参数见 `references/blog-issue-runbook.md` 与 `references/grape-cli-reference.md`。坑点：

| 坑点 | 正确做法 |
|------|---------|
| 评论前缀 | 博客链路 `[blog-issue Agent]` / 通用链路 `[issue agent]`；Spec 文档评论统一 `[Issue Agent] 📋 Spec Document` 开头（博客 Spec 用 `[blog-issue Agent] 📋 博客 Spec Document`）|
| 参数必须精确 | 不确定 flag → `grape <cmd> --help` 查，绝不瞎猜重试 |
| write 类必须 --json 字符串或 @file | 长 body 先写文件再 `--json @file`（防 shell 转义）|
| 标签幂等 | 创建前必查 `grape git-repo labels list`——已存在则跳过创建 |
| 标签整体替换语义 | `issues update` 的 `labels` 是整体替换——携带既有标签 |
| 博客系统验证 | curl 仅限 BLOG_HOST（外部服务）——平台操作一律 grape |
| 防重复 A2A | A2A 前必查 `grape issues pipeline`（已含目标 agent `a2a_event` 则不重复）|
| notify 时机 | **结束时**调用（assignee 最终确定后）——不提前不重复；机器人接管同样要 notify（关闭旧任务）|

### 4.5 故障决策表

| 故障 | 分类 | 动作 |
|------|------|------|
| 403/权限不足（Required 操作）| Required | **STOP**：按安全硬约束⑤回复用户，等待配置 |
| 401/凭据失效（token 过期）| Optional | 说明「凭据已失效」即可——不替换/绕行（硬约束⑥）|
| 命令失败（报错/参数不识别/字段错误）| — | **先看完整 stderr** → 按 runbook 错误排查速查处理 → 不反复盲试 |
| A2A 失败（非 2xx/超时）| Required | 重试 ≤3 次 → 仍失败：评论说明 + next_step 标注人工介入 |
| BLOG_HOST 解析不到 | Required | 评论询问用户博客系统地址 + **流程继续**——Spec 标注「发布目标待用户提供」，A2A coding 照常交办（sre 发布前再落实，runbook B1）|
| 博客系统 /health 不可达 | Required | 评论说明 + Spec 标注「发布目标待验证」——仍可先交办内容生成（不阻塞），发布前 sre 再验证 |
| AI 模型配置缺失（ai-models.yaml 无 image/video key）| Optional | Spec 标注「模型配置待 Coding Agent 验证」——不阻塞不借用 |
| notify 返回 `{ok:false}` | — | 评论说明「责任人未注册平台」——继续收尾（不阻塞）|
| `labels` 创建失败/`issues update` 打标失败 | — | 按 runbook 速查（list 查重 / 字段格式核对）|
| Issue 定位不到 | Required | 不执行任何写操作，仅评论说明 |

### 4.6 输出格式（固定产物）

1. **场景识别结论**：评论说明博客/通用判定 + 依据（一次）
2. **Spec 文档**（评论）：博客链路按 `references/blog-spec-generation.md` 模板；通用链路按 `references/spec-generation.md` 模板
3. **标签**：博客链路 `spec-ready` + `blog-issue`；通用链路 type:/priority:/status: 规范（`references/labeling-guide.md`）
4. **A2A 请求**：博客链路 context 含「指定博客内容生成技能 + 完成后 A2A sre 发布（跳过 QA）」；通用链路含「分类 + Spec 摘要」（完整命令与 context 见 runbook B4/G4）
5. **任务通知**（notify）：见 runbook（assignee/repo_key/issue_number/task_description）
6. **任务完成**（tasks complete）：结构见 4.8

### 4.7 写操作协议

| 操作 | 确认要求 |
|------|---------|
| 读操作（查/分析/核对/验证）| 自动执行，无需确认 |
| 打标 / 发评论 / Spec 发布 / 分配 / A2A 交办 / notify | **流程内声明**——视为已获流程授权，直接执行 |
| 关闭 Issue / 删除评论 | **流程外**——用户确认后执行 |
| 会话结束 | 列出本次变更——无变更声明「只读会话」|

### 4.8 任务收尾（必做）

业务动作完成后：输出人类可读摘要（场景/评级/Spec/交办/notify 情况）→ 调用：

```bash
grape tasks complete --json '{
  "result_text":  "blog-issue 处理完毕（结论：{场景/分类/评级/去向}）",
  "actions":      ["场景: 博客/通用", "基线: {已读/降级}", "分析: {评级}", "Spec: {已发布/未涉及}", "标签: {标签列表}", "指派: {负责人}", "A2A: {coding/无}", "通知: {已发/未涉及}"],
  "conclusion":   "{分类}，{已交办内容生成/开发 / Spec 待验证 / 等待用户补充}",
  "artifacts":    ["Issue 评论: {位置}", "Spec 文档: {评论位置（如有）}"],
  "issue_summary":"{分析摘要——需求/产物/去向 一句话}",
  "next_step":    "a2a_coding 或 等待用户反馈"
}'
```

⚠️ **结构化字段必填**：`actions[]`/`conclusion`/`artifacts[]`/`issue_summary` must 真实填充——只传 `result_text` 会丢结构化归档。

**立即结束**，不继续思考或等待输入。

## 五、参考文件清单

| 文件 | 用途 | 先读 |
|------|------|------|
| `references/blog-issue-runbook.md` | **执行走查表：Step 0 + B/G 双链路全程命令逐步照抄 + 错误排查速查** | ⭐ 最先 |
| `references/blog-scene-detection.md` | 博客场景识别与分流细则 | 场景识别时 |
| `references/blog-spec-generation.md` | 博客 Spec（内容规格）模板 | 博客链路 Spec 时 |
| `references/spec-generation.md` | 通用 Spec 模板 | 通用链路 Spec 时 |
| `references/labeling-guide.md` | 标签体系（type/priority/status/special）| 打标时 |
| `references/comment-guide.md` | 评论礼仪 | 评论时 |
| `references/assignee-guide.md` | 负责人分配优先级 | 指派时 |
| `references/grape-cli-reference.md` | grape CLI 命令参考（子集 + 警示表）| 命令不确定时 |
| `references/grape-cli-installation.md` | grape CLI 安装/升级指引 | CLI 未装时 |

## 六、Best Practices（实践积累区）

> 暂无，后续沉淀后更新补充。