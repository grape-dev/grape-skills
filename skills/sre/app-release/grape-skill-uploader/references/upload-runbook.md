# grape-skill-uploader 执行走查表（upload-runbook）

> 目的：把「打包上传 skill」的**每一步要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名）、`$REPO_FULL_NAME`（owner/repo）、`$ISSUE_NUMBER`、`$PR_NUMBER`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> ⚠️ **owner 只用 `$REPO_OWNER`**；`$ACCOUNT` 是触发人 actor，**仅用于 A2A payload `account` 字段**。
> **评论前缀硬规**：所有评论 body 一律以 `[Skill Uploader Agent]` 开头。

---

## 统一流程（上传 skill）

### Step 0 · 前置确认（必做）
```bash
# ① 当前任务 / Issue / 前序 A2A payload
grape tasks current --json-out
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape events detail --seq {seq} --json-out   # 读前序交接（QA A2A / PR merged）

# ② 确认 worktree / 可访问 skill 目录
grape git status   # 确认仓库根目录（含 .grape/skills/ 或 skills/）
```
- 从 payload/context 提取：触发点（QA 通过 / PR 合并）、skill 目录路径、agent_type、pr_number；缺失则用 `grape issues clarify` 追问。

### Step 1 · 触发点判定 + skill 目录定位（必做）
**触发点判定**（见 `references/upload-workflow.md` §一）：
- A2A context 含「审查通过」/「QA passed」/「skill ready」→ 触发点 (b) 预注册上传
- A2A context / 事件含「PR merged」/「已合并」/「merge」→ 触发点 (c) 正式上传；先用 `pulls get` 确认 merged
```bash
grape git-repo pulls get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out   # (c) 确认 merged
grape git-repo pulls files --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out # 定位 skill 目录
```
**skill 目录定位**：从前序 payload / PR 变更筛出 `.grape/skills/{agent_type}/{name}/`（本流水线生成地），兼容 `skills/{agent_type}/{name}/` / `skills/{name}/`。
- agent_type：从目录路径（`.grape/skills/{agent_type}/…`）或 A2A context 提取。

### Step 2 · 打包 skill 为 ZIP（必做）
```bash
# ⚠️ 打包路径从 name 目录开始，聚焦技能本身：进入 name 父目录后打包 name，ZIP 顶层即 {name}/（含 SKILL.md）
#    不要带 .grape/skills/{agent_type}/ 多层前缀（会导致打包层数过多、服务端无法定位）。
SKILL_PARENT=".grape/skills/{agent_type}"    # name 的父目录：.grape/skills/{agent_type} 或 skills/{agent_type}（兼容旧路径）
cd "{worktree_root}/$SKILL_PARENT"
zip -r "/tmp/{name}.zip" "{name}" 2>/dev/null \
  || python -c "import shutil; shutil.make_archive('/tmp/{name}', 'zip', '.', '{name}')"

# 校验 ZIP 结构：首层应为 {name}/SKILL.md（无多余层级）
unzip -l "/tmp/{name}.zip" 2>/dev/null | head -20
```
> ⚠️ ZIP 顶层 = `{name}/`（skill 目录本身，含 SKILL.md + references/）；不要带入 `.grape/skills/{agent_type}/` 或 `skills/{agent_type}/` 等父路径；也不要从 skill 目录内部打（丢失 `{name}/` 层）。

### Step 3 · 上传（必做）
```bash
grape skills upload --file "/tmp/{name}.zip" --scope repo --repo "$REPO_FULL_NAME" --agent_type {agent_type} 2>&1 | tail -20
```
- 成功 → 记录返回的 `skill_id`。
- **403** → 检查 token 作用域（`skills` 为 dual，`tk_` 应可用；若仍 403 说明需 `grape_`）→ 评论说明并收尾，不回交 coding。
- 其他失败 → 进入 Step 5 失败处理。

### Step 4 · 上传后验证（必做，见 `references/verify-flow.md`）
```bash
grape skills list --scope repo --repo "$REPO_FULL_NAME" --json-out          # 确认已注册
grape skills detail --skill_id {skill_id} --json-out                         # 确认 SKILL.md 可读
grape skills sub list --skill_id {skill_id} --json-out                       # 确认 references/ 完整
```
- 未出现 → 重试上传 1 次；仍不命中 → 进入 Step 5。

### Step 5 · 失败处理（仅失败时）
| 错误 | 处理 |
|------|------|
| HTTP 422（ZIP/请求体格式） | 检查 ZIP 结构 → 评论附 `detail` → A2A 回交 coding |
| 500/502/503 | 重试 1 次（间隔 5s）；仍失败 → 评论报障，收尾 |
| 上传 200 但验证未命中 | 重试 1 次；仍失败 → 评论报障，附 skill_id（若有） |
| ZIP 打包失败（zip 缺失） | 用 `python shutil.make_archive` 兜底；仍失败报障 |

失败回交 coding（agent 名，非技能名）：
```bash
grape a2a handoff --json '{
  "agent": "coding",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": '"${PR_NUMBER:-0}"',
    "context": "skill {name} 上传失败：{错误摘要}，请排查 skill 目录/ZIP 格式。"
  }
}' --json-out
```

### Step 6 · Issue 评论 + 收尾（必做）
```bash
# 成功
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Skill Uploader Agent] ✅ skill {name} 已上传注册为仓库级 skill（scope=repo, skill_id={id}）"}'
# 失败
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Skill Uploader Agent] ⚠️ skill {name} 上传失败：{原因}，已回交 coding 排查。"}'
```

### Step 7 · 任务完成流程（必做，任何分支都必须执行到最后）
> ⚠️ **强约束：收尾 = `grape tasks complete`（情形一）**，最后一个动作；评论发完 ≠ 任务完成。结构化字段**必须真实填充**。

```bash
grape tasks complete --json '{
  "result_text": "结论：skill {name} <已上传 scope=repo / 上传失败>。",
  "next_step": "done",
  "actions": ["打包 {name}.zip", "skills upload", "skills list/detail/sub-list 验证", "Issue 评论", "A2A 回交 coding（失败时）"],
  "conclusion": "<已上传 skill_id={id} 验证通过 / 上传失败原因，已回交 coding>",
  "artifacts": ["skill_id={id}", "Issue #'"$ISSUE_NUMBER"' 评论（comment id=XXXXXX）", "A2A event seq=XXXX（失败时）"],
  "issue_summary": "skill <已上传/上传失败> | {name} | scope=repo"
}'
```
> 失败回交 coding 时 `next_step=a2a_coding`，`conclusion` 如实说明；成功时 `done`。`already:true` 忽略。**然后结束任务**。

---

## 错误排查速查

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook/reference；仍不确定 `grape commands <关键词>` |
| `skills upload` 403 | token 作用域问题：`skills` 为 dual 应 `tk_` 可用；仍 403 → 说明需 `grape_`/JWT 权限，评论告知后收尾 |
| `skills upload` 422 | ZIP/请求体格式错，检查 ZIP 顶层是否为 `{name}/SKILL.md`（勿带父路径层级） |
| `zip` 缺失 | 用 `python -c "import shutil; shutil.make_archive(..., 'zip', '.', '$SKILL_DIR')"` |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 契约字段错误 | 看 `grape <g> <v> --help` Body fields 删多余字段 |

## 明确禁止

- ❌ 上传 QA 未通过 / 未合并的 skill（以 A2A context / PR merged 状态为准）。
- ❌ `issues update` 改写 Issue body（结果/失败用 comments 发布）。
- ❌ A2A 交办写技能名（如 `grape-skill-generator`）——失败回交用 agent `coding`。
- ❌ 修改 skill 目录内容 / 直接 curl 直连 API / token 落盘。