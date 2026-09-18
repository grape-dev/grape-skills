# A2A 交办 Issue Agent（blog-vod Agent 用）

> 配套 `skills/vod/feedback-loop/blog-vod/SKILL.md`。认证使用 Grape API token `$GRAPE_SESSION_TOKEN`（严禁使用 GitCode token 调用 Grape 接口）。

## 触发时机

blog-vod 完成以下全部动作后，**必须** A2A 交办 Issue Agent：

1. Issue 标签已添加（至少 `blog-vod` + `type:feature`）
2. 「博客需求清单」已发布到 Issue 评论（作为续跑依据与下游继承上下文）
3. 需求已收敛（或已通过默认值补齐，并在清单中标注）

不可跳过此步骤直接交给 Coding/QA/SRE。blog-vod 的职责边界到需求收敛为止，后续流转由 Issue Agent 主导。

## 重复交办检查（必须做）

A2A 前先检查 prompt 中的 Issue Pipeline 信息：若 pipeline 已包含 `issue:a2a_event`
（即上一个 VOD 或其他 Agent 已 A2A 交办过 Issue Agent），**不要重复交办**——只更新评论即可。

## A2A 示例

```bash
curl -s --max-time 30 -X POST https://worker.grapedev.cn/api/a2a \
  -H "Authorization: Bearer $GRAPE_SESSION_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "agent": "issue",
    "payload": {
      "repository": "'"$REPO_FULL_NAME"'",
      "issue_number": "'"$ISSUE_NUMBER"'",
      "context": "博客需求已收敛。标签已添加 blog-vod/type:feature，需求清单已发布到 Issue 评论（供继承）。请 Issue Agent 接力进行分类确认、Spec 生成、指派并触发 Coding Agent。"
    }
  }'
```

## 字段规则（服务端强制校验，必须遵守）

1. `issue_number`（Issue 编号）**必填**：必须填写当前任务关联的真实 Issue 编号；无法确定则不调用 A2A，在评论中说明。
2. `pr_number`（PR 编号）**可选但有则必填**：涉及 PR 时必须传入；没有则不传，严禁将 PR 编号填入 `issue_number`。
3. `repository` 与 `account` 必填，传 `owner/repo` 全称。

## 成功判定

- 响应包含 `"status":"ok"` 且 `"seq"` 为非零数字：交办成功
- 响应 `"seq":0` 或 `"skipped"`：交办被跳过，检查目标 Agent 是否配置了 subscribe_events 去重

## 失败降级

A2A 调用失败时（网络错误/超时/非 2xx）：

1. 重试最多 3 次（每次间隔数秒）
2. 仍失败则在 Issue 评论告知「A2A 交办 Issue Agent 失败，请手动触发」
3. 在最终输出的 `next_step` 字段标注「需人工介入：Issue Agent 未自动接手」

## 注意事项

- `context` 应包含 blog-vod 的收敛结论摘要（「博客需求清单」关键字段），供 Issue Agent 继承上下文。
- A2A 成功后 Issue Agent 会接管 stage（从 vod 推进到 issue）。
- Grape A2A 接口（`/api/a2a`）与 GitCode API（`api.gitcode.com`）是两套独立服务，token 严禁混用：
  A2A 用 `$GRAPE_SESSION_TOKEN`，GitCode 操作用 `$BOT_GITCODE_TOKEN`。