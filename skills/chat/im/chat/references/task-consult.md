# 咨询类任务：一般询问与信息查询（task-consult）

当用户做**一般性询问**（如项目信息、Issue/PR 状态、仓库结构、责任人、commit 等）时执行本流程：**用 `grape` CLI 查询获取信息，然后答复用户**。

## 0. 任务边界（最高优先级，先读）

**本流程只做「查询 + 答复」，不修改任何仓库状态，不执行任务本身。**

- ✅ 查询项目/仓库/Issue/PR/commit 等只读信息，用 `grape` CLI 获取后以自然语言答复
- ❌ **不要** clone 仓库、部署、起服务、写代码、改文件、执行 git 写操作
- ❌ **不要**创建/关闭 Issue、修改标签、分配负责人、发评论（除非本明确流程允许）
- ❌ **不要**替用户完成 Issue 的实际工作（开发/部署/验证/实现）

> 分清「咨询类」与「澄清类」：咨询 = 用户问信息、想了解情况；澄清 = 用户被分配了 Issue 需要把需求讲清楚并回帖。二者都以只读为主，但澄清以「回帖 Issue」收尾，咨询以「直接答复」收尾。

## 1. 判断是否进入咨询流程

- 用户问「这个项目是做什么的」「仓库有哪些文件」「Issue #N 现在什么状态」「这个 PR 合入了吗」「谁负责哪个模块」「帮我看看 Issue #N」等 → 咨询流程（**无任务绑定的查询意图**；如有该 Issue 属于归属用户且是「让我处理」的指令式表达，则属澄清类）
- 用户通过任务中心被分配后明确「帮我看看/处理 Issue #N」（prompt 含「📋 任务分配 · Issue #N」或 `场景: task`）→ **澄清类**（task-clarify.md）
- 仅闲聊 / 非 DevOps 话题 → 按 SKILL「能力边界」礼貌说明，不读流程文件

## 2. 查询信息（用 grape CLI）

根据问题类型选用对应的只读命令：

```bash
# 项目 / 仓库信息
grape repos project info --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out   # 项目知识基线（含结构/能力摘要）
grape git-repo repo --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out          # 仓库元信息

# 仓库结构 / 文件
grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --depth single --json-out
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path README.md --raw

# Issue 信息
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out   # 聚合视图（状态/阶段/事件）
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape issues list --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out

# PR 信息
grape git-repo pulls get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out
grape git-repo pulls list --owner "$REPO_OWNER" --repo "$REPO_NAME" --state all --per_page 20 --json-out
grape git-repo pulls files --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out

# 分支 / commit / 责任人
grape git-repo branches --owner "$REPO_OWNER" --repo "$REPO_NAME" --per_page 50 --json-out
grape git-repo commits --owner "$REPO_OWNER" --repo "$REPO_NAME" --per_page 20 --json-out
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path CODEOWNERS --raw   # 模块责任人
```

> `{owner}/{repo}` 用 `$REPO_OWNER`/`$REPO_NAME`；查询对象若有具体编号（`$ISSUE_NUMBER`/`$PR_NUMBER`）优先用注入值，缺省则由问题上下文确定。

## 3. 组织答复

- 基于查到的事实回答，**先打开原对象核对**，不要凭记忆/推断作答
- 未查询到 / 权限不足（403）→ 如实说明「未能获取：<原因>」，不编造
- 用自然语言回复，关键信息加粗、链接用 Markdown 格式，遵循 SKILL「输出格式」

## 4. 收尾

咨询为纯用户主动对话（无任务绑定）时，正常回复即可，**不调用 `grape tasks complete`**；若本会话由任务中心触发（含「📋 任务分配」）→ 按 SKILL「任务完成流程」自报完成。