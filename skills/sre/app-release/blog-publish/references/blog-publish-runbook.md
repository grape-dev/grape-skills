# blog-publish 执行手册（runbook）· grape CLI + 外部 BLOG_HOST API

> 配套 `../SKILL.md`。**平台侧命令**用 `grape`（A2A 接收 / PR 合并 / Issue 评论 / 收尾）；**博客系统命令**用 curl 直连外部 `BLOG_HOST`（合法——硬约束②）。完整命令面查询见 `grape-cli-reference.md`。

---

## Step 0 · 初始化（CLI 自愈 + 上下文获取）

前置门 4 项（SKILL 三）按序执行——任何一项失败按安装手册自愈或按故障表决策：

```bash
grape --version                          # ≥ 0.3.2；低于则按 grape-cli-installation.md 升级
grape refresh 2>&1 | tail -2             # 契约刷新（失败重试 ≤2 次后继续）
grape tasks current --json-out           # 当前任务上下文：A2A payload（PR_NUMBER + 博客目录 + 发布目标）在这里
```

**上下文清单**（缺哪个补哪个）：`PR_NUMBER`（待合并 PR）、`BLOG_OUTPUT_DIR`（博客产物目录——缺省 `/root/grape-workspaces/{owner}/{repo}/issues/{issue_number}/coding/blog_output/` 或按 `blog/{topic-slug}/` 定位）、`BLOG_HOST`（解析顺序见下）。

**`BLOG_HOST` 解析顺序**（沿用外部值约定——**取到值后立即导出** `export BLOG_HOST="<取到的值>"`——后续 bash curl 与 python `os.environ["BLOG_HOST"]`（P4）直接引用，未导出则两者皆空/KeyError）：
1. 知识基线 `project-info/member/blog-config.yaml`（或类似配置）的 `blog.host` 字段
2. A2A context / 当前对话上下文已含 → 直接用
3. 工作区 `project-info/` 目录搜索部署地址文件
4. 以上皆无 → **询问用户**（不猜测地址）

---

## 场景路由判定

| 信号 | 场景 | 路径 |
|---|---|---|
| context 含 PR 编号 + 博客目录 | 发布（A2A 主流程）| P1 → P6 → 收尾 |
| 用户明确要求编辑/删除/恢复 | 编辑/删除/恢复 | 附录 A |
| 用户明确要求说说/留言/评论/标签/用户 | 其他操作 | 附录 B |
| 不明 | 看 Issue 上下文（Spec/评论）→ 仍无法判定 → 询问用户 | — |

---

## P1 · 健康检查（必做——先于一切博客 API 操作）

```bash
curl -s "https://$BLOG_HOST/health"
```
- 期望：`{"status":"ok","service":"blog-api","version":"1.0.0"}`
- 失败 / BLOG_HOST 未提供：报告用户 + 重试 3 次（间隔 5s）→ 仍不可用 → **不 STOP 全链**：P3 内容 PR 合并照常（不依赖 BLOG_HOST）→ 博客 API 发布（P2/P4-P6）跳过 + 评论/result_text 如实注明「博客 API 未发布：BLOG_HOST 未提供/不可达」（对齐 SKILL 4.5）

---

## P2 · 获取标签列表（发布主流程必做）

```bash
curl -s "https://$BLOG_HOST/api/lables"
```
- 常见标签：1=技术 2=生活 3=随笔 4=教程
- 主题无匹配标签（如产品介绍/美食）→ **新建标签**（写操作——用户确认后执行）：
  ```bash
  curl -s -X POST "https://$BLOG_HOST/api/lables" -H "Content-Type: application/json" -d '{"lname":"美食"}'
  ```

---

## P3 · 合并 PR（A2A 链路——grape CLI）

```bash
grape git-repo pulls merge --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$PR_NUMBER" 2>&1 | tail -3
```
- 成功 → 继续 P4；失败/PR 不存在/编号缺失 → 报告用户（建议人工合并）→ **跳过合并步骤直接发布**（SKILL 4.5——发布链路优先，不阻塞）
- 说明：合并动作是发布链路的第一步（保证产物入库可追溯）；失败不中断发布（内容产物已在工作区本地）

---

## P4 · 媒体上传 + HTML 路径替换（核心——必做）

产物目录下的图片/视频必须**先上传**再发文章——否则文章内媒体 404。

```python
import os, json, glob
import requests

BLOG_HOST = os.environ["BLOG_HOST"]
OUTPUT_DIR = os.environ.get("BLOG_OUTPUT_DIR", "/root/grape-workspaces/{owner}/{repo}/issues/{issue_number}/coding/blog_output/")
UPLOAD_URL = f"https://{BLOG_HOST}/api/upload"

# 4a: 上传全部媒体（记录 rel_path -> upload_url；失败文件记入 pending 清单——不中断）
upload_map = {}      # rel_path -> /uploads/xxx
pending = []         # 上传失败文件（如实报告——不得隐藏）
for ext in ["*.png", "*.jpg", "*.jpeg", "*.gif", "*.mp4"]:
    for fp in glob.glob(os.path.join(OUTPUT_DIR, "**", ext), recursive=True):
        rel = os.path.relpath(fp, OUTPUT_DIR)
        with open(fp, "rb") as f:
            resp = requests.post(UPLOAD_URL, files={"file": f}, timeout=60)
        d = resp.json()
        if d.get("code") == 200:
            upload_map[rel] = d["data"]["url"]
            print(f"  [ok] {rel} -> {d['data']['url']}")
        else:
            pending.append(rel)
            print(f"  [FAIL] {rel}: {resp.text}")

# 4b: 替换 index.html 中相对路径为上传 URL（先长后短避免前缀误替换）
html_path = os.path.join(OUTPUT_DIR, "index.html")
with open(html_path, "r", encoding="utf-8") as f:
    html = f.read()
for rel_path, upload_url in sorted(upload_map.items(), key=lambda x: -len(x[0])):
    html = html.replace(f'src="{rel_path}"', f'src="{upload_url}"')
    html = html.replace(f'poster="{rel_path}"', f'poster="{upload_url}"')
with open(html_path, "w", encoding="utf-8") as f:
    f.write(html)
print(f"HTML updated（替换 {len(upload_map)} 个媒体路径；pending={len(pending)}）")
# pending 非空时：发布后必须在 Issue 评论如实列出（SKILL 硬约束⑤）
```

**关键点**：`src="intro.mp4"`、`poster="cover.png"`、`src="images/theme_1.png"` 等全部替换为 `/uploads/xxx`——一个没换 = 那个媒体在文章页挂掉。

---

## P5 · 提取标题与封面（发布元数据）

```python
import re

with open(os.path.join(OUTPUT_DIR, "index.html"), "r", encoding="utf-8") as f:
    html = f.read()

m = re.search(r"<h1[^>]*>(.*?)</h1>", html, re.DOTALL)
BLOG_TITLE = m.group(1).strip() if m else "无标题"

BLOG_IMG = ""
m = re.search(r'poster="(/uploads/[^"]+)"', html)
if m:
    BLOG_IMG = m.group(1)
else:
    m = re.search(r'<img[^>]+src="(/uploads/[^"]+)"', html)
    if m:
        BLOG_IMG = m.group(1)

print(f"Title: {BLOG_TITLE}")
print(f"Cover: {BLOG_IMG}")
```

---

## P6 · 发布文章（写操作——先确认）

> ⚠️ **写操作确认**（SKILL 硬约束③）：A2A 链路 = 用户的发布期望已在 Issue/上下文明示（「请使用博客发布技能…发布文章」）；直接交互 = 发出前向用户确认标题/标签/是否发布。

**发前查重**（幂等——标题已存在则不重复发）：
```bash
curl -s "https://$BLOG_HOST/api/articles?keyword=$BLOG_TITLE" | head -c 500
```

```python
import json

article = {
    "title": BLOG_TITLE,
    "content": open(os.path.join(OUTPUT_DIR, "index.html"), encoding="utf-8").read(),  # 已替换上传 URL 的完整 HTML
    "uid": 1,        # 缺省作者（admin）
    "lid": LABEL_ID, # 来自 P2
    "img": BLOG_IMG,
    "heat": 0
}
with open("/tmp/blog_article.json", "w", encoding="utf-8") as f:
    json.dump(article, f, ensure_ascii=False)
```

```bash
curl -s -X POST "https://$BLOG_HOST/api/articles" \
  -H "Content-Type: application/json" \
  -d @/tmp/blog_article.json
```
- 期望：`{"code":200,"message":"文章发布成功","data":{"id":N}}` → `ARTICLE_ID=N`
- 500 失败：按标题查重（可能已存在）→ 重试 1 次 → 仍失败报告用户

**验证**：
```bash
curl -s "https://$BLOG_HOST/api/articles/$ARTICLE_ID"
echo "https://$BLOG_HOST/article/$ARTICLE_ID"
```
- 校验 title/content 正确、页面可达、媒体路径为 `/uploads/`（无相对路径残留）——图片视频能加载

---

## 收尾（必做——先评论后 complete）

**1. 发布结果 → Issue 评论**（grape CLI——确保用户可追溯）：
```bash
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[blog-publish Agent] 博客已发布：{标题} | article_id='$ARTICLE_ID' | $BLOG_HOST/article/'$ARTICLE_ID'\n媒体上传 {成功数} 个（{pending 清单——从 P4 输出取,非空时列出}）（PR #{PR_NUMBER} 已合并）"}' --json-out
```

**2. 清理临时文件**（发布临时 JSON——技能自己的产物，非用户数据）：
```bash
rm -f /tmp/blog_article.json
```

**3. 任务收尾**（结构见 SKILL 4.8）：
```bash
grape tasks complete --json '{
  "result_text": "结论：博客发布成功（article_id='$ARTICLE_ID' | '$BLOG_HOST'/article/'$ARTICLE_ID' | 媒体 '$UPLOAD_COUNT' 个（{pending 清单——从 P4 输出取,非空时列出}）",
  "actions": ["health_check", "label_query", "pr_merge", "media_upload", "article_publish", "verify", "issue_report"],
  "conclusion": "文章已发布",
  "next_step": "结果已回传 Issue '$ISSUE_NUMBER'——等待用户验收",
  "issue_summary": "博客文章已发布：'$BLOG_TITLE' | article_id='$ARTICLE_ID' | url='$BLOG_HOST'/article/'$ARTICLE_ID'"
}'
```

---

## 附录 A · 编辑 / 删除 / 恢复（用户明确要求时）

| 操作 | 命令 | 确认 |
|---|---|---|
| 更新文章 | `curl -s -X PUT "https://$BLOG_HOST/api/articles/{id}" -H "Content-Type: application/json" -d '{"title":"新标题","content":"新内容"}'` | 须确认（写）|
| 软删（可恢复）| `curl -s -X DELETE "https://$BLOG_HOST/api/articles/{id}"` | 须确认（写）|
| 硬删（永久）| `curl -s -X DELETE "https://$BLOG_HOST/api/articles/{id}?soft=false"` | **逐次显式确认**（硬约束④）|
| 恢复 | `curl -s -X POST "https://$BLOG_HOST/api/articles/{id}/restore"` | 须确认（写）|

> 更新内容为**用户提供的全文**——禁止从产物目录二次改写（内容一致性由上游保证）。

## 附录 B · 其他操作（说说 / 留言 / 评论 / 标签 / 用户）

| 操作 | 命令 | 确认 |
|---|---|---|
| 发说说 | `curl -s -X POST "https://$BLOG_HOST/api/moods" -H "Content-Type: application/json" -d '{"title":"…","content":"…","src":"img/…"}'` | 须确认（写）|
| 发评论 | `curl -s -X POST "https://$BLOG_HOST/api/comments" -H "Content-Type: application/json" -d '{"uid":1,"aid":{aid},"content":"…"}'` | 须确认（写）|
| 留言/回复 | `curl -s -X POST "https://$BLOG_HOST/api/messages" -d '{"uid":1,"content":"…"}'`；回复 `POST /api/messages/reply {"uid":1,"mid":1,"content":"…"}` | 须确认（写）|
| 建标签 | `curl -s -X POST "https://$BLOG_HOST/api/lables" -H "Content-Type: application/json" -d '{"lname":"新标签"}'` | 须确认（写）|
| 建用户 | `curl -s -X POST "https://$BLOG_HOST/api/users" -H "Content-Type: application/json" -d '{"uname":"…","phone":"…","pwd":"…","email":"…","img":"…"}'` | 须确认（写）|
| 列表查询（文章/标签/评论/留言/说说/用户）| `curl -s "https://$BLOG_HOST/api/xxx"` | GET 自动 |

> 所有 POST/PUT/DELETE = 写操作——执行前确认（SKILL 4.7 写操作协议）；GET 自动执行。

---

## 错误排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `/health` 不通 | 博客服务未起/安全组未放行 | 报告用户；重试 3×5s；停止 |
| 发布 500 | 标题已在库/服务异常 | 查重 → 重试 1 次 → 报告 |
| 页面媒体挂掉 | P4 替换漏项 | 检查 HTML 是否残留相对路径 → 补上传补替换 → 再验证 |
| `grape ... 403` | pull merge/issues comments 需会话级 token（tk_）——API key 被网关拒绝 | 平台 skill 环境天然有 tk_——重试一次；仍失败报告（不伪造成功）|
| PR 合并失败 | PR 已合并/冲突/无权限 | 报告 + 建议人工合并 → 跳过合并直接发布 |
| pending 上传 | 单文件失败 | 如实列入评论与 JSON（硬约束⑤）——不隐藏 |

## 断点续跑（中断恢复——沿用旧版 Resume 机制）

1. `/tmp/blog_article.json` 存在 → 说明 P6 已构建发布 JSON——**跳过 P5 提取段**（标题/封面已在 JSON 里），P6 改为读 JSON 直接查重+发布
2. HTML 已替换 `/uploads/` → 跳过 P4b（上传可重放——幂等）
3. `GET /api/articles?keyword={标题}` 已有 → 该文章已发布——不重复发布，直接验证+收尾