# grape CLI 参考（common-skill-creator 子集）

> 本文件是 **grape CLI 命令契约**（v0.3.x，经本机 `grape --help` 实测核对）。平台交互（PR/评论/A2A/任务）一律走 grape CLI——**禁止 curl 直连平台 API**。规范源拉取（`fetch_checks.js` 的 https 请求）属外部规范源域，与平台交互严格区分。

## 1. 安装与自愈

前置检查（硬约束② + 三 前置检查门第 5 项）发现 `grape` 未安装或版本过低（< 0.3.2）→ 按 `references/grape-cli-installation.md` 自动安装/升级，不直接报障。安装后重试 `grape --version`——仍失败 STOP。

## 2. 认证（自动，无需配置）

`grape` 自动读取服务端注入的 `$GRAPE_SESSION_TOKEN`——**严禁**寻找/读取其他 token 用于 grape 命令。

> ⚠️ token scope 注意（实测 CLI 帮助确认）：
> - `pulls merge` / `tasks complete` / `a2a handoff` / `issues comments create` → **session token（tk_）可用** ✅
> - `scenes detail` 等 scenes 组 → **session token 会 403**（需 GRAPE_API_TOKEN——agent 环境不注入）→ 本技能不使用 scenes 组命令

## 3. 命令子集（本技能真实使用）

### 3.1 创建 PR（Step 7，脚本封装——不手动敲 pulls）

`scripts/create_common_skill_pr.sh` 内部使用：

```bash
grape git-repo repo --owner "$OWNER" --repo "$REPO" --json-out          # 默认分支（--base 可覆盖）
grape git-repo pulls list --state open --per_page 100 --json-out        # 幂等查重（head.ref 匹配）
grape git-repo pulls create --json '{"title":"...","head":"...","base":"...","related_issue_nums":["owner/repo#N"],"auto_close_issues":true}'
grape git-repo pulls update --number "$PR_NUMBER" --json '{"body":"..."}'   # 补 PR body（幂等双保险）
grape git-repo pulls get --number "$PR_NUMBER" --json-out               # base 校验
```

> **契约字段（服务端 PRCreateBody 实测）**：关联 Issue 用 `related_issue_nums: ["owner/repo#N"]` + `auto_close_issues: true`——**不是** `inner_issue_nums`/`close_related_issue`（那是服务端 translate 后的 GitCode 内部名——pydantic 会静默忽略，关联/自动关闭不生效）。
> **设置审查人（assignees）**：grape 0.3.3 无此接口——脚本已跳过该步（原为 curl 直连平台 API，已按纪律移除）。

### 3.2 Issue 评论（Step 7 硬规则）

```bash
grape git-repo issues comments create \
  --owner "${REPO_FULL_NAME%/*}" --repo "${REPO_FULL_NAME#*/}" \
  --number "$ISSUE_NUMBER" \
  --json '{"body": "[Coding Agent] ✅ Skill 已创建并提交 PR\n\n{评论内容}"}'
```

- 评论 body 一律以 `[Coding Agent]` 开头（见 SKILL 4.6 输出格式）

### 3.3 A2A 交棒（Step 8）

```bash
grape a2a handoff --json '{"agent":"qa","payload":{"repository":"'"$REPO_FULL_NAME"'","account":"'"$ACCOUNT"'","issue_number":'"$ISSUE_NUMBER"',"pr_number":'"$PR_NUMBER"',"context":"Issue #'"$ISSUE_NUMBER"' skill 已创建，PR #'"$PR_NUMBER"' 已提交。请对 skill 进行功能验证。Skill 名称：{name}"}}'
```

- **agent 用场景标准节点名 `qa`**——不传技能名（#10 not_in_scene 教训）
- payload 必带 issue_number + pr_number（tester 拉取/合并/交棒依赖；平台从 payload 提取注入 `PR_NUMBER` 环境变量）

### 3.4 任务管理

```bash
grape tasks current          # 可选，确认当前任务
grape tasks complete --json '{"result_text":"<处理结论>","actions":[...],"conclusion":"...","artifacts":[...],"next_step":"..."}'
# 收尾协议：业务动作完成后（含 Step 7/8）先调 tasks complete，再输出 JSON 块（见 SKILL 4.8 任务收尾）
```

## 4. ❌ 不要尝试的命令（不存在或禁止使用）

| 命令 | 说明 |
|------|------|
| `grape tasks close / mine / start / status / clarify` | tasks 组仅有 complete/current/notify/wait |
| `grape git xxx`（透传） | **存在但不用**（0.3.3 实测：`grape git` = 本地 git 透传，会尝试注入平台凭据到 git 命令）——本技能 git 操作全部用**原生 git**（worktree 由平台准备），透传会引入凭据注入风险且无必要 |
| `grape api` | 已移除（0.2.2 起），且平台禁止直连 API |
| `grape knowledge context/content` | 不存在，知识基线由 prompt 内联注入 |
| `grape events detail --seq` | --seq 平台不注入，勿用 |
| `grape scenes detail` 等 scenes 组 | session token 403（需 GRAPE_API_TOKEN——agent 环境不注入）——本技能不用 |

## 5. 退出码 与 安全边界

- 命令失败：检查输出错误信息（401=token 无效 / 403=无权限），按 SKILL 一 安全硬约束②③区分处理——**不重试、不用其他 token 绕行**
- 安全边界：不用 grape commands 之外的方式拼平台 API；token 不落盘/不进日志/不进评论/不进脚本文件