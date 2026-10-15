# VOD-Advance 执行走查表（runbook）

> 目的：把 VOD 处理 Issue 的**识别 + 路由 + 各场景步骤命令**固化，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名）、`$ISSUE_NUMBER`、`$REPO_FULL_NAME`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`。
> ⚠️ **owner 只用 `$REPO_OWNER`**；`$ACCOUNT` 是触发人 actor，仅用于 A2A payload `account`。
> **评论前缀硬规**：评论 body 一律以 `[VOD Agent]` 开头。
> 命令取舍速查：读 Issue 聚合用 `issues detail`；评论用 `git-repo issues comments create`；列目录/查文件用 `git-repo tree`（`--depth single`）/ `contents --path ... --raw`。

### 防抖纪律（必须遵守）

1. **owner 只用 `$REPO_OWNER`**：不要把它换成 `Jason7602` 等猜测值；若命令报错/403，先核对 `$REPO_OWNER` 是否注入为空（环境问题），**不要改 owner 重复试错**。
2. **一条命令取到即继续**：`issues detail` 已含阶段/事件/路线图；`tree --depth single` 一次看清结构，再按需读 2-3 个文件；**不要重复 `tree`/`list` 换参数折腾**。
3. **命令失败先看完整错误**：先看 `--help` 或完整 stderr，**不重复相同命令试错**；不确定命令/参数先 `grape <组> --help` 一次确认。
4. **收敛门禁**：功能/Bug 收敛前必须先做「可推断 vs 必澄清」判定（见对应 flow 与 `requirement-elicit-guide.md` §二）；并列歧义 → 澄清分支。

---

## 统一流程

### Step 0 · 项目知识基线（必须最先，先调查）
```bash
grape repos project info --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out
grape knowledge stats --repo "$REPO_FULL_NAME" --json-out
grape knowledge list --repo "$REPO_FULL_NAME" --source agent --json-out
grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --depth single --json-out   # 仓库结构
```
- 基线可用 → 基于它分析；`degraded=true`/files 空 → 降级用 `git-repo repo`/`tree`/`contents README` 补；标注 `[degraded]`。
- 这是「先自主调查」的事实基础：功能/Bug 先在此定位相关模块/代码/线索，能收敛直接收敛。

### Step 1 · 读 Issue 上下文（必做）
```bash
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out   # 按需
```

### Step 2 · 需求类型识别（必做，先判定再路由）
对照「需求类型识别信号」（`references/requirement-elicit-guide.md` §一）与 SKILL「需求类型识别表」判定：

| 信号 | 类型 | 路由 |
|------|------|------|
| 功能动词（增加/支持/扩展/能够/需要） | 功能 | `feature-flow.md` |
| 异常/报错/失败/不工作/崩溃/坏了 | Bug | `bug-flow.md` |
| 询问项目/功能/安装/部署/使用 | 咨询 | `consult-flow.md` |
| 提交 PR/更新 PR/定位 Bug/检视 PR/跑测试 等执行指令 | 任务型 | `task-flow.md` |

- 无法判定 → 按功能需求引导一次澄清（或按功能收敛），不硬猜。
- **识别完成 → 读对应 flow 并执行其步骤**；各 flow 结尾均回到本 runbook「Step 收尾」。

### Step 3 · 路由到对应 flow（必做）
- **功能**：读 `references/feature-flow.md`——自主调查现状 → 四要素（仅调查后不清才问）→ 结构化收敛评论 → A2A issue。
- **Bug**：读 `references/bug-flow.md`——自主调查定位 → 六要素（仅调查后不清才问）→ Bug 结构模板 → A2A issue。
- **咨询**：读 `references/consult-flow.md`——只读查询 → 评论答复；**VOD 闭环，不 A2A、不建 Issue**。
- **任务型**：读 `references/task-flow.md`——识别 + 边界判断（安全直 A2A / 危险委婉答复）；**不执行任何任务**。

### Step 4 · 任务完成流程（必做，任何分支都必须执行到最后）
> ⚠️ **强约束：收尾 = `grape tasks complete`**，最后一个动作；评论发完 ≠ 任务完成。结构化字段**必须真实填充**。

按分支选定 `next_step`：
| 分支 | next_step |
|------|-----------|
| 功能/Bug 收敛并 A2A issue | `a2a_issue` |
| 咨询已答复 / 任务型已答复 | `reply_comment` |
| 澄清追问 / 需求不清晰 | `a2a_need_clarify` |

先输出人类可读摘要（需求类型 + 调查结论 + 收敛/答复/A2A），再调用：
```bash
grape tasks complete --json '{
  "result_text": "结论：Issue #'"$ISSUE_NUMBER"' 已按需求类型处理。",
  "next_step": "reply_comment",
  "actions": ["项目知识基线", "需求类型识别", "自主调查场景", "<结构化收敛/咨询答复/任务型答复>", "A2A 交办（按需）"],
  "conclusion": "<需求类型>: <收敛/答复结论>；<下一步>",
  "artifacts": ["Issue #'"$ISSUE_NUMBER"' 评论（comment id=XXXXXX）", "A2A event seq=XXXX（如交办）"],
  "issue_summary": "<需求类型> | <摘要> | <后续>"
}'
```
> `already:true` 忽略。**然后结束任务**。

---

## 错误排查速查

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook/flow 抄写；仍不确定 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 字段不在允许集，看 `grape <g> <v> --help` Body fields 删多余字段 |
| `contents` 路径不存在 | 用 `tree --depth single` / `contents --path ""` 定位 |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT，本技能不涉及 |
| A2A 交办失败 | 重试 ≤3 次；仍失败 → 评论说明 + next_step 标注人工介入 |

## 明确禁止

- ❌ 修改 Issue 标签/里程碑/分配（issue agent 职责）。
- ❌ 修改代码 / 建 PR / 执行任何任务型动作（VOD 不执行任务）。
- ❌ 危险任务（删除/重启/付费/不可逆/合并未审）直交后端 agent——委婉答复不在职责范围。
- ❌ 咨询类 A2A / 建 Issue（VOD 闭环）。
- ❌ 用裸 `git`（一律 `grape git`，保证凭据注入）。
- ❌ 不因"等待用户回复"跳过 Step 收尾（tasks complete）。