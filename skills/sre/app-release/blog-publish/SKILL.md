---
name: blog-publish
description: "Use when publishing, editing, deleting, or listing blog posts via the Blog System API. Also handles mood publishing, comments, messages, labels, and media uploads."
author: Hermes Agent
license: MIT
tools:
  - name: curl
    min_version: "7.68.0"
  - name: python3
    min_version: "3.8"
requires:
  - env: BOT_TOKEN
    description: VCS API token (for PR merge)
  - env: REPO_FULL_NAME
    description: Repository full name (owner/repo)
  - env: ISSUE_NUMBER
    description: Issue number
inputSchema:
  type: object
  required:
    - BLOG_HOST
  properties:
    BLOG_HOST:
      type: string
      description: Blog system host address (IP:PORT or domain)
    REPO_FULL_NAME:
      type: string
      description: Repository full name for PR operations
    ISSUE_NUMBER:
      type: integer
      description: Issue number for context
    PR_NUMBER:
      type: integer
      description: PR number to merge before publishing
    BLOG_OUTPUT_DIR:
      type: string
      description: Local directory containing blog output files
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
      description: List of performed actions
    conclusion:
      type: string
      description: Result summary
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
      description: Next step description
    issue_summary:
      type: string
      description: Issue summary
metadata:
  hermes:
    tags: [blog, publishing, api, content]
    related_skills: []
---

# Blog Publish

## Overview

Publish blog posts to the Blog System API. FastAPI + MySQL, no authentication required. Supports articles, comments, messages, moods, labels, and users.

## Configuration

Before using this skill, the target server address must be determined. Replace `{BLOG_HOST}` in all commands below with the actual deployment address in the format `IP:PORT` or domain (e.g., `{BLOG_HOST}`).

The `{BLOG_HOST}` value is resolved in this priority order:

1. **Project Knowledge** — check `project-info/member/blog-config.yaml` (or similar config file) for `blog.host` field.
2. **Current context** — the user provides it or the current conversation context already contains it; use it directly as `{BLOG_HOST}`.
3. **Workspace files** — search the project's knowledge directory at `/root/grape-workspaces/{owner}/{repo}/project-info/` for a file containing the blog system deployment address.
4. **Ask user** — if none of the above found, ask the user for the target server address before proceeding.

## When to Use

- User asks to publish / create / post a blog article
- User asks to update / edit / delete a blog post
- User asks to list articles, view detail, or check hot articles
- User asks to publish a mood (说说) or leave a message (留言)
- User asks to create labels or users for the blog system

Don't use for: non-blog content or when the API is not reachable.

## API Base URL

```
https://{BLOG_HOST}
```

All endpoints below are relative to this base. No auth header needed.

> ⚠️ **HTTPS requirement**: All API requests must use HTTPS. If the blog server does not support HTTPS, the user must explicitly confirm downgrade to HTTP before proceeding.

## Endpoints

> **Read/Write Semantics**: GET operations (read) execute automatically. POST/PUT/DELETE operations (write) require user confirmation before execution.

### Articles (文章)

| Method | Path | Body | Description | Semantics |
|--------|------|------|-------------|-----------|
| GET | `/api/articles?page=1&size=10&lid=0&keyword=` | — | List articles (paginated, filter by label/keyword) | Read (auto) |
| GET | `/api/articles/{id}` | — | Get article detail (increments heat) | Read (auto) |
| POST | `/api/articles` | `{title, content, uid, lid, img, heat}` | Publish new article | Write (confirm) |
| PUT | `/api/articles/{id}` | `{title?, content?, lid?, img?, heat?}` | Update article | Write (confirm) |
| DELETE | `/api/articles/{id}?soft=true` | — | Delete (soft default, soft=false for hard) | Write (confirm) |
| POST | `/api/articles/{id}/restore` | — | Restore soft-deleted article | Write (confirm) |
| GET | `/api/articles/heat/top?limit=5` | — | Top hot articles | Read (auto) |

### Labels (标签)

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/api/lables` | — | List all labels |
| POST | `/api/lables` | `{lname}` | Create label |

### Comments (评论)

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/api/comments/{aid}` | — | List comments for article |
| POST | `/api/comments` | `{uid, aid, content}` | Add comment |
| DELETE | `/api/comments/{id}` | — | Delete comment (soft) |

### Messages (留言)

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/api/messages` | — | List messages with replies |
| POST | `/api/messages` | `{uid, content}` | Post message |
| POST | `/api/messages/reply` | `{uid, mid, content}` | Reply to message |
| DELETE | `/api/messages/{id}` | — | Delete message (soft) |

### Moods (说说)

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/api/moods` | — | List moods |
| POST | `/api/moods` | `{title, content, src}` | Publish mood |
| DELETE | `/api/moods/{id}` | — | Delete mood |

### Users (用户)

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/api/users` | — | List users |
| POST | `/api/users` | `{uname, phone, pwd, email, img}` | Create user |

### Upload (上传文件)

| Method | Path | Body | Description |
|--------|------|------|-------------|
| POST | `/api/upload` | `multipart/form-data: file=@文件` | Upload image/video, returns `{url: "/uploads/xxx.png"}` |

### Pages (前端页面)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Blog home page (HTML) |
| GET | `/article/{id}` | Article detail page (HTML) |
| GET | `/docs` | Swagger API docs |
| GET | `/health` | Health check |

## Publish an Article

Step-by-step workflow:

### 1. Check API is reachable

```bash
curl -s https://{BLOG_HOST}/health
```
Expect: `{"status":"ok","service":"blog-api","version":"1.0.0"}`

### 2. Get available labels

```bash
curl -s https://{BLOG_HOST}/api/lables
```

### 3. Upload media files to blog server

Media files (images, cover, video) are stored locally in the blog output directory. They must be uploaded to the blog server first, and relative paths in the HTML must be replaced with the upload URLs.

Determine `OUTPUT_DIR` from the A2A context (coding agent handoff provides the product path). If not provided, look in:
```
/root/grape-workspaces/{owner}/{repo}/issues/{issue_number}/coding/blog_output/
```

```python
import os, json, subprocess, glob, re

BLOG_HOST = "{BLOG_HOST}"  # Resolved from project knowledge or context
OUTPUT_DIR = "/root/grape-workspaces/..."  # From A2A context
UPLOAD_URL = f"https://{BLOG_HOST}/api/upload"

# Step 3a: Upload all media files (using requests library instead of subprocess curl)
import requests

upload_map = {}  # rel_path -> upload_url
for ext in ["*.png", "*.jpg", "*.jpeg", "*.gif", "*.mp4"]:
    for fp in glob.glob(os.path.join(OUTPUT_DIR, "**", ext), recursive=True):
        rel = os.path.relpath(fp, OUTPUT_DIR)
        print(f"Uploading: {rel}...")
        with open(fp, "rb") as f:
            resp = requests.post(UPLOAD_URL, files={"file": f}, timeout=60)
        d = resp.json()
        if d.get("code") == 200:
            upload_map[rel] = d["data"]["url"]
            print(f"  -> {d['data']['url']}")
        else:
            print(f"  FAILED: {resp.text}")

# Step 3b: Replace relative paths in index.html with upload URLs
html_path = os.path.join(OUTPUT_DIR, "index.html")
with open(html_path, "r", encoding="utf-8") as f:
    html = f.read()

for rel_path, upload_url in sorted(upload_map.items(), key=lambda x: -len(x[0])):
    html = html.replace(f'src="{rel_path}"', f'src="{upload_url}"')
    html = html.replace(f'poster="{rel_path}"', f'poster="{upload_url}"')

with open(html_path, "w", encoding="utf-8") as f:
    f.write(html)

print("HTML updated with upload URLs")
```

**Important**: After this step, all `src="intro.mp4"`, `poster="cover.png"`, `src="images/theme_1.png"` etc. are replaced with `/uploads/xxx.xxx` paths served by the blog server.

### 4. Extract title and cover image URL from the updated HTML

```python
import re
with open(os.path.join(OUTPUT_DIR, "index.html"), "r") as f:
    html = f.read()

# Extract title (<h1>)
m = re.search(r'<h1[^>]*>(.*?)</h1>', html, re.DOTALL)
BLOG_TITLE = m.group(1).strip() if m else "无标题"

# Extract cover image URL (first poster or first img)
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

### 5. Choose label ID

From the label list obtained in step 2, pick the matching label ID for the article topic. Common labels:
| ID | Name |
|----|------|
| 1 | 技术 |
| 2 | 生活 |
| 3 | 随笔 |
| 4 | 教程 |

If the topic is food/美食/product introduction and no matching label exists, create one with `POST /api/lables {"lname": "美食"}`.

### 6. Publish article to blog API

> ⚠️ **Write operation**: Confirm with the user before publishing the article to the blog API.

```python
import json
article = {
    "title": BLOG_TITLE,
    "content": html,       # Full HTML with uploaded URLs
    "uid": 1,
    "lid": LABEL_ID,       # From step 5
    "img": BLOG_IMG,
    "heat": 0
}

with open("/tmp/blog_article.json", "w", encoding="utf-8") as f:
    json.dump(article, f, ensure_ascii=False)
```

```bash
curl -s -X POST https://{BLOG_HOST}/api/articles \
  -H "Content-Type: application/json" \
  -d @/tmp/blog_article.json
```
Expect: `{"code":200,"message":"文章发布成功","data":{"id":N}}`

### 7. Verify

```bash
curl -s https://{BLOG_HOST}/api/articles/{id}
```

### 8. View in browser

```bash
echo "https://{BLOG_HOST}/article/{id}"
```

The article page should now load images and video from the blog server's `/uploads/` directory.

### 9. Resource cleanup

After successful publication, clean up temporary files:

```bash
rm -f /tmp/blog_article.json
```

> ⚠️ **Cleanup confirmation**: Confirm with the user before deleting temporary files.

### Article Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| title | string | Yes | — | Article title |
| content | string | Yes | — | Article body (plain text) |
| uid | int | No | 1 | Author user ID |
| lid | int | No | 1 | Label ID (1=技术, 2=生活, 3=随笔, 4=教程) |
| img | string | No | null | Cover image path |
| heat | int | No | 0 | Initial heat value |

## Update an Article

```bash
curl -s -X PUT https://{BLOG_HOST}/api/articles/{id} \
  -H "Content-Type: application/json" \
  -d '{"title": "新标题", "content": "新内容"}'
```

All fields optional: title, content, lid, img, heat.

## Delete / Restore

```bash
# Soft delete (default, can restore)
curl -s -X DELETE https://{BLOG_HOST}/api/articles/{id}

# Hard delete (permanent)
curl -s -X DELETE "https://{BLOG_HOST}/api/articles/{id}?soft=false"

# Restore soft-deleted article
curl -s -X POST https://{BLOG_HOST}/api/articles/{id}/restore
```

## Other Operations

### Publish a Mood (说说)
```bash
curl -s -X POST https://{BLOG_HOST}/api/moods -H "Content-Type: application/json" \
  -d '{"title":"今日心情","content":"今天完成了博客系统","src":"img/mood1.jpg"}'
```

### Post a Comment
```bash
curl -s -X POST https://{BLOG_HOST}/api/comments -H "Content-Type: application/json" \
  -d '{"uid":1,"aid":1,"content":"很棒的文章！"}'
```

### Leave a Message (留言)
```bash
curl -s -X POST https://{BLOG_HOST}/api/messages -H "Content-Type: application/json" \
  -d '{"uid":1,"content":"你好，很高兴来到这个博客！"}'
# Reply: POST /api/messages/reply {"uid":1,"mid":1,"content":"谢谢支持！"}
```

### Create a Label
```bash
curl -s -X POST https://{BLOG_HOST}/api/lables -H "Content-Type: application/json" -d '{"lname":"新标签"}'
```

### Create a User
```bash
curl -s -X POST https://{BLOG_HOST}/api/users -H "Content-Type: application/json" \
  -d '{"uname":"作者名","phone":"13800000000","pwd":"123456","email":"author@example.com"}'
```

## Common Pitfalls

1. **API not reachable.** Always check `/health` first. The API port must be open in security group.
2. **Wrong label ID.** Query `/api/lables` first to get current IDs. New labels can be created via POST.
3. **Content with special characters.** Use a temp file for long content with quotes/newlines: `curl -d @/tmp/article.json`
4. **Deleting without confirming.** Soft delete is default and recoverable. Hard delete (soft=false) is permanent — always confirm with user first.
5. **uid mismatch.** If no blog user account exists, uid defaults to 1 (admin). Create a user first if authorship matters.

## Verification Checklist

### Publish Flow
- [ ] `GET /health` returns `{"status":"ok"}`
- [ ] `POST /api/articles` returns `{"code":200,"data":{"id":N}}`
- [ ] `GET /api/articles/{id}` returns the created article with correct title/content
- [ ] Article is visible on home page at `https://{BLOG_HOST}/`
- [ ] Article detail page at `https://{BLOG_HOST}/article/{id}` renders correctly

### E2E Lifecycle (create → query → update → delete)
- [ ] **Create**: POST article → returns article_id
- [ ] **Query**: GET /api/articles/{id} → title/content match
- [ ] **Update**: PUT /api/articles/{id} with new title → GET confirms update
- [ ] **Delete**: DELETE /api/articles/{id} (soft) → GET returns 404 or deleted flag
- [ ] **Restore**: POST /api/articles/{id}/restore → GET returns article again
- [ ] **Hard delete**: DELETE with soft=false (after user confirmation) → permanently removed

## Performance Budget

| Metric | Budget | Notes |
|--------|--------|-------|
| Skill load latency | < 2s | SKILL.md ~15KB, no external references |
| P95 execution latency | < 90s | Health check + label query + media upload + publish + verify |
| LLM call budget | ≤ 2 | Intent parsing (1) + error diagnosis (1) |
| Token budget | ≤ 5000 | SKILL.md ~3500 tokens + runtime context ~1500 tokens |

## Version Management Strategy

- Current version: v1.0 (no version field in frontmatter, per v1.0 spec)
- Changelog maintained in repository CHANGELOG.md
- Backward compatibility: outputSchema new fields are optional (non-required)
- Gradual rollout: via GitCode branch management (dev → main), requires linter + tester + auditor before merge

## Resume Mechanism

If the workflow is interrupted, resume from the last completed step:

1. **Check temp file**: `ls /tmp/blog_article.json` — if exists, skip to step 6 (publish)
2. **Check uploaded media**: Query `GET /api/articles` to see if article was already published
3. **Check HTML state**: Read index.html — if paths already replaced with `/uploads/`, skip step 3
4. **Resume from failed step**: Re-run only the failed step, not the entire workflow

## Fallback Strategy

| Failure | Fallback |
|---------|----------|
| Blog API unreachable | Report to user, retry 3 times with 5s interval, then stop |
| Media upload fails | Skip failed file, continue with remaining, mark as "pending upload" |
| Article publish fails (500) | Check if article already exists by title query, retry once |
| PR merge fails | Report to user, suggest manual merge, continue with publish from local files |

## Idempotency

| Operation | Strategy |
|-----------|----------|
| POST /api/articles | Before publishing, query `GET /api/articles?keyword={title}` to check for duplicates |
| Media upload | Upload returns unique URL; re-uploading same file creates new URL (acceptable) |
| PR merge | Check PR state via VCS API before attempting merge |
| Comment/message | Include unique identifier in content for deduplication |

## Multi-Skill Coordination

This skill is invoked by the coding Agent (via A2A) after blog content generation. It does not directly call other skills.

- **Upstream**: Receives A2A context from coding Agent with PR number and blog output directory
- **Downstream**: Reports publication result back to the Issue (comment) for review
- **Conflict resolution**: If multiple publish tasks target the same blog, use article title deduplication
- **Cross-Skill data**: Returns `article_id` and `article_url` in output JSON for downstream consumption

## Lifecycle Declaration

This skill handles create/update/delete operations for blog articles. Hard delete requires explicit user confirmation. Article restoration is supported via POST /api/articles/{id}/restore.

## Output Format

After task completion, output a structured JSON block:

```json
{
  "actions": ["health_check", "label_query", "media_upload", "article_publish", "verify"],
  "conclusion": "Article published successfully",
  "artifacts": {
    "article_id": 42,
    "article_url": "https://{BLOG_HOST}/article/42",
    "media_uploads": 6
  },
  "next_step": "Article is live. Report result to Issue comment.",
  "issue_summary": "Blog article published: title | article_id=42 | url=..."
}
```

**Not outputting the JSON block means the task is incomplete.**
