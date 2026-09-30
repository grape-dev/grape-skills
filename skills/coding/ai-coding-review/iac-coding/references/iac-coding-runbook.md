# IaC 代码实现执行走查表（runbook）

> 目的：把 iac-coding 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> **CLI 纪律**：本表已覆盖本技能全部平台交互命令（issues / git-repo pulls/issues / a2a / tasks）——**禁止 curl 直连平台 API（读操作也一样）**——每个节点需要的命令已写在该节点——按节点照抄；命令失败才看「错误排查速查」。
> 环境变量直接使用：`$ACCOUNT`、`$REPO_NAME`（=`${REPO_FULL_NAME#*/}`）、`$ISSUE_NUMBER`、`$PR_NUMBER`（有则填）、`$GRAPE_WORK_BRANCH`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`。
> **评论前缀硬规**：所有评论 body 一律以 `[coding Agent]` 开头。

---

## Step 0 · 任务上下文与就绪（必须最先，任何事件都做）

```bash
# ⚠️ CLI 前置自愈（最先）：`grape --version` ≥0.3.2；未装/版本过低 → 按 `references/grape-cli-installation.md` 自动安装/升级 → 装好再验；仍不可用 → 结束任务并说明
grape --version
# ⚠️ terraform 前置：≥1.7.5 且 ≤1.10.5；缺失/版本不符 → 按官方源安装到版本区间 → 再验；仍不可用 → 报告阻塞
terraform version
grape refresh 2>&1 && echo REFRESH_OK
grape tasks current --json-out
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out 2>&1 | head -120
printenv GRAPE_WORK_BRANCH 2>/dev/null
git status 2>&1 | head -5        # 确认 worktree 与分支（feat/issue-{n} 已就绪）
```

## 场景入口判定（必做——信号优先级：PR_NUMBER 注入 > context 文字，见 SKILL 4.2）

- **复制需求场景**：prompt 提示「用户已为此 Issue 指定了开发场景」→ 按**新开发**执行（不因标题相似判重复）
- **$PR_NUMBER 有值**（存在 PR）→ **代码优化**（优先信号——无论 context 措辞）
- **$PR_NUMBER 无值** → 按 context 文字特征判定（⚠️ 无 PR 编号≠新开发——优化场景可能不带 PR）：
  - 含「启动开发」「实现」「feature」「bug」→ 走场景 A（新开发）
  - 含「PR 审查反馈」「审查发现问题」「需要修改」「优化」→ 走场景 B（代码优化）
- **其他**（无上述特征）→ **不做处理，直接结束**（收尾仅 tasks complete——actions 填「场景识别: 非本技能场景,不处理」，不建 PR 不评论）

## 场景 A · 新开发（按顺序执行，上一步未完成不得进入下一步）

### A1 · 需求理解（必做）

- 从 tasks current / issues detail 的 context 读需求；需求不明确 → 先评论确认（[coding Agent] 追问——评论命令同 A8）
- 需外部 API/第三方服务 → 先获取文档确认接口存在且参数明确；缺失 → 评论说明暂缓（评论命令同 A8）

### A2 · 需求文档 + 方案设计（所有 feature 必做）

```bash
# 在 worktree 下产出 spec/plan/todo（doc 结构——按惯例 docs/spec-{topic}.md、tasks/plan-{topic}.md、tasks/todo-{topic}.md）
mkdir -p docs tasks
```

### A3 · 资源规格查询验证（生成 TF 前必须执行——不可跳过）

```bash
# 前置：${HUAWEI_AK:+ok} 校验——缺失 → STOP 提示在【项目场景 → 点击单个场景 → 场景详情页 → 高级选项 → 自定义配置】配 name=HUAWEI_AK/HUAWEI_SK 或【通用设置】配置华为云 AK/SK（不寻找不借用——见 SKILL 4.5）
# ECS flavor（确认所选 flavor 在目标区域可用——JMESPath 过滤，防上下文爆炸）：
hcloud ECS ListFlavors --cli-region=cn-north-4 --cli-output=json \
  --cli-query="flavors[?contains(name, '{flavor}')].{name:name, vcpus:vcpus, ram:ram}" 2>&1 | head -30
# 镜像（获取精确名称——公共镜像）：
hcloud IMS ListImages --cli-region=cn-north-4 --__imagetype=gold --__isregistered=true --limit=20 2>&1 | grep -i "{平台}" | head -5
# 可用区：
hcloud ECS NovaListAvailabilityZones --cli-region=cn-north-4 2>&1 | head -10
# VPC/子网（避免 CIDR 冲突——查现有网络资源）：
hcloud VPC ListVpcs 2>&1 | grep -i "{VPC名}" || echo "无同名 VPC"
hcloud VPC ListSubnets 2>&1 | grep -i "{子网名}" || echo "无同名子网"
# OBS 桶名占用（obsutil——华为云官方 OBS 工具；无同名桶 → 桶名可用）：
obsutil ls -s 2>&1 | grep -i "{桶名}" || echo "无同名桶"
# ⚠️ 查询结果为空/失败 → 修复查询环境重试 / 报告阻塞——不允许"降级继续"（TF 未验证的规格会导致 plan/apply 失败）
# 参数拿不准时 → hcloud <Service> <Action> --cli-region=cn-north-4 --help 查参数后重试（不猜不 curl 平台 API）
```

### A4 · TF 配置生成（必做）

```bash
# 所有 TF 代码放仓库 iac/ 子目录（不存在则创建）：
mkdir -p iac
# 按 `references/huaweicloud-tf-conventions.md` 生成（目录结构/凭证映射/版本约束/OBS backend）
# 凭证映射（env——不写进 .tf）：
export HW_ACCESS_KEY="${HUAWEI_AK}"; export HW_SECRET_KEY="${HUAWEI_SK}"
export HW_REGION="cn-north-4"; export AWS_ACCESS_KEY_ID="$HW_ACCESS_KEY"; export AWS_SECRET_ACCESS_KEY="$HW_SECRET_KEY"; export AWS_DEFAULT_REGION="cn-north-4"
```

### A5 · 校验（必做——到 plan 为止）

```bash
cd iac && timeout 120 terraform fmt -recursive 2>&1 | tail -5
timeout 180 terraform init 2>&1 | tail -8
timeout 180 terraform validate 2>&1 | tail -8
timeout 300 terraform plan -out=tfplan 2>&1 | tail -30
# ⚠️ 到 plan 为止——【禁止 terraform apply / destroy】（SRE 职责）
# plan 输出记录：create/update/destroy 资源数（作为 PR body 资源清单 + plan_summary）
```

### A6 · 自审查（建 PR 前必做，不可跳过）

- 按 `references/code-review-checklist.md` 逐项检查（正确性/安全/规范——AK 无硬编码/边界/范围）→ 修复发现的问题
- 补充必要测试（lint/validate 类）

### A7 · 创建 PR（必做）

```bash
git add -A && git commit -m "feat(issue-$ISSUE_NUMBER): {变更说明}" 2>&1 | tail -3
git push -u origin feat/issue-$ISSUE_NUMBER 2>&1 | tail -3
# ⚠️ 先查同分支 open MR（防重复创建）：
grape git-repo pulls list --owner "$REPO_OWNER" --repo "$REPO_NAME" --state open --json-out 2>&1 | head -20
# 创建 PR（契约字段：title/head/base/inner_issue_nums/close_related_issue——create 无 body 字段，@file 防转义）：
printf '%s' '{"title":"feat(issue-{n}): {变更说明}","head":"feat/issue-{n}","base":"'"$GRAPE_WORK_BRANCH"'","inner_issue_nums":"'"$ACCOUNT/$REPO_NAME"'#{n}","close_related_issue":true}' > /tmp/pr-body.json
grape git-repo pulls create --owner "$REPO_OWNER" --repo "$REPO_NAME" \
  --json @/tmp/pr-body.json --json-out 2>&1 | head -30
# 从返回取 PR 编号（$PR_NUMBER 未注入时）——后续 update 与 A8 交办必须用真实编号
# PR 描述四段（变更说明/资源清单/文件变更/后续步骤）——create 后 pulls update 补 body：
printf '%s' '{"body":"### 变更说明\n{...}\n\n### 资源清单\n{...}\n\n### 文件变更\n{...}\n\n### 后续步骤\n{...}"}' > /tmp/pr-body-desc.json
grape git-repo pulls update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number {真实 PR 编号} --json @/tmp/pr-body-desc.json --json-out 2>&1 | head -20
# PR 链接用 Web 页面 /pull/（单数）markdown 格式——不得用 API 路径
```

### A8 · Issue 评论 + A2A 通知 QA（必做，不可跳过）

```bash
# Issue 评论告知（长 body 用 @file）：
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[coding Agent] ✅ 已完成实现，请审查 PR [#{n}](https://gitcode.com/'"$ACCOUNT/$REPO_NAME"'/pull/{n})。{实现内容摘要}"}' --json-out
# ⚠️ 防重复：先查 pipeline，已含 qa:a2a_event 则不重复 A2A，只发评论
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 交办（issue_number 必填；pr_number 有则填，严禁混用）：
grape a2a handoff --json '{"agent":"qa","payload":{"repository":"'"$ACCOUNT/$REPO_NAME"'","account":"'"$ACCOUNT"'","issue_number":{真实编号},"pr_number":{真实编号},"context":"PR #{n} 已创建（{实现摘要}），请审查"}}'
# A2A 失败 → 重试 ≤3 次 → 仍失败：评论说明 + next_step 人工介入
```

## 场景 B · 代码优化（按顺序执行）

### B1 · 理解审查反馈（必做）

```bash
# PR_NUMBER 缺失时先定位（评论/复审触发可能不带 PR 编号——不能默认有值）：
[ -n "$PR_NUMBER" ] || grape git-repo pulls list --owner "$REPO_OWNER" --repo "$REPO_NAME" --state open --json-out 2>&1 | head -30
# 定位不到 open PR → Issue/PR 评论询问「请提供 PR 编号」，不猜测
# 读 PR 审查评论/反馈（逐条核对是否已修改、问题是否解决）：
grape git-repo pulls get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "${PR_NUMBER:-{定位到的编号}}" --json-out 2>&1 | head -60
grape git-repo pulls comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "${PR_NUMBER:-{定位到的编号}}" --json-out 2>&1 | head -60
```

### B2 · 制定修改方案 + 实施（原子提交）

```bash
# 方案 = 问题点清单 → 每点修改策略（依据 B1 反馈逐条映射；涉及文件/改动方式/验证方式）
# 实施：每个问题一个原子提交（commit message 注明修复的问题编号）
git add {变更文件} && git commit -m "fix(issue-{n}): {修复点}" && git push 2>&1 | tail -3
```

### B3 · PR 评论告知（必做）

```bash
grape git-repo pulls comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" \
  --json '{"body":"[coding Agent] 已按审查意见修改：{修改摘要}"}' --json-out
```

### B4 · A2A 通知 QA（必做）

```bash
# 防重复 + 交办（同 A8——agent=qa，context 注明"已按审查意见修改，请复审"）
```

## Step 收尾 · 任务完成流程（必做——任何分支都必须执行到最后）

```bash
grape tasks complete --json '{
  "result_text":  "结论：{场景}处理完毕（{完成摘要}）",
  "actions":      ["场景识别: {新开发/优化}", "需求文档+方案: {spec/plan/todo}", "资源规格查询: {已查/阻塞}", "TF 生成: iac/", "校验: {fmt/init/validate/plan 结果}", "自审查: {通过}", "PR: #{pn}", "评论/A2A: qa"],
  "conclusion":   "{已实现并创建 PR #{pn}，待 QA 审查 / 已按审查意见修改完成}",
  "artifacts":    ["PR #{pn}", "分支 feat/issue-{n}", "iac/ {tf 文件清单}", "评论: {位置}"],
  "issue_summary":"{完成摘要——实现内容/校验结果/PR 一句话}",
  "next_step":    "a2a_qa 或 等待用户反馈"
}'
```

> ⚠️ **结束信号**：tasks complete 后立即结束任务，不要继续思考或等待输入。结构化字段 must 真实填充——结尾是下一节点的输入。

---

## 错误排查速查（命令返回异常时）

> ⚠️ 出错时**先看完整错误**（命令去掉 `| tail -N` 截断，`2>&1` 保留 stderr）；runbook 命令照抄仍失败，才允许 `grape commands <关键词>` / `grape <group> --help` 修正。**不反复盲试同一命令**。

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名抄错，核对本 runbook；仍不确定再 `grape commands <关键词>` |
| `unknown request field(s): ...` | `--json` 有契约不允许字段 → `grape <group> <verb> --help` 看 Body fields |
| terraform init/validate/plan 失败 | 看完整错误定位（provider/镜像/flavor）→ 修后重试 ≤2 次 → 仍失败：不创建 PR，Issue 评论报告原因和修复建议 |
| git push 失败 | 检查分支状态后重试 ≤1 次；仍失败报告 |
| 华为云查询失败 / AK/SK 缺失 | **不降级继续**——STOP 提示配置 或 报告阻塞（资源规格是 TF 生成前置）|
| MR 创建重复 | 先查同分支 open MR（pulls list --state open）——有则不重复创建 |
| `comments create` 失败（长 body 转义）| 改用 `--json @file` |
| 401 凭据失效 | 说明「凭据已失效」即可，不换 token |
| 403 权限不足 | 说明需管理员配置——不绕行 |
| 报「契约过期/命令不识别」| 先 `grape refresh` 再重试 |