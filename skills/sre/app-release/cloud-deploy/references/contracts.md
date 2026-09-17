# Cloud Deploy — 接口契约（inputSchema / outputSchema）

> 本文档为 cloud-deploy 技能的正式接口契约，是 SKILL.md `## 步骤 / Steps`（§1 入参获取、§6 任务完成输出）的完整声明。修改入参/出参结构时须同步更新本文档与 SKILL.md 对应步骤。

## 1. inputSchema（入参契约）

触发方式：A2A 事件（`a2a_event`）或 PR 合并事件（`pull_request_merged`），入参取自 A2A payload / Issue 上下文。

| 字段 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| `operation_type` | string | 是 | — | 取值 `deploy`（部署）或 `release`（资源释放） |
| `issue_number` | int | 是 | — | 触发任务的 Issue 编号，用于回帖与评论查询 |
| `pr_number` | int | 否 | null | PR 编号；部署场景下存在时拉取对应 PR 分支代码，否则拉默认分支 |
| `repo_full_name` | string | 是 | — | 仓库全名（owner/repo），决定代码源与资源命名前缀 |
| `resource_list` | array | 否 | [] | 资源释放场景的目标资源清单（ECS 名称/IP、RDS 实例名、OBS 桶名等） |

JSON 示例：

```json
{
  "operation_type": "deploy",
  "issue_number": 42,
  "pr_number": 128,
  "repo_full_name": "org/demo-app",
  "resource_list": []
}
```

### 校验规则

- 必填缺失（`operation_type` / `issue_number` / `repo_full_name`）→ 拒绝执行，回帖要求补齐后重试。
- `operation_type` 不在 `{deploy, release}` 枚举内 → 按关键词重新判定；仍不匹配则输出 `SKIP`。
- `resource_list` 引用非本仓库前缀的资源 → 拒绝，回帖要求确认资源归属。
- 非法输入一律不落任何写操作（含创建/更新/删除）。

## 2. outputSchema（输出契约）

所有执行路径（部署成功/失败、资源释放、SKIP、追问）统一输出以下结构，并回帖 Issue：

```json
{
  "actions": [
    {
      "type": "create",
      "resource": "deploy-org-demo-app-084723",
      "status": "ok",
      "detail": "ECS created in cn-north-4a"
    }
  ],
  "conclusion": "success",
  "verification": {
    "http_code": 200,
    "port": 5000,
    "reachable": true
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `actions` | array | 是 | 按执行顺序列出全部操作及状态；部署含 create/deploy/verify，释放含 release/cleanup |
| `conclusion` | string | 是 | 最终结论：`success` / `partial` / `failed` / `skipped` |
| `verification` | object | 否 | 部署场景附验证结果（HTTP 状态码、端口监听、公网可达性） |

### Issue 回帖格式

```
## 部署结果
- 结论：<success|partial|failed|skipped>
- 摘要：<一句话结果说明>
<JSON 块>
<失败时：错误信息 + 建议（如需回滚，明确提示需用户确认）>
```

`type` 枚举：`create`（创建资源）、`deploy`（部署代码）、`verify`（验证）、`release`（释放资源）、`cleanup`（清理关联资源）。
`status` 枚举：`ok` / `skipped` / `failed`。

## 3. 一致性说明

- 入参校验（合法通过/非法拒绝）与 SKILL.md「场景 / When to Use」的关键词识别保持一致。
- 出参结构与 `references/deploy-guide.md` §6「资源释放」（先查再删、逐个验证）及 §5「验证」的输出约定保持一致。
- 本契约不引入任何凭据字段：token/AK/SK 一律仅经环境变量注入，不进入入参或出参 JSON。