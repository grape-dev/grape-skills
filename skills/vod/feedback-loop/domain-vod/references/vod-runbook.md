# VOD 执行走查表（runbook）

> 目的：把 domain-vod 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名 = `${REPO_FULL_NAME#*/}`）、`$ACCOUNT`（触发人 actor）、`$ISSUE_NUMBER`、`$DEVOPS_EVENT_TYPE`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取——**不传 `--token`、不 export 其他 token**）。
> 引导漏斗/Issue 模板细节见 `references/domain-requirement-guide.md`；**平台交互一律 grape CLI**——禁止 curl 直连平台 API。

## Step 0 就绪检查（前置门——按序执行）
```bash
grape refresh 2>&1 && echo REFRESH_OK          # 契约保鲜；失败重试 ≤2 次后回退内置快照继续
grape tasks current --json-out                 # 当前任务（事件/上下文/基线提示）
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out 2>&1 | head -80
# ISSUE 缺失 → grape git-repo issues get / issues list 定位；定位不到 → STOP（不执行写操作）
```

## 场景 A：开发者声音引导建 Issue

```bash
# A1 知识基线（必须最先——未读基线前不分析）：
# 本地读取基线仓库 jiuwenswarm（develop 分支）：README + jiuwenswarm/extensions/legal_platform/（最近先例）
#   + channels/web/frontend/src/components/{LegalCasePanel,...}/ + services/legalApi.ts
#   + stores/legalStore.ts + utils/frontendPlatform.ts + components/SessionSidebar/index.tsx
#   + public/legal-ai-logo.svg + resources/agent/
# 优先复用 prompt 内联的「项目知识基线」；缺失 → 按上述本地路径降级分析

# A2 历史全貌（重复/在造判断）
grape issues mine --json-out
grape git-repo issues list --owner "$REPO_OWNER" --repo "$REPO_NAME" --state all --json-out
grape git-repo pulls list --owner "$REPO_OWNER" --repo "$REPO_NAME" --state all --json-out

# A3-A3a 需求引导漏斗 + 四维就绪度检查（看 SKILL「A3/A3a」，每次 1-3 个具体问题，≤3 轮）
# 核心必问：「功能模块期望（前端页/后端 RPC/落库数据）」「对话代办操作期望（哪些操作可由主对话代办）」
#           「产品设计细节（列表字段/表单校验/操作按钮/空态错误态加载）」「品牌改造期望」

# A4 结构化建 Issue（长 body 先写文件再 --json @file，防 shell 转义）
grape issues create --owner "$REPO_OWNER" --repo "$REPO_NAME" \
  --json '{"title":"feat: <Domain>Swarm <中文品牌名> 领域 Swarm 二次开发","description":"{模板结构化 body，含四要素+功能模块+每功能操作方法/字段期望+对话代办+产品设计细节+品牌改造+就绪度评级，标注 auto-submitted by domain-vod Agent}"}'

# A5 A2A 交办 domain-issue（就绪度非 needs-discussion 才可交办；⚠️ 必须防重复）
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 已含 issue:a2a_event → 不重复 A2A，只发评论；否则：
grape a2a handoff --json '{"agent":"issue","payload":{"repository":"$REPO_FULL_NAME","account":"$ACCOUNT","issue_number":'$ISSUE_NUMBER',"readiness":"{评级}","review_items":[{...}],"next_hop":"coding","allowed_agents":["issue","coding","qa","sre"],"context":"VOD 已完成需求收敛与就绪度评级，请继续 Spec 设计（功能模块 + 对话代办 + 品牌改造），完成后交办 domain-coding"}}'
# 失败 → 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入
```

## 场景 B：Issue 审视（event 接管）

```bash
# B0 读取 Issue 全貌（含阶段/事件/pipeline）
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# 含 auto-submitted by domain-vod → 跳过审视，直接 A4/A5 交办
# B1 读评论列表（审视时辅助判断）
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
# B4 澄清评论（不清晰时）——引原文 + 1-3 个具体问题
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Domain VOD Agent] > {用户原文}\n\n{澄清问题}"}'
# B5 结构化 body 收敛（不修改 labels/分配——留给 domain-issue）
grape git-repo issues update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"state":"open","body":"{按模板结构化的 body}"}'
# B6 A2A 交办（同 A5 防重复 + a2a handoff）
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape a2a handoff --json '{"agent":"issue","payload":{"repository":"$REPO_FULL_NAME","account":"$ACCOUNT","issue_number":'$ISSUE_NUMBER',"readiness":"{评级}","review_items":[{...}],"next_hop":"coding","allowed_agents":["issue","coding","qa","sre"],"context":"VOD 已完成 Issue 审视与结构化，请继续 Spec 设计，完成后交办 domain-coding"}}'
```

## 收尾（结构化——must 真实填充）
```bash
grape tasks complete --json '{
  "result_text":  "VOD 处理完毕（结论：{分析摘要}）",
  "actions":      ["知识基线: {已读/降级}", "历史全貌: 分析 {n} 条 Issue/PR", "引导: {轮数} 轮/无需", "建/审 Issue: {#n}", "就绪度评级: {ready/almost-ready/needs-discussion}", "A2A: issue"],
  "conclusion":   "{已建 Issue #n 并交办 / 已审视并结构化 / 待澄清}",
  "artifacts":    ["Issue #{n}（新建/结构化）", "评论: {评论位置}", "A2A handoff: {agent=issue, status=ok/降级}"],
  "issue_summary":"{分析摘要——领域主题/清晰度/就绪度 一句话}",
  "next_step":    "a2a_issue 或 等待开发者补充"
}'
# 结束任务——不继续思考/不追加内容
```

## 错误排查速查（先看完整 stderr，不截断不盲试）
| 现象 | 处理 |
|------|------|
| `No such command` | 命令名抄错 → 核对本 runbook / `references/grape-cli-reference.md`；仍不确定 `grape commands <关键词>` |
| `unknown method` / 命令不存在但应为平台功能 | 契约过期 → `grape refresh` 后重试 |
| `run_all_request` 含不识别字段 | `--json` 有契约不允许字段 → `grape <group> <verb> --help` 看 Body fields |
| 401 | token 失效（tk_ 短命正常）→ 说明已失效即可，不替换不绕行 |
| 403 | 权限不足 → STOP：按 SKILL 安全硬约束④回复用户等待配置 |
| Issue 定位不到 | `grape git-repo issues get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER"` / `issues list` 放宽条件 |
| A2A handoff 非 2xx/超时（退出码 ≥400） | 重试 ≤3 次 → 仍失败评论说明「A2A 服务不可达」+ 人工介入标注 |
| CLI 未装/版本过低 | `references/grape-cli-installation.md`：`timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git` → 再验 |
| 长命令篡改 | 长 body 先写文件再 `--json @file`——禁止 shell 内联转义踩坑 |
| 重复 A2A | pipeline 已含 `issue:a2a_event` → 不重复，只发评论 |