---
name: ai-blog-generation
description: |
  AI 博客生成技能。学习参考文章排版风格 → 撰写同风格主题文章 →
  AI 配图 + AI 视频 → 提交博客内容到代码仓 blog/ 目录并创建 PR →
  交办 SRE Agent 发布。整合了 git 操作与 PR 创建的工作流。
tools:
  - name: curl
    min_version: "7.68.0"
  - name: ffmpeg
    min_version: "4.2"
  - name: git
    min_version: "2.20"
requires:
  - env: BOT_TOKEN
    description: VCS API 访问令牌
  - env: REPO_FULL_NAME
    description: 仓库全名（owner/repo 格式）
  - env: ISSUE_NUMBER
    description: Issue 编号
  - env: BOT_USERNAME
    description: Bot 用户名
inputSchema:
  type: object
  required:
    - REPO_FULL_NAME
    - ISSUE_NUMBER
  properties:
    REPO_FULL_NAME:
      type: string
      pattern: "^[\\w-]+/[\\w-]+$"
      description: 仓库全名，owner/repo 格式
    ISSUE_NUMBER:
      type: integer
      minimum: 1
      description: GitCode Issue 编号
    BOT_TOKEN:
      type: string
      description: VCS API 访问令牌（从环境变量获取）
    BOT_USERNAME:
      type: string
      description: Bot GitCode 用户名
    REFERENCE_URL:
      type: string
      description: 参考文章 URL（可选）
    TOPIC:
      type: string
      description: 博客主题（可选，可从 Issue 正文提取）
outputSchema:
  type: object
  required:
    - actions
    - conclusion
    - artifacts
    - next_step
  properties:
    actions:
      type: array
      items:
        type: string
      description: 执行动作列表
    conclusion:
      type: string
      description: 处理结论
    artifacts:
      type: object
      properties:
        blog_dir:
          type: string
        branch:
          type: string
        pr_number:
          type: integer
        pr_url:
          type: string
        images:
          type: integer
        has_video:
          type: boolean
    next_step:
      type: string
      description: 下一步动作描述
    summary:
      type: string
      description: 任务摘要
---

## 安全硬约束（必须遵守）

1. **所有 API 信息（Key、URL、Model）从项目知识（Project Knowledge）中获取**，来自 `project-info/member/ai-models.yaml`。包含：
   - 图片生成：`ai_models.image`（url、key、model）
   - 视频生成：`ai_models.video`（url、key、model）
2. 调用 ModelArts API 只用此 Key，严禁从数据库 / 配置文件 / 日志 / 历史中寻找其他 token。
3. token 不得写入日志或回复。
4. API 返回 403 / 429 时：停止重试并报告用户。速率限制 2 req/s。
5. **长命令执行会静默**：视频生成约 30s，图片生成约 7s/张，提前告知用户等待。
6. 调用 VCS API 一律以 `$SKILL_DIR/references/vcs-api-reference.md` 为准，严禁根据经验/记忆/猜测自行拼写 API 路径。
7. API 返回 403/无权限时：立即停止该操作并回复用户「该操作需要管理员/维护者权限」，严禁尝试其他 token 或绕行手段。

# AI 博客生成 + PR 提交流程

## 核心原则

### 专注博客内容生成与 PR 提交
负责内容生成到 PR 创建：学习参考文章 → 规划主题 → 撰写文章 → 生成配图 → 生成视频 → 提交到仓库 blog/ 目录 → 创建 PR → **交办 SRE 发布**。

**SRE 职责（本技能绝对禁止执行以下操作）：**
- ❌ **禁止** 直接调用博客发布 API（curl/requests 调任何 blog API 都不行）
- ❌ **禁止** 直接上传文件到博客服务器
- ❌ **禁止** 直接创建/更新/删除博客文章
- ✅ **必须** 创建 PR 并通过 A2A 交办 SRE Agent

本技能的唯一发布出口是：**git commit + git push → GitCode PR → A2A 通知 SRE**。任何绕过此流程直接发布的行为都违反硬规则。

### 博客目录结构约定
博客产物统一提交到代码仓库的 `blog/` 目录（与 `src/` 同级）。
- `blog/_tools/`：共用工具/模板/样式文件（已存在则复用，不覆盖）
- `blog/{topic-slug}/`：每篇博客一个独立子目录，含 `index.html`、`intro.mp4`、`cover.png`、`images/`、`meta.json`
- `meta.json`：`{"title":"标题","description":"摘要","tags":["tag1"],"author":"Grape AI","date":"2026-08-24","featured_image":"cover.png"}`

### 三步模仿法
1. **学结构**：分析参考文章的标题层级、段落长度、配图密度、引用/高亮/表格等特殊元素的用法
2. **学风格**：分析语气（技术深度/轻松活泼/营销推广）、句式特点
3. **学排版**：分析配图位置、标签样式、元数据展示方式

### 依赖前序分析
通过 A2A 被调用时，prompt 顶部包含「前序 Agent 处理摘要」。
必须与用户确认参考文章和主题后再开始生成。

### 超出能力范围时主动请求支援
如需要发布到小红书/公众号等平台，通过 A2A 交办给发布技能（不经过本流程）。

## 场景识别

收到事件或 A2A 调用后，先判断触发场景：

| 特征关键词 | 场景 | 执行流程 |
|-----------|------|---------|
| 含「博客」「文章」「专栏」「生成文章」「写文章」「图文并茂」等 | **博客生成** | 按本文档流程执行 |
| 含「学习这个」「仿照这个」「参考这个」等 + URL | **参考文章学习** | 先抓取分析，再按博客生成流程 |
| 其他 | 不做处理，结束 | — |

## 前置依赖

```bash
# 系统包安装（仅缺失时执行）
apt-get install -y ffmpeg git

# Python 依赖在虚拟环境中安装（推荐）
python3 -m venv .venv && source .venv/bin/activate
pip install --index-url https://pypi.tuna.tsinghua.edu.cn/simple edge-tts Pillow requests
```

## 环境变量（系统注入）

| 变量 | 来源 | 说明 |
|------|------|------|
| `$BOT_TOKEN` | 系统 prompt 注入 | VCS API token（PRIVATE-TOKEN） |
| `$REPO_FULL_NAME` | 系统 prompt 注入 | 当前仓库全名（owner/repo） |
| `$ISSUE_NUMBER` | 系统 prompt 注入 | Issue 编号 |
| `$BOT_USERNAME` | 系统 prompt 注入 | Bot 用户名 |

## 工作流

### 1. 学习参考文章（如有）

用浏览器打开目标 URL，提取以下信息：

```python
# 使用 browser_navigate + browser_console 提取文章正文
# 用 document.body.innerText 获取全部文本
# 分析：标题层级、段落长度、配图数量、特殊元素（表格/引用/高亮块/标签）
```

输出分析结论：

| 分析维度 | 记录内容 |
|---------|---------|
| 标题风格 | 吸引型/技术型/营销型 |
| 段落结构 | 每段字数范围、配图间隔 |
| 特殊元素 | 是否有表格/引用块/高亮块/对比表格 |
| 语言风格 | 技术深度、是否使用第一人称 |
| 配图数量 | 每篇文章约几张 |

### 2. 撰写文章（HTML）

根据参考文章的风格，撰写同风格 HTML 文章。样式模板和内容要求详见 `references/article-template.md`。

### 3. 产品实物调研与视觉特征提取

**仅当博客主题涉及具体产品或品牌时执行此步骤。** 如主题为抽象概念、通用知识、纯教程，则跳过此步。

详见 `references/product-research.md`，包含：
- 3a. 定位产品官网（搜索引擎 + 浏览器提取）
- 3b. 提取视觉特征（颜色/设计/logo/场景）
- 3c. 将视觉特征注入生成提示词
- 3d. 提取真实产品 Logo 并保存（Pillow 裁剪 + 去底）

### 4. 生成配图

详见 `references/image-video-generation.md`，包含：
- 从项目知识获取 qwen-image API 信息
- 调用 ModelArts 图片生成 API
- 图片生成后叠加真实产品 logo
- 限流间隔 ≥ 1 秒

### 5. 生成视频

详见 `references/image-video-generation.md`（同上文件下半部分），包含：
- 从项目知识获取视频生成模型信息
- ⚠️ 禁止使用 I2V 模型，只能用 T2V 模型
- 视频 prompt 基于 visual_info 构造
- 下载视频 + Edge TTS 旁白 + ffmpeg 合成音视频

### 6. 组织产物并写入博客目录

确定 topic slug（从文章标题自动生成英文短横线名），在代码仓本地 `blog/` 下创建目录结构。

**如果 `blog/` 目录尚未存在，先创建它并初始化 `_tools/`：**
```bash
# 假设当前在仓库根目录
mkdir -p blog/_tools
cat > blog/_tools/README.md << 'TOOLSEOF'
# Blog Tools

此目录存放所有博客通用的工具/模板文件。
- `blog-styles.css` — 通用样式
- `article-template.html` — 文章 HTML 模板
TOOLSEOF
```

**如果 `blog/` 已有 `_tools/`，直接复用不覆盖已有文件。**

**将临时目录中的产物迁入博客子目录：**
```bash
TOPIC_SLUG="从标题自动生成的英文短横线名"
mkdir -p "blog/$TOPIC_SLUG/images"
cp /tmp/blog-gen-*/index.html "blog/$TOPIC_SLUG/index.html"
cp /tmp/blog-gen-*/intro.mp4 "blog/$TOPIC_SLUG/intro.mp4"
cp /tmp/blog-gen-*/cover.png "blog/$TOPIC_SLUG/cover.png"
cp /tmp/blog-gen-*/images/*.png "blog/$TOPIC_SLUG/images/" 2>/dev/null || true
```

**创建 meta.json：**
```bash
cat > "blog/$TOPIC_SLUG/meta.json" << JSONEOF
{
  "title": "博客标题",
  "description": "一句话摘要",
  "tags": ["tag1", "tag2"],
  "author": "Grape AI",
  "date": "$(date +%Y-%m-%d)",
  "featured_image": "cover.png"
}
JSONEOF
```

### 7. 提交 PR

**前置准备：** 确保仓库已克隆到本地且当前在正确的分支。从 `dev` 或 `main` 分出一个 feature 分支：

```bash
cd /path/to/repo
git fetch origin
BASE_BRANCH="dev"  # 或从仓库配置读取
BRANCH_NAME="feat/blog-${TOPIC_SLUG}-$(date +%Y%m%d)"
git checkout -b "$BRANCH_NAME" "origin/$BASE_BRANCH"
```

**阶段性提交（每个文件一个原子变更，方便审查）：**
```bash
# 1. 先提交 _tools/（如果没有变动则跳过）
if git diff --name-only --cached | grep -q '^blog/_tools/'; then
  git add blog/_tools/
  git commit -m "docs(blog): add shared blog tools and templates"
fi

# 2. 提交博客内容
git add "blog/$TOPIC_SLUG/"
git commit -m "docs(blog): add article '$BLOG_TITLE'

- HTML 文章
- 封面图 + 配图
- 5秒介绍视频
- 元数据 meta.json"
```

**推送并创建 PR（使用 Python 调用 VCS API）：**

```python
import json, urllib.request, os

TOKEN = os.environ.get("BOT_TOKEN", "")
REPO = os.environ.get("REPO_FULL_NAME", "")
BRANCH = os.environ["BRANCH_NAME"]
BASE_BRANCH = "dev"
TOPIC = "博客标题"

# 推送（使用 subprocess.run 替代 os.system，避免命令注入）
import subprocess
subprocess.run(["git", "push", "origin", BRANCH], check=True)

# 创建 PR
pr_body = json.dumps({
    "title": f"[博客] {TOPIC}",
    "head": BRANCH,
    "base": BASE_BRANCH,
    "body": f"## 变更说明\n\n新增博客文章：{TOPIC}\n\n## 文件变更\n\n"
            f"| 文件 | 说明 |\n"
            f"|------|------|\n"
            f"| `blog/{BRANCH.split('-', 2)[-1]}/` | 博客产物目录 |\n"
            f"| `blog/_tools/` | 博客通用工具（首次创建） |\n\n"
            f"## 后续步骤\n\n创建后交办 SRE Agent 发布博客。"
}).encode("utf-8")

req = urllib.request.Request(
    f"$VCS_API_BASE/repos/{REPO}/pulls",
    data=pr_body,
    method="POST"
)
req.add_header("PRIVATE-TOKEN", TOKEN)
req.add_header("Content-Type", "application/json")

with urllib.request.urlopen(req) as r:
    result = json.loads(r.read())
    pr_number = result.get("number", "")
```

**在 Issue 发评论告知 PR 已创建（评论 body 前缀 `[coding Agent]`）：**

```bash
curl -s --max-time 30 -X POST \
  -H "PRIVATE-TOKEN: $BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"body": "[coding Agent] ✅ 博客已提交\n\n博客文章已生成并通过 PR #PR_NUMBER 提交到仓库。\n\n- 目录：blog/TOPIC_SLUG/\n- 分支：BRANCH_NAME\n- PR：'$REPO_FULL_NAME'/pull/PR_NUMBER\n\n下一步由 SRE Agent 进行博客发布。"}' \
  "$VCS_API_BASE/repos/$REPO_FULL_NAME/issues/$ISSUE_NUMBER/comments"
```

### 8. ✅ 交办 SRE 发布（必须执行）

PR 创建后，**必须**通过 A2A 通知 SRE Agent 进行博客发布。传递的上下文中包含 PR 信息，SRE 需 PR 合并后才能发布：

```bash
# 构造 A2A 上下文
A2A_CONTEXT='{
  "agent": "sre",
  "context": "博客内容已生成并提交到代码仓库。\n\n- 仓库：'$REPO_FULL_NAME'\n- 分支：'$BRANCH_NAME'\n- PR 编号：'$PR_NUMBER'\n- 博客目录：blog/'$TOPIC_SLUG'/（仓库内与 src/ 同级）\n- 博客主题：'$TOPIC'\n\n请完成以下步骤：\n1. 合并 PR\n2. 从 blog/ 目录读取文章内容\n3. **上传发布到目标博客网站**\n4. 在 Issue 评论反馈发布结果"
}'

curl -X POST {{SERVER_URL}}/api/a2a \
  -H "Authorization: Bearer {{A2A_TOKEN}}" \
  -H "Content-Type: application/json" \
  -d "$A2A_CONTEXT"
```

> ⚠️ `{{SERVER_URL}}` 和 `{{A2A_TOKEN}}` 从项目知识中获取，勿硬编码。

## 硬规则

| 行为 | 态度 | 读写语义 |
|------|------|----------|
| 按场景识别结果执行对应流程 | ✅ **必须做** | — |
| 先学习参考文章再写 | ✅ **必须做，不可跳过** | 读（自动执行） |
| 配图间隔分布，不连续堆叠 | ✅ **必须做** | — |
| 文章顶部嵌入视频 | ✅ **必须做（如有）** | — |
| 至少包含一个特殊元素 | ✅ **表格/引用/高亮块至少选一个** | — |
| 涉及具体产品时先官网调研再生成配图/视频 | ✅ **必须做（不可跳过）** | 读（自动执行） |
| 图片/视频 prompt 必须包含 real product 视觉特征 | ✅ **必须做（颜色、logo、前脸等须官网核实）** | — |
| 图片生成后必须叠加真实产品 logo | ✅ **必须做（logo_overlay.png 存在时不可跳过）** | — |
| 每次 API 调用间隔 ≥ 1 秒 | ✅ **必须做（防限流）** | — |
| 博客产物必须提交到仓库 blog/ 目录而非临时路径 | ✅ **必须做** | — |
| blog/_tools/ 已存在时复用它，不覆盖已有文件 | ✅ **必须做** | — |
| 从 dev 分支分出 feature 分支 | ✅ **必须做** | 写（须确认） |
| 提交博客产物到仓库前需用户确认 | ✅ **必须做** | 写（须确认） |
| 执行写操作前（如 git push、PR 创建、A2A 交办）须先向用户确认 | ✅ **必须做** | — |
| 执行删除操作前（如删除临时文件、删除博客产物）须先向用户确认 | ✅ **必须做** | — |
| 提交 PR 后在 Issue 发评论告知 | ✅ **必须做，不可跳过** | 写（须确认） |
| 创建 PR 后 A2A 通知 SRE 发布 | ✅ **必须做，不可跳过** | 写（须确认） |
| 任务结束输出 JSON 块 | ✅ **必须做，不可跳过** | — |
| 工作流结束后清理临时目录 /tmp/blog-gen-*/ | ✅ **必须做** | — |
| 分支名使用时间戳确保唯一，避免多实例冲突 | ✅ **必须做** | — |
| PR 创建前检查是否已存在同内容 PR | ✅ **必须做（幂等性）** | — |
| 直接合并 PR | ❌ **禁止（仅创建，合并由 SRE 执行）** | — |
| 修改 blog/ 以外仓库文件 | ❌ **禁止（除非博客工具初始化）** | — |
| 直接调用博客发布 API（curl/requests 调用 blog 相关 API） | ❌ **禁止（SRE 职责）** | — |
| 直接上传文件到博客服务器 | ❌ **禁止（SRE 职责）** | — |
| 直接创建/更新/删除博客文章 | ❌ **禁止（SRE 职责）** | — |
| 未经用户确认执行删除/清理操作 | ❌ **禁止** | — |
| 仅凭模型预训练记忆生成产品外观不核实官网 | ❌ **禁止（须先执行步骤 3 产品调研）** | — |
| 使用 I2V（图生视频）模型生成视频 | ❌ **禁止（只能用 T2V 文生视频模型）** | — |

## 输出格式

任务完成后，**必须在最终答复末尾输出结构化 JSON 块**：

```json
{
  "actions": ["blog_generation", "pr_created", "a2a_to_sre"],
  "conclusion": "completed",
  "artifacts": {
    "blog_dir": "blog/{topic-slug}/",
    "branch": "feat/blog-{topic}-{date}",
    "pr_number": 123,
    "pr_url": "https://gitcode.com/{owner}/{repo}/pull/123",
    "images": 5,
    "has_video": true
  },
  "next_step": "已创建 PR 并 A2A 通知 SRE Agent 合并后发布博客",
  "summary": "已生成图文并茂的博客文章，提交到仓库 blog/ 目录，创建 PR 并交办 SRE 发布"
}
```

**不输出 JSON 块视为任务未完成。**

## 性能预算

| 指标 | 预算值 | 说明 |
|------|--------|------|
| Skill 加载时延 | < 3s | SKILL.md ~15KB + 2 references ~10KB |
| P95 执行时延 | < 120s | 不含用户交互等待；图片 ~7s/张 × N + 视频 ~30s + 其他 |
| LLM 调用次数 | ≤ 6 次 | 参考文章分析(1) + 文章撰写(1) + 产品调研(1) + prompt 构造(1) + 评论生成(1) + 容错(1) |
| Token 消耗 | ≤ 10000 tokens | SKILL.md ~3000 + references ~2500 + 运行时上下文 ~4500 |
| 上下文压缩 | 超过 8000 tokens 时触发 | 自动压缩早期分析，保留最近步骤 |

## 版本管理策略

- 当前版本：v1.0（frontmatter 不声明 version 字段，遵循 v1.0 规范）
- 变更日志记录在仓库 CHANGELOG.md 中
- 向后兼容策略：outputSchema 新增字段为可选（非 required），不破坏下游解析
- 灰度机制：通过 GitCode 分支管理（dev → main），合并前需通过三阶段测试

## 断点续跑机制

若会话因超时或中断重启，按以下策略恢复进度：

1. **检查临时目录**：`ls /tmp/blog-gen-*/` 确认中间产物是否存在（index.html、images/、intro.mp4 等）
2. **检查 git 分支**：`git branch | grep feat/blog-` 确认是否已创建分支和提交
3. **检查 PR 状态**：通过 VCS API 查询是否已有同标题 PR
4. **检查 Issue 评论**：是否已有 `[coding Agent]` 前缀的评论
5. **从最后完成的步骤继续**：跳过已完成的步骤，从下一步继续执行

## 工具失败降级策略

| 失败场景 | 降级方案 |
|----------|----------|
| 图片生成 API 失败（403/429） | 停止重试，在 Issue 评论中报告，使用纯色占位图标记「待生成」 |
| 视频生成 API 失败 | 跳过视频步骤，文章标记为「无视频版本」，继续提交 PR |
| 浏览器提取文章失败 | 改用 curl 直接下载 HTML 页面并解析 |
| Edge TTS 语音合成失败 | 跳过旁白，使用无音频视频 |
| GitCode PR 创建失败 | 在 Issue 评论中手动贴出产物路径，通知 SRE 手动处理 |

## 幂等性保证

| 操作 | 幂等策略 |
|------|----------|
| git push | push 前检查远程分支是否已存在同名分支，存在则切换到该分支继续 |
| PR 创建 | 创建前 GET /repos/:owner/:repo/pulls?head=BRANCH 查询是否已有同分支 PR，存在则更新而非重复创建 |
| A2A 通知 | A2A payload 携带 idempotency_key（issue_number + skill_name + timestamp），SRE 端去重 |
| 评论发布 | 评论 body 含唯一标识 `<!-- blog-gen:{issue_number}:{timestamp} -->`，发布前查询已有评论 |

## 资源清理

工作流结束后（PR 创建 + A2A 通知完成后），执行清理：

1. **清理临时目录**：`rm -rf /tmp/blog-gen-$$`（经用户确认后执行）
2. **清理临时分支**：如 PR 已创建，本地 feature 分支可保留（远端跟踪用）；如 PR 创建失败，删除本地分支
3. **确认产物完整性**：blog/{topic-slug}/ 目录下 index.html、cover.png、images/、intro.mp4、meta.json 齐全

## 生命周期声明

本 skill 负责 create/update 操作（创建博客产物、提交 PR、A2A 通知），不负责 delete 操作。博客产物的删除、PR 的关闭由下游 SRE 或管理员手动处理。

## 参考

- `$SKILL_DIR/references/product-research.md` — 产品实物调研与视觉特征提取（步骤 3 详细实现）
- `$SKILL_DIR/references/image-video-generation.md` — 图片与视频生成（步骤 4、5 详细实现）
- `$SKILL_DIR/references/vcs-api-reference.md` — VCS API 调用规范
- qwen-image 图片生成：`POST /v1/images/generations`（URL/Key/Model 从项目知识获取）
- Wan2.2 T2V 视频生成：`POST /v1/video/generations`（URL/Key/Model 从项目知识获取，只能用 T2V 模型，禁止 I2V）
- Edge TTS：`edge-tts --voice zh-CN-XiaoxiaoNeural --text "文案" --write-media output.mp3`
- A2A 端点：`POST {{SERVER_URL}}/api/a2a`（URL 和 Token 从项目知识获取）