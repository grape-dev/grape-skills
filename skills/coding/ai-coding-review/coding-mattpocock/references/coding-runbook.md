# Coding-MattPocock 执行走查表（runbook）

> 目的：把「Spec→tickets → seams 协商 → TDD → bug 反馈环 → 原型 → PR → A2A」的**步骤 + 确切命令**固化，Agent **照着执行、不要查 `--help`**。
> 环境变量：`$REPO_OWNER`/`$REPO_NAME`/`$ISSUE_NUMBER`/`$REPO_FULL_NAME`/`$PR_NUMBER`/`$GRAPE_WORK_BRANCH`。owner 只用 `$REPO_OWNER`。
> 分支纪律：直接用预置 worktree 分支 `feat/issue-{n}`；PR base = `$WORK_BRANCH`（不硬编码 main）。
> 防抖纪律：一条命令取到即继续；命令失败先看完整错误；owner 不硬猜。

---

## 统一流程

### Step 0 · 前置 + 读上下文 + 分支（必须最先）
```bash
# 工作基线（PR base）
WORK_BRANCH="${GRAPE_WORK_BRANCH:-$(grape git-repo repo --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out | jq -r '.default_branch // "main"')}"
echo "$WORK_BRANCH" > /tmp/work_branch.txt
grape git status                                  # 确认在 feat/issue-{n}
grape git config user.name  "$BOT_USERNAME"
grape git config user.email "$BOT_USERNAME@noreply.git.com"

# 项目/仓库线索
grape repos project info --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out
grape git-repo pulls get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out 2>/dev/null
```

### Step 1 · 读 Spec / tickets（必做）
```bash
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```
- 提取 Spec（用户故事/实现决策/测试决策/Out of Scope）+ tickets 列表（含 Blocked-by）。
- 执行顺序按「可释放前沿」：blockers 完成的切片先做；依赖末完成 → 说明阻塞，不空做。

### Step 2 · 协商测试 seams（必做，一 seam 一测试）
- 对首个切片，明确**公开接口/测试 seam**（用户可见行为，不测内部）；必要时在评论声明 seam 计划。
- 复用已有 seam > 新建；新 seam 放尽量高处；理想整库 seam 少而高。

### Step 3 · TDD 逐竖切片实现（必做）
对每个切片：**红 → 绿 → 提交**：
```bash
# ① 红：写失败测试（只测行为，不测实现细节）
grape git add -A && grape git commit -m "test(#$ISSUE_NUMBER): {切片} 先写失败测试"
# ② 绿：最小实现使其通过
grape git add -A && grape git commit -m "feat(#$ISSUE_NUMBER): {切片} 实现"
# ③ push
grape git push origin "feat/issue-$ISSUE_NUMBER"
```
- 一竖切片一测试一提交；不加未来测试、不做投机抽象。
- 反模式避免：实现耦合测试 / 同义反复断言 / 水平切片（先写全部测试再全部实现）。

### Step 4 · Bug 修复路径（仅遇 bug 时，先可红反馈环）
- 先建**能对当前 bug 变红的测试**（复现用户症状的精确断言），再最小化复现，再 3-5 假设排名，再插桩，再修复，回归测试。
- 无红测试不进假设/修复；无法建红测试 → 显式说明并求环境/artifact。

### Step 5 · 原型（仅设计不确定时）
- 一次性原型回答设计问题（HTML 或几版 UI 变体）；结论并入 Spec/决策，**不留入交付**或显式 `prototype/` 标记。

### Step 6 · 自检（建 PR 前必做）
- 对照 Spec 逐切片核对：需求缺项 / 越界实现；每切片有绿测试；Seam 计划留痕。
- 不通过 → 修后再建。

### Step 7 · 建 PR + Issue 评论（必做）
```bash
WORK_BRANCH="$(cat /tmp/work_branch.txt)"
grape git-repo pulls create --owner "$REPO_OWNER" --repo "$REPO_NAME" \
  --json '{
    "title": "feat: #'"$ISSUE_NUMBER"' {标题}",
    "head": "feat/issue-'"$ISSUE_NUMBER"'",
    "base": "'"$WORK_BRANCH"'",
    "body": "## Summary\n\n{最小可视化：伪码/树/diff}\n\n## Evidence\n- Before: {失败/旧}\n- After: {通过测试运行}\n\n## Merge Danger\n**Door:** two-way\n**Blast Radius:** {..}",
    "related_issue_nums": ["'"$ISSUE_NUMBER"'"],
    "auto_close_issues": true
  }' --json-out
# PR 编号 → pulls get html_url → Issue 评论
```
- ⚠️ 关联字段用 `related_issue_nums`（Issue 号数组，非 owner/repo#N）。

### Step 8 · A2A 交办 qa-mattpocock（必做）
```bash
grape a2a handoff --json '{
  "agent": "qa",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": '"${PR_NUMBER:-0}"',
    "context": "Spec 已实现（切片 N），PR #{'$PR_NUMBER'} 已创建（含 Evidence）。原始 Spec 评论在 Issue。请做两轴审查（Standards vs Spec）+ merge danger 门。"
  }
}' --json-out
```
- 场景无 qa 节点 → 评论说明，不 A2A。

### Step 9 · 任务完成流程（必做）
按 SKILL「任务完成流程」调用 `grape tasks complete`（next_step=`a2a_qa` 或 `reply_comment`）。`already:true` 忽略，结束任务。

---

## 错误排查速查

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook/reference；仍不确定 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 字段越界，看 `grape <g> <v> --help` Body fields 删多余 |
| `git commit` 被拒（无身份） | 先 `grape git config user.name/user.email` |
| `pulls create` 关联字段报错 | `related_issue_nums`/`auto_close_issues`；报错删 留 title/head/base |
| 测试失败 | 修复断言（对行为不依赖时序/实现细节）再跑 |
| 401/403 | 说明凭据失效/需 `grape_`，不换 token |

## 明确禁止

- ❌ 不协商 seams 直接开测 / 横向写一堆测试再实现。
- ❌ 无红测试就进 bug 假设与修复。
- ❌ 建 PR 前不自检；直接合入 / 部署。
- ❌ 裸 `git`（一律 `grape git`）。
- ❌ 硬编码 `base: main`（用 `$WORK_BRANCH`）。
- ❌ 不因"等待"跳过 Step 收尾（tasks complete）。