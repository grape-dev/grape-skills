# grape-skill-uploader 执行走查表（upload-runbook）

> 目的：把「打包上传 skill」的**每一步要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量可直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名）、`$REPO_FULL_NAME`（owner/repo）、`$ISSUE_NUMBER`、`$PR_NUMBER`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> ⚠️ **owner 只用 `$REPO_OWNER`**；`$ACCOUNT` 是触发人 actor，**仅用于 A2A payload `account` 字段**。
> **评论前缀硬规**：所有评论 body 一律以 `[Skill Uploader Agent]` 开头。
> **skill 内容一律从仓库拉取**（`grape git-repo pulls files` + `git-repo contents`），**不要**在本地文件系统 `find`/`ls` 乱找——流水线生成物在仓库 `.grape/skills/` 下，worktree 本地未必 checkout。

---

## 统一流程（上传 skill）

### Step 0 · 前置确认（必做）
```bash
# ① 当前任务 / Issue / 前序 A2A payload
grape tasks current --json-out
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape events detail --seq {seq} --json-out   # 读前序交接（QA A2A / PR merged）
```
- 从 payload/context 提取：触发点（QA 通过 / PR 合并）、skill 目录路径、agent_type、pr_number；缺失则用 `grape issues clarify` 追问。
- ⚠️ `--seq` 缺省时事件 payload 在 `tasks current` 的 A2A context 里，读到即可，不必强求 `events detail`。

### Step 1 · 触发点判定 + skill 目录定位（必做）
**触发点判定**：
- A2A context 含「审查通过」/「QA passed」/「skill ready」→ 触发点 (b) 预注册上传
- A2A context / 事件含「PR merged」/「已合并」/「merge」→ 触发点 (c) 正式上传；先用 `pulls get` 确认 merged
```bash
grape git-repo pulls get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out   # (c) 确认 merged
grape git-repo pulls files --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out  # 定位 skill 目录（来源唯一）
```
**skill 目录定位**：从 `pulls files` 返回的变更清单中筛出 `{skill_dir}`（形如 `.grape/skills/{agent_type}/{name}/`，兼容 `skills/{agent_type}/{name}/` / `skills/{name}/`）：
- `agent_type` 从目录路径（`.grape/skills/{agent_type}/…`）提取；`{name}` 取最后一段。
- 从文件中列出该目录下的全部文件（含 references/）：`grape git-repo contents --path {skill_dir} --json-out`。

### Step 2 · 获取 skill 内容 + 打包 ZIP（必做）
> ⚠️ **优先本地 worktree；无本地目录时用 git-repo contents 直拉**，不要反复 `find`/`ls`。三步内定位不到即走 CLI 直拉。

```bash
skill_dir=".grape/skills/{agent_type}/{name}"   # 来源：Step 1 pulls files 筛选
# ① 本地 worktree 有该目录 → 直接用本地内容打包（cd 到 {name} 父目录）
if [ -d "{worktree_root}/$skill_dir" ]; then
  cd "{worktree_root}/${skill_dir%/*}"          # {name} 的父目录
  zip -r "/tmp/{name}.zip" "{name}" 2>/dev/null \
    || python -c "import shutil; shutil.make_archive('/tmp/{name}', 'zip', '.', '{name}')"
else
  # ② 本地没有 → 用 git-repo contents 拉取到 /tmp/{name}/，保证层级 = {name}/SKILL.md
  mkdir -p "/tmp/{name}/references"
  grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path "$skill_dir/SKILL.md" --raw > "/tmp/{name}/SKILL.md"
  # 逐个拉 references/ 下文件（文件名按 Step 1 列出的清单）：
  # grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path "$skill_dir/references/{f}" --raw > "/tmp/{name}/references/{f}"
  # 无 references/ 时跳过拉取。
  cd /tmp
  zip -r "/tmp/{name}.zip" "{name}" 2>/dev/null \
    || python -c "import shutil; shutil.make_archive('/tmp/{name}', 'zip', '.', '{name}')"
fi

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
- **503 且提示「OBS 存储未启用」** → 服务端配置阻塞，见 Step 5「503 服务端阻塞」，**不重试、不 A2A coding**。
- 其他失败 → 进入 Step 5 失败处理。

### Step 4 · 上传后验证（必做）
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
| HTTP 403（token 作用域） | 评论说明需 `grape_`/JWT 权限 → 收尾，**不回交 coding** |
| **HTTP 503 且提示「OBS 存储未启用」** | **服务端配置阻塞**：评论明确「需管理员启用服务端 OBS 存储后重新触发上传」→ 收尾（next_step=done，human 注释），**不重试、不 A2A coding** |
| 500/502/503（其他原因） | 重试 1 次（间隔 5s）；仍失败 → 评论报障，收尾 |
| 上传 200 但验证未命中 | 重试 1 次；仍失败 → 评论报障，附 skill_id（若有） |
| ZIP 打包失败（zip 缺失） | 用 `python shutil.make_archive` 兜底；仍失败报障 |

失败回交 coding（仅 422/内容类问题；agent 名，非技能名）：
```bash
grape a2a handoff --json '{
  "agent": "coding",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": '"${PR_NUMBER:-0}"',
    "context": "skill {name} 上传失败:{错误摘要}，请排查 skill 目录/ZIP 格式。"
  }
}' --json-out
```

### Step 6 · Issue 评论 + 收尾（必做）
```bash
# 成功
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Skill Uploader Agent] ✅ skill {name} 已上传注册为仓库级 skill（scope=repo, skill_id={id}）"}'
# 失败（OBS 服务端阻塞）
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Skill Uploader Agent] ⚠️ skill {name} 上传失败：服务端返回 HTTP 503（OBS 存储未启用）。非 skill 内容/ZIP 格式问题，需管理员启用服务端 OBS 存储后重新触发上传。"}'
# 其他失败
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Skill Uploader Agent] ⚠️ skill {name} 上传失败：{原因}，已回交 coding 排查。"}'
```

### Step 7 · 任务完成流程（必做，任何分支都必须执行到最后）
> ⚠️ **强约束：收尾 = `grape tasks complete`（情形一）**，最后一个动作；评论发完 ≠ 任务完成。结构化字段**必须真实填充**。

```bash
grape tasks complete --json '{
  "result_text": "结论：skill {name} <已上传 scope=repo / 上传失败>。",
  "next_step": "done",
  "actions": ["获取 skill 内容", "打包 {name}.zip", "skills upload", "skills list/detail/sub-list 验证", "Issue 评论", "A2A 回交 coding（内容类失败时）"],
  "conclusion": "<已上传 skill_id={id} 验证通过 / 上传失败原因（服务端 OBS 未启用则注明需人工处理），是否回交 coding>",
  "artifacts": ["skill_id={id}", "Issue #'"$ISSUE_NUMBER"' 评论（comment id=XXXXXX）", "A2A event seq=XXXX（失败时）"],
  "issue_summary": "skill <已上传/上传失败> | {name} | scope=repo"
}'
```
> 失败回交 coding 时 `next_step=a2a_coding`，`conclusion` 如实说明；成功或服务端阻塞（OBS）时 `done`。`already:true` 忽略。**然后结束任务**。

---

## 错误排查速查

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook/reference；仍不确定 `grape commands <关键词>` |
| `skills upload` 403 | token 作用域问题：`skills` 为 dual 应 `tk_` 可用；仍 403 → 说明需 `grape_`/JWT 权限，评论告知后收尾 |
| `skills upload` 503「OBS 存储未启用」 | **服务端配置阻塞**——评论报障（需启用 OBS 后重新触发），不重试不 A2A，next_step=done |
| `skills upload` 422 | ZIP/请求体格式错，检查 ZIP 顶层是否为 `{name}/SKILL.md`（勿带父路径层级） |
| 本地找不到 skill 目录 | 不要 `find`/`ls` 乱找——用 `pulls files` + `git-repo contents --raw` 从仓库直拉（见 Step 2 ②） |
| `zip` 缺失 | 用 `python -c "import shutil; shutil.make_archive(..., 'zip', '.', '{name}')"` |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 契约字段错误 | 看 `grape <g> <v> --help` Body fields 删多余字段 |

## 明确禁止

- ❌ 上传 QA 未通过 / 未合并的 skill（以 A2A context / PR merged 状态为准）。
- ❌ 在本地文件系统 `find`/`ls` 反复搜索 skill 目录（内容一律走 `git-repo contents` 直拉）。
- ❌ `issues update` 改写 Issue body（结果/失败用 comments 发布）。
- ❌ A2A 交办写技能名（如 `grape-skill-generator`）——失败回交用 agent `coding`。
- ❌ 修改 skill 目录内容 / 直接 curl 直连 API / token 落盘。