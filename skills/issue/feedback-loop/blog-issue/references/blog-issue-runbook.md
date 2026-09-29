# blog-issue 执行走查表（runbook）

> 目的：把 blog-issue 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> **CLI 纪律**：本表已覆盖本技能全部平台操作命令（issues / git-repo 含 labels/pulls/contents/comments / a2a / tasks）——**禁止 curl 直连平台 API**；curl 仅用于**外部博客系统**（BLOG_HOST）验证探测。
> 环境变量直接使用：`$ACCOUNT`、`$REPO_NAME`（= `${REPO_FULL_NAME#*/}`）、`$ISSUE_NUMBER`、`$PR_NUMBER`（有则填）、`$DEVOPS_EVENT_TYPE`、`$BLOG_HOST`（博客场景解析）。
> **评论前缀硬规**：博客链路所有评论 `[blog-issue Agent]` 开头；通用链路 `[issue agent]` 开头；Spec 文档评论 `[Issue Agent] 📋 Spec Document` 开头（博客 Spec 用 `[blog-issue Agent] 📋 博客 Spec Document`）。

---

## Step 0 · 任务上下文与就绪（必须最先，任何事件都做）

```bash
# ⚠️ CLI 前置自愈（最先）：`grape --version` ≥0.3.2；未装/版本过低 → 按 references/grape-cli-installation.md
#    自动安装/升级（timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git——安装可能无输出，加 timeout 防误判）
#    → 装好再验证一次；仍不可用 → 输出「前置检查未通过：<原因>」并结束任务（不降级直连）
grape --version
grape refresh 2>&1 && echo REFRESH_OK        # 契约保鲜；失败重试 ≤2 次后回退内置快照继续
grape tasks current --json-out               # 前序 A2A payload/上下文在这里（不依赖 $SEQ——平台不注入）
# ⚠️ 入口事件识别（$DEVOPS_EVENT_TYPE）：issue_opened / a2a_event → 全流程 Step 1 起；
#    评论类事件（用户回复/质疑/补充）→ 直接走「评论进件分流」（下节），重跑相关分析后答复
#    （如需前序事件详情——如 a2a_event 的 payload 不在 current 里——用 grape events detail --seq {seq} 读；seq 为事件编号——从 tasks current 输出/当前事件上下文取，平台不单独注入 $SEQ）
# ISSUE_NUMBER 缺失 → 先用 `git-repo issues get`/`git-repo issues list` 定位；定位不到 → STOP（不执行任何写操作）
if [ -n "$ISSUE_NUMBER" ]; then
  grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out 2>&1 | head -120
fi
```

## 评论进件分流（评论/交互事件必做——按语义走分支）

- **补充信息**（澄清回答/新增需求细节）→ 重跑 Step 3 四维分析 → 必要时重发 Spec（版本 +1）→ 评论确认
- **质疑分配** → 重读 CODEOWNERS 重新核对 → 评论说明理由
- **Spec 修改意见** → Spec 版本 +1 重发布（Step B2/G3 命令）→ 评论说明变更点
- **确认 Spec / 催办** → 评论确认；若尚未交办 → 补 A2A（Step B4/G4）
- **关闭请求** → 验证已完成（博客场景：BLOG_HOST 文章可见；通用：git log/PR 合并状态）→ 已达成 → 评论说明 + `grape git-repo issues update --json '{"state":"closed"}'`（流程外——先确认）→ tasks notify 收尾；未达成 → 回复当前进展

```bash
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[blog-issue Agent] {回复}"}' --json-out
```

---

## Step 1 · 场景识别（必须最先——博客 vs 通用分流）

- 判定顺序（从 `references/blog-scene-detection.md`）：① VOD A2A context 携「博客需求清单」→ 博客；② 已带博客澄清标签（blog-vod）→ 博客；③ 关键词命中博客候选 + 内容确认通过 → 博客；④ 以上都不满足 → 通用
- **超出本技能能力**（SKILL 4.1 边界表——如被要求直接写博客内容/直接发布）→ 评论说明 + A2A 交办对应 Agent（coding/sre）——不硬做
- **博客** → 走 B 链路（下节）；**通用** → 走 G 链路（再下节）
- 场景识别结论用评论说明一次（前缀按链路）

## Step 2 · 知识基线（分析前提）

- 知识基线由服务端在 prompt「项目知识基线」章节内联注入（主路径——**无需命令**，Agent 不自取/不自行生成；不存在 `grape knowledge context` 命令——见 grape-cli-reference 警示表）
- 标注「无基线」/`[degraded]` → 降级：`grape git-repo repo --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out` + README（`grape git-repo contents --path README.md --raw`），不阻塞
- 博客场景注意从基线提取：`project-info/member/blog-config.yaml`（BLOG_HOST）、`project-info/member/ai-models.yaml`（qwen-image / Wan2.2 配置）
  - **提取到 BLOG_HOST 值后先导出** `export BLOG_HOST="<取到的值>"`——后续 `curl https://$BLOG_HOST/...`（B4/B5）直接引用，未导出则 URL 为空

## Step 3 · 四维分析（每次处理都执行——博客=可产出性 / 通用=可开发性）

| 维度 | 博客（可产出性）| 通用（可开发性）|
|------|---------------|---------------|
| 需求完整性 | 主题/风格/结构/配图/视频/长度/语调 是否齐 | 需求描述是否可执行 |
| 技术/内容可行性 | 内容规格可实现（模型工具在列）| 方案技术上可行 |
| 依赖就绪性 | AI 模型配置（ai-models.yaml）+ BLOG_HOST 可达 | 依赖库/服务就绪 |
| 范围确定性 | 边界清晰（单篇/系列/是否含视频）| 改动范围明确 |

- 评级：`ready` / `almost-ready` / `needs-discussion` / `not-feasible`
- `ready` → 走 B/G 链路执行；`almost-ready` → 分配责任人 + 精确追问 1-2 个问题；`needs-discussion` → 分配 + 逐维度列缺失追问 + 标记 `need-info`；`not-feasible` → 评论说明 + 标记 `invalid`

---

## B 链路 · 博客场景（内容产出）

### B1 · BLOG_HOST 解析与验证（博客必须——外部 curl 合法）

```bash
# BLOG_HOST 解析优先级：① 知识基线 project-info/member/blog-config.yaml 的 blog.host
#   ② VOD A2A context 提及的博客地址 ③ Issue 正文/评论提及的地址
#   ④ 都没有 → STOP，评论询问用户（不猜不编）
# 博客系统健康与接口探测（curl 仅限 BLOG_HOST——外部交付系统，非平台 API）：
curl -s --max-time 10 "https://$BLOG_HOST/health"
# 期望 {"status":"ok","service":"blog-api",...}；不可达 → 评论说明 + Spec 标注「发布目标待验证」（不阻塞内容生成交办——sre 发布前再验）
curl -s --max-time 10 "https://$BLOG_HOST/api/lables"
curl -s --max-time 10 "https://$BLOG_HOST/api/articles?page=1&size=2"
# AI 模型配置就绪性（从知识基线读）：image.url/key/model（qwen-image）+ video.url/key/model（Wan2.2）——缺失 → Spec 标注「模型配置待 Coding Agent 验证」，不阻塞不借用
```

### B2 · 博客 Spec 生成（内容规格）

```bash
# 按 references/blog-spec-generation.md 模板组织（主题/风格/结构/配图规格/视频规格/发布目标/验收标准）
# 长 body 先写文件再 @file（外层单引号防 shell 转义）：
printf '%s' '{"body":"[blog-issue Agent] 📋 博客 Spec Document\n\n{Spec 正文}"}' > /tmp/blog-spec.json
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json @/tmp/blog-spec.json --json-out
```

### B3 · 打标 + 分配（博客）

```bash
# 标签（幂等——先 list 再 create 缺失项）：
grape git-repo labels list --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out
grape git-repo labels create --owner "$ACCOUNT" --repo "$REPO_NAME" --json '{"name":"blog-issue","color":"#f9d0c4"}'
grape git-repo labels create --owner "$ACCOUNT" --repo "$REPO_NAME" --json '{"name":"spec-ready","color":"#0e8a16"}'
# 打标（整体替换语义——携带既有标签）：
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"labels":"{既有标签,}spec-ready,blog-issue"}' --json-out
# 分配（CODEOWNERS 优先——见 references/assignee-guide.md；博客链路缺省分配机器人 sts 账号）：
grape git-repo contents --owner "$ACCOUNT" --repo "$REPO_NAME" --path CODEOWNERS --ref main --json-out 2>&1 | head -30
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"assignee":"{GitCode 用户名}"}' --json-out
```

### B4 · A2A 交办 coding（博客内容生成——必做防重复）

**协作链路总览**（博客链路 = 内容产出流水线，QA 跳过）：

```
VOD（需求澄清）→ A2A → blog-issue（本技能：分析→博客 Spec→A2A）
  → A2A → coding（博客内容生成技能：正文+配图+视频 → 提交 PR）
    → A2A → sre（博客发布技能：合并 PR → 上传媒体 → 发布文章）  ← QA 跳过
```

**触发时机**：博客 Spec 生成完成 + 评级 ready → 交办 coding；coding→sre 由 coding 技能内部触发（本技能不参与）。**职责边界**：blog-issue 不写内容/不发布（见 SKILL 4.1）；coding 不发布；sre 仅发布。

```bash
# ⚠️ 防重复：先查 pipeline，已含 coding:a2a_event 则不重复 A2A，只发评论
grape issues pipeline --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 交办（context 明确指定博客内容生成技能 + 提示完成后 A2A sre、跳过 QA）：
grape a2a handoff --json '{"agent":"coding","payload":{"repository":"'$ACCOUNT/$REPO_NAME'","account":"'$ACCOUNT'","issue_number":'$ISSUE_NUMBER',"pr_number":null,"context":"博客需求已分析（评级 ready），博客 Spec 已发布（评论位置见前序评论）。请使用【博客内容生成技能】生成正文+配图+视频并提交 PR。发布目标: '$BLOG_HOST'。完成后请 A2A 通知 sre 使用博客发布技能发布（跳过 QA——内容产物无需代码审查）。"}}'
# ⚠️ 字段规则：pr_number 字段——$PR_NUMBER 非空时填其值，无则 null（严禁将 PR 编号填入 issue_number）
# 成功判定：status=ok 且 seq 非零 = 交办成功；seq=0/skipped = 被去重跳过（检查目标 Agent subscribe_events 配置）
# A2A 失败 → 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入
```

**coding → sre 交接参考**（由 coding 博客内容生成技能执行，本技能不参与；命令供上下文理解）：

```bash
grape a2a handoff --json '{"agent":"sre","payload":{"repository":"'$ACCOUNT/$REPO_NAME'","account":"'$ACCOUNT'","issue_number":'$ISSUE_NUMBER',"pr_number":{PR_NUMBER},"context":"博客内容已生成并提交 PR #{PR_NUMBER}。博客目录: blog/{topic-slug}/。请使用博客发布技能：1. 合并 PR 2. 从 blog/ 目录读取文章+媒体 3. 上传媒体到博客服务器 4. 发布文章 5. 在 Issue 评论反馈发布结果。"}}'
```

### B5 · 任务通知（必做——assignee 最终确定后）

```bash
grape tasks notify --json '{"assignee":"{最终 assignee 用户名——机器人接管也通知}","repo_key":"'$ACCOUNT/$REPO_NAME'","issue_number":'$ISSUE_NUMBER',"task_description":"Issue #'$ISSUE_NUMBER' 博客需求已分析（评级 ready），博客 Spec 已发布，已 A2A 交办 coding（博客内容生成技能）。"}'
# 返回 {ok:false}（责任人未注册平台）→ 评论说明即可，继续收尾
```

---

## G 链路 · 通用场景（软件交付——保持既有流程）

### G1 · 分类与打标

```bash
grape git-repo labels list --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out
# 缺失标签按 references/labeling-guide.md 规范创建（type:/priority:/status: 前缀）：
grape git-repo labels create --owner "$ACCOUNT" --repo "$REPO_NAME" --json '{"name":"type:feature","color":"#0e8a16"}' --json-out
# 打标（整体替换——携带既有标签）：
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"labels":"{原有标签},type:feature,status:triaged"}' --json-out
```

### G2 · 指派

```bash
grape git-repo contents --owner "$ACCOUNT" --repo "$REPO_NAME" --path CODEOWNERS --ref main --json-out 2>&1 | head -30
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"assignee":"{GitCode 用户名}"}' --json-out
```

### G3 · 通用 Spec（feature/enhancement 类必做）

```bash
# 按 references/spec-generation.md 模板（需求描述/技术方案/范围/依赖/测试策略/风险）：
printf '%s' '{"body":"[Issue Agent] 📋 Spec Document\n\n{Spec 正文}"}' > /tmp/gen-spec.json
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json @/tmp/gen-spec.json --json-out
```

### G4 · A2A 交办 coding（防重复）

```bash
grape issues pipeline --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape a2a handoff --json '{"agent":"coding","payload":{"repository":"'$ACCOUNT/$REPO_NAME'","account":"'$ACCOUNT'","issue_number":'$ISSUE_NUMBER',"pr_number":null,"context":"{分类}，评级 ready，通用 Spec 已发布（评论位置见前序评论）。请按 Spec 开发提交 PR。"}}'
# 失败重试 ≤3 次 → 仍失败：评论说明 + next_step 人工介入
```

### G5 · 任务通知（必做）

```bash
grape tasks notify --json '{"assignee":"{最终 assignee}","repo_key":"'$ACCOUNT/$REPO_NAME'","issue_number":'$ISSUE_NUMBER',"task_description":"Issue #'$ISSUE_NUMBER' 已分析（评级 ready），Spec 已发布，已 A2A 交办 coding。"}'
```

---

## Step 收尾 · 任务完成流程（必做——任何分支都必须执行到最后）

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

> ⚠️ **结束信号**：tasks complete 后立即结束任务，不要继续思考或等待输入。A2A 交办成功 ≠ 任务结束（仍需 complete）。结构化字段（actions/conclusion/artifacts/issue_summary）must 真实填充——结尾是下一节点的输入。

---

## 错误排查速查（命令返回异常时）

> ⚠️ 出错时**先看完整错误**（命令去掉 `| tail -N` 截断，`2>&1` 保留 stderr）；runbook 命令照抄仍失败，才允许 `grape commands <关键词>` / `grape <group> --help` 按 Body fields 修正。**不反复盲试同一命令**。

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名抄错，核对 runbook/reference；仍不确定再 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 有契约不允许字段 → `grape <group> <verb> --help` 看 Body fields 删多余 |
| `comments create` 失败（长 body 转义）| 改用 `--json @file`（body 先写文件）|
| `labels create` 失败 / 重复 | 先 `labels list` 确认标签存在（不存在才 create）——不重复创建 |
| `issues update` 失败（打标/分配不生效）| 核对字段：`labels` 用字符串逗号分隔（`"spec-ready,blog-issue"`）、`assignee` 用 GitCode 用户名 |
| `pulls list` / `issues list` 返回空 | 属正常（无 PR/无 Issue）——按「无历史」分支处理 |
| A2A 非 2xx / 超时 | 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入 |
| notify 返回 `{ok:false}` | 责任人未注册平台——评论说明即可，继续收尾不阻塞 |
| BLOG_HOST 解析不到 | 博客链路 STOP——评论询问用户（不猜不编）|
| 博客系统 /health 不可达 | 评论说明 + Spec 标注「发布目标待验证」——内容生成仍交办（不阻塞），sre 发布前再验 |
| AI 模型配置缺失 | Spec 标注「模型配置待 Coding Agent 验证」——不阻塞不借用 |
| 401 凭据失效 | 说明「凭据已失效」即可，不换 token（安全硬约束⑥）|
| 403 账户/平台管理类 | 说明需管理员配置/`grape_` 级凭据，本技能不涉及——不绕行 |
| 报「契约过期/命令不识别」| 先 `grape refresh` 再重试（前置门②）|