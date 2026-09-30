# 评论与标签规范（blog-vod Agent 用）

> 配套 `skills/vod/feedback-loop/blog-vod/SKILL.md`。覆盖：Issue 评论礼仪、评论类型与格式、标签体系与管理规则。
> 所有 GitCode 操作用 grape CLI 完成（`grape git-repo ...`），禁止 curl 直连平台 API。

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
| 需求清单评论 | 已输出「博客需求清单」 | 按 requirement-elicit-guide §三 JSON 模板组织，未回复维度标注「默认值」 |
| A2A 交办说明 | 已交办 Issue Agent | 简述已收敛结论与交办结果 |
| 失败/降级说明 | 命令 403 / A2A 不可达 | 按安全硬约束说明原因与人工介入路径 |

### 3. 评论命令（grape CLI）

```bash
# 发评论（长 body 先写文件再 --json @file，防转义）
cat > /tmp/blog_vod_comment.json << 'EOF'
{"body": "> {用户评论原文}\n\n[blog-vod Agent] {答复/追问正文}"}
EOF
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json @/tmp/blog_vod_comment.json
```

### 4. 评论幂等

- 发布前先查是否已有同前缀评论，避免重复追问/重复确认：

```bash
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```

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

1. 创建标签前先 `labels list` 查询，已存在则跳过创建（幂等）。
2. `issues update` 的 `labels` 字段为整体替换语义，更新时需携带全部既有标签，避免只传新标签导致旧标签丢失。
3. 每个 Issue 至少有 1 个 type 标签；类型存疑时优先 `type:feature`（博客需求为内容生成需求）。
4. 冲突标签（同一类别存在多个取值）需清理为唯一取值。
5. 优先复用已有标签，仅当确实缺失时新建。

### 4. 标签操作（grape CLI）

```bash
# 查重（幂等——已存在则跳过创建）
grape git-repo labels list --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out

# 创建缺失标签
grape git-repo labels create --owner "$REPO_OWNER" --repo "$REPO_NAME" --json '{"name":"blog-vod","color":"#f9d0c4"}'
grape git-repo labels create --owner "$REPO_OWNER" --repo "$REPO_NAME" --json '{"name":"type:feature","color":"#0e8a16"}'

# 给 Issue 打标（整体替换语义——携带既有标签）
grape git-repo issues update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"labels":"{既有标签列表,}blog-vod,type:feature"}'
```

> 标签操作统一通过 grape CLI（grape git-repo labels / issues update），平台 token 由 CLI 自动读取（$GRAPE_SESSION_TOKEN），禁止 curl 直连。