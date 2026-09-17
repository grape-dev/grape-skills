---
name: pr
version: 2.0.0
description: |
  Pull Request 全生命周期管理：接收 → 关联 Issue → 代码审查 → 安全扫描 → 合并检查 → 评论回复。
   当收到 pull_request_opened、pull_request_updated、push 或 PR 上的评论事件时使用此技能。
tools:
  - git
---
## 安全硬约束（必须遵守）

1. 调用 GitCode API 只用 prompt 注入的 \\，严禁从数据库/configs/日志/历史中寻找其他 token。
2. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据。
3. API 返回 403/无权限时：立即停止该操作并回复用户「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」，严禁尝试其他 token 或绕行手段。
4. token 不得写入任何文件/日志/评论。
5. 删除操作（如关 PR/删分支）需用户确认后执行。

## 输入事件 Schema（inputSchema）

本 Skill 由 GitCode 平台 Webhook 事件驱动，输入为事件负载（JSON 对象）。字段声明如下，执行前必须先完成 Schema 校验，**缺少必填字段或事件类型不受支持时拒绝执行**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `event_type` | string | 是 | 事件类型，枚举：`pull_request_opened` / `pull_request_updated` / `push` / `note_hook_pr`（PR 评论事件） |
| `repository` | string | 是 | 仓库全名 `{owner}/{repo}`，用于全部 API 路径 |
| `account` | string | 是 | 事件触发账号 |
| `pr_number` | string | 是 | PR 编号（pull_request 类事件必填） |
| `issue_number` | string | 否 | 关联 Issue 编号；仅在能确认为真实 Issue 时使用（A2A 服务端强制校验字段） |
| `head_sha` | string | 是 | PR 最新 head commit SHA，用于变更检视与行内评论 `commit_id` |
| `body` | string | 否 | PR 描述/评论内容，仅作 claim 参考，须打开原对象核对，不直接采信 |

校验规则：`event_type` 不在枚举内 → 拒绝执行并返回错误；缺少任一必填字段 → 拒绝执行；`issue_number` 缺失或无法确认 → A2A 能力项降级为跳过并在最终评论说明；`pr_number` 与 `issue_number` 相互独立，**严禁混用**。

# PR 运营

## 核心原则

### 验证外部 claim
PR body / commit message 里的 `fixes #N`、`tests pass`、`small fix` 都是 claim，不是事实。**先打开原对象核对**。

### Consult freely, decide carefully
可以自主拉取上下文做评估/review，但 merge/close/roadmap 等硬决策需人工确认。

### 所有评论统一在能力项执行完毕后发送
各能力项的分析结果先记录，最后统一合并为一条评论发送，不得在中间步骤单独发评论。

### 禁止探索 Grape 内部
不要执行 `ls`、`grep`、`cat` 等命令查看 workspace 目录、Grape 代码、日志文件或数据库。
**所有信息通过 GitCode API 获取**，不读取本地文件。

### 涉及代码需要继续优化时，A2A 通知 Coding Agent
审查发现代码需要继续优化/修改（存在 Critical 或 Required 级别问题），**必须通过 A2A 调用 Coding Agent 进行优化实现**，不得由 QA 直接改代码。

```bash
curl -X POST {{SERVER_URL}}/api/a2a \
  -H "Authorization: Bearer $BOT_GITCODE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "agent": "coding",
    "payload": {
      "repository": "'"$REPO_FULL_NAME"'",
      "account": "'"$ACCOUNT"'",
      "issue_number": "'"$ISSUE_NUMBER"'",
      "pr_number": "'"$PR_NUMBER"'",
      "context": "PR #'"$PR_NUMBER"' 审查发现代码需要优化：'"$REVIEW_SUMMARY"'"
    }
  }'
```

> ⚠️ **字段规则（A2A 服务端强制校验）：** `issue_number` 必填，必须是本 PR 关联的真实 Issue 编号（`$ISSUE_NUMBER`）。**若无法确定关联的 issue_number，则不要调用 A2A**，在最终审查评论中说明。`pr_number` 填写 PR 编号（`$PR_NUMBER`）；**严禁把 PR 编号填入 issue_number，两者不可混用**。

**触发条件**：review_comments 中存在 Critical 或 Required 级别问题需要修改代码时。
**响应**：A2A 返回后，将优化结论合并进最终审查评论。

## PR 分析（每次执行前先分析，⚠️ 必须按 1→2→3 顺序依次执行，上一步未完成不得进入下一步）

### 分析内容

1. **PR 配置检查（仅首次 `pull_request_opened` 事件时执行）**

   如果是 `pull_request_updated`、`push` 或 `note_hook_pr` 事件，**跳过此步**（配置已在 PR 创建时检查过）。

   读取 `references/pr-config-check.md` 执行检查，将不通过项记录到 `review_comments` 中（暂不评论，统一到最后处理）。

   如果有关联 Issue，在对应 Issue 中评论 `📌 关联 PR #{pr_number}`，对应 Issue 是 bug 则更新标签 `labels="bug,triaged"`。

2. **变更检视**

   判断是否有新的代码变更：

   ```bash
   cat ../.last_pr_review/{pr_number}.sha 2>/dev/null
   ```

   - 文件不存在或 SHA 不同 → 有新的变更，继续
   - SHA 相同 → 无新变更，**跳过以下所有能力项**（配置检查的评论仍会发送）

3. **任务类型判断**

   | 判断条件 | 任务类型（按顺序执行） |
   |---------|----------------------|
   | PR 修改了 `skills/` 目录下的文件 | 常规审查 → Skill 审查 → A2A 通知 → 回复评论 |
   | PR 包含 IaC 文件（K8s/Terraform/Dockerfile） | 常规审查 → IaC 审查 → A2A 通知 → 回复评论 |
   | 普通代码变更 | 常规审查 → A2A 通知 → 回复评论 |
   | 无新变更 | 不做处理，结束 |

### 分析结论示例

```
分析结论：
- 配置检查：Title 和 Description 通过，缺少 Labels 和 Assignee
- 变更检视：有新变更（首次审查）
- 任务类型：常规审查 + 安全扫描（IaC 文件变更）
- 需要执行：常规审查 → IaC 审查 → A2A 通知 → 评论回复
```

## 能力项

审查过程中对每个发现的问题直接在对应代码位置发布行内评论，最后在「评论回复」中发一条总结性评论。

### 能力一：常规审查

读取 `references/code-review-and-quality.md`，按 5 轴标准逐项审查（正确性、可读性、架构、安全、性能）。

**审查前先获取 PR 上已有行内评论，检查上次发现的问题是否已修复：**

```bash
# 获取 PR 所有行内评论
GET /repos/{owner}/{repo}/pulls/{number}/comments
```

对每条已有评论：
- 检查对应代码位置的代码是否已无问题（问题已修复）
- 如果已修复 → 调用 API 标记为已解决：

```bash
curl -s -X PUT -H "Authorization: Bearer $BOT_GITCODE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"resolved": true}' \
  https://api.gitcode.com/api/v5/repos/{owner}/{repo}/pulls/{number}/comments/{discussion_id}
```

其中 `discussion_id` 为评论对象的 `discussion_id` 字段（不是 `id` 字段）。

**然后审查新变更，对发现的每个问题发布行内评论：**

```bash
# 先获取 PR 变更文件列表和 diff 信息
GET /repos/{owner}/{repo}/pulls/{number}/files
```

从返回中获取每个文件在 diff 中的行号映射。然后在对应位置发布评论：

```bash
curl -s -X POST -H "Authorization: Bearer $BOT_GITCODE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "body": "[QA Agent] 🔴 Critical: 硬编码密钥，建议使用环境变量",
    "commit_id": "'"$HEAD_SHA"'",
    "path": "src/config.py",
    "position": 42
  }' \
  https://api.gitcode.com/api/v5/repos/{owner}/{repo}/pulls/{number}/comments
```

- `commit_id` 为 PR 最新的 head.sha（阶段 0 已获取）
- `path` 为问题所在的文件路径
- `position` 为问题在 diff 中的行号（从 PR files API 返回的 diff 中获取）
- 发现 Critical 或 Required 级别问题时，记录问题摘要用于后续 A2A 通知

### 能力二：Skill 审查

**仅当 PR 修改了 `skills/` 目录时执行。**

读取 `references/skill-review-and-quality.md`，审查技能文件的格式规范、完整性、引用路径、向后兼容性。

对发现的每个问题，参照能力一的格式在对应代码位置发布行内评论。

### 能力三：IaC 审查（仅当 PR 包含 IaC 文件）

额外扫描 IaC（基础设施即代码）文件：

| 文件类型 | 关注点 |
|---------|--------|
| Kubernetes Manifest | 特权容器、hostPath 挂载、`securityContext` 缺失、`runAsRoot`、资源限制未设置 |
| Terraform / OpenTofu | 公开 S3 bucket、`ingress` 全开放（`0.0.0.0/0`）、硬编码凭据、未启用加密 |
| Dockerfile | `FROM latest`、`ADD` 替代 `COPY`、root 用户运行、多余端口暴露 |
| Helm Chart | values 中的敏感默认值、RBAC 权限过度、镜像拉取策略不当 |

对发现的每个问题，参照能力一的格式在对应代码位置发布行内评论。

### 能力四：A2A 通知

**当审查发现问题需要修改时，调用 A2A 通知 Coding Agent（coding）处理。**

如果 review_comments 中存在 Critical 或 Required 级别的问题，说明需要修改代码。此时调用 A2A API 将审查意见传递给 Coding Agent：

```bash
curl -X POST {{SERVER_URL}}/api/a2a \
  -H "Authorization: Bearer $BOT_GITCODE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "agent": "coding",
    "payload": {
      "repository": "'"$REPO_FULL_NAME"'",
      "account": "'"$ACCOUNT"'",
      "issue_number": "'"$ISSUE_NUMBER"'",
      "pr_number": "'"$PR_NUMBER"'",
      "context": "PR #'$PR_NUMBER' 审查发现问题需要修改：'$REVIEW_SUMMARY'"
    }
  }'
```

> ⚠️ **字段规则（A2A 服务端强制校验）：** `issue_number` 必填（本 PR 关联的真实 Issue 编号 `$ISSUE_NUMBER`），**无法确定则不要调用 A2A**；`pr_number` 填 PR 编号；**严禁把 PR 编号填入 issue_number，两者不可混用**。

其中 `$REVIEW_SUMMARY` 为上述审查中发现的 Critical 和 Required 级别问题的汇总。
A2A 返回后，将 Coding Agent 的优化结论合并进最终审查评论（能力五）。

### 能力五：评论回复

**⚠️ 所有能力项执行完毕后，最后统一执行此步。不得在中间步骤单独发评论。**

将所有 `review_comments` 中的内容合并为一条评论发送：

```bash
POST /repos/{owner}/{repo}/pulls/{number}/comments
Authorization: Bearer $BOT_GITCODE_TOKEN
Content-Type: application/json
{"body": "[QA Agent] 审查报告\n\n## 配置检查\n- ✅ Title：通过\n- ⚠️ Labels：缺少分类标签\n\n## 代码审查\n✅ 通过\n\n## 安全扫描\n✅ 安全\n\n## 合并检查\n⚠️ 测试未确认"}
```

- body **必须**以 `[QA Agent]` 开头
- 汇总所有能力项的发现，按章节组织
- 如果全部通过，评论：`[QA Agent] 审查通过，所有检查项均正常。`

**跳过此步 = 事件未完成处理。**

**例外：** 变更检视判定 SHA 未变更而跳过时，不发评论。

## 输出规范

```markdown
## PR 审查报告

### 关联 Issue
- Closes #N — 状态: triaged

### 变更摘要
- 文件: X 个文件变更，+Y -Z

### 代码审查
**结论**: ✅ 通过 / ⚠️ 需修改 / ❌ 需重大修改

| 级别 | 文件 | 行号 | 问题 | 建议 |
|------|------|------|------|------|
| 🔴 | src/main.go | 42 | 硬编码密钥 | 使用环境变量 |

### 安全扫描
**结论**: ✅ 安全

### 合并检查
- ✅ 安全通过
- ✅ 审查通过
```

## 输出 Schema（outputSchema）

本 Skill 的输出固定为两部分：PR 上的一条统一总结评论（Markdown，见「输出规范」）+ 一个结构化 JSON 结果块（供上游消费与存档）。JSON 结构声明如下：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `skill` | string | 是 | 固定值 `pr` |
| `event_type` | string | 是 | 本次处理的事件类型 |
| `repository` / `account` / `pr_number` | string | 是 | 事件上下文回显 |
| `conclusion` | string | 是 | 枚举：`pass` / `needs_changes` / `needs_major_changes`（对应 ✅ / ⚠️ / ❌ 结论） |
| `review_comments` | array | 是 | 行内评论清单，元素含 `file`/`line`/`level`/`problem`/`suggestion` |
| `a2a_notified` | boolean | 是 | 是否已通过 A2A 通知 Coding Agent |
| `report_markdown` | string | 是 | 最终统一评论正文，**必须以 `[QA Agent]` 开头** |

校验规则：`conclusion` 必须是枚举值；`review_comments` 每个元素必须含 `file` 与 `line`；`report_markdown` 不以 `[QA Agent]` 开头视为非法输出，不得提交。

## 性能预算

| 指标 | 预算/基线 | 说明 |
|------|-----------|------|
| 单次执行时延（P95） | ≤ 60s（基线；暂无实测值时以此基线为准） | 5 个能力项线性执行；GitCode API 调用 ≤ 10 次（GET pulls/files/comments、PUT resolve、POST 评论、A2A），外部 API 时延占主导 |
| LLM 调用次数 | 1 次/事件 | 单次线性审查，无循环/自调用设计；A2A 交办后的优化实现计数归 Coding Agent 侧，不计入本 Skill |
| token 消耗 | ≤ 15k token/事件 | 全量文档约 42.5KB；输入以事件负载 + 变更文件 diff + API 响应为主 |
| API 调用预算 | ≤ 10 次/事件 | 全部为官方 GitCode API（api.gitcode.com / {{SERVER_URL}} 占位符 A2A 端点） |

上下文压缩策略：references 文档按能力项按需读取；变更检视只读 `.sha` 状态；PR diff 仅取变更文件部分；已有行内评论只摘要 status/path/line；所有发现合并为一条评论输出。

超预算处理：上下文/token 接近上限时停止继续拉取，基于已获取信息出结论；API 调用失败重试 1 次仍失败 → 按「可靠性声明」降级处理。

## 版本管理

- 当前版本：v2.0.0（Frontmatter 声明 `version: 2.0.0`；GS-008 规范已调整为 Low 级「不建议带 version」，保留 version 字段合规）。
- 版本识别：以仓库提交历史/本目录文件变更记录为版本基准，不依赖 Frontmatter version 字段。
- 新旧版本兼容：输入采用「只读已声明字段 + 忽略未知字段」策略，事件负载新增字段不影响既有行为，向后兼容。
- 灰度策略：行为变更（新增能力项、调整预算/基线）须在 `description` 中标注变更说明，并建议小流量观察后全量；服务端强制规则（如 A2A `issue_number` 校验）不随 Skill 版本变化。

## 可靠性声明

| 机制 | 声明 |
|------|------|
| 断点续跑（resume） | 每次审查后将 head SHA 写入 `../.last_pr_review/{pr_number}.sha`；中断后重新执行时，变更检视读取该文件：SHA 相同 → 跳过能力项直接结束（不重复审查/评论）；SHA 不同或文件缺失 → 从能力一继续。A2A 未返回时不阻塞流程，将「优化进行中」写入最终评论，由后续事件续跑 |
| 重试幂等 | 写操作均为「先查后写」：发送评论前先经 SHA 变更检视与已有评论比对去重；重复事件（SHA 未变）不重复发评论；同次运行内 review_comments 统一合并为一条评论，重试不产生重复副作用 |
| 资源清理 | 执行过程不创建临时文件/进程；唯一持久状态为 `../.last_pr_review/{pr_number}.sha`（设计内状态，覆盖写）；输出评论为 GitCode 平台托管资源，无本地残留；事件处理结束即结束任务 |
| 工具失败降级 | API 返回 403/无权限 → 停止该操作并回复用户既有人工指引，不换 token 绕行；A2A 失败或 issue_number 无法确定 → 跳过 A2A 并在最终评论说明；网络失败 → 重试 1 次，仍失败则基于已获取信息出结论并在评论中标注 |

## 依赖兼容声明

| 依赖 | 类型 | 最低版本/兼容范围 | 说明 |
|------|------|-------------------|------|
| git | CLI 工具 | ≥ 2.20（2020 年后主流发行版均满足） | Frontmatter 声明工具；本 Skill 不依赖特定 git 子命令 |
| curl | CLI 工具 | ≥ 7.58（支持 `-s`/`-X`/`-H`/`-d` 与 https） | 全部 API 示例调用 |
| bash（POSIX） | 运行时 | POSIX sh 兼容即可 | 示例命令基础，均使用固定参数 + 占位符 |
| GitCode API | HTTP API | api/v5（现有端点范围） | 端点为官方域名与 {{SERVER_URL}} 占位符；响应结构按实际返回为准 |

兼容策略：示例命令无版本特有语法；不安装任何全局依赖；依赖不可用时优先走平台 HTTP API 直连路径。

## 硬规则

| 行为 | 态度 |
|------|------|
| 按分析结论执行 PR 审查 | ✅ **必须做** |
| 审查发现问题需要修改时调用 A2A 通知 Coding Agent | ✅ **必须做** |
| 所有评论统一在最后发送 | ✅ **必须做，不得在中间步骤发评论** |
| ⚠️ **发送评论是最终强制步骤** | ✅ **必须做**（除非 SHA 未变更跳过） |
| 只通过 GitCode API 获取信息 | ✅ **必须做** |
| 直接合并 PR | ❌ **禁止**（仅输出检查结论） |
| 修改 PR 代码或文件 | ❌ **禁止** |
| 删除 PR | ❌ **禁止** |
| 回复 Token、密码等敏感信息 | ❌ **禁止** |
| 探索 workspace、Grape 系统文件 | ❌ **禁止** |

## 参考

需要调用 GitCode API 时，读取 `references/gitcode-api-reference.md`。

> ⚠️ **任务结束**：完成所有业务动作（审查评论/A2A 交办）后，输出最终 JSON 块并**结束任务**，不要继续思考或等待输入。
