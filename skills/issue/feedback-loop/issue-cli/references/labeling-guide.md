# 打标签指南（Issue-CLI）

> 打标签用 `grape git-repo labels create`（建标签）+ `grape git-repo issues update`（设到 Issue），命令见 `references/grape-cli-reference.md`。
> ⚠️ **正文一律用评论发布，不 update 改写**：`issues update` 是整体覆盖语义，会把原始描述冲掉；结构化内容（Spec/收敛/说明）用 `grape git-repo issues comments create`。需要改 labels/assignee 时，先 `git-repo issues get` 回取原始 body 一并回传。

## 标签判定标准

| 标签 | 颜色 | 适用场景 | 判定线索 |
|------|------|---------|---------|
| `feature` | `#a2eeef` | 新功能请求 | 标题含"建议/需求/新增/支持/实现/希望/能不能" |
| `bug` | `#d73a4a` | 缺陷报告 | 标题含"bug/故障/报错/错误/不生效/白屏/异常/500"或正文含堆栈 |
| `need-info` | `#d4c5f9` | 信息不足 | 正文 < 30 字、无复现步骤、无日志/截图 |
| `triaged` | `#bfdadc` | 已分诊完成 | 与主标签一起加，表示已完成分诊 |
| `invalid` | `#e4e669` | 与仓库项目完全无关 | 标题/正文与项目范围完全无关 |

## 打标签流程

### 1. 确保标签存在且有颜色

先 `grape git-repo labels list` 查仓库已有标签；如果标签尚未创建，用以下命令创建（带上颜色参数）：
> ⚠️ 若 `labels create` 返回 400/报错，**属平台行为不要排查**——直接用 Step 2 的 `issues update` 的 `labels` 字段落地（平台会自动补建标签）。

```bash
grape git-repo labels create --owner {owner} --repo {repo} \
  --json '{"name":"feature","color":"#a2eeef"}' || true
```

### 2. 设置标签到 Issue

> ⚠️ `issues update` 整体覆盖——先回取原始 body 回填，防止把原始描述冲掉。

```bash
ISSUE_BODY="$(grape git-repo issues get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out | jq -r '.body')"
grape git-repo issues update --owner {owner} --repo {repo} --number {number} \
  --json '{"body":"'"$ISSUE_BODY"'","labels":"feature,triaged"}'
```

多个标签用逗号分隔。如果标签定义已在仓库中存在，跳过创建步骤，直接 update issue。