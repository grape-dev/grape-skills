---
name: blog-publish
description: "Use when publishing, editing, deleting, or listing blog posts via the Blog System API. Also handles mood publishing, comments, messages, labels, and media uploads. Invoked via A2A by the coding Agent after blog content generation."
author: Hermes Agent
license: MIT
version: 2.1.0
tools:
  - name: curl
    min_version: "7.68.0"
  - name: python3
    min_version: "3.8"
  - name: grape
    min_version: "0.3.2"
requires:
  - env: GRAPE_SERVER_URL
    description: 平台服务地址（CLI 自动读取）
  - env: GRAPE_SESSION_TOKEN
    description: 会话令牌（CLI 自动读取——禁止手动使用）
  - env: REPO_FULL_NAME
    description: 仓库全名（owner/repo——REPO_NAME 派生之源）
  - env: ACCOUNT
    description: 仓库属主（--owner）
  - env: REPO_NAME
    description: 仓库名（--repo）
  - env: ISSUE_NUMBER
    description: 关联 Issue 编号（结果汇报落点）
  - env: PR_NUMBER
    description: 待合并 PR 编号（A2A context 注入）
inputSchema:
  type: object
  required:
    - BLOG_HOST
  properties:
    BLOG_HOST:
      type: string
      description: 博客系统外部地址（IP:PORT 或域名）——解析顺序：知识基线 blog-config.yaml → 上下文 → 询问
    PR_NUMBER:
      type: integer
      description: 待合并 PR 编号
    BLOG_OUTPUT_DIR:
      type: string
      description: 博客产物目录（A2A context 提供——缺省 /root/grape-workspaces/{owner}/{repo}/issues/{issue_number}/coding/blog_output/）
outputSchema:
  type: object
  required:
    - actions
    - conclusion
    - next_step
  properties:
    actions:
      type: array
      items:
        type: string
    conclusion:
      type: string
    artifacts:
      type: object
      properties:
        article_id:
          type: integer
        article_url:
          type: string
        media_uploads:
          type: integer
    next_step:
      type: string
    issue_summary:
      type: string
metadata:
  hermes:
    tags: [blog, publishing, api, content, sre]
    related_skills: [ai-blog-generation, blog-issue]
---

# 博客发布（blog-publish v2.1 · grape CLI）

> 把已生成的博客产物发布到**外部博客系统**（独立部署的 FastAPI + MySQL 服务——非平台组件）。发布链路 = 合并 PR → 读取 `blog/` 产物目录 → 上传媒体 → 发布文章 → Issue 评论反馈。触发：A2A context 收到 coding Agent 交办（含 PR 编号 + 博客目录），或用户直接要求发布/编辑/删除文章、发说说/留言/评论、建标签/用户。

## 一、安全硬约束（必须遵守）

1. ⚠️ 平台侧操作一律 grape CLI——**禁止** curl 直连平台 API
2. ✅ 博客系统 = **外部系统**——BLOG_HOST API 直连**合法**（与 grape 平台 API 隔离）——本技能唯一直接调用的外部 API 面（runbook P1-P6）
3. ⚠️ 写操作（发布/更新/删除/硬删/恢复）执行前**用户确认**（A2A 链路 = 发布动作在 Issue 评论或上下文明示后执行；直接交互 = 逐次确认）
4. ⚠️ 禁止硬删（`soft=false`）——除非用户逐次显式确认（破坏性不可恢复）
5. ⚠️ 媒体上传失败不阻塞发布——但必须如实报告「pending upload」清单（不隐藏缺失）
6. ⚠️ 合并 PR 失败不阻塞发布——跳过合并从本地产物直接发布 + 如实报告（发布链路优先原则）
7. ⚠️ 发布内容 = 产物目录 HTML——**禁止**二次改写正文（标题/封面提取除外）——内容一致性由上游链路保证

## 二、环境变量表（平台注入 + 外部解析值）

| 变量 | 说明 | 状态 |
|---|---|---|
| `GRAPE_SERVER_URL` | 平台服务地址（CLI 自动读）| CLI 域 |
| `GRAPE_SESSION_TOKEN` | 会话令牌（CLI 自动读）| CLI 域 |
| `REPO_FULL_NAME` | 仓库全名（派生 `REPO_NAME`）| 派生之源 |
| `ACCOUNT` / `REPO_NAME` | 平台操作实参（--owner/--repo）| 使用 |
| `ISSUE_NUMBER` | 结果汇报落点 | 使用 |
| `PR_NUMBER` | 待合并 PR 编号（A2A 注入）| 使用 |
| `BLOG_HOST` | **外部博客系统地址**（外部解析值——非平台注入）| 使用 |
| `BLOG_OUTPUT_DIR` | 博客产物目录（缺省约定路径）| 使用 |

> 平台注入变量由服务端在 prompt 内联提供（Agent 可溯源）；`BLOG_HOST` 为**外部值**（解析顺序：知识基线 blog-config.yaml → 上下文 → 工作区 → 询问——见 runbook Step 0）。

## 三、前置检查门（自愈 → 重试 → STOP）

| 检查 | 不通过时 |
|---|---|
| CLI 可用（`grape --version` ≥ 0.3.2）| 按 references/grape-cli-installation.md 自愈 |
| 契约刷新（`grape refresh`——失败重试 ≤2 次后继续）| 重试后继续 |
| 任务上下文（`grape tasks current`——A2A payload 在这里）| 缺 context 时按 4.2 兜底 |
| 博客系统可达（`curl {BLOG_HOST}/health`——BLOG_HOST 未提供或不可达）| 报告用户 + 重试 3 次（间隔 5s）→ 仍不可用 → **P3 内容 PR 合并照常**（`grape git-repo pulls merge`，不依赖 BLOG_HOST）→ 博客 API 发布（P2/P4-P6）跳过 + 如实报告「博客 API 未发布：BLOG_HOST 未提供/不可达」——不假装成功 |

## 四、技能定义与执行

### 4.1 定位与职责边界
- ✅ 发布/编辑/软删/恢复/硬删（硬删需逐次确认）文章；上传媒体；发说说/留言/评论；建标签/用户
- ✅ 合并 PR（`grape git-repo pulls merge`——A2A 链路第一步）
- ❌ 生成博客内容（coding 技能职责）；产出 Spec（blog-issue 职责）；不修改博客系统代码

### 4.2 场景路由（入口 → 路径）
| 场景 | 判定 | 路径 |
|---|---|---|
| 发布（A2A 主流程）| context 含 PR 编号 + 博客目录 | P1-P6 + 收尾 |
| 编辑/删除/恢复 | 用户直接要求或 Issue 明确 | runbook 附录 A |
| 其他操作（说说/留言/评论/标签/用户）| 用户明确要求 | runbook 附录 B |
| 无法判定 | 检查 Issue 上下文（spec/评论）→ 仍无 → 询问用户 | — |

### 4.3 处理流程（统一骨架）
```
P1 健康检查     → curl {BLOG_HOST}/health（不可达/未提供 → 不 STOP 全链：P3 合并照常，博客 API 发布降级如实报告）
P2 获取标签     → curl {BLOG_HOST}/api/lables（无匹配则新建——写操作确认）
P3 合并 PR      → grape git-repo pulls merge（A2A 链路——失败不阻塞）
P4 媒体上传     → 遍历产物目录 → POST /api/upload → HTML src/poster 替换为 /uploads/ 路径
P5 提取元数据   → <h1> 标题 + poster/img 封面
P6 发布文章     → POST /api/articles（写操作——先确认）→ GET 验证
收尾           → Issue 评论反馈 + grape tasks complete
```
（详见 runbook——每个 P 有确切命令与判定）

### 4.4 命令标准（子集与坑点）
**平台命令（grape——必有 tk_ 会话 token）**：
```
grape --version / refresh / tasks current        # 就绪与上下文
grape git-repo pulls merge --owner --repo --number   # 合并 PR（session-only）
grape git-repo issues comments create --number --json '{"body":"..."}'   # 发布结果反馈
grape tasks complete --json '{"result_text":..., "actions":[...], ...}'  # 收尾
```
**外部命令（BLOG_HOST——curl 直连合法）**：`curl -s https://$BLOG_HOST/health|/api/lables|...`（runbook P1-P6/附录全量）
**坑点**：
- pulls merge / issues comments create / tasks complete 均 session-only——API key（grape_ 前缀）直调 403——Agent 环境天然有 tk_
- `grape tasks complete --json` 支持多行（multi-line, no escaping）——长 payload 直接整块写
- 完整命令面与 ❌ 警示表见 `references/grape-cli-reference.md`（如 `grape api`、`grape git <verb>` 不存在）

### 4.5 故障决策表
| 故障 | 决策 |
|---|---|
| BLOG_HOST 未提供 / 博客 API 不可达 | 报告用户 + 重试 3 次（间隔 5s）→ 仍不可用 → **P3 内容 PR 合并照常**（入库主线不丢）+ 博客 API 发布跳过（P2/P4-P6）+ 评论/result_text 如实注明「博客 API 未发布：BLOG_HOST 未提供/不可达」——不假装成功 |
| 媒体上传失败 | 跳过该文件标记「pending upload」，其余继续 |
| 发布失败（500）| 按标题查重（可能已存在）→ 重试 1 次 |
| PR 合并失败 | 报告用户 + 建议人工合并 → 继续从本地产物发布（不阻塞）|
| PR 不存在 / 编号缺失 | 跳过合并步骤——直接从产物目录发布 + Issue 评论说明 |

### 4.6 输出格式（固定产物）
```json
{
  "result_text": "结论：博客发布{成功/失败}（{article_id/article_url/媒体统计}）",
  "actions": ["health_check", "label_query", "pr_merge", "media_upload", "article_publish", "verify", "issue_report"],
  "artifacts": {"article_id": N, "article_url": "https://{BLOG_HOST}/article/N", "media_uploads": M},
  "conclusion": "文章已发布（或：发布失败原因）",
  "next_step": "a2a 结果已回传 Issue {ISSUE_NUMBER}——等待用户验收或下一个任务",
  "issue_summary": "博客文章已发布：{标题} | article_id=N | url=..."
}
```
未输出 JSON = 任务未完成。产物结构约定（与上游 coding 链路一致）：`blog/{topic-slug}/` 下 `index.html` + `images/` + `intro.mp4` 等。

### 4.7 写操作协议
| 动作 | 确认要求 |
|---|---|
| POST/PUT/DELETE（发布/更新/软删/恢复/建标签/建用户/说说/留言/评论）| 执行前**用户确认**（A2A 链路 = 上下文明示后执行）|
| DELETE `soft=false`（硬删）| **逐次显式确认**（不可恢复——硬约束④）|
| 媒体路径替换（src/poster → /uploads/）| 必做（不做 = 文章内媒体 404——硬约束⑤ pending 如实报）|
| 标题去重（发前 keyword 查重）| 幂等——重复标题不重复发 |

### 4.8 任务收尾（必做）
收尾顺序：**先 Issue 评论反馈发布结果 → 再 `grape tasks complete`**（评论确保用户可追溯）：
```bash
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[blog-publish Agent] 博客已发布：{标题} | article_id={n} | {BLOG_HOST}/article/{n}（{媒体统计/pending}）"}' --json-out
grape tasks complete --json '{
  "result_text": "结论：博客发布成功（article_id={n} | {BLOG_HOST}/article/{n} | 媒体 {n} 个）",
  "actions": ["health_check", "label_query", "pr_merge", "media_upload", "article_publish", "verify", "issue_report"],
  "artifacts": {"article_id": {n}, "article_url": "https://{BLOG_HOST}/article/{n}", "media_uploads": {n}},
  "conclusion": "文章已发布",
  "next_step": "结果已回传 Issue {ISSUE_NUMBER}——等待用户验收",
  "issue_summary": "博客文章已发布：{标题} | article_id={n} | url={BLOG_HOST}/article/{n}"
}'
```
评论前缀固定 `[blog-publish Agent]`（链路角色标识——与 coding / blog-issue 各自前缀区分）。A2A 链路位置：上游 = coding Agent（A2A context：PR_NUMBER + 博客目录）；下游 = Issue 评论反馈（供 blog-issue 收尾复盘）。

## 五、参考文件清单

| 文件 | 用途 |
|---|---|
| `references/blog-publish-runbook.md` | **执行主路径**：Step 0 + P1-P6 命令与判定 + 附录 A（编辑/删除/恢复）+ 附录 B（其他操作）+ 错误排查 + 断点续跑 |
| `references/grape-cli-reference.md` | 本技能平台命令面（3 写 2 读）+ ❌ 警示表（8 条）|
| `references/grape-cli-installation.md` | CLI 版本要求与安装/自愈 |

## 六、Best Practices（实践积累区）

- **BLOG_HOST 是外部值**：不来自平台注入——按解析顺序（知识基线 → 上下文 → 工作区 → 询问）确定，绝不猜地址；博客系统无鉴权——**不臆造凭据、不把平台 token 发给外部系统**
- **断点续跑**（沿用旧版 Resume 机制）：`/tmp/blog_article.json` 存在 → 跳 P5 直接 P6；HTML 已替换 `/uploads/` → 跳 P4b；标题查重已有 → 不重复发布
- **发布链路优先**：合并 PR 失败不阻塞发布（本地产物直接发）——追溯性和上线速度冲突时上线优先，但要如实报告 + 建议人工合并
- **媒体挂掉是最高频故障**：P4 替换漏项 → 验证环节必须检查 HTML 无相对路径残留（`src="intro.mp4"` 之类一个都不能留）