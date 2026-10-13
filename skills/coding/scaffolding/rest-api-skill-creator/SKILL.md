---
name: rest-api-skill-creator
version: 2.2.0
description: |
  按需求自动创建 REST API 管理 skill：查重 → 读取 Spec → OpenAPI/文档/基础信息三级调研 →
  骨架生成（脚本+SKILL.md+端点文档+测试用例）→ 自测 → 创建 PR → A2A 交棒 QA Agent 测试。
  通用不限目标系统（博客/CMS/Wiki/商城等gitcode代码仓），认证方式按 Spec 确认。
  凭据变量名由 skill name 推导前缀（如 blog-manager → BLOG_MANAGER_*）。
tools:
  - curl
  - git
---

# REST API Skill Creator（通用REST API skill生成器）v2.1

## 一、安全硬约束（必须遵守）

1. **平台交互一律走 grape CLI**（自动读取 `$GRAPE_SESSION_TOKEN`），严禁从数据库/configs/日志/历史中寻找其他 token。**禁止 curl 直连平台 API**（`grape api` 已移除——契约未覆盖的端点不可调用；curl 仅用于**目标系统 API 探测**——被创建的 skill 要管理的系统）。
2. **严禁读取 Grape 内部数据**（data/、configs/、sessions.db、user_accounts 等）。
3. **403/无权限**：立即停止该操作并回复用户，严禁尝试其他 token 或绕行手段。
4. **token 不得写入任何文件/日志/评论**。
5. **所有 curl / git 调用设 30s 超时**（curl `--max-time 30`；git 用 `timeout 30`）——超时判定失败，不 hang。
6. **命令以参考文件为准**：平台交互一律以 `references/grape-cli-reference.md` 为准——严禁根据经验/记忆/猜测自行拼写命令或 API 路径。
7. **域界声明**：目标系统（被创建的 REST API skill 要管理的系统）自测调用用 curl/requests——**属生成器执行域，不是平台直连**（平台交互仍走 CLI）；**查明生成物规范**：生成的 skill 必须符合 `references/skill-spec.md`（生成物规范与平台技能框架是两个逻辑——按 skill-spec 生成，不套平台统一框架段落）。

## 二、环境变量表

| 变量 | 来源 | 用在哪 |
|------|------|--------|
| `GRAPE_SESSION_TOKEN` | 平台注入（grape 自动读取）| 平台交互（查重/评论/PR/A2A/任务）|
| `REPO_FULL_NAME` | 平台注入 | 仓库全名（拆 `ACCOUNT`/`REPO_NAME`）|
| `ACCOUNT` | 派生 | `${REPO_FULL_NAME%/*}`——owner 名（命令参数用）|
| `REPO_NAME` | 派生 | `${REPO_FULL_NAME#*/}`——repo 名（命令参数用）|
| `ISSUE_NUMBER` | 平台注入 | Issue 编号（评论/commit/PR/幂等查重）|
| `PR_NUMBER` | 平台注入（A2A 时）| 交棒 tester 时 payload 透传 |
| `SKILL_NAME` | 需求提取/Issue 标题 | 目标 skill 名（小写连字符——创建脚本参数、目录名）|
| `{PREFIX}_BASE_URL` | 目标系统（用户提供/.project-info/）| 自测探测目标系统——PREFIX = skill name 转大写下划线（如 blog-manager → BLOG_MANAGER）|
| `{PREFIX}_USERNAME` / `{PREFIX}_PASSWORD` | 目标系统（Basic Auth）| 自测探测 |
| `{PREFIX}_TOKEN` | 目标系统（Bearer Token）| 自测探测 |
| `{PREFIX}_API_KEY` | 目标系统（API Key）| 自测探测 |

平台侧敏感变量（token 类）**不 printenv、不落盘**；目标系统凭据由**生成的 skill 自行管理**（与本技能无涉——生成物运行时才用）。

## 三、前置检查门（自愈 → 重试 → STOP）

| 检查项 | 判定 | 通过标准 | 失败动作 |
|--------|------|---------|---------|
| CLI 可用 | `grape --version` | ≥0.3.2 | 按 `references/grape-cli-installation.md` 自愈；仍不可用 → 输出「前置检查未通过：<原因>」并结束任务 |
| 契约刷新 | `grape refresh` | 成功 | 重试 ≤2 次；仍失败 → 继续（回退内置快照）|
| 需求输入齐全 | 需求澄清 4 维度（base_url/认证方式/API 文档形式/操作能力）| 全覆盖且用户确认 | 用户跳过提问直接说「开始」→ 提醒需求澄清必须先完成；目标系统信息不足 → 追问 |
| Python 环境 | `python3 -c "import requests"` | ≥3.8 + requests 可用 | 缺 requests → 提示安装（pip install requests）——生成物运行时依赖 |
| 目标系统可达（探测自测）| curl 探测只读端点 | 200 且返回有效结构 | 凭据缺失 → 提示用户提供，不提供 → 终止；探测失败 → 标记 ⛔ → 失败门控 |

## 四、技能定义与执行

### 4.1 定位与职责边界

**职责**：按需求自动创建 REST API 管理 skill——查重 → 需求澄清 → API 文档调研 → 骨架生成（脚本+SKILL.md+端点文档+测试用例）→ 自测 → 创建 PR → A2A 交棒 QA Agent 测试。**不负责 Issue 分类、打标签、分配负责人**（Issue Agent 职责）；不负责测试/发布（tester/publish 职责）。

**依赖前序**：通过 A2A 被调用时，prompt 包含前序 Agent 的处理摘要——通过 grape CLI 获取 Issue 完整信息。

| 行为 | 态度 |
|------|------|
| 创建 PR 后在 Issue 发评论告知 | ✅ **必须做，不可跳过** |
| 创建 PR 后 A2A 通知测试 Agent | ✅ **必须做，不可跳过** |
| A2A 携带 issue_number 和 pr_number | ✅ **必须做** |
| 一个 PR 只改一个 Skill 目录 | ✅ **必须做** |
| API 端点只认文档解析/curl 探测结果 | ✅ **必须做（端点不预设——不预设"一定有 create-post / list-posts"）** |
| 生成物合格 | ✅ **必须做**——validate-skill.sh 16 项全过 + 真实 API 调用一次成功 |
| 按命名模式猜测/推断 API 端点 | ❌ **禁止** |
| 直接合并 PR | ❌ **禁止**（仅创建，交 tester 判断）|
| 读取 Grape 内部数据 | ❌ **禁止**（硬约束②）|
| 生成含 mock 模式/假数据的脚本 | ❌ **禁止** |
| 预设子命令（不根据 API 文档动态生成）| ❌ **禁止** |
| 生成清单之外的文件 | ❌ **禁止**（只生成 5 件套：SKILL.md/scripts/{name}.py/references/api-reference.md/templates/test-vars.json/requirements.txt）|
| 平台交互绕过 CLI 直连 | ❌ **禁止**（硬约束①）|

### 4.2 场景路由（入口 → 路径）

| 触发场景 | 处理路径 |
|---------|---------|
| worktree 无 `skills/{name}/` 目录 → 新建 skill | 4.3 流程 0 → 1 → 2 → 3 → 3.5 → 4 → 5 → 6 |
| worktree 已有 `skills/{name}/` 目录 → 修复 skill（tester 回退后重新执行）| 流程 0（跳过查重）→ 1（跳过确认）→ 2 → 3（更新产物）→ 3.5 → 4 → 5 → 6 |
| 远程已有同名 skill | 回复「已存在，可复用/更新」——不重复造 |
| 非 skill 创建类请求 | 不处理，回复说明范围（4.8 收尾）|

Don't use for: 测试 skill（tester 职责）/ 发布 skill（publish 职责）/ Issue 分类打标签（Issue Agent 职责）。

**入参契约**（A2A payload）：repository / account / issue_number / pr_number / context（含需求描述、目标系统信息）。

### 4.3 处理流程（统一骨架）

**流程总览（一行）**：

Step 0 查重（远程同名 skill——先查后做）→ Step 1 需求澄清（4 维度 + 凭据变量前缀推导）
→ Step 2 技术调研（API 文档三级回退 + 真实 API 验证）
→ Step 3 骨架生成（只生成 5 件套）→ Step 3.5 自测（三项门禁）
→ Step 4 创建 PR（脚本封装 + 必发 Issue 评论）→ Step 5 清理 → Step 6 A2A 交棒 tester → 4.8 任务收尾

**执行规则**：

- ⚠️ **启动即读 `references/creator-runbook.md`**——每步具体命令按走查表照抄执行（不现场查 --help）
- **查重必须先**：`grape git-repo tree` 查目标仓库 skills/ 已有同名 skill → 已有则复用/更新，不重复造
- **API 端点只认文档解析或 curl 探测结果，严禁猜测**；凭据可用时 curl 真实调用一次只读端点验证；所有端点都失败 → 终止，不生成任何文件
- **只生成 5 件套**（SKILL.md / scripts/{name}.py / references/api-reference.md / templates/test-vars.json / requirements.txt）——生成清单之外的文件禁止
- **Step 3.5 自测门禁**：`--help` 无语法错误 + validate-skill.sh 16 项校验全过 + 真实 API 可达——三项不过不建 PR
- **Step 4**：PR 走 `scripts/create_rest_api_skill_pr.sh`（幂等查重/契约字段 related_issue_nums + auto_close_issues/补 body/base 校验）——创建后**必须发 Issue 评论**（模板见 4.6）
- **Step 6**：A2A payload **必带 issue_number + pr_number**（tester 拉取/合并/交棒依赖）——agent 用场景标准节点名 `qa`（⚠️ **不传技能名**）
- **收尾顺序**：Step 6 完成 → 4.8 tasks complete（**先交棒再关任务**）

> 每步阶段摘要/命令/产物详表 → 按 `references/creator-runbook.md` Step 0-6 照抄执行。

### 4.4 命令标准（子集与坑点）

**grape CLI（平台交互）**——见 `references/grape-cli-reference.md` 完整子集 + ❌ 警示表。核心：
```bash
grape --version / grape refresh                                        # 前置门
grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --path skills --json-out   # Step 0 查重
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"body":"[Coding Agent] ..."}'   # Step 4 评论
grape a2a handoff --json '{"agent":"qa","payload":{...}}'              # Step 6 交棒
grape tasks complete --json '{...}'                                    # 收尾（4.8）
```
（PR 创建全走 `scripts/create_rest_api_skill_pr.sh`——内部 pulls list/create/update/get——不手动敲）

**坑点（pulls 契约）**：
- `pulls create` 契约字段：`title/head/base/body/related_issue_nums/auto_close_issues`（`related_issue_nums` 传 Issue 号数组如 `["12"]`，不要用 `inner_issue_nums`/`close_related_issue` 旧字段或 `owner/repo#N` 全限定格式）→ PR 描述已在 create 的 body 传入（update 补写仅幂等双保险）
- **设置审查人：grape 0.3.3 无 assignees 接口**——跳过（原 curl 直连已按纪律移除——审查人缺省不影响创建与测试，需要时人工指派）

**目标系统探测（curl——生成器域，合法）**：见 `references/api-research-guide.md`（OpenAPI 解析 / Markdown 提取 / curl 探测三级回退 + 认证探测 + 时间盒）。

**❌ 不存在的命令（警示）**：见 `references/grape-cli-reference.md` §4（tasks close/mine/start/status/clarify、git 透传、grape api 兜底、knowledge context/content、events detail --seq、curl 直连平台 API）。

### 4.5 故障决策表

| 现象 | 处理 |
|------|------|
| 远程已有同名 skill | 回复「已存在——可复用/更新」——不重复造 |
| 用户跳过提问直接说「开始」| 提醒：需求澄清必须先完成 |
| 凭据环境变量缺失/为空且 .project-info/ 无配置 | 提示用户提供；用户不提供 → 终止流程 |
| API 调研超 5 分钟未确认端点 | 标记 ⛔（API 不存在）→ 走失败门控（全 ⛔ → 终止，不生成任何文件）|
| 无法修复（validate 失败/API 不可用）| Issue 评论说明失败原因，不创建 PR，不交棒 tester |
| 创建 PR 失败（grape 无输出/无 number）| 脚本 exit 2——重试一次；仍失败 → Issue 评论说明 |
| PR base 校验不过 | 脚本 exit 2——检查 pulls create base 参数 |
| 命令 403/无权限 | 立即停止该操作并回复用户（硬约束③——不换 token 不绕行）|
| 401/凭据失效 | 说明凭据已失效（tk_ 短命属正常）——不替换不绕行 |
| 目标系统 API 404 | 端点不存在——标记 ⛔ 或按文档修正 |

### 4.6 输出格式（固定产物）

**评论**：body 前缀固定 `[Coding Agent]`；引用用户原文：`> {用户评论}\n\n[Coding Agent] {回复}`。

**成功评论模板**（Step 4 后必发）：`[Coding Agent] ✅ Skill 已创建并提交 PR` + Skill 名称/功能摘要/API 端点数/认证方式/PR 链接/测试状态/下一步。

**分析结论示例**：
```
成功：
分析结论：
- 场景：skill 创建（A2A 触发，Issue Agent 交棒 Coding Agent）
- Skill：{skill_name} v{version}
- 产物：SKILL.md + scripts/{skill_name}.py + references/ + templates/test-vars.json
- 验证：validate-skill.sh ✅ / API 调用 ✅
- 必须执行：创建 PR → A2A 交棒 QA

失败：
分析结论：
- 场景：skill 创建
- Skill：{skill_name}
- 结果：🔴 失败（validate-skill.sh 失败 / API 调研失败）
- 必须执行：Issue 评论报告错误 → A2A 回 Issue Agent
```

**收尾 JSON 块**（最终答复末尾输出——平台读取，只输出一个）：
```json
{
  "actions": ["做了什么，如 created:rest-api-skill-xxx / submitted:PR#N / a2a:qa"],
  "conclusion": "处理结论（skill 已创建/创建失败）",
  "artifacts": ["产生的产物：PR#N / skill 目录 / 评论"],
  "next_step": "下一步建议",
  "issue_summary": "Issue 最新聚合结论（紧凑文本，用 | 分隔）"
}
```
不得用长流程叙述替代 JSON 块；无法确定动作/结论 → 填空数组/空字符串，不伪造。

### 4.7 写操作协议

| 动作 | 确认要求 |
|------|---------|
| 创建 PR（脚本封装 pulls create）| 流程内（Step 4——直接执行）|
| Issue 评论（创建完成告知/失败说明）| **必做**——创建 PR 后必须发（4.6 模板）|
| A2A 交棒 tester | 流程内（Step 6——直接执行，payload 必带 issue_number/pr_number）|
| git commit + push（skills/{name}/ 产物）| 流程内（脚本内执行）|
| 合并 PR | ❌ **禁止**（交 tester 判断）|

### 4.8 任务收尾（必做）

1. **先调 `grape tasks complete` 关闭当前任务**（任务中心闭环）：
```bash
grape tasks complete --json '{"result_text": "<处理结论>", "actions": ["做了什么，如 created:rest-api-skill-xxx / submitted:PR#N / a2a:qa"], "conclusion": "处理结论（skill 已创建/创建失败）", "artifacts": ["产生的产物：PR#N / skill 目录 / 评论"], "next_step": "下一步建议"}'
```
2. **再在最终答复末尾输出结构化 JSON 块**（4.6 格式——actions/conclusion/artifacts/issue_summary must 真实填充）。
3. 结束信号：complete 后立即结束任务，不要继续思考或等待输入。

## 五、参考文件清单

| 文件 | 内容 | 何时用 |
|------|------|--------|
| `references/skill-spec.md` | **生成物规范**（生成的 SKILL 段落要求——按它生成，不套平台框架）| Step 3 生成前必读 |
| `references/rest-api-skill-template.md` | Python 脚本模板 + 生成 SKILL 段落模板 | Step 3 脚本/文档生成 |
| `references/api-research-guide.md` | REST API 文档三级回退调研方法 | Step 2 |
| `references/grape-cli-reference.md` | grape 命令全表 + ❌ 警示表 | 平台交互 |
| `references/grape-cli-installation.md` | CLI 安装/升级指引 | 前置门 CLI 自愈 |
| `templates/requirement-template.md` | 用户需求模板 | Step 1 需求澄清（引导用户填写）|
| `scripts/validate-skill.sh` | 生成物 16 项结构校验 | Step 3.5 自测 |
| `scripts/create_rest_api_skill_pr.sh` | PR 创建脚本（pulls 幂等/补 body/base 校验）| Step 4 |
| `references/creator-runbook.md` | **执行走查表：Step 0-6 全程命令逐步照抄 + 错误排查速查** | ⭐ **最先**——启动即读，全流程照抄不查 --help |

## 六、Best Practices（实践积累区）

- **不预设 API 结构**：子命令数量/端点路径/参数定义全部由用户提供的 API 文档动态决定——「不预设一定有 create-post / list-posts」。
- **端点只认可信来源**：OpenAPI paths 定义 / Markdown 文档明确描述 / curl 探测 200——严禁按命名模式猜测（从 /api/posts 推断 /api/comments）。
- **时间盒纪律**：每端点调研 ≤5 分钟——超时标记 ⛔，不无限循环搜索。
- **失败门控**：所有端点 ⛔ / 无法修复 → 终止流程——不生成半成品、不创建 PR、不交棒 tester。
- **生成物安全**：无 mock/假数据；无硬编码 IP；test-vars.json 不含真实地址/凭据；token 不落盘。
- **preflight 查重**：任何创建前先查重（tree skills/ + pulls list 幂等）——不重复造、不重复建 PR。