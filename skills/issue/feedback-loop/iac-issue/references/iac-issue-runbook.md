# IaC Issue 运营执行走查表（runbook）

> 目的：把 iac-issue 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> **CLI 纪律**：本表已覆盖本技能全部日常操作命令（issues / git-repo 含 labels/pulls/contents/comments / a2a / tasks）——**禁止 curl 直连平台 API（读操作也一样）**——每个节点需要的命令已写在该节点——按节点照抄即可；命令失败才看「错误排查速查」。
> 环境变量直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名 = `${REPO_FULL_NAME#*/}`）、`$ISSUE_NUMBER`、`$PR_NUMBER`（有则填）、`$DEVOPS_EVENT_TYPE`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。`ACCOUNT`（触发人 actor）一般不作 --owner。
> **评论前缀硬规**：所有评论 body 一律以 `[issue agent]` 开头；Spec 文档评论以 `[Issue Agent] 📋 Spec Document` 开头。

---

## Step 0 · 任务上下文（必须最先，任何事件都做）

```bash
# ⚠️ CLI 前置自愈（最先）：`grape --version` ≥0.3.2；未装/版本过低 → 按 references/grape-cli-installation.md 自动安装/升级 → 装好再验；仍不可用 → 结束任务并说明
grape --version
grape refresh 2>&1 && echo REFRESH_OK        # 契约保鲜；失败重试 ≤2 次后继续（回退内置快照）
grape tasks current --json-out
# 入口事件识别（$DEVOPS_EVENT_TYPE）：issue_opened → 全流程 Step 1→6；评论/交互类事件（comment 等）→ 直接走 Step 6 评论进件分流；a2a_event → 按 payload 上下文定位续做
# ISSUE_NUMBER 缺失 → 先用 `git-repo issues get`/`issues list` 定位；定位不到 → STOP（不执行写操作）
if [ -n "$ISSUE_NUMBER" ]; then
  grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
fi
```

## Step 1 · Issue 与历史（防重复/找模式——必做）

> 项目知识基线 = prompt 内联注入的「项目知识基线」章节（平台服务端维护，Agent 不自取/不自行生成）——需全文时读 prompt 标注的 project-info/ 路径；`[degraded]` → 降级分析不阻塞（错误排查速查）。

```bash
# 读 Issue 详情 + 评论：
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 历史 Issue/PR（识别同类处理模式——原始职责内化）：
grape git-repo issues list --owner "$REPO_OWNER" --repo "$REPO_NAME" --state all --per_page 20 --json-out
grape git-repo pulls list --owner "$REPO_OWNER" --repo "$REPO_NAME" --state all --per_page 10 --json-out
```

## Step 2 · 分类与标签（必做——diff 先行）

```bash
# 查现有标签（确定存在性 before create）：
grape git-repo labels list --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out
# 不存在 → 创建（按 references/labeling-guide.md 规范——type:/priority:/status: 前缀）：
grape git-repo labels create --owner "$REPO_OWNER" --repo "$REPO_NAME" --json '{"name":"{标签名}","color":"#0e8a16"}' --json-out
# 更新 Issue 标签（labels 逗号分隔字符串——先 diff 再提交）：
grape git-repo issues update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"labels":"{原有标签},新标签"}' --json-out
# 去除冗余/冲突标签 → 评论列 diff + 理由（见 Step 6 命令）
```

## Step 3 · 指派（必做）

```bash
# CODEOWNERS 读取（分配依据）：
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path CODEOWNERS --ref main --json-out 2>&1 | head -30
# 指派（按 references/assignee-guide.md——CODEOWNERS 优先→模块专家→默认流转人）：
grape git-repo issues update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"assignee":"{GitCode 用户名}"}' --json-out
```

## Step 4 · Spec 生成（feature 类必做——IaC 资源规划）

```bash
# 查看仓库结构（IaC 目录识别——terraform modules / pulumi stacks / cloudformation）：
grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --depth 2 --json-out
# 华为云凭据取值（两个入口：①场景高级选项 name=HUAWEI_AK/HUAWEI_SK 按 name 直注；②通用设置注入 HUAWEICLOUD_SDK_AK/SK 自动兜底）：
#   HUAWEI_AK="${HUAWEI_AK:-${HUAWEICLOUD_SDK_AK:-}}"; HUAWEI_SK="${HUAWEI_SK:-${HUAWEICLOUD_SDK_SK:-}}"
# 华为云资源现状查询（仅 HUAWEI_AK/SK 有值时——用 hcloud 查现有 VPC/ECS/RDS，避免 CIDR 冲突/重复创建/规格建议。命令族同 iac-coding A3/SRE A2）：
#   hcloud VPC ListVpcs 2>&1 | grep -i "名称" || echo 无同名
#   hcloud ECS ListServersDetails --limit 20 2>&1 | head -20
#   hcloud RDS ListInstances 2>&1 | head -20
# HUAWEI_AK/SK 缺失 → 跳过，Spec 标注「待 Coding Agent 验证」，不寻找不借用）
# Spec body 按 references/spec-generation.md 模板（需求描述/验收标准/技术方案/IaC 资源规划）写文件，再 @file（外层单引号防 shell 转义）：
printf '%s' '{"body":"[Issue Agent] 📋 Spec Document\n\n{Spec 正文——按 spec-generation.md 模板}"}' > /tmp/iac-spec.json
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json @/tmp/iac-spec.json --json-out
```

## Step 5 · A2A 交办（必做——防重复）

```bash
# ⚠️ 防重复：先查 pipeline，已含 coding:a2a_event 则不重复 A2A，只发评论（场景节点存在性与防悬空也由该检查覆盖）
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 交办（必须携带真实 issue_number；pr_number 有则填——$PR_NUMBER 非空时填其值，无则删该字段；严禁混用）：
grape a2a handoff --json '{"agent":"coding","payload":{"repository":"'"$ACCOUNT/$REPO_NAME"'","account":"'"$ACCOUNT"'","issue_number":{真实编号},"pr_number":{有则填=$PR_NUMBER 值},"context":"{分类 + Spec 摘要 + Spec 评论位置}"}}'
# A2A 失败（非 2xx/超时）→ 重试 ≤3 次 → 仍失败：评论说明 + next_step 标注人工介入
# 评论含「部署/发布」语义（如用户要求部署验证）→ agent 改为 sre（payload 写明部署方式偏好）
```

## Step 6 · 评论进件分流与回复（评论/交互事件必做——按语义走分支）

**判定评论语义（4 类）**：
- **补充信息**（澄清回答/新增需求细节）→ 重新审视：重跑 Step 2（分类标签 diff）→ 必要时重跑 Step 3/Step 4（指派/Spec）→ 回复确认
- **质疑分配 / Spec 修改 / 确认 Spec**：
  - 质疑分配 → 重跑 Step 3（先 `git-repo contents` 读 CODEOWNERS）重新核对指派 → 评论说明理由
  - Spec 修改 → Spec 版本 +1 重发布（Step 4 命令）→ 评论说明变更点
  - 确认 Spec → 评论确认；若尚未交办 → 补 Step 5 A2A 通知 coding
- **部署/发布语义**（评论含部署验证/发布等）→ A2A 交办 sre（payload 写明部署方式偏好）
- **无上述语义**（普通讨论）→ 直接回复

```bash
# 回复命令（长文用 @file 同 Step 4；短评直接内联）：
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[issue agent] {回复}"}' --json-out
```

## Step 收尾 · 任务完成流程（必做——任何分支都必须执行到最后）

```bash
grape tasks complete --json '{
  "result_text":  "Issue #'$ISSUE_NUMBER' 处理完毕（结论：{分类 + Spec + 交办}）",
  "actions":      ["分类: {类型}", "打标: {标签}", "指派: {负责人}", "Spec: {已发布/未涉及}", "A2A: {coding/sre/无}", "华为云查询: {已查/未注入}"],
  "conclusion":   "{分类}，{已交办开发 / 等待用户补充 / Spec 待验证}",
  "artifacts":    ["Issue 评论: {位置}", "Spec 文档: {评论位置（如有）}"],
  "issue_summary":"{分析摘要——需求/资源规划/去向 一句话}",
  "next_step":    "a2a_coding 或 等待用户反馈"
}'
```

> ⚠️ **结束信号**：tasks complete 后立即结束任务，不要继续思考或等待输入。结构化字段（actions/conclusion/artifacts/issue_summary）must 真实填充——结尾是下一节点的输入，只传 result_text 会丢结构化归档。

---

## 错误排查速查（命令返回异常时）

> ⚠️ 出错时**先看完整错误**（命令去掉 `| tail -N` 截断，`2>&1` 保留 stderr）；runbook 命令照抄仍失败，才允许 `grape commands <关键词>` / `grape <group> --help` 按 Body fields 修正。**不反复盲试同一命令**。

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名抄错，核对本 runbook；仍不确定再 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 里有契约不允许的字段 → `grape git-repo issues update --help` 看 Body fields，删掉多余字段 |
| `issues update` 失败（标签/分配不生效）| 核对字段格式：`labels` 用字符串逗号分隔（`"triaged,spec-ready"`）、`assignee` 用 GitCode 用户名 |
| `labels` 创建失败 / 重复 | 先 `labels list` 确认标签存在（不存在才 `labels create`）——不重复创建 |
| `comments create` 失败（长 body 转义问题）| 改用 `--json @file`（body 先写文件，见 Step 4）|
| `pulls list` / `issues list` 返回空 | 属正常（无 PR/无 Issue）——按「无历史」分支处理 |
| 401 凭据失效 | 说明「凭据已失效」即可，不换 token（安全硬约束⑤）|
| 403 账户/平台管理类 | 说明需管理员配置/`grape_` 级凭据，本技能不涉及——不绕行 |
| 华为云查询失败 / 凭据缺失 | Spec 标注「待 Coding Agent 验证」——不阻塞不借用 |
| 报「契约过期/命令不识别」| 先 `grape refresh` 再重试（前置门②）|