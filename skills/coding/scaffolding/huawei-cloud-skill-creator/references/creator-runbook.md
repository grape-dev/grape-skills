# Creator Runbook（创建后必做交付步骤）

## 目的与触发

- **触发时机**：华为云 Skill 创建完成（六阶段严格流水线 Phase 1-6 全部通过）后**必须**执行本文件，不可跳过。
- **职责**：创建 PR → 清理 → A2A 交棒 tester，形成 creator → tester 协作闭环。
- **实现方式**：一律使用 **grape CLI**（禁止 curl 直连平台 API——grape v0.2.2 起已移除 `grape api` 逃生舱，契约未覆盖的端点不可调用）。

## 硬规则（行为 × 态度）

| 行为 | 态度 |
|------|------|
| 创建 PR 后在 Issue 发评论告知 | ✅ **必须做，不可跳过** |
| 创建 PR 后通过 A2A 通知 tester | ✅ **必须做，不可跳过** |
| A2A 必须携带 issue_number 和 pr_number | ✅ **必须做** |
| 一个 PR 只改一个 Skill 目录 | ✅ **必须做**（与 Phase 6「One PR submits only one Skill」一致） |
| PR base 指向仓库默认分支（main） | ✅ **必须做** |
| 平台 API 调用一律走 grape CLI | ✅ **必须做**（issues comments / pulls / a2a 等） |
| curl 直连 GitCode API / 找 `grape api` 逃生舱 | ❌ **禁止**（契约外端点不可调用） |
| 认证只用 `$GRAPE_SESSION_TOKEN`（grape 自动读取）；`$BOT_GITCODE_TOKEN` 等平台 token 已不注入 | ✅ **必须做** |
| 直接合并 PR | ❌ **禁止**（仅创建，交 tester 判断） |
| validate-skill.sh 未通过就创建 PR | ❌ **禁止** |

## 前置：grape CLI 就绪

grape CLI 为公开可安装包（`gitcode.com/grape-dev/grape-cli`），agent 环境通常已预装。检查与安装：

```bash
grape --version    # 要求 >= 0.3.2；未装或过低 → 自行安装，无需等待管理员
pip install git+https://gitcode.com/grape-dev/grape-cli.git   # 未装时安装（禁止 pip3 install grape——那是第三方公有包）
grape commands     # 可选：命令发现
# 认证自动：$GRAPE_SESSION_TOKEN（tk_ 前缀）由服务端注入，grape 自动读取，不需手动 export
# base_url 自动：$GRAPE_SERVER_URL → config → localhost 兜底
```

安装后仍失败（如 Python < 3.10）→ 输出「前置检查未通过：<原因>」并结束任务，不无限重试。

## 前置环境变量（系统已注入，直接用，不查 env）

| 变量 | 说明 |
|------|------|
| `GRAPE_SESSION_TOKEN` | 任务级临时 token（`tk_` 前缀），grape 自动读取（必填） |
| `REPO_FULL_NAME` | 仓库全名 `owner/repo`（必填；OWNER=`${REPO_FULL_NAME%/*}`、REPO=`${REPO_FULL_NAME#*/}`） |
| `ISSUE_NUMBER` | Issue 编号（必填） |
| `ACCOUNT` | 触发者账号（actor，A2A 载荷用；一般不用作 `--owner`）|
| `GRAPE_SERVER_URL` | 服务端注入的 API 地址（grape 自动读取） |

## Step 1: 创建 PR

1. **只 add 当前 Skill 目录**（不含其他技能目录），commit + push：
   ```bash
   git add "skills/{skill-path}/"
   git commit -m "feat(skill): 新增 {skill-name}"
   git push origin "feat/issue-${ISSUE_NUMBER}"
   ```
2. **幂等查重**：同 head 分支已有 open PR → 直接复用其 `number`，跳到 Step 2：
   ```bash
   grape git-repo pulls list --owner "${REPO_FULL_NAME%/*}" --repo "${REPO_FULL_NAME#*/}" --state open --per_page 100 --json-out
   ```
3. **获取仓库默认分支**（base 候选，不硬编码 main）：
   ```bash
   grape git-repo repo --owner "${REPO_FULL_NAME%/*}" --repo "${REPO_FULL_NAME#*/}" --json-out
   ```
4. **创建 PR**（`pulls create` 无 body 字段——body 用下一步 `pulls update` 补）：
   ```bash
   grape git-repo pulls create --owner "${REPO_FULL_NAME%/*}" --repo "${REPO_FULL_NAME#*/}" \
     --json '{"title":"feat(skill): 新增 {skill-name}","head":"feat/issue-'"$ISSUE_NUMBER"'","base":"'"${BASE_BRANCH:-main}"'","inner_issue_nums":"'"$REPO_FULL_NAME"'#'"$ISSUE_NUMBER"'","close_related_issue":true}'
   ```
5. **补 PR body** + **base 校验**：
   ```bash
   grape git-repo pulls update --owner "${REPO_FULL_NAME%/*}" --repo "${REPO_FULL_NAME#*/}" --number "$PR_NUMBER" \
     --json '{"body":"## 新增 Skill: {skill-name}\n\n由 huawei-cloud-skill-creator 自动创建\n\nFixes #'"$ISSUE_NUMBER"'"}'
   grape git-repo pulls get --owner "${REPO_FULL_NAME%/*}" --repo "${REPO_FULL_NAME#*/}" --number "$PR_NUMBER" --json-out
   ```
6. **输出**：`PR_NUMBER`（从 pulls create 返回值取）、`PR_URL=https://gitcode.com/${REPO_FULL_NAME}/pull/${PR_NUMBER}`。

> 审查人（assignees）：grape 0.3.3 无此接口，跳过。创建失败**不要反复盲试**——先看完整 stderr，精简 JSON 字段再试；仍失败 → 走失败门控。

## Step 2: Issue 评论告知（创建 PR 后必须）

```bash
grape git-repo issues comments create --owner "${REPO_FULL_NAME%/*}" --repo "${REPO_FULL_NAME#*/}" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Coding Agent] ✅ Skill 已创建并提交 PR\n\n**Skill 名称**：{skill-name}\n**功能摘要**：{一句话描述}\n**PR 链接**：[#{PR_NUMBER}](https://gitcode.com/'"$REPO_FULL_NAME"'/pull/'"$PR_NUMBER"')\n**测试状态**：已 A2A 交棒 tester，测试中\n\n**下一步**：\n- 测试通过后自动合并 → 发布"}'
```

评论 body 一律以 `[Coding Agent]` 开头。

## Step 3: 清理

- 删除临时调研产物：`{skill-path}/phase-*.json`、临时下载的检查点缓存、`*.tmp`、调研草稿。
- 确认 `skills/{skill-path}/` 只含最终产物，工作区无残留文件。

## Step 4: A2A 交棒 tester

```bash
grape a2a handoff --json '{"agent":"qa","payload":{"repository":"'"$REPO_FULL_NAME"'","account":"'"$ACCOUNT"'","issue_number":'"$ISSUE_NUMBER"',"pr_number":'"$PR_NUMBER"',"context":"Issue #'"$ISSUE_NUMBER"' skill 已创建，PR #'"$PR_NUMBER"' 已提交。请对 skill 进行功能验证。Skill 名称：{skill-name}"}}'
```

> 交办前若 `$GRAPE_SCENE_ID` 已注入：用 `grape scenes detail --scene_id "$GRAPE_SCENE_ID" --json-out` 校验含 `qa` 节点，命中才交办；未注入场景 → 用默认 `qa`。

## 判断标准

- 前置：validate-skill.sh 通过（华为云 Skill 检查规范，结构 / frontmatter / 命名 / 单 Skill 变更范围）。
- PR 创建：`pulls create` 返回 PR number = 成功。
- Issue 评论：`issues comments create` 成功 = 成功。
- A2A 交棒：`a2a handoff` 返回成功 = 成功。
- 全部通过 = 创建完成，等 tester 测试。
- 任一步失败 → **不交棒 tester**，Issue 评论说明原因；无法修复 → 不创建 PR，直接评论失败原因。

## 失败门控

- grape 未装 / 版本过低 → 按「前置：grape CLI 就绪」安装；重装后仍失败 → 终止并说明。
- `GRAPE_SESSION_TOKEN` / `REPO_FULL_NAME` / `ISSUE_NUMBER` 缺失 → 终止，说明环境不完整。
- API 返回 403/401 → 停止操作，回复「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」——**不尝试其他 token 或绕行手段**。
- validate-skill.sh 失败 → 修复后重试；无法修复 → Issue 评论说明，不创建 PR、不交棒。
- PR 创建失败 → 精简 JSON 重试一次；仍失败 → 评论说明，不交棒。

## 任务结束

完成全部动作后，最终答复末尾输出 JSON 块：

```json
{
  "actions": ["created:{skill-name} / submitted:PR#{number} / a2a:tester"],
  "conclusion": "处理结论（skill 已创建并交棒测试 / 创建失败）",
  "artifacts": ["PR#{number} / skills/{skill-path}/ 目录 / Issue 评论"],
  "next_step": "下一步建议（等待 tester 验证结论）",
  "issue_summary": "Issue 最新聚合结论（紧凑文本，用 | 分隔）"
}
```