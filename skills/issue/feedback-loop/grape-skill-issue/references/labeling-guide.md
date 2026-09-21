# 打标签指南

## 标签判定标准

| 标签 | 颜色 | 适用场景 | 判定线索 |
|------|------|---------|---------|
| `feature` | `#a2eeef` | 新功能请求 | 标题含"建议/需求/新增/支持/实现/希望/能不能" |
| `bug` | `#d73a4a` | 缺陷报告 | 标题含"bug/故障/报错/错误/不生效/白屏/异常/500"或正文含堆栈 |
| `need-info` | `#d4c5f9` | 信息不足 | 正文 < 30 字、无复现步骤、无日志/截图 |
| `triaged` | `#bfdadc` | 已分诊完成 | 与主标签一起加，表示已完成分诊 |
| `invalid` | `#e4e669` | 与仓库项目完全无关 | 标题/正文与项目范围完全无关 |
| `spec-ready` | `#0075ca` | Spec 已生成 | 可开发性评级 ready，Spec 文档已发布 |

## 打标签流程

### 1. 确保标签存在且有颜色

如果标签尚未创建，用 grape CLI 创建：

```bash
grape git-repo labels create --owner {owner} --repo {repo} --json '{"name":"feature","color":"#a2eeef"}'
```

### 2. 查看已有标签

```bash
grape git-repo labels list --owner {owner} --repo {repo} --json-out
```

### 3. 设置标签到 Issue

```bash
grape git-repo issues update --owner {owner} --repo {repo} --number {n} --json '{"labels":"feature,triaged"}'
```

多个标签用逗号分隔。如果标签定义已在仓库中存在，跳过创建步骤，直接更新 Issue。

> ⚠️ `grape git-repo issues update` 的 `labels` 字段为逗号分隔的字符串，覆盖原有标签。如需保留原有标签，先查询当前标签再合并设置。
