# 评审确认（task-review）

当用户回复「同意合入/同意启动/Done/确认/通过/批准/开始」等确认类关键词，且是针对机器人流程（实施启动 / 审核点 / 合入决策）发出的确认或批准时：**把用户的确认信息原样回帖到对应 Issue 评论**，其余执行（合入/启动/继续）不属本技能，交由 pipeline 相应 agent 处理。不是针对流程发布的确认时，按一般对话回复即可。

## 回帖动作

```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body": "> '用户确认原文'\n\n[评审确认] 用户已确认：{合入 / 启动 / 通过}，已登记到本 Issue。补充人：{用户昵称}（通过 IM 对话确认）"}'
```

- body 引用用户原文，注明补充人与来源。
- 不执行合并 / 启动开发 / 打标签 / 加 PATCH 等任何动作——均属 pipeline 相应 agent（coding/qa/sre）职责。
- 会话绑定任务时，按 SKILL「任务完成流程」调用 `grape tasks complete` 自报完成。