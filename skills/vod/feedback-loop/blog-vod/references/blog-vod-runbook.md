# blog-vod 执行走查表（runbook）

> 目的：把 blog-vod 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量直接使用：`$ACCOUNT`、`$REPO_NAME`（= `${REPO_FULL_NAME#*/}`）、`$ISSUE_NUMBER`、`$DEVOPS_EVENT_TYPE`。
> **评论前缀硬规**：所有评论 body 一律以 `[blog-vod Agent]` 开头。
> 问卷内容与需求清单模板见 `references/requirement-elicit-guide.md`；评论/标签规范见 `references/comment-labeling-guide.md`；A2A 交办见 Step B6（防重复/字段规则/失败降级已内联）。

---

## Step 0 · 任务上下文与就绪（必须最先，任何事件都做）

```bash
# ⚠️ CLI 前置自愈（最先）：`grape --version` ≥0.3.2；未装/版本过低 → 按 references/grape-cli-installation.md
#    自动安装/升级（timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git——安装可能无输出，加 timeout 防误判）
#    → 装好再验证一次；仍不可用 → 输出「前置检查未通过：<原因>」并结束任务（不降级直连）
grape --version
grape refresh 2>&1 && echo REFRESH_OK        # 契约保鲜；失败重试 ≤2 次后回退内置快照继续
grape tasks current --json-out               # 前序 A2A payload/上下文在这里（平台不注入 $SEQ 环境变量——不依赖它）
# ⚠️ 入口事件识别（$DEVOPS_EVENT_TYPE）：issue_opened → 全流程 B1→B6；
#    评论类事件（用户回复收敛问题）→ 续跑：读 Issue 最新评论恢复轮次，从 B3 继续；
#    无法判断 → 按事件 payload 内容判定，仍不明 → STOP 评论说明
# ISSUE_NUMBER 缺失 → 先用 `git-repo issues get`/`git-repo issues list` 定位；定位不到 → STOP（不执行任何写操作）
if [ -n "$ISSUE_NUMBER" ]; then
  grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out 2>&1 | head -120
fi
```

---

## 场景 B · 博客需求引导（接管 issue_opened）

### B1 · 场景识别（必须最先——非博客即结束）

- 用 Step 0 拿到的 Issue 标题/正文判断是否为博客需求（关键词：「博客」「文章」「图文」「写文章」「发博客」「视频」「配音」「配图」等 + 产品/概念/服务名称）
- **非博客**（含「代码」「bug」「编译」「部署」等非博客关键词，或完全无博客关键词）→ **不做处理**：不执行任何写操作，输出收尾（4.8）声明「非博客未处理」即结束
- **博客需求** → 继续 B2

### B2 · 项目知识基线（分析前提）

- 知识基线由服务端在 prompt「项目知识基线」章节内联注入（主路径——**无需命令**，Agent 不自取/不自行生成；不存在 `grape knowledge context` 命令——见 grape-cli-reference 警示表）
- 标注「无基线」/`[degraded]` → 降级：`grape git-repo repo --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out` + README（`grape git-repo contents --raw`），不阻塞

### B3 · 三轮递进收敛（博客维度问卷，≤3 轮）

- 读既有评论（幂等/续跑检查，避免重复提问已确认项）：

```bash
grape git-repo issues comments list --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```

- **第一轮（大方向）**：主题聚焦 / 参考风格 / 标签分类——每次只问 2-4 个问题：

```bash
# 引原文 + 1-3 个具体澄清问题（body 前缀 [blog-vod Agent]；长 body 先写文件再 --json @file）
cat > /tmp/blog_vod_q1.json << 'EOF'
{"body": "[blog-vod Agent] 收到博客需求，先确认几个方向：\n- 主题聚焦：您提到「{产品/概念}」，想从哪个角度切入？\n- 参考风格：有没有想模仿的文章链接？或想要什么风格（科技评测/轻松科普/营销推广）？\n- 标签分类：这篇文章发到博客的哪个分类？（现有标签：1=技术、2=生活、3=随笔、4=教程，也可新建）"}
EOF
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json @/tmp/blog_vod_q1.json
```

- **第二轮（内容细节）**：文章结构（章节/表格/引用块）/ 配图风格（数量/封面）/ 视频方向（画面/旁白）——同 Q1 模式（`/tmp/blog_vod_q2.json` 写好后 `comments create`）
- **第三轮（边界）**：文章长度（标准约 1200 字 / 深度约 2000 字）/ 语调偏好——同 Q1 模式
- 每轮用户回复后：把已确认维度（增量）并入清单，更新到 Issue 评论（供续跑）
- **超限（>3 轮）或用户未回复**：未回复维度用默认值填充并在清单标注「默认值」

### B4 · 博客需求清单输出（固定产物）

- 把已收敛字段按 `references/requirement-elicit-guide.md` §三 JSON 模板组织「博客需求清单」→ 发布为 Issue 评论（作为续跑依据与下游继承上下文）：

```bash
cat > /tmp/blog_vod_summary.json << 'EOF'
{"body": "[blog-vod Agent] 博客需求清单已收敛（未回复维度已用默认值填充并标注）：\n{topic}: {主题}\n{focus}: {切入点}\n{reference_style}: {风格描述}\n{structure}: {章节/特殊元素}\n{images}: {张数/风格/封面}\n{video}: {画面/旁白语调}\n{labels}: {分类}\n{length}: {标准/深度}\n{tone}: {语调}\n（完整 JSON 见下方代码块）\n```json\n{requirement_summary JSON}\n```"}
EOF
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json @/tmp/blog_vod_summary.json
```

### B5 · 标签 + 评论确认（blog-vod / type:feature）

```bash
# ① 查重（幂等）：已存在则跳过创建
grape git-repo labels list --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out
# ② 缺失的创建（blog-vod + type:feature 各查一次，缺失才建）：
grape git-repo labels create --owner "$ACCOUNT" --repo "$REPO_NAME" --json '{"name":"blog-vod","color":"#f9d0c4"}'
grape git-repo labels create --owner "$ACCOUNT" --repo "$REPO_NAME" --json '{"name":"type:feature","color":"#0e8a16"}'
# ③ 给 Issue 打标（整体替换语义——先取既有标签再拼上新标签）：
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"labels":"{既有标签列表,}blog-vod,type:feature"}'
```

> ⚠️ `labels` 字段为整体替换语义——必须携带既有标签，只传新标签会丢旧标签；类型存疑时 blog 需求默认 `type:feature`。

### B6 · A2A 交办 Issue Agent（含防重复检查）

```bash
# ⚠️ 防重复：先查 pipeline，已含 issue:a2a_event 则不重复 A2A，只发评论
grape issues pipeline --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 交办（必须携带真实 issue_number；无 pr_number 则不传，严禁将 PR 编号填入 issue_number）
grape a2a handoff --json '{"agent":"issue","payload":{"repository":"$ACCOUNT/$REPO_NAME","account":"{user}","issue_number":$ISSUE_NUMBER,"context":"博客需求已收敛。标签已添加 blog-vod/type:feature，需求清单已发布到 Issue 评论（供继承）。请 Issue Agent 接力进行分类确认、Spec 生成、指派并触发 Coding Agent。"}}'
# 成功判定：status=ok 且 seq 非零 = 交办成功；seq=0/skipped = 被去重跳过（检查目标 Agent subscribe_events 配置）
# A2A 失败 → 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入
```

- 字段规则：`issue_number` 必填（真实编号——无法确定则不调用 A2A，评论说明）；`pr_number` 有则必填、无则不传；`repository` + `account` 必填（owner/repo 全称）。
- context 需包含收敛结论摘要（需求清单关键字段），供 Issue Agent 继承上下文；A2A 成功后 Issue Agent 接管 stage（vod → issue）。

---

## Step 收尾 · 任务完成流程（必做，业务动作完成后）

```bash
grape tasks complete --json '{
  "result_text":  "blog-vod 处理完毕（结论：{收敛摘要}）",
  "actions":      ["场景识别: 博客/非博客", "知识基线: {已读/降级}", "收敛: {轮数} 轮/无需", "清单: 已输出", "标签: blog-vod,type:feature", "A2A: issue"],
  "conclusion":   "{需求已收敛并交办 / 非博客未处理 / 待用户补充}",
  "artifacts":    ["Issue #{n}（博客需求清单已发布）", "评论: {评论位置}"],
  "issue_summary":"{收敛摘要——主题/风格/结构/配图/视频/标签/长度/语调 一句话}",
  "next_step":    "a2a_issue 或 等待用户补充"
}'
```

> ⚠️ **结束信号**：tasks complete 后立即结束任务。A2A 交办成功 ≠ 任务结束（仍需 complete）。结构化字段 must 真实填充（结尾 = 下一节点输入）。

---

## 错误排查速查（命令返回异常时）

> ⚠️ 出错时**先看完整错误**（命令去掉 `| tail -N` 截断，`2>&1` 保留 stderr）；runbook 命令照抄仍失败，才允许 `grape commands <关键词>` / `grape <group> --help` 按 Body fields 修正。**不反复盲试同一命令**。

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名抄错，核对 runbook/reference；仍不确定再 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 有契约不允许字段 → `grape <group> <verb> --help` 看 Body fields 删多余 |
| `comments create` 失败（长 body 转义）| 改用 `--json @file`（body 先写文件）|
| `labels create` 失败 / 重复 | 先 `labels list` 确认标签存在（不存在才 create）——不重复创建 |
| `issues update` 失败（打标不生效）| 核对字段：`labels` 用字符串逗号分隔（`"blog-vod,type:feature"`）；携带既有标签 |
| A2A 非 2xx / 超时 | 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入 |
| 401 凭据失效 | 说明「凭据已失效」即可，不换 token（安全硬约束⑤）|
| 403 账户/平台管理类 | 说明需管理员配置/`grape_` 级凭据，本技能不涉及——不绕行 |
| `knowledge context` 返回空/degraded | 该命令不存在（警示表）——基线一律走 prompt 内联；degraded → 降级 README + git-repo 分析并标注 `[degraded]`，不阻塞 |
| 报「契约过期/命令不识别」| 先 `grape refresh` 再重试（前置门②）|