# A2A 部署协作流程（Issue Agent 用）

## 多 Agent 协作交付链路

IaC 变更从 Issue 到部署的完整协作流程：

```
Issue Agent（需求分类、标签、指派、触发 A2A）
  → Coding Agent（创建 PR，实现 IaC 模板）
  → QA Agent（代码审查、安全检查、自动化测试）
    → 合并 PR
  → SRE Agent（部署执行、运维处置、故障排查）
```

### 各 Agent 职责边界

| Agent | 职责 | 不做 |
|-------|------|------|
| Issue | 需求分类、标签、指派、Spec 生成、A2A 触发 | 直接合并 PR |
| Coding | TF 配置生成、自审查、PR 创建 | 直接合并 PR |
| QA | 代码质量/功能/安全审查、报告输出 | 修改代码 |
| SRE | 部署执行、故障排查、运维处置 | 修改源代码（仅输出建议） |

## A2A 触发

Issue Agent 完成分类和 Spec 生成后，通过 A2A 交办 coding（Step 5）；coding 完成后 QA 节点接力审查；PR 合并后或评论含部署语义时，通过 A2A 交办 SRE Agent 执行部署。

### A2A 触发示例

```bash
# 一律用 grape a2a handoff（禁 curl 直连——命令见 iac-issue-runbook Step 5）：
grape a2a handoff --json '{
  "agent": "sre",
  "payload": {
    "repository": "$ACCOUNT/$REPO_NAME",
    "account": "$ACCOUNT",
    "issue_number": {真实编号},
    "pr_number": {有则填=$PR_NUMBER 值},
    "context": "PR已合并，凭证已就绪，执行部署"
  }
}'
```

### 触发时机

| 目标 Agent | 触发条件 | context 内容 | 谁触发 |
|-----------|---------|-------------|--------|
| coding | Issue 分类完成，spec 已生成 | 需求描述、方案建议、关联资源 | **Issue Agent**（Step 5） |
| qa | coding 创建 PR 后 | PR 编号、变更说明、资源清单 | Coding/QA 节点接力——**非 Issue Agent 直接触发** |
| sre | PR 已合并，凭证已就绪；或评论含部署语义 | 仓库、Issue 编号、部署上下文 | Issue Agent（部署语义分支） |
