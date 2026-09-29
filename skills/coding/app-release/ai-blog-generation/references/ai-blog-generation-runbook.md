# 博客内容生成执行走查表（runbook）

> 目的：把 ai-blog-generation 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> **CLI 纪律**：本表已覆盖本技能全部平台交互命令（issues / git-repo pulls / a2a / tasks）——**禁止 curl 直连平台 API**；curl/requests 仅用于**外部服务**：AI 模型 API（qwen-image/Wan2.2——从 ai-models.yaml 读 url/key/model）、参考文章/官网页面、媒体文件下载。
> 环境变量直接使用：`$ACCOUNT`、`$REPO_NAME`（= `${REPO_FULL_NAME#*/}`）、`$ISSUE_NUMBER`、`$PR_NUMBER`（有则填）。
> **评论前缀硬规**：所有评论 body 一律以 `[coding Agent]` 开头。

---

## Step 0 · 任务上下文与就绪（必须最先，任何事件都做）

```bash
# ⚠️ CLI 前置自愈（最先）：`grape --version` ≥0.3.2；未装/版本过低 → 按 references/grape-cli-installation.md
#    自动安装/升级（timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git——安装可能无输出，加 timeout 防误判）
#    → 装好再验证一次；仍不可用 → 输出「前置检查未通过：<原因>」并结束任务（不降级直连）
grape --version
# ⚠️ 本地工具链（缺失才装）：git/ffmpeg/python3——`apt-get install -y git ffmpeg`
git --version && ffmpeg -version 2>&1 | head -1 && python3 --version
grape refresh 2>&1 && echo REFRESH_OK        # 契约保鲜；失败重试 ≤2 次后回退内置快照继续
grape tasks current --json-out               # 前序 A2A payload/上下文在这里（Spec 摘要/发布目标）
grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out 2>&1 | head -120
git status 2>&1 | head -5                    # 确认 worktree 与分支状态
```

## 场景入口判定（必做——信号优先级：PR_NUMBER 注入 > context 文字，见 SKILL 4.2）

- **$PR_NUMBER 有值**（存在 PR）→ **内容优化**（优先信号——无论 context 措辞）
- **$PR_NUMBER 无值** → 按 context 文字特征判定（⚠️ 无 PR 编号≠新生成——优化场景可能不带 PR）：
  - 含「生成」「创建」「撰写」「写文章」「博客 Spec 已发布」「内容产出」→ 走场景 A（新生成）
  - 含「PR 审查反馈」「需要修改」「优化」「调整内容」→ 走场景 B（内容优化）
- **其他**（无上述特征）→ **不做处理，直接结束**（收尾仅 tasks complete——actions 填「场景识别: 非本技能场景,不处理」，不建 PR 不评论）
- ⚠️ 生成前确认：A2A context / Issue 评论里有博客 Spec（blog-issue 产出）→ 按 Spec 内容规格执行；无 Spec → 评论询问（不猜不编）——询问后仍无 → 结束任务

## 场景 A · 博客内容生成（按顺序执行，上一步未完成不得进入下一步）

### A1 · 参考文章学习（Spec 含参考链接时必做）

- 从 Spec/Issue 提取参考文章 URL（REFERENCE_URL）
- 用浏览器/curl 访问提取正文（curl 仅外部参考页面——合法）：
```bash
curl -sL --max-time 20 "{参考文章 URL}" -H "User-Agent: Mozilla/5.0" | head -c 20000 > /tmp/blog-gen-$$/reference.html
```
- 输出分析结论（标题风格/段落结构/特殊元素/语言风格/配图数量——见 SKILL 三步模仿法），写入临时目录供撰写参考

### A2 · 撰写文章（HTML——必做）

- 按 `references/article-template.md` 模板组织（标题+元数据 / 顶部视频位 / 配图间隔分布 / ≥1 特殊元素 / 结尾署名）
- 内容口径来自博客 Spec（主题/风格/结构/字数/章节）——按 Spec 逐项落地
- 长文分节撰写，写入 `/tmp/blog-gen-$$/index.html`

### A3 · 产品实物调研（涉具体产品时必做——不可跳过）

- 从 Spec/Issue 提取产品/品牌名（如「问界M9」「iPhone 16」）
- 按 `references/product-research.md`：定位官网 → 提取视觉特征（颜色/设计/logo/场景）→ 保存 `product_visual_info.json` + 裁剪 `logo_overlay.png`
- ⚠️ 抽象概念/通用知识/纯教程主题 → 跳过此步（Spec 会注明）

### A4 · 生成配图（有模型配置时必做）

- 从知识基线 `ai-models.yaml` 读 `image.url/key/model`（qwen-image）——缺失 → 按 SKILL 4.5 降级
- 按 `references/image-video-generation.md` 上半部分：构造 prompt（嵌入 visual_info 真实特征）→ 调用外部 AI API → 叠加 logo → 限流间隔 ≥1s
- 输出到 `/tmp/blog-gen-$$/images/`

### A5 · 生成视频（有模型配置时必做）

- 从知识基线读 `video.url/key/model`——**模型名含 I2V 一律不得调用**（只能 T2V）
- 按 `references/image-video-generation.md` 下半部分：构造视频 prompt（基于视觉特征）→ 调用 → 下载视频 → Edge TTS 旁白 → ffmpeg 合成
- 输出 `/tmp/blog-gen-$$/intro.mp4`

### A6 · 组织产物并写入博客目录（必做）

```bash
TOPIC_SLUG="{从标题生成的英文短横线名}"
# 仓库内 blog/ 目录（与 src/ 同级——不存在则创建 + 初始化 _tools/）：
mkdir -p "blog/$TOPIC_SLUG/images" blog/_tools
# _tools/ 已存在 → 直接复用不覆盖已有文件
cp /tmp/blog-gen-*/index.html "blog/$TOPIC_SLUG/index.html"
cp /tmp/blog-gen-*/intro.mp4 "blog/$TOPIC_SLUG/intro.mp4" 2>/dev/null || true
cp /tmp/blog-gen-*/cover.png "blog/$TOPIC_SLUG/cover.png" 2>/dev/null || true
cp /tmp/blog-gen-*/images/*.png "blog/$TOPIC_SLUG/images/" 2>/dev/null || true
# 产物完整性校验（PR 前置——不齐则补/降级标注）：
ls -la "blog/$TOPIC_SLUG/"
# meta.json：
printf '%s' '{"title":"{标题}","description":"{一句话摘要}","tags":["{tag}"],"author":"Grape AI","date":"'"$(date +%Y-%m-%d)"'","featured_image":"cover.png"}' > "blog/$TOPIC_SLUG/meta.json"
```

### A7 · 提交 PR（必做）

```bash
# 分支（从 dev 分出——时间戳防多实例冲突）：
git fetch origin
BRANCH_NAME="feat/blog-${TOPIC_SLUG}-$(date +%Y%m%d)"
git checkout -b "$BRANCH_NAME" "origin/dev" 2>&1 | tail -2
# 原子提交（_tools/ 与产物分开；产物可再按文件拆分）：
if git diff --name-only origin/dev | grep -q '^blog/_tools/'; then git add blog/_tools/ && git commit -m "docs(blog): add shared blog tools and templates" 2>&1 | tail -2; fi
git add "blog/$TOPIC_SLUG/"
git commit -m "docs(blog): add article '$TOPIC_SLUG'" 2>&1 | tail -2
git push -u origin "$BRANCH_NAME" 2>&1 | tail -3
# ⚠️ 先查同分支 open PR（防重复创建）：
grape git-repo pulls list --owner "$ACCOUNT" --repo "$REPO_NAME" --state open --json-out 2>&1 | head -20
# 创建 PR（契约字段：title/head/base/inner_issue_nums——create 无 body 字段，@file 防转义）：
printf '%s' '{"title":"docs(blog): {主题}","head":"'$BRANCH_NAME'","base":"dev","inner_issue_nums":"'$ACCOUNT/$REPO_NAME'#'$ISSUE_NUMBER'","close_related_issue":true}' > /tmp/pr-body.json
grape git-repo pulls create --owner "$ACCOUNT" --repo "$REPO_NAME" \
  --json @/tmp/pr-body.json --json-out 2>&1 | head -30
# 从返回取 PR 编号（$PR_NUMBER 未注入时）——后续 update 与 A8 交办必须用真实编号
# PR 描述四段（变更说明/产物清单/文件变更/后续步骤）——create 后 pulls update 补 body：
printf '%s' '{"body":"### 变更说明\n新增博客文章：{主题}\n\n### 产物清单\n- HTML 文章：blog/{slug}/index.html\n- 封面+配图：{N} 张（cover.png + images/）\n- 介绍视频：intro.mp4（{有/无}）\n- 元数据：meta.json\n\n### 文件变更\n| 文件 | 说明 |\n|------|------|\n| `blog/{slug}/` | 博客产物目录 |\n| `blog/_tools/` | 博客通用工具（首次创建时）|\n\n### 后续步骤\n创建后 A2A 交办 SRE Agent 发布博客（跳过 QA——内容产物无需代码审查）。"}' > /tmp/pr-body-desc.json
grape git-repo pulls update --owner "$ACCOUNT" --repo "$REPO_NAME" --number {真实 PR 编号} --json @/tmp/pr-body-desc.json --json-out 2>&1 | head -20
# PR 链接用 Web 页面 /pull/（单数）markdown 格式——不得用 API 路径
```

### A8 · Issue 评论 + A2A 通知 SRE（必做，不可跳过）

```bash
# Issue 评论告知（长 body 用 @file）：
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[coding Agent] ✅ 博客内容已生成，请 SRE 发布 PR [#{n}](https://gitcode.com/'$ACCOUNT/$REPO_NAME'/pull/{n})。\n\n- 目录：blog/{slug}/\n- 配图：{N} 张\n- 视频：{有/无（降级原因）}\n- 博客主题:{主题}"}' --json-out
# ⚠️ 防重复：先查 pipeline，已含 sre:a2a_event 则不重复 A2A，只发评论
grape issues pipeline --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 交办 SRE（issue_number/pr_number 必填真实值——跳过 QA）：
grape a2a handoff --json '{"agent":"sre","payload":{"repository":"'$ACCOUNT/$REPO_NAME'","account":"'$ACCOUNT'","issue_number":{真实编号},"pr_number":{真实编号},"context":"博客内容已生成并提交 PR #{n}。博客目录: blog/{topic-slug}/。请使用博客发布技能：1. 合并 PR 2. 从 blog/ 目录读取文章+媒体 3. 上传媒体到博客服务器 4. 发布文章 5. 在 Issue 评论反馈发布结果。"}}'
# A2A 失败 → 重试 ≤3 次 → 仍失败：评论说明 + next_step 人工介入
```

## 场景 B · 内容优化（PR 反馈——按顺序执行）

### B1 · 理解审查反馈（必做）

```bash
# PR_NUMBER 缺失时先定位（评论/复审触发可能不带 PR 编号——不能默认有值）：
[ -n "$PR_NUMBER" ] || grape git-repo pulls list --owner "$ACCOUNT" --repo "$REPO_NAME" --state open --json-out 2>&1 | head -30
# 定位不到 open PR → Issue/PR 评论询问「请提供 PR 编号」，不猜测
# 读 PR 审查评论/反馈（逐条核对：图片/文字/排版问题）：
grape git-repo pulls get --owner "$ACCOUNT" --repo "$REPO_NAME" --number "${PR_NUMBER:-{定位到的编号}}" --json-out 2>&1 | head -60
grape git-repo pulls comments list --owner "$ACCOUNT" --repo "$REPO_NAME" --number "${PR_NUMBER:-{定位到的编号}}" --json-out 2>&1 | head -60
```

### B2 · 制定修改方案 + 实施（原子提交）

```bash
# 方案 = 问题点清单 → 每点修改策略（涉及文件 blog/{slug}/ 下产物——如需重新生成配图/视频，重新调用外部 AI API）
# ⚠️ 分支：从 B1 的 pulls get 返回的 head 字段取【真实分支名】（feat/blog-{slug}-{date}——不要用占位符 checkout）
git checkout {真实 head 分支名——pulls get 返回的 head 字段} 2>&1 | tail -2
# 实施：每个问题一个原子提交
git add {变更文件} && git commit -m "fix(blog): {修复点}" && git push 2>&1 | tail -3
```

### B3 · PR 评论告知（必做）

```bash
grape git-repo pulls comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$PR_NUMBER" \
  --json '{"body":"[coding Agent] 已按审查意见修改：{修改摘要}"}' --json-out
```

### B4 · A2A 通知 SRE（必做）

```bash
# 防重复 + 交办（同 A8——agent=sre，context 注明"已按审查意见修改，请复审"）
```

## Step 收尾 · 任务完成流程（必做——任何分支都必须执行到最后）

```bash
# 清理本技能临时产物（仅 /tmp/blog-gen-*）：
rm -rf /tmp/blog-gen-* 2>/dev/null || true
grape tasks complete --json '{
  "result_text":  "结论：{新生成/内容优化}处理完毕（{产物摘要 + PR 摘要}）",
  "actions":      ["场景识别: {新生成/优化}", "参考学习: {已学/无参考}", "文章撰写: {章节数/字数}", "产品调研: {已调研/不涉及}", "配图: {N 张/跳过}", "视频: {有/无/跳过}", "产物: blog/{topic-slug}/", "PR: #{pn}", "评论/A2A: sre"],
  "conclusion":   "{已生成并创建 PR #{pn}，A2A 交办 SRE 发布 / 已按审查意见修改完成}",
  "artifacts":    ["PR #{pn}", "分支 feat/blog-{topic}-{date}", "blog/{topic-slug}/ {文件清单}", "评论: {位置}"],
  "issue_summary":"{完成摘要——产物/PR/交办一句话}",
  "next_step":    "a2a_sre 或 等待用户反馈"
}'
```

> ⚠️ **结束信号**：tasks complete 后立即结束任务，不要继续思考或等待输入。A2A 交办成功 ≠ 任务结束（仍需 complete）。结构化字段 must 真实填充——结尾是下一节点的输入。

---

## 错误排查速查（命令返回异常时）

> ⚠️ 出错时**先看完整错误**（命令去掉 `| tail -N` 截断，`2>&1` 保留 stderr）；runbook 命令照抄仍失败，才允许 `grape commands <关键词>` / `grape <group> --help` 修正。**不反复盲试同一命令**。

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名抄错，核对本 runbook；仍不确定再 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 有契约不允许字段 → `grape <group> <verb> --help` 看 Body fields |
| `comments create` 失败（长 body 转义）| 改用 `--json @file`（body 先写文件）|
| `pulls create` 报字段错误 | 契约无 body/assignees——只用 title/head/base/inner_issue_nums；描述用 pulls update 补 |
| git push 失败 | 检查分支状态后重试 ≤1 次；仍失败报告 |
| 图片生成 API 403/429 | **停止重试**——评论报告，纯色占位图「待生成」→ 继续 |
| 视频生成 API 失败 | 跳过视频——文章标注「无视频版本」→ 继续提交 PR |
| AI 模型配置缺失 | 评论标注「跳过配图/视频，只提交文章」→ 继续（不借用其他 token/服务）|
| PR 创建重复 | 先查同分支 open PR（pulls list --state open）——有则不重复创建 |
| 401 凭据失效 | 说明「凭据已失效」即可，不换 token |
| 403 权限不足 | 说明需管理员配置——不绕行 |
| 报「契约过期/命令不识别」| 先 `grape refresh` 再重试 |