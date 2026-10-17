# 任务型需求流程（task-flow，strict 版）

> 适用：「提交 PR / 更新 PR / 定位 Bug / 检视 PR / 跑测试 / 部署 / 资源释放」等执行性指令。
> 核心：**VOD 只识别 + 边界答复，自身不执行任何任务**；strict 语义下**部署/资源释放直 A2A `sre`**，安全任务直 A2A 对应 agent，危险类委婉答复不在 VOD 职责范围。

## 0. 边界（最高优先级）

- ✅ VOD 识别任务类型 → 边界判断 →（strict 路由）直 A2A 对应 agent /（危险类）委婉答复。
- ❌ **VOD 自身不执行任何任务**（不 clone、不 push、不跑测试、不部署、不检视实现、不碰资源）。

## 1. 识别与边界判断（strict 路由表，见 `requirement-elicit-guide.md` §五）

| 任务 | 类别 | 处理（strict） |
|------|------|------|
| 部署 / 上线 / 发布 / 运行服务 / 启动应用 / 云资源 / ECS / 容器 | 🟢 安全（高危但合规） | 直 A2A **sre**（跳过中间环节） |
| 资源释放 / 销毁 / 删除资源 / 回收 | 🟢 安全（高危但合规） | 直 A2A **sre** |
| 提交 PR / 更新 PR / 推送分支代码 | 🟢 安全 | 直 A2A **coding** |
| 定位 Bug / 检视 PR / 审查代码 | 🟢 安全 | 直 A2A **qa** |
| 跑测试用例 / 构建验证 | 🟢 安全 | 直 A2A **coding**（或 **sre**，视构建/部署） |
| 删除分支 / 删除项目 / 删除 Issue | 🔴 危险 | **委婉答复，不执行不转交** |
| 重启测试环境 / 停服务 | 🔴 危险 | **委婉答复** |
| 涉及付费资源 / 不可逆操作（删库、清空数据） | 🔴 危险 | **委婉答复** |
| 直接合并 PR（冲突/风险需人拍板） | 🔴 危险 | **委婉答复** |
| 查看/查询某状态 | ✅ 并归咨询 | `consult-flow.md` |

> ⚠️ **危险类理由**：涉及项目危险操作，未授权给 VOD/后端 agent 无门控直接执行；应由具备相应权限的负责人处理。
> ⚠️ **部署/资源释放虽合规但高风险**：VOD **只做识别与移交**（直 A2A `sre`），**自身绝不执行任何部署/资源动作**（strict 硬线）。

## 2. 合规任务：直 A2A 对应 agent

```bash
# TARGET = sre（部署/资源释放）/ coding / qa（按上表）；先场景核验（scenes detail 含目标节点）再交办；≤3 次重试
grape a2a handoff --json '{
  "agent": "sre",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": {PR_NUMBER:-0},
    "context": "任务型需求：<用户指令摘要>。请执行。（strict：VOD 仅移交，不执行）"
  }
}' --json-out
```
- A2A 前查 pipeline 已含目标 `a2a_event` → 不重复 A2A，评论说明即可。

## 3. 危险任务：委婉答复（不执行、不转交）

- 仅发评论答复，**不 A2A、不建 Issue**：
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] 该操作涉及项目危险操作（<删除/重启/付费/不可逆/合并>），不在 VOD 的职责范围内。建议联系具备相应权限的负责人处理，处理前请谨慎确认。"}' --json-out
```

## 4. 收尾

回到 `vod-runbook.md` Step 4（tasks complete，next_step=`reply_comment`；A2A `sre` 交办时 `a2a_sre` 或手动标注）。