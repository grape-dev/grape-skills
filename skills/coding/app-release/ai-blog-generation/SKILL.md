---
name: ai-blog-generation
version: 2.1.0
description: |
  博客内容生成技能（ai-blog-generation）：接收 A2A 交办（博客 Spec 已由 issue 阶段产出），生成图文并茂的博客文章
  （HTML 正文 + AI 配图 + AI 视频）→ 提交到仓库 blog/ 目录并创建 PR → A2A 交办 SRE 发布（跳过 QA——内容产物无需代码审查）。
  Use when：博客生成、写文章、图文并茂、AI 配图、AI 视频、博客内容产出、ai-blog-generation。
tools:
  - grape
  - bash
  - git
  - ffmpeg
---

# 博客内容生成与 PR 提交（ai-blog-generation v2.1 · grape CLI）

## 一、安全硬约束（必须遵守）

1. **CLI 优先**：凡 grape CLI 能做的走 CLI，禁止绕过 CLI 直连平台 API（curl/python httpx 等）。CLI 未装/版本过低 → **自动安装/升级**（`references/grape-cli-installation.md`）→ 装好继续；仅当安装失败/环境不可用时才报障说明（不降级直连）。
2. **外部 AI 服务豁免**：配图/视频生成调用**外部 AI API**（qwen-image / Wan2.2——URL/Key/Model 从知识基线 `project-info/member/ai-models.yaml` 读取）——这是外部服务依赖，**合法直连，与 grape 平台 API 严格隔离**；除 AI 模型 API 与博客系统（BLOG_HOST——本技能通常不直接触达，发布是 SRE 职责）外，**任何平台 API 一律禁止直连**。
3. **执行前先读任务上下文**：`grape tasks current --json-out` + `grape issues detail --json-out`，明确已做/待做（前序 Agent 的 Spec/分析在 A2A context 与 Issue 评论里）。
4. 严禁读取 data/、configs/、sessions.db 等 Grape 内部数据；**AI 模型 Key 不得写入日志/评论/文章/代码**（只用于外部 API 调用；文章/仓库内不得出现任何 token）。
5. **403/无权限**：立即停止该操作并回复「该操作需要管理员/维护者权限」，不尝试其他 token 或绕行；**401（凭据失效）**：说明「凭据已失效」即可，不替换（403=权限需配置；401=token 过期——区别处理）。
6. **内容产出边界**：本技能只做「生成内容 → 提交 PR → A2A 交办 SRE」——**禁止直接调用博客发布 API、上传文件到博客服务器、创建/更新/删除博客文章**（SRE 职责）。
7. **视频模型纪律**：只能用 **T2V（文生视频）** 模型（如 `Wan2.2-T2V-A14B`）——**禁止 I2V（图生视频）**（模型名含 `I2V` 一律不得调用）；prompt 必须包含产品真实视觉特征（来自官网调研，不得凭记忆编造外观）。
8. **长命令静默**：视频生成约 30s、图片生成约 7s/张、媒体下载合成耗时——执行前在评论告知用户等待（防误判卡死）。

## 二、环境变量表（平台注入，按 ai-blog-generation Agent 类型）

| 变量 | 语义 | 用在哪 | 何时有 |
|------|------|--------|--------|
| `GRAPE_SERVER_URL` / `GRAPE_SESSION_TOKEN` | 服务端地址 / 会话 token（tk_）| grape CLI 自动读取 | 全部任务 |
| `REPO_FULL_NAME` | 仓库全名（owner/repo） | A2A 交办 `repository`；repo_key 拼装 | 全部 |
| `REPO_OWNER` | 仓库属主（owner，不含 /repo） | CLI 用 --owner | 全部 |
| `REPO_NAME` | 仓库名 | CLI 用 --repo | 全部 |
| `ACCOUNT` | 个人账号（触发人 actor，与仓库属主解耦） | A2A payload `account`（一般不用作 --owner） | 全部 |
| `REPO_NAME` | 仓库名（派生：`${REPO_FULL_NAME#*/}`）| --repo 参数 | 全部 |
| `ISSUE_NUMBER` | Issue 编号 | A2A payload / 分支名 / PR 关联 | 全部 |
| `PR_NUMBER` | PR 编号（内容优化场景有）| A2A payload | 有 PR 时 |

派生变量：`REPO_NAME` = `${REPO_FULL_NAME#*/}`。敏感变量（token 类）**不 printenv、不落盘、不写评论**。
**AI 模型配置（ai-models.yaml）不是环境变量**——从知识基线读取（`image.url/key/model` + `video.url/key/model`），读取不到 → 见 4.5 降级。

## 三、前置检查门（自愈 → 重试 → STOP）

| 检查项 | 判定命令 | 通过标准 | 失败动作 |
|--------|---------|---------|---------|
| CLI 可用 | `grape --version` | ≥0.3.2 | **自愈**：按 `references/grape-cli-installation.md` 自动安装/升级（`timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git`）→ 装好再验；仍不可用 → 结束任务并说明 |
| 契约刷新 | `grape refresh` | 拉取最新契约成功 | **重试** ≤2 次；仍失败 → 继续（回退内置快照）|
| 任务上下文 | `grape tasks current` + `grape issues detail` | 拿到任务与上下文 | 定位不到 → STOP（不执行写操作）|
| 本地工具链 | `git --version` + `ffmpeg -version` + `python3 --version` | 可达 | **自愈**：`apt-get install -y git ffmpeg`（缺失才装）→ 再验；仍不可用 → 报告阻塞 |
| AI 模型配置（配图/视频前）| 知识基线 `ai-models.yaml` 读 `image/video` 段 | url/key/model 齐 | **降级**：评论标注「模型配置缺失/不完整——跳过配图/视频，只提交文章」——不借用不猜（详见 4.5）|
| 瞬时失败（网络/限流）| — | — | **重试**：自动重试 ≤3 次（退避 1s/2s/4s）——AI API 403/429 不重试（见硬约束⑤）|

## 四、技能定义与执行

### 4.1 定位与职责边界

**职责**：把博客 Spec（内容规格——由 blog-issue 阶段产出）变成**可发布的 PR**——学习参考文章 → 撰写 HTML 文章 → 产品调研（涉产品时）→ AI 配图 → AI 视频 → 组织产物到 `blog/{topic-slug}/` → 创建 PR → A2A 交办 SRE。

**守门不越界**：不直接发布博客（SRE 职责）、不合并 PR、不修改 `blog/` 以外仓库文件（博客工具初始化除外）。

| 行为 | 态度 |
|------|------|
| 学习参考文章再写（Spec 含参考链接时）| ✅ **必须做，不可跳过** |
| 撰写 HTML 文章（按 article-template）+ 至少一个特殊元素（表格/引用/高亮块）| ✅ **必须做** |
| 涉具体产品时先官网调研再生成（product-research——颜色/logo/前脸须官网核实）| ✅ **必须做，不可跳过** |
| 配图间隔分布 + 生成后叠加真实 logo（logo_overlay 存在时）| ✅ **必须做** |
| 视频用 T2V 模型、prompt 含真实产品特征 | ✅ **必须做（I2V 禁止）** |
| 产物提交到仓库 `blog/{topic-slug}/`（index.html/cover.png/images/intro.mp4/meta.json）| ✅ **必须做** |
| `blog/_tools/` 已存在时复用它，不覆盖 | ✅ **必须做** |
| 产品调研 prompt / 生成前确认 Spec（内容规格）| ✅ **必须做** |
| 创建 PR 后 Issue 评论告知 + A2A 通知 SRE | ✅ **必须做，不可跳过** |
| 每张配图一个文件、每个原子变更一个 commit | ✅ **必须做** |
| 直接发布博客（调用博客 API/上传文件/创建文章）| ❌ **禁止（SRE 职责）** |
| 合并 PR / 修改 blog/ 以外文件（工具初始化除外）| ❌ **禁止** |
| 使用 I2V 模型 / 凭记忆编造产品外观 | ❌ **禁止** |
| curl 直连平台 API | ❌ 禁止（必须走 grape CLI；外部 AI API 除外——见硬约束②）|

### 4.2 场景路由（入口 → 路径）

> **判定信号优先级**：`$PR_NUMBER` 已注入（存在 PR）→ 判定**内容优化**（无论 context 措辞）；`$PR_NUMBER` 未注入 → 按 A2A context 特征判定（下表）。⚠️ 无 PR_NUMBER **不代表**新生成——评论/复审触发的优化场景可能不带 PR 编号（runbook B1 有定位兜底）。

| A2A context 特征 | 场景 | 路径 |
|-----------------|------|------|
| `$PR_NUMBER` 有值；或含「PR 审查反馈」「需要修改」「优化」「调整内容」| **内容优化** | 修改产物 → 推送 → PR 评论告知 → A2A SRE |
| 含「生成」「创建」「撰写」「写文章」「博客 Spec 已发布」「内容产出」| **新生成** | 参考学习 → 撰写 → 调研 → 配图 → 视频 → 产物组织 → PR → A2A SRE |
| 其他 | 不做处理，结束 | — |

### 4.3 处理流程（统一骨架）

**流程总览（一行）**：
- 新生成：⓪ 上下文 → ① 场景识别 → ② 参考文章学习（如有）→ ③ 撰写文章 → ④ 产品调研（涉产品时）→ ⑤ 生成配图 → ⑥ 生成视频 → ⑦ 组织产物（blog/）+ meta.json → ⑧ PR 创建 → ⑨ Issue 评论 + A2A SRE → 收尾（4.8）
- 内容优化：⓪ 上下文 → ① 场景识别 → ② 按反馈修改产物（原子提交）→ ③ PR 评论 → ④ A2A SRE → 收尾（4.8）

**执行规则**：
- ⚠️ **启动即读 `references/ai-blog-generation-runbook.md`**——每步具体命令按走查表照抄执行（不现场查 --help）
- AI 模型配置缺失（⑤⑥前置）→ **降级不越界**：评论标注后只提交文章（见 4.5）——不得借用其他 token/服务
- 产物完整（⑦）是 PR 前提——index.html/cover.png/images/intro.mp4/meta.json 齐全校验后再建 PR
- ⑨ A2A 防重复：先 `issues pipeline` 查已含 `sre:a2a_event` 则不重复，只发评论
- MUST 硬性必经节点：③ → ⑤/⑥（有模型时）→ ⑦ → ⑧ → ⑨ → 收尾

### 4.4 命令标准（子集与坑点）

完整命令与参数见 `references/ai-blog-generation-runbook.md` 与 `references/grape-cli-reference.md`。坑点：

| 坑点 | 正确做法 |
|------|---------|
| 参数必须精确 | 不确定 flag → `grape <cmd> --help` 查，绝不瞎猜重试 |
| write 类必须 --json 字符串或 @file | 长 body 先写文件再 `--json @file`（防 shell 转义）|
| 评论前缀 | 全部评论 `[coding Agent]` 开头（博客链路沿用 coding 角色前缀）|
| PR 描述 | `pulls create` 契约无 body 字段——创建后 `git-repo pulls update` 补描述四段（变更说明/产物清单/文件变更/后续步骤）；title 用 `docs(blog): {主题}` |
| 防重复 A2A | A2A 前必查 `grape issues pipeline`（已含 `sre:a2a_event` 则不重复）|
| PR 链接 | Web 页面 `/pull/`（单数）markdown 格式——不得用 API 路径 |
| 分支命名 | `feat/blog-{topic-slug}-{yyyyMMdd}`——时间戳防多实例冲突；base = `dev` |
| 外部 AI 调用 | requests/curl 直连 ModelArts（qwen-image/Wan2.2）——**合法**（外部服务——url/key/model 只从 ai-models.yaml 读）|

### 4.5 故障决策表

| 故障 | 分类 | 动作 |
|------|------|------|
| 403/权限不足 | Required | **STOP**：按安全硬约束⑤回复用户，等待配置 |
| 401/凭据失效 | Optional | 说明「凭据已失效」即可——不尝试替换/绕行 |
| 命令失败（报错/字段错误）| — | **先看完整 stderr** → 按 runbook 错误排查速查处理 → 不反复盲试 |
| AI 模型配置缺失（ai-models.yaml 无 image/video 段）| Required | **降级**：评论标注「模型配置缺失——跳过配图/视频，只提交文章」→ 继续文章+PR（不阻塞主流程）；**不借用其他 token/服务** |
| 图片生成 API 失败（403/429）| Required | **停止重试**——评论报告，用纯色占位图标记「待生成」→ 继续 |
| 视频生成 API 失败 | Optional | **跳过视频**——文章标记「无视频版本」→ 继续提交 PR（降级：prompt 标注待补视频）|
| 浏览器提取参考文章失败 | Optional | 改用 curl 直接下载 HTML 页面并解析（外部文章——合法）|
| Edge TTS 语音合成失败 | Optional | 跳过旁白——无音频视频（或文章内标注）|
| git push 失败 | — | 检查分支状态后重试 ≤1 次；仍失败报告 |
| A2A 调用非 2xx / 超时 | Required | 自动重试 ≤3 次 → 仍失败：评论说明 + next_step 人工介入 |
| PR 创建重复 | — | 先查是否已有同分支 open PR（`grape git-repo pulls list --state open`）——有则不重复创建 |

### 4.6 输出格式（固定产物）

1. **PR 创建**（`grape git-repo pulls create` → 再 `grape git-repo pulls update` 补描述四段：变更说明/产物清单/文件变更/后续步骤）：feature 分支 `feat/blog-{topic-slug}-{yyyyMMdd}`，base = `dev`
2. **Issue 评论**：`[coding Agent] ✅ 博客内容已生成，请 SRE 发布 [#n](https://gitcode.com/{repo}/pull/{n})`——含产物摘要（目录/图片数/有无视频）
3. **A2A 请求**：`{"agent":"sre","payload":{"repository":"$ACCOUNT/$REPO_NAME","account":"$ACCOUNT","issue_number":{真实编号},"pr_number":{真实编号},"context":"博客内容已生成并提交 PR #{n}。博客目录: blog/{topic-slug}/。请使用博客发布技能：1. 合并 PR 2. 从 blog/ 目录读取文章+媒体 3. 上传媒体到博客服务器 4. 发布文章 5. 在 Issue 评论反馈发布结果。"}}`（跳过 QA——内容产物无需代码审查）
4. **任务完成**（tasks complete）：结构见 4.8

### 4.7 写操作协议

| 操作 | 确认要求 |
|------|---------|
| 读操作（查 Spec/参考文章/官网）| 自动执行，无需确认 |
| git 提交/push、PR 创建、评论、A2A 交办、媒体生成调用 | **流程内声明**——A2A 流水线显式触发，自动执行 |
| 直接发布博客 / 合并 PR | ❌ **禁止**（SRE 职责——即使是流程内也不执行）|
| 删除文件（清理临时目录）| 流程内清理（/tmp/blog-gen-*）——仅限本技能自己的临时产物 |
| 会话结束 | 列出本次变更（PR/产物/评论）|

### 4.8 任务收尾（必做）

业务动作完成后：输出人类可读摘要（场景/产物/PR）→ 调用：

```bash
grape tasks complete --json '{
  "result_text":  "结论：{新生成/内容优化}处理完毕（{产物摘要 + PR 摘要}）",
  "actions":      ["场景识别: {新生成/优化}", "参考学习: {已学/无参考}", "文章撰写: {章节数/字数}", "产品调研: {已调研/不涉及}", "配图: {N 张/跳过}", "视频: {有/无/跳过}", "产物: blog/{topic-slug}/", "PR: #{pn}", "评论/A2A: sre"],
  "conclusion":   "{已生成并创建 PR #{pn}，A2A 交办 SRE 发布 / 已按审查意见修改完成}",
  "artifacts":    ["PR #{pn}", "分支 feat/blog-{topic}-{date}", "blog/{topic-slug}/ {文件清单}", "评论: {位置}"],
  "issue_summary":"{完成摘要——产物/PR/交办一句话}",
  "next_step":    "a2a_sre 或 等待用户反馈"
}'
```

⚠️ **结构化字段必填**（结尾 = 下一节点的输入）：`actions[]`/`conclusion`/`artifacts[]`/`issue_summary` must 真实填充——SRE 接收方以结构化字段为主消费。

**立即结束**，不继续思考或等待输入。

## 五、参考文件清单

| 文件 | 用途 | 先读 |
|------|------|------|
| `references/ai-blog-generation-runbook.md` | **执行走查表：新生成/内容优化全程命令逐步照抄 + 错误排查速查** | ⭐ 最先 |
| `references/article-template.md` | HTML 文章模板与内联样式 | 撰写时 |
| `references/product-research.md` | 产品实物调研与视觉特征提取（涉产品时）| 调研时 |
| `references/image-video-generation.md` | 配图/视频生成 + 音视频合成（外部 AI API）| 生成时 |
| `references/grape-cli-installation.md` | grape CLI 安装/升级指引（前置门自愈用）| CLI 未装时 |
| `references/grape-cli-reference.md` | grape CLI 命令参考 + 警示表 | 命令不确定时 |

## 六、Best Practices（实践积累区）

- 暂无，后续沉淀后更新补充（配图生成失败分布/视频生成超时模式/产品 logo 叠加常见问题）。