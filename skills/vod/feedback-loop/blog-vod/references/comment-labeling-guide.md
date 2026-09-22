# 评论与标签规范（blog-vod Agent 用）

> 配套 `skills/vod/feedback-loop/blog-vod/SKILL.md`。覆盖：Issue 评论礼仪、评论类型与格式、标签体系与管理规则。

## 一、评论规范

### 1. 评论礼仪

| 要求 | 说明 |
|------|------|
| 建设性与专业性 | 评论以帮助收敛需求/推进合作为目的，语气专业 |
| 中文书写 | 所有 Issue/PR 评论使用中文 |
| 禁止内部推理 | 评论不出现思考过程、分析步骤或英文分析 |
| 禁止敏感信息 | 不输出 token、密码、密钥等任何敏感信息 |
| 前缀固定 | 评论 body 一律以 `[blog-vod Agent]` 开头（环境变量未注入时用 skill name 作为前缀） |

### 2. 评论类型

| 类型 | 适用场景 | 要点 |
|------|---------|------|
| 需求澄清追问 | 博客需求信息不足 | 引用用户原文 + 提出 1-3 个具体问题，不一次性抛太多 |
| 需求确认评论 | 已输出「博客需求清单」待确认 | 说明待执行的写操作清单，请用户回复确认 |
| A2A 交办说明 | 已交办 Issue Agent | 简述已收敛结论与交办结果 |
| 失败/降级说明 | API 403 / A2A 不可达 | 按安全硬约束说明原因与人工介入路径 |

### 3. 评论格式示例

```bash
curl -s --max-time 30 -X POST \
  -H "Authorization: Bearer $BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"body": "> {用户评论原文}\n\n[blog-vod Agent] {答复/追问正文}"}' \
  "$VCS_API_BASE/repos/${REPO_FULL_NAME}/issues/${ISSUE_NUMBER}/comments"
```

### 4. 评论幂等

- 发布前先 `GET .../issues/{number}/comments` 查询是否已有同前缀评论，避免重复追问/重复确认。
- 内容唯一性检查以「评论前缀 + 本技能标记」为准，防止 Issue 重新打开触发重复评论。

## 二、标签规范

### 1. 标签体系

本技能负责创建以下标签，其余类别（优先级、状态）由 Issue Agent 负责：

| 标签 | 类别 | 说明 |
|------|------|------|
| `blog-vod` | 来源标注 | 表示该 Issue 由 blog-vod 引导收敛的博客需求 |
| `type:feature` | 类型 | 博客内容生成属于功能需求 |

### 2. 通用标签参考（Issue Agent 可能使用，本技能不越权创建）

| 前缀 | 取值示例 | 说明 |
|------|---------|------|
| type | type:bug / type:feature / type:enhancement / type:documentation / type:question | 类型 |
| priority | priority:P0 / P1 / P2 / P3 | 优先级 |
| status | status:triaged / in-progress / review / blocked / done | 状态 |
| special | vod / good-first-issue / help-wanted | 特殊标签 |

### 3. 管理规则

1. 创建标签前先 `GET /repos/{owner}/{repo}/labels` 查询，已存在则跳过创建（幂等）。
2. `PATCH /issues/{number}` 的 `labels` 字段为整体替换语义，更新时需携带全部既有标签，避免只传新标签导致旧标签丢失。
3. 每个 Issue 至少有 1 个 type 标签；类型存疑时优先 `type:feature`（博客需求为内容生成需求）。
4. 冲突标签（同一类别存在多个取值）需清理为唯一取值。
5. 优先复用已有标签，仅当确实缺失时新建。

### 4. 标签操作示例

```bash
# 创建标签（form-encoded，不接受 JSON body）
curl -s --max-time 30 -X POST \
  -H "Authorization: Bearer $BOT_TOKEN" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "name=blog-vod&color=#f9d0c4" \
  "$VCS_API_BASE/repos/${REPO_FULL_NAME}/labels"

# 给 Issue 添加标签（整体替换语义，携带既有标签）
curl -s --max-time 30 -X PATCH \
  -H "Authorization: Bearer $BOT_TOKEN" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "labels=blog-vod,type:feature" \
  "$VCS_API_BASE/repos/${REPO_FULL_NAME}/issues/${ISSUE_NUMBER}"
```

> 标签操作统一通过 VCS API，使用 `$BOT_TOKEN` 认证；A2A 等 Grape 接口使用 `$GRAPE_SESSION_TOKEN`，两者不混用。