# GitCode API 参考（blog-vod Agent 用）

> 配套 `skills/vod/feedback-loop/blog-vod/SKILL.md`。所有 GitCode 操作使用 `$BOT_GITCODE_TOKEN` 认证；A2A 等 Grape 接口使用 `$GRAPE_SESSION_TOKEN`，两者严禁混用。

## Base URL

```
https://api.gitcode.com/api/v5
```

读写操作均使用此 Base URL。

## Authentication

```
PRIVATE-TOKEN: $BOT_GITCODE_TOKEN
# 或
Authorization: Bearer $BOT_GITCODE_TOKEN
```

注意事项（实测）：

- GitCode 的 token 不是 OAuth token，`Authorization: token xxx`（注意是 `token` 不是 `Bearer`）会导致 **401**；只能用 `PRIVATE-TOKEN` 或 `Bearer`。
- `access_token=` 查询参数方式不推荐，部分端点不接受。
- token 长度约 24 字符属正常，不要因短而怀疑格式。

## Content-Type 规则

| 操作 | Content-Type | Body 格式 |
|------|--------------|-----------|
| 创建/更新 Label | `application/x-www-form-urlencoded` | `name=xxx&color=xxx` |
| 给 Issue 加标签 | `application/x-www-form-urlencoded` | `labels=blog-vod,type:feature` |
| 创建评论（多行 markdown） | `application/json` | JSON body，用 `--data` 传文件避免转义问题 |

注意：Label 接口**不接受 JSON body**（返回 400），必须用 form-encoding；多行 markdown 评论用 curl 传 `--data @file.json`（JSON 文件）而不是内联转义。

## 常见操作示例（curl）

### 1. 读取 Issue（步骤 1 必做）

```bash
curl -s --max-time 30 \
  -H "Authorization: Bearer $BOT_GITCODE_TOKEN" \
  "https://api.gitcode.com/api/v5/repos/${REPO_FULL_NAME}/issues/${ISSUE_NUMBER}"
```

### 2. 发布评论（多行 body 用文件）

```bash
cat > /tmp/blog_vod_comment.json << 'EOF'
{"body": "[blog-vod Agent] 这是 blog-vod 的答复内容。"}
EOF

curl -s --max-time 30 -X POST \
  -H "Authorization: Bearer $BOT_GITCODE_TOKEN" \
  -H "Content-Type: application/json" \
  --data @/tmp/blog_vod_comment.json \
  "https://api.gitcode.com/api/v5/repos/${REPO_FULL_NAME}/issues/${ISSUE_NUMBER}/comments"
```

### 3. 列出评论（发布前幂等检查）

```bash
curl -s --max-time 30 \
  -H "Authorization: Bearer $BOT_GITCODE_TOKEN" \
  "https://api.gitcode.com/api/v5/repos/${REPO_FULL_NAME}/issues/${ISSUE_NUMBER}/comments"
```

### 4. 创建标签（form-encoded）

```bash
curl -s --max-time 30 -X POST \
  -H "Authorization: Bearer $BOT_GITCODE_TOKEN" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "name=blog-vod&color=f9d0c4" \
  "https://api.gitcode.com/api/v5/repos/${REPO_FULL_NAME}/labels"
```

### 5. 给 Issue 加标签（form-encoded，整体替换语义）

```bash
curl -s --max-time 30 -X PATCH \
  -H "Authorization: Bearer $BOT_GITCODE_TOKEN" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "labels=blog-vod,type:feature" \
  "https://api.gitcode.com/api/v5/repos/${REPO_FULL_NAME}/issues/${ISSUE_NUMBER}"
```

### 6. 关闭 Issue

```bash
curl -s --max-time 30 -X PATCH \
  -H "Authorization: Bearer $BOT_GITCODE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"state": "close"}' \
  "https://api.gitcode.com/api/v5/repos/${REPO_FULL_NAME}/issues/${ISSUE_NUMBER}"
```

## Endpoints 速查

| 资源 | Method | Endpoint |
|------|--------|----------|
| 仓库详情 | GET | `/repos/:owner/:repo` |
| 文件内容 | GET | `/repos/:owner/:repo/contents/:path?ref=:branch` |
| Issue 列表 | GET | `/repos/:owner/:repo/issues` |
| Issue 详情 | GET | `/repos/:owner/:repo/issues/:number` |
| 建 Issue | POST | `/repos/:owner/:repo/issues` |
| 更新 Issue | PATCH | `/repos/:owner/:repo/issues/:number` |
| 评论列表 | GET | `/repos/:owner/:repo/issues/:number/comments` |
| 发评论 | POST | `/repos/:owner/:repo/issues/:number/comments` |
| Label 列表 | GET | `/repos/:owner/:repo/labels` |
| 建 Label | POST | `/repos/:owner/:repo/labels` |
| 更新 Label | PATCH | `/repos/:owner/:repo/labels/:name` |
| 删除 Label | DELETE | `/repos/:owner/:repo/labels/:name` |
| PR 列表 | GET | `/repos/:owner/:repo/pulls` |
| PR 详情 | GET | `/repos/:owner/:repo/pulls/:number` |
| 建 PR | POST | `/repos/:owner/:repo/pulls` |
| PR 评论 | POST | `/repos/:owner/:repo/pulls/:number/comments` |
| 分支列表 | GET | `/repos/:owner/:repo/branches` |
| 提交列表 | GET | `/repos/:owner/:repo/commits` |

## 已知坑（实测）

1. **`Authorization: token` 格式会 401**：必须用 `PRIVATE-TOKEN` 或 `Authorization: Bearer`。
2. **403 = 权限不足**：token 对目标仓库无写权限，检查 scope；不要换 host 或换 header 绕过。
3. **Label 创建/Issue 标签用 form-encoding**，不要用 JSON body。
4. **多行 markdown 评论**：用 curl `--data @file.json` 传 JSON 文件，避免转义与超长命令行问题。
5. **同一操作连续失败 3 次就停下检查 auth 格式和 Content-Type**，不要继续微调。
6. **分页**：`?page=1&per_page=100`（max 100）。
7. **限流**：默认约 400 req/min、4000 req/hour，超限返回 429。