# IaC-VOD 执行走查表（runbook）

> 目的：把 iac-vod 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> **CLI 纪律**：本表已覆盖本技能全部日常操作命令（issues / git-repo / a2a / tasks）——**禁止 curl 直连平台 API（读操作也一样）**——按节点照抄即可；命令失败才看「错误排查速查」。
> 环境变量直接使用：`$ACCOUNT`、`$REPO_NAME`（=`${REPO_FULL_NAME#*/}`）、`$ISSUE_NUMBER`（有则填）、`$DEVOPS_EVENT_TYPE`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> **评论前缀硬规**：所有评论 body 一律以 `[iac-vod Agent]` 开头。

---

## Step 0 · 任务上下文与就绪（必须最先，任何事件都做）

```bash
# ⚠️ CLI 前置自愈（最先）：`grape --version` ≥0.3.2；未装/版本过低 → 按 references/grape-cli-installation.md
#    自动安装/升级 → 装好再验证一次；仍不可用 → 输出「前置检查未通过：<原因>」并结束任务（不降级直连）
grape --version
grape refresh 2>&1 && echo REFRESH_OK        # 契约保鲜；失败重试 ≤2 次后回退内置快照继续
grape tasks current --json-out               # 前序 A2A payload/上下文在这里（平台不注入 $SEQ 环境变量——不依赖它）
# ⚠️ 场景路由（必做判定）：按 $DEVOPS_EVENT_TYPE 分流——vod_signal / 飞书 IaC 消息 → 走「场景 A」；
#    issue_opened → 走「场景 B」；无法判断 → 按事件 payload 内容判定，仍不明 → STOP 评论说明
# 场景 B 才执行下行（场景 A 无 ISSUE_NUMBER——跳过）：ISSUE_NUMBER 缺失 → 先用 `git-repo issues get`/`git-repo issues list` 定位；
#    定位不到 → STOP——不执行任何写操作
if [ -n "$ISSUE_NUMBER" ]; then
  grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out 2>&1 | head -120
fi
```

## 场景 A · IaC 开发者声音引导建 Issue（vod_signal / 飞书消息）

### A1 · 项目知识基线（必须最先）

```bash
# 知识基线 = prompt 内联注入的「项目知识基线」章节（主路径，无需命令——基线由平台服务端维护，Agent 不自取/不自行生成）
# 需全文时读 prompt 标注的 project-info/ 路径
# 降级（仅当 prompt 标注「无项目知识基线」/ [degraded]）：
grape git-repo repo --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out
grape git-repo tree --owner "$ACCOUNT" --repo "$REPO_NAME" --depth 2 --json-out
# IaC 场景特别关注：IaC 目录结构（terraform modules / pulumi stacks / cloudformation templates）——从 tree 输出里识别
```

### A2 · 项目历史全貌（必做——防重复/重复反馈聚类）

```bash
# 近期 Issue（判断重复/已解决）：
grape git-repo issues list --owner "$ACCOUNT" --repo "$REPO_NAME" --state all --per_page 20 --json-out
# 近期 PR（是否已有 IaC 方案）：
grape git-repo pulls list --owner "$ACCOUNT" --repo "$REPO_NAME" --state all --per_page 10 --json-out
# 历史反馈画像：聚类此前 auto-submitted by iac-vod Agent 的 Issue——从 list 结果按标题/正文标注筛选
```

### A3 · 需求引导漏斗

- 判断清晰度（`references/requirement-elicit-guide.md` 四要素 + IaC 特化要素：目标云资源类型、IaC 工具链、目标区域/环境、资源规模）——用上面已取的数据判断，不需新命令
- 已清晰 → A4；不清晰 → 飞书/评论引导 ≤3 轮（每次 1-3 个澄清问题）；超限 → 建「待澄清」Issue（只建档、不触发流水线——信息不全不启动开发链；开发者补充信息后由场景 B 审视接管）

```bash
# 待澄清建档：git-repo issues create 只建档不触发流水线（已清晰需求才走 A4 的 issues create 进流水线）
printf '%s' '{"title":"[IaC-VOD][待澄清] <问题简述>","body":"已获取：{已获取信息清单}\n缺失：{缺失信息清单}\n请开发者补充后，iac-vod 将按场景 B 接管。"}' > /tmp/iac-vod-clarify-issue.json
grape git-repo issues create --owner "$ACCOUNT" --repo "$REPO_NAME" --json @/tmp/iac-vod-clarify-issue.json --json-out 2>&1 | head -30
```

### A4 · 结构化建 Issue（必做）

```bash
# body 按 requirement-elicit-guide §四 IaC 模板（目标/现状/期望/验收/优先级/来源/目标云服务/IaC 工具链/目标区域/资源规模/安全约束）写文件，再 @file
# ⚠️ 统一入口 grape issues create：同时创建 GitCode Issue 并在平台触发流水线（git-repo issues create 仅用于 A3 待澄清建档；已清晰需求一律走本命令进流水线）
printf '%s' '{"title":"[IaC-VOD] <聚类标签>: <问题简述>","description":"{模板结构化 body，标注 auto-submitted by iac-vod Agent（Feishu）}"}' > /tmp/iac-vod-issue.json
grape issues create --owner "$ACCOUNT" --repo "$REPO_NAME" --json @/tmp/iac-vod-issue.json --json-out 2>&1 | head -30
# 从返回取 issue_number（$ISSUE_NUMBER 未注入时）——后续 A5 交办必须用真实编号
# 403（任务 token 无建 Issue 权限——契约标注）：不重试、不降级直连——评论说明「平台任务 token 无建 Issue 权限，需平台配置」后按错误排查速查 403 行 STOP
```

### A5 · A2A 交办 IaC Issue Agent（必做——含防重复检查）

```bash
# ⚠️ 防重复：先查 pipeline，已含 iac-issue:a2a_event 则不重复 A2A，只发评论
grape issues pipeline --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 交办（必须携带真实 issue_number；无法确定则不调用，评论说明）：
grape a2a handoff --json '{"agent":"iac-issue","payload":{"repository":"'"$ACCOUNT/$REPO_NAME"'","account":"'"$ACCOUNT"'","issue_number":{真实编号},"pr_number":null,"context":"iac-vod 已完成 IaC 需求收敛与结构化，请继续 spec 设计/打标/分配"}}'
# ⚠️ 交办返回 not_in_scene（目标 agent 名不在本场景流水线——场景实际用通用 agent 名挂 iac 技能）：
#   ① 先 grape issues pipeline 确认本场景既有 agent 序列（如 vod→issue→coding→qa→sre）
#   ② 按场景既有 issue 阶段 agent 名重发（payload 不变——事件将命中挂有 iac 技能的场景节点）
#   ③ 重发仍 not_in_scene → 评论说明「场景无 iac 节点，已停止」→ 收尾（不盲发）
# A2A 失败 → 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入
```

## 场景 B · IaC Issue 审视（接管 issue_opened）

### B1 · 项目知识基线（同 A1，若已存在则复用）

```bash
# 命令同 A1；prompt 已内联基线摘要时直接用
```

### B2 · 前置分流（必做）

- **自建排除**：Issue 含 `auto-submitted by iac-vod Agent` → **跳过审视**，直接 B6 A2A 交办（防自我循环）
- **复制需求场景**：prompt 提示「用户已为此 Issue 指定了开发场景」→ **不因标题/内容与已有 Issue 相似判重复**——跳过 B1/B2，直接 B3 → B6 执行

### B3 · 清晰度审视

```bash
# 读 Issue 完整内容（title/body/标签/评论）：
grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape git-repo issues comments list --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 对照四要素 + IaC 特化要素判断清晰度/可执行性/重复
# IaC 相关性判定：涉及 terraform/hcl/pulumi/cloudformation/云资源编排 → 本技能管辖；
# 纯应用层 Issue → 回退通用 vod 流程（不强行接管）
```

### B4 · 与开发者沟通澄清（不清晰时，≤3 轮）

```bash
# 渠道：Issue 评论——引原文 + 1-3 个具体澄清问题（结合知识基线；IaC 场景：目标区域？实例规格？网络隔离层数？状态后端？）
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[iac-vod Agent] > {原文}\n\n{1-3 个澄清问题}"}'
# 超限 → 评论列出已获取/缺失信息，标记「待澄清」
```

### B5 · 结构化总结（必做）

```bash
# 将 body 收敛为 IaC 模板结构（来源标注「iac-vod 审视结构化」；不修改标签/分配——IaC Issue Agent 职责）
printf '%s' '{"body":"[iac-vod Agent] 审视结构化：目标云服务 / IaC 工具链 / 目标区域 / 资源规模 / 安全约束——{收敛后需求}"}' > /tmp/iac-vod-body.json
grape git-repo issues update --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json @/tmp/iac-vod-body.json --json-out
```

### B6 · A2A 交办 IaC Issue Agent（同 A5，含防重复检查）

```bash
# 命令同 A5（pipeline 防重复检查 → a2a handoff agent=iac-issue）
```

## Step 收尾 · 任务完成流程（必做——任何分支都必须执行到最后）

```bash
grape tasks complete --json '{
  "result_text":  "iac-vod 处理完毕（结论：{分析摘要——IaC 声音主题/清晰度/去向}）",
  "actions":      ["知识基线: {已读/降级}", "历史全貌: 分析 {n} 条", "引导: {轮数} 轮/无需", "建/审 Issue: {#n}", "A2A: iac-issue"],
  "conclusion":   "{已建 Issue #n 并交办 / 已审视并结构化 / 待澄清 / 非 IaC 回退}",
  "artifacts":    ["Issue #{n}（新建/结构化）", "评论: {评论位置}"],
  "issue_summary":"{分析摘要——声音主题/清晰度/去向 一句话}",
  "next_step":    "a2a_iac-issue 或 等待开发者补充"
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
| `issues create` 失败（字段/模板错误）| 核对 description 模板与字段 → 修正重试（≤2 次）→ 仍失败评论说明 |
| 评论不生效（长 body 转义问题）| 改用 `--json @file`（body 先写文件，见 A4）|
| `pulls list` / `issues list` 返回空 | 属正常（无 PR/无 Issue）——按「无历史」分支处理，不报错 |
| 401 凭据失效 | 说明「凭据已失效」即可，不换 token（安全硬约束⑤）|
| 403 账户/平台管理类 | 说明需管理员配置/`grape_` 级凭据，本技能不涉及——不绕行 |
| 知识基线 [degraded] | 降级 README + git-repo 分析并标注 `[degraded]`，不阻塞 |
| 报「契约过期/命令不识别」| 先 `grape refresh` 再重试（前置门②）|