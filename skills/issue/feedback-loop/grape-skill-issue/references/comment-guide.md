# 评论回复指南

## 回复前准备

回复前先做三件事：
1. **读讨论记录** — `grape git-repo issues comments list --owner {owner} --repo {repo} --number {n} --json-out` 读取所有评论
2. **回顾分析结论** — 回顾本次处理的分析结果（可开发性评级、标签、负责人等）
3. **理解诉求** — 明确用户当前想通过这条评论达成什么

基于以上信息决定回复内容。

## 回复要点

- ✅ 说明打了什么标签、分配给了谁
- ✅ 可以追问补充信息或讨论方案设计
- ✅ 可以给出实现思路和技术方向
- ❌ 不要输出内部处理步骤和术语
- ❌ 不要写代码实现、提交 PR、合并 PR

## 场景参考

| 场景 | 行为 |
|------|------|
| almost-ready | 针对不明确维度精确追问 1-2 个问题，说明确认后即可生成 Spec |
| needs-discussion | 逐维度列出缺失项，逐一追问，标记 need-info |
| Spec 发布 | 以 `[issue agent] 📋 Spec Document` 开头发布格式化 Spec |
| Spec 更新 | 以 `[issue agent] 📋 Spec Document v{N}` 开头，末尾标注变更摘要 |
| 补充信息后重新分析 | 重新执行深度可开发性分析，根据新评级执行对应动作 |
| Spec 修改意见 | 更新 Spec 版本，重新发布，A2A 通知 coding agent |
| 确认 Spec 可执行 | A2A 通知 coding agent 开始开发 |
| 新 Issue | 告知理解总结，说明处理结果（评级、标签、分配） |
| @提及机器人 | 分析评论并回复 |
| 补充信息（原 need-info） | 重新分类，`grape git-repo issues update` 更新 labels，再回复 |
| 请求关闭 Issue | 验证后回复建议 |
| 讨论方案设计 | 参与讨论给出建议 |
| 质疑分配结果 | 重新核对 CODEOWNERS，基于分析维持或调整 |
| 要求超出范围任务 | 查 Agent 列表，通过 A2A API 交办 |
| 其他 DevOps 相关 | 分析并回复 |

## 评论格式要求

```bash
grape git-repo issues comments create --owner {owner} --repo {repo} --number {n} --json '{"body":"> 用户的问题原文\n\n[issue agent] 这是机器人的回复内容。"}'
```

- body 必须以 `[issue agent]` 开头
- issue_comment 事件需引用原文：`> {用户评论}\n\n[issue agent] {机器人回复}`
- 引用 commit：` [`{sha}`](https://gitcode.com/{owner}/{repo}/commit/{sha})`
- 引用 Issue/PR：`[#{N}](https://gitcode.com/{owner}/{repo}/issues/{N})`

## 可开发性评级评论模板

### ready 评级评论

```
[issue agent] ✅ 该 Issue 已通过深度可开发性分析，评级：**ready**

**分析结论**：
- 需求完整性：complete — 功能点明确，验收标准清晰
- 技术可行性：feasible — 涉及模块：{模块列表}
- 依赖就绪性：ready — 无缺失依赖
- 范围确定性：clear — 预估改动：{描述}

已生成 Spec 文档并发布在下方，负责人已分配给机器人，将自动启动开发实现。
```

### almost-ready 评级评论

```
[issue agent] 🔍 该 Issue 可开发性分析评级：**almost-ready**

需求基本清晰，但有以下问题需要确认：

1. **{维度名}**：{具体问题}
2. **{维度名}**：{具体问题}

确认后即可生成开发规格文档并启动实现。
```

### needs-discussion 评级评论

```
[issue agent] 🔍 该 Issue 可开发性分析评级：**needs-discussion**

{逐维度列出缺失项和追问}

请逐一回复以上问题，确认后将重新评估可开发性。
```
