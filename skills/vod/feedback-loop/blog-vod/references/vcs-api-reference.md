# VCS API Reference (Shared)

## Base URL

```
$VCS_API_BASE
```

读写操作均使用此 Base URL（实测 POST/PATCH/DELETE 打到 `api.gitcode.com` 正常工作）。

## Authentication

```
PRIVATE-TOKEN: $BOT_TOKEN
# 或
Authorization: Bearer $BOT_TOKEN
```

⚠️ **`Authorization: token $BOT_TOKEN`（注意是 `token` 不是 `Bearer`）会导致 401！**
GitCode 的 token 不是 OAuth token，`token` 关键字不被接受。只能用 `PRIVATE-TOKEN` 或 `Bearer`。

- token 长度约 24 字符是正常的，不要因为短就怀疑格式。
- `access_token=` 查询参数方式不推荐，部分端点不接受。

## Content-Type 规则

| 操作 | Content-Type | Body 格式 |
|------|--------------|-----------|
| 创建/更新 Label | `application/x-www-form-urlencoded` | `name=xxx&color=xxx` |
| 给 Issue 加标签 | `application/x-www-form-urlencoded` | `labels=bug,priority:P0` |
| 创建评论 / Issue / PR | `application/json` | `json.dumps(body).encode("utf-8")` |

⚠️ Label 接口**不接受 JSON body**（返回 400），必须用 form-encoding。
多行 markdown 评论用 curl 直接传会 400，用 Python `urllib.request` + `json.dumps()`。

## 已知坑（实测）

1. **`Authorization: token` 格式 → 401**：必须用 `PRIVATE-TOKEN` 或 `Authorization: Bearer`。这是文档老版本里最容易踩的坑。
2. **403 = 权限不足**：token 对目标仓库没有写权限。检查 token 的 scope，不要尝试换 host 或换 header 绕过——换 host 无效。
3. **Label 创建/Issue 标签** 用 form-encoding，不要用 JSON body。
4. **多行 markdown 评论** 用 Python `urllib.request` + `json.dumps().encode("utf-8")`。
5. **同一操作连续失败 3 次就停下来检查 auth 格式和 Content-Type**，不要继续微调。

## 写操作模板（Python）

```python
import json, urllib.request, urllib.parse, os

TOKEN = os.environ["BOT_TOKEN"]
BASE = "$VCS_API_BASE"

def gitcode_get(path):
    url = f"{BASE}{path}"
    req = urllib.request.Request(url)
    req.add_header("PRIVATE-TOKEN", TOKEN)
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())

def gitcode_write(method, path, body, form=False):
    url = f"{BASE}{path}"
    if form:
        data = urllib.parse.urlencode(body).encode("utf-8")
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
    else:
        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Content-Type", "application/json")
    req.add_header("PRIVATE-TOKEN", TOKEN)
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())

# 例：发评论（JSON）
gitcode_write("POST", f"/repos/{owner}/{repo}/issues/{number}/comments",
              {"body": "VOD 分析内容..."})

# 例：创建标签（form-encoding）
gitcode_write("POST", f"/repos/{owner}/{repo}/labels",
              {"name": "type:bug", "color": "#E91E63"}, form=True)

# 例：给 Issue 加标签（form-encoding）
gitcode_write("PATCH", f"/repos/{owner}/{repo}/issues/{number}",
              {"labels": "vod,type:bug,priority:P0"}, form=True)
```

## Endpoints

### Repository
- GET /repos/:owner/:repo - Get repository info
- GET /repos/:owner/:repo/contents/:path - Get file contents

### Issues
- GET /repos/:owner/:repo/issues - List issues
- GET /repos/:owner/:repo/issues/:number - Get single issue
- POST /repos/:owner/:repo/issues - Create issue
- PATCH /repos/:owner/:repo/issues/:number - Update issue
- GET /repos/:owner/:repo/issues/:number/comments - List comments
- POST /repos/:owner/:repo/issues/:number/comments - Create comment

### Labels
- GET /repos/:owner/:repo/labels - List labels
- POST /repos/:owner/:repo/labels - Create label
- PATCH /repos/:owner/:repo/labels/:name - Update label
- DELETE /repos/:owner/:repo/labels/:name - Delete label

### Pull Requests
- GET /repos/:owner/:repo/pulls - List PRs
- GET /repos/:owner/:repo/pulls/:number - Get PR detail
- POST /repos/:owner/:repo/pulls - Create PR
- GET /repos/:owner/:repo/pulls/:number/comments - List PR comments
- POST /repos/:owner/:repo/pulls/:number/comments - Create PR comment
- GET /repos/:owner/:repo/pulls/:number/files - List PR changed files

### A2A
- POST https://grape-dev.topxtopx.com/api/a2a - Trigger agent-to-agent handoff

## Notes
- All endpoints use v5 API unless specified
- Pagination: ?page=1&per_page=100
- Rate limiting: 5000 requests/hour

## GitHub 与 GitCode 差异对照（重要！）

调用 VCS API 前先确认仓库 provider（由 prompt 的 VCS API Access 段指定），按下表选择正确的参数格式：

| 功能 | GitCode | GitHub |
|------|---------|--------|
| Issue 关闭 | `state="close"` | `state="closed"` |
| labels 格式 | 逗号分隔字符串 `"bug,feature"` | 数组 `["bug","feature"]` |
| assignees | `assignee` 单值字符串 | `assignees` 数组 `["user1"]` |
| Create Issue body | 需带 `repo` 字段 | 不需要（repo 在 URL 里） |
| PR 普通评论 | `POST /pulls/:n/comments` | `POST /issues/:n/comments`（GitHub 把 PR 视为 Issue） |
| Create file | `POST /contents/:path` | `PUT /contents/:path` |
| Update file | `PUT /contents/:path`（需 `sha`） | `PUT /contents/:path`（需 `sha`） |
| Create branch | `POST /branches`（body: `branch_name`, `ref`） | `POST /git/refs`（body: `ref`, `sha`） |
| Delete file | 不支持 | `DELETE /contents/:path` |
| Accept header | 不需要 | `application/vnd.github+json`（必须带！） |
| Create label | form-encoded | JSON body |
| Add labels to issue | 通过 `PATCH /issues/:n` 的 `labels` 字段 | `POST /issues/:n/labels`（专用端点） |
| Rate limit | 400 req/min | 5000 req/hour（认证用户） |
| 关联 Issue | `inner_issue_nums` / `close_related_issue` | PR body 中 `Closes #N` / `Fixes #N` |
