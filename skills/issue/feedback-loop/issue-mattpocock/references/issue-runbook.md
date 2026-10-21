# Issue-MattPocock 执行走查表（runbook）

> 目的：把「Triage → Spec → tickets → A2A」的**步骤 + 确切命令**固化，Agent **照着执行、不要查 `--help`**。
> 环境变量：`$REPO_OWNER`/`$REPO_NAME`/`$ISSUE_NUMBER`/`$REPO_FULL_NAME`。owner 只用 `$REPO_OWNER`。
> 评论前缀硬规：`[issue agent]`。
> 防抖纪律：一条命令取到即继续；命令失败先看完整错误；owner 不硬猜。

---

## 统一流程

### Step 0 · 项目知识基线 + 领域词汇（必须最先）
```bash
grape repos project info --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out
grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --depth single --json-out
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path GLOSSARY.md --raw 2>/dev/null
```

### Step 1 · 读需求单（vod-mattpocock 交棒，必做）
```bash
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```
- 从评论中提取「结构需求单」（目标/用户故事/验收/Out of Scope）。缺失 → 评论说明并 A2A 回 vod 澄清，或标「待澄清」。

### Step 2 · Triage 分诊（必做）
- **查重（按域概念）**：`grape issues list --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out` + `git-repo contents {相关目录}` 检索已有实现（用 GLOSSARY 词汇，不只按请求措辞）。
  - 已实现 → wontfix：评论说明位置并 close（不写 out-of-scope）。
- **验证 claim**：bug 需求尝试复现/核对（`commits`/`pulls`）；无法验证 → 标注「未验证」。
- **先前拒绝**：若存在 out-of-scope 规划，对照复查；相似已拒绝 → wontfix。
- 输出：分诊结论 + codebase 摘要（相关实现/是否已存在）。

### Step 3 · Spec 生成（必做，内化 to-spec）
按 `references/spec-and-tickets-guide.md` §一 模板生成 Spec（Problem / Solution / User Stories 长表 / Implementation Decisions / Testing Decisions / Out of Scope），评论发布（不改写 body）：
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[issue agent] Spec（mattpocock 版）：\n\n{§一 模板}"}' --json-out
```

### Step 4 · 垂直切片 tickets（必做，内化 to-tickets）
- 将 Spec 拆为**竖切片**：每条 ticket 一条完整可演示路径（穿 schema/API/UI/测试），声明 **Blocked-by**。
- 前置 refactor（改动面横跨多调用点）作为独立 ticket，先 expand-contract。
- 承载方式（grape 化）：评论列出 tickets 表 + Blocked-by；或按需 `git-repo issues create` 建子任务（依赖平台是否支持 sub-issue）。
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[issue agent] 切片 tickets：\n\n## Ticket 1 ...\n## Blocked by ...\n..."}' --json-out
```

### Step 5 · A2A 交办 coding-mattpocock（必做）
```bash
grape a2a handoff --json '{
  "agent": "coding",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": 0,
    "context": "Spec 与切片 tickets 已评论发布（含 Blocked-by 阻断图）。请按 mattpocock 流程：先协商测试 seams → TDD 逐切片实现。Spec 摘要：<..>"
  }
}' --json-out
```
- A2A 前查 pipeline 已含 `coding:a2a_event` → 不重复 A2A，评论即可。

### Step 6 · 任务完成流程（必做）
按 SKILL「任务完成流程」调用 `grape tasks complete`（next_step=`a2a_coding` 或 `reply_comment`）。`already:true` 忽略，结束任务。

---

## 错误排查速查

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook/reference；仍不确定 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 字段不在允许集，看 `grape <g> <v> --help` Body fields 删多余字段 |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT，本技能不涉及 |
| A2A 交办失败 | 重试 ≤3 次；仍失败 → 评论说明 + next_step 标注人工介入 |

## 明确禁止

- ❌ 修改代码 / 建 PR / 部署（coding/sre 职责）。
- ❌ 查重只看措辞不讲域概念（漏掉"已实现"）。
- ❌ 危险操作（删除/不可逆）直交后端。
- ❌ 裸 `git`（一律 `grape git`）。
- ❌ 不因"等待"跳过 Step 收尾（tasks complete）。