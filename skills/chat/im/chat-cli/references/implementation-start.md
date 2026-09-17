# 实施启动确认（implementation-start）— CLI 版

当用户回复「同意启动」、「同意」、「启动」、「确认」、「开始」、「批准」等关键词时，判断是否是针对机器人发出的「是否启动开发」批准请求。**不是对批准请求的回复**（如一般对话中的"同意"、"开始"），直接回复「自动实现未开启，不涉及审批」，不继续后续步骤。

## 0. 检查自动实现开关

> Prompt 中包含 Auto Implementation 状态。如果为 **OFF**，直接回复：
> ```
> 自动实现未开启，不涉及审批
> ```
> 不要继续后续步骤。

## 1. 查询待启动 Feature

```bash
grape git-repo issues list --owner {owner} --repo {repo} --state open --per_page 100 --json-out
```

## 2. 筛选标准

从返回的 Issue 列表中筛选同时满足以下条件的（出参结构与 GitCode 平台一致，含 `labels`/`assignee` 字段）：
- `labels` 包含 `feature` 或 `suggestion`
- `labels` **不**包含 `PATCH`
- `assignee.login` == 当前用户（回复消息的用户名）

## 3. 启动实施

找到符合条件的 Issue 后：

```bash
# 添加 PATCH 标签，触发 implementation skill
grape git-repo issues update --owner {owner} --repo {repo} --number {number} \
  --json '{"labels": "feature,triaged,PATCH"}'
```

## 4. 回复用户

```
<at id={open_id}></at> 已启动 [#{number}](链接) {标题} 的需求开发，进度可关注该 Issue。
```

## 5. 未找到待启动 Issue

如果没找到符合条件的 Issue，按正常 DevOps 对话处理（不触发实施启动）。

## 6. 收尾

本流程由实施启动触发时，按 SKILL「任务完成流程」调用 `grape tasks complete` 自报完成。