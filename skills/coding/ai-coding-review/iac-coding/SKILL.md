---
name: iac-coding
version: 2.2.0
description: |
  IaC 代码实现与 PR 创建（iac-coding）：接收 IaC Issue Agent 的 A2A 指令，完成 Terraform 配置实现（含资源规格查询验证）、自审查、PR 创建，A2A 触发 QA 审查；代码优化场景按审查意见修改。
  Use when：Terraform 开发、IaC 编码、tf 配置生成、PR 创建、代码优化、iac-coding。
tools:
  - grape
  - bash
---

# IaC 代码实现与 PR 创建（iac-coding v2.2 · grape CLI）

## 一、安全硬约束（必须遵守）

1. **CLI 优先**：凡 grape CLI 能做的走 CLI，禁止绕过 CLI 直连平台 API（curl/python httpx 等）。
   CLI 未装/版本过低 → **自动安装/升级**（官方源/签名包优先）→ 装好继续；仅当安装失败/环境不可用时才报障说明（不降级直连）。⚠️ 安装指引请参考：`references/grape-cli-installation.md`。
2. **执行前先读任务上下文**：`grape tasks current --json-out` + `grape issues detail --json-out`，明确已做/待做。
3. 严禁读取 data/、configs/、sessions.db 等 Grape 内部数据（data/workspaces/ 项目知识文档除外）；token 不写文件/日志/评论，不 printenv 打印。
4. **403/无权限**：立即停止该操作并回复用户「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」，不尝试其他 token 或绕行。
5. **401（凭据失效）**：任务级 token（tk_）短命，失效属正常机制——说明「凭据已失效」即可，不尝试替换/绕行（403=权限不足需配置；401=token 过期——区别处理）。
6. **AK/SK 纪律**：华为云凭据经场景 custom_fields 注入（`GRAPE_CF_MAP` 按 key 取 `HUAWEI_AK/HUAWEI_SK`——凭据走平台通道）；未配置 → 前置门 STOP 提示「在场景高级选项 custom_fields 配置 HUAWEI_AK/HUAWEI_SK」，**严禁从其他位置寻找凭证**；AK/SK 不得硬编码到任何 .tf 文件（一律环境变量映射 `HW_ACCESS_KEY`/`HW_SECRET_KEY`）。
7. **terraform 边界**：编码只执行到 `terraform plan`（只读预览）——**禁止 terraform apply / destroy**（部署是 SRE 职责）。
8. **长命令/常驻命令纪律**：terraform init/plan 等可能长耗时 → 加 `timeout` 限制、一次只装必要依赖；常驻/服务命令严禁前台执行（后台 + 验证 + kill 或交 SRE）。

## 二、环境变量表（平台注入，按 iac-coding Agent 类型）

| 变量 | 语义 | 用在哪 | 何时有 |
|------|------|--------|--------|
| `GRAPE_SERVER_URL` / `GRAPE_SESSION_TOKEN` | 服务端地址 / 会话 token（tk_）| grape CLI 自动读取 | 全部任务 |
| `REPO_FULL_NAME` / `ACCOUNT` | 仓库全名 / 属主 | CLI 的 --owner/--repo 参数 | 全部 |
| `REPO_NAME` | 仓库名（派生：`${REPO_FULL_NAME#*/}`）| --repo 参数 | 全部 |
| `ISSUE_NUMBER` | Issue 编号 | A2A payload / 分支名 feat/issue-{n} | 全部 |
| `PR_NUMBER` | PR 编号（代码优化场景有）| A2A payload | 有 PR 时 |
| `GRAPE_WORK_BRANCH` | 场景工作基线分支 | checkout 基座 | 场景任务 |
| `HUAWEI_AK`/`HUAWEI_SK` | 华为云凭据（资源规格查询/plan 凭证——场景 custom_fields → `GRAPE_CF_MAP` 按 key 动态取值，**凭据走平台通道**）| hcloud/obsutil 查询 + terraform 凭证映射 | 场景配置时 |

派生变量：`REPO_NAME` = `${REPO_FULL_NAME#*/}`。敏感变量（token/AK/SK 类）**不 printenv、不落盘、不写评论**。

> **华为云凭据取值（GRAPE_CF_* 通道）**：场景 custom_fields 配置 `HUAWEI_AK`/`HUAWEI_SK` key → 平台注入 `GRAPE_CF_1..N` + `GRAPE_CF_MAP`。技能不硬编码序号，按 key 动态取值：

```bash
eval "$(printenv GRAPE_CF_MAP | python3 -c 'import json, os, sys
m = json.load(sys.stdin) if os.environ.get("GRAPE_CF_MAP") else {}
for var, key in m.items():
    v = os.environ.get(var, "")
    print("export %s=%r" % (key, v))
')"
HUAWEI_AK="${HUAWEI_AK:-}"; HUAWEI_SK="${HUAWEI_SK:-}"
```
（凭据值只进 env 不进 prompt——不回显到日志/评论）
本技能不涉及 `USER_GITCODE_TOKEN`（Chat 域）。

## 三、前置检查门（自愈 → 重试 → STOP）

| 检查项 | 判定命令 | 通过标准 | 失败动作 |
|--------|---------|---------|---------|
| CLI 可用 | `grape --version` | ≥0.3.2 | **自愈**：按 `references/grape-cli-installation.md` 自动安装/升级（`timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git`）→ 装好再验；仍不可用 → 结束任务并说明 |
| 契约刷新 | `grape refresh` | 拉取最新契约成功 | **重试** ≤2 次；仍失败 → 继续（回退内置快照）|
| 任务上下文 | `grape tasks current` + `grape issues detail` | 拿到任务与上下文 | 定位不到 → STOP（不执行写操作）|
| terraform 可用 | `terraform version` | ≥1.7.5 且 ≤1.10.5 | **自愈**：按官方源安装 → 再验；仍不可用 → 报告阻塞 |
| 华为云凭据（资源规格查询前）| `${HUAWEI_AK:+ok}` 校验（GRAPE_CF_MAP 映射后）| 有值 | **STOP**：提示「请在场景高级选项 custom_fields 配置 HUAWEI_AK/HUAWEI_SK 后重试」——不寻找不借用（资源规格查询是 TF 生成前置——见 4.3）|
| 瞬时失败（网络/限流）| — | — | **重试**：自动重试 ≤3 次（退避 1s/2s/4s）|

## 四、技能定义与执行

### 4.1 定位与职责边界

**职责**：把 IaC Issue 的实现需求变成**可审查的 PR**——资源规格查询验证 → TF 配置生成（iac/ 目录）→ fmt/init/validate/plan 校验 → 自审查 → PR 创建 → A2A 通知 QA。
**守门不越界**：不 terraform apply/destroy（SRE 职责）、不合并 PR、不修改 Issue 范围外代码。

| 行为 | 态度 |
|------|------|
| 场景识别（按 A2A context 特征）| ✅ **必须做**（新开发 vs 代码优化）|
| 生成 TF 前资源规格查询验证 | ✅ **必须做，不可跳过**（flavor/镜像/可用区/VPC/安全组/OBS 桶名）|
| 所有 TF 代码放 `iac/` 子目录 | ✅ **必须做** |
| 所有 feature 开发先输出需求文档+方案设计再编码 | ✅ **必须做** |
| 开发任务包含测试用例 | ✅ **必须做** |
| terraform fmt/init/validate/plan（到 plan 为止）| ✅ **必须做**（plan 提交 PR 前）|
| 创建 PR 前自审查（code-review-checklist.md）| ✅ **必须做，不可跳过** |
| 创建 PR 后 Issue 评论告知 + A2A 通知 QA | ✅ **必须做，不可跳过** |
| 每个提交一个原子变更 | ✅ **必须做** |
| 通过 grape CLI 获取平台信息 | ✅ **必须做** |
| 执行 terraform apply / destroy | ❌ **禁止（SRE 职责——Coding 只到 PR 创建）** |
| 跳过资源规格查询直接生成 TF 配置 | ❌ **禁止** |
| 修改非 Issue 相关代码 / 直接合并 PR | ❌ **禁止** |
| curl 直连 API | ❌ 禁止（必须走 grape CLI）|

### 4.2 场景路由（入口 → 路径）

> **判定信号优先级**：`$PR_NUMBER` 已注入（存在 PR）→ 判定**代码优化**（无论 context 措辞）；`$PR_NUMBER` 未注入 → 按 A2A context 特征判定（下表）。⚠️ 无 PR_NUMBER **不代表**新开发——评论/复审触发的优化场景可能不带 PR 编号（runbook B1 有定位兜底）。

| A2A context 特征 | 场景 | 路径 |
|-----------------|------|------|
| `$PR_NUMBER` 有值；或含「PR 审查反馈」「审查发现问题」「需要修改」「优化」| **代码优化** | 修改 → 推送 → PR 评论告知 → A2A QA |
| 含「启动开发」「实现」「feature」「bug」| **新开发** | 需求文档+方案 → 资源规格查询 → TF 生成 → 校验 → 自审查 → PR → A2A QA |
| 其他 | 不做处理，结束 | — |

> **复制需求场景**：prompt 提示「用户已为此 Issue 指定了开发场景」时——按新开发执行（不因标题相似判断重复）。

### 4.3 处理流程（统一骨架）

**流程总览（一行）**：
- 新开发：⓪ 上下文 → ① 场景识别 → ② 需求文档+方案设计 → ③ 资源规格查询验证 → ④ TF 生成（iac/）→ ⑤ 校验（fmt/init/validate/plan）→ ⑥ 自审查 → ⑦ PR 创建 → ⑧ Issue 评论 + A2A QA → 收尾（4.8）
- 代码优化：⓪ 上下文 → ① 场景识别 → ② 按审查意见修改（原子提交）→ ③ PR 评论 → ④ A2A QA → 收尾（4.8）

**执行规则**：
- ⚠️ **启动即读 `references/iac-coding-runbook.md`**——每步具体命令按走查表照抄执行（不现场查 --help）
- 资源规格查询（③）成功是 TF 生成前提——查询失败/凭据缺失 → **不降级继续**（STOP 提示配置或报告阻塞——见 4.5）
- TF 边界：只到 `terraform plan`——apply/destroy 一律禁止
- ⑧ A2A 防重复：先 `issues pipeline` 查已含 `qa:a2a_event` 则不重复，只发评论
- MUST 硬性必经节点：③ → ④ → ⑤ → ⑥ → ⑦ → ⑧ → 收尾

### 4.4 命令标准（子集与坑点）

完整命令与参数见 `references/iac-coding-runbook.md` 与 `references/grape-cli-reference.md`。坑点：

| 坑点 | 正确做法 |
|------|---------|
| 参数必须精确 | 不确定 flag → `grape <cmd> --help` 查，绝不瞎猜重试 |
| write 类必须 --json 字符串或 @file | 长 body 先写文件再 `--json @file`（防 shell 转义）|
| 评论前缀 | 全部评论 `[coding Agent]` 开头 |
| PR 描述 | `pulls create` 契约无 body 字段——创建后 `git-repo pulls update` 补描述（四段：变更说明/资源清单/文件变更/后续步骤）；title 用 Conventional Commits |
| terraform 凭证 | `HW_ACCESS_KEY=${HUAWEI_AK}` 映射（env——不写进 .tf）|
| 防重复 A2A | A2A 前必查 `grape issues pipeline`（已含 `qa:a2a_event` 则不重复）|
| PR 链接 | Web 页面 `/pull/`（单数）markdown 格式——不得用 API 路径 |

### 4.5 故障决策表

| 故障 | 分类 | 动作 |
|------|------|------|
| 403/权限不足 | Required | **STOP**：按安全硬约束④回复用户，等待配置 |
| 401/凭据失效 | Optional | 说明「凭据已失效」即可——不尝试替换/绕行 |
| 命令失败（报错/字段错误）| — | **先看完整 stderr** → 按 runbook 错误排查速查处理 → 不反复盲试 |
| 华为云查询失败 / 凭据缺失 | Required | **不降级继续**——STOP 提示「请在场景 custom_fields 配置 HUAWEI_AK/HUAWEI_SK 后重试」或报告阻塞（资源规格是 TF 生成前置）|
| terraform init/validate/plan 失败 | Required | 看完整错误定位（provider/镜像/flavor 等问题）→ 修后重试 ≤2 次 → 仍失败：不创建 PR，Issue 评论报告失败原因和修复建议 |
| git push 失败 | — | 检查分支状态后重试 ≤1 次；仍失败报告 |
| A2A 调用非 2xx / 超时 | Required | 自动重试 ≤3 次 → 仍失败：评论说明 + next_step 人工介入 |
| MR 创建重复 | — | 先查是否已有同分支 open MR（`grape git-repo pulls list --state open`）——有则不重复创建 |

### 4.6 输出格式（固定产物）

1. **PR 创建**（`grape git-repo pulls create` → 再 `grape git-repo pulls update` 补描述四段：变更说明/资源清单/文件变更/后续步骤）：feature 分支 `feat/issue-{n}`，base = `$GRAPE_WORK_BRANCH`
2. **Issue 评论**：`[coding Agent] ✅ 已完成实现，请审查 PR [#n](https://gitcode.com/{repo}/pull/{n})`——含实现内容摘要
3. **A2A 请求**：`{"agent":"qa","payload":{"repository":"$ACCOUNT/$REPO_NAME","account":"$ACCOUNT","issue_number":{真实编号},"pr_number":{有则填=$PR_NUMBER 值},"context":"PR #{n} 已创建，{实现摘要}，请审查"}}`
4. **任务完成**（tasks complete）：结构见 4.8

### 4.7 写操作协议

| 操作 | 确认要求 |
|------|---------|
| 读操作（查/分析/terraform plan 预览）| 自动执行，无需确认 |
| git 提交/push、PR 创建、评论、A2A 交办、terraform fmt/init/validate | **流程内声明**——A2A 流水线显式触发，自动执行 |
| terraform apply/destroy | ❌ **禁止**（SRE 职责——即使是流程内也不执行）|
| 删除文件 / 合并 PR | ❌ 禁止 |
| 会话结束 | 列出本次变更（PR/提交/评论）|

### 4.8 任务收尾（必做）

业务动作完成后：输出人类可读摘要（场景/PR/校验结果）→ 调用：

```bash
grape tasks complete --json '{
  "result_text":  "结论：{新开发/代码优化}处理完毕（{实现内容 + PR 摘要}）",
  "actions":      ["场景识别: {新开发/优化}", "需求文档+方案: spec/plan/todo", "资源规格查询: {已查/阻塞}", "TF 生成: iac/ 目录", "校验: fmt/init/validate/plan {结果}", "自审查: {通过}", "PR: #{pn}", "评论/A2A: qa"],
  "conclusion":   "{已实现并创建 PR #{pn}，待 QA 审查 / 已按审查意见修改完成}",
  "artifacts":    ["PR #{pn}", "分支 feat/issue-{n}", "iac/ {tf 文件清单}", "评论: {位置}"],
  "issue_summary":"{完成摘要——实现内容/校验结果/PR 一句话}",
  "next_step":    "a2a_qa 或 等待用户反馈"
}'
```

⚠️ **结构化字段必填**（结尾 = 下一节点的输入）：`actions[]`/`conclusion`/`artifacts[]`/`issue_summary` must 真实填充——只传 `result_text` 会丢结构化归档；下游/A2A 接收方以结构化字段为主消费。

**立即结束**，不继续思考或等待输入。

## 五、参考文件清单

| 文件 | 用途 | 先读 |
|------|------|------|
| `references/iac-coding-runbook.md` | **执行走查表：新开发/代码优化全程命令逐步照抄 + 错误排查速查** | ⭐ 最先 |
| `references/grape-cli-installation.md` | grape CLI 安装/升级指引（前置门自愈用）| CLI 未装时 |
| `references/huaweicloud-tf-conventions.md` | 华为云 TF 编码规范（目录/凭证映射/cn-north-4 避坑/provider 版本/OBS backend）| TF 生成时 |
| `references/code-review-checklist.md` | 自审查清单（逐项检查）| 自审查时 |
| `references/grape-cli-reference.md` | grape CLI 命令参考 | 命令不确定时 |

## 六、Best Practices（实践积累区）

- 暂无，后续沉淀后更新补充（TF 校验高频失败模式/资源规格查询命中率/plan 常见问题分布）。