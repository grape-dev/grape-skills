# 打标签指南（Issue-CLI）

> 打标签用 `grape git-repo labels create`（建标签）+ `grape git-repo issues update`（设到 Issue），命令见 `references/grape-cli-reference.md`。

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

```bash
grape git-repo labels create --owner {owner} --repo {repo} \
  --json '{"name":"feature","color":"#a2eeef"}'
```

### 2. 设置标签到 Issue

```bash
grape git-repo issues update --owner {owner} --repo {repo} --number {number} \
  --json '{"labels":"feature,triaged"}'
```

多个标签用逗号分隔。如果标签定义已在仓库中存在，跳过创建步骤，直接 update issue。