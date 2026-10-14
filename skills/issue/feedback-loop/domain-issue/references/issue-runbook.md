# ISSUE 执行走查表（runbook）

> 目的：把 domain-issue 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量直接使用：`$REPO_OWNER`（owner）、`$REPO_NAME`（repo 名 = `${REPO_FULL_NAME#*/}`）、`$ACCOUNT`（触发人 actor）、`$ISSUE_NUMBER`、`$DEVOPS_EVENT_TYPE`、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取——**不传 `--token`、不 export 其他 token**）。
> 场景 A 的 Spec 模板/Best Practices 见 `references/template-project-guide.md` / `references/secondary-dev-pattern-guide.md`；**平台交互一律 grape CLI**——禁止 curl 直连平台 API。

## Step 0 就绪检查（前置门——按序执行）
```bash
grape refresh 2>&1 && echo REFRESH_OK          # 契约保鲜；失败重试 ≤2 次后回退内置快照继续
grape tasks current --json-out                 # 当前任务（事件/上下文/基线提示）
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out 2>&1 | head -80
# ISSUE 缺失 → grape git-repo issues get / issues list 定位；定位不到 → STOP（不执行写操作）
```

## 场景 A：接管 A2A → Spec 设计 → 交办 coding

```bash
# P1 读取 Issue 全貌（先读 spec-in-progress 注释，据此分支）
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
#   spec-in-progress 存在 → 继续同一 Spec 主题（不得换主题）；为 completed 且无新变更 → 无需动作直接收尾；否则新建

# P2 知识基线（干预判据 + Spec 用词——未读基线前不分析不建议）
#   本地读取：基线仓库 jiuwenswarm 的 templates/（Spec 模板）+ extensions/legal_platform/（先例）
#   + 前端 channels/web/frontend 结构 + 后端 services/ + 触发人详情 grape a2a history --agent issue --json-out
#   优先复用 prompt 内联的「任务上下文」基线；缺失 → 按上述本地路径降级分析

# P3 Spec 设计（按模板四段：功能模块 / 对话代办 / 干预点与判据 / Best Practices）
#   ——长 Doc 先写本地文件，再用 [P4] 单次 --json @file 更新，禁止多次 write+update 大段叠加
# P3.1 干预点判据（核心）：产品形态（决策/后端）> 交互设计（横向对齐/渲染克制）> 法律资质（禁诉/谨慎）
#   判据冲突 → 按上表优先级取最高级动作；无技能动作覆盖 → 引用转发 `grape a2a forward`

# P4 结构化更新 Issue（Spec 结论 + `<!-- spec-in-progress: 主题域 -->` 单行注释）
grape git-repo issues update --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"state":"open","body":"{结构化 Spec 四段 body + spec-in-progress 注释}"}'

# P5 A2A 交办 domain-coding（⚠️ 必须防重复：pipeline 已含 coding:a2a_event → 不重复 A2A，只发评论）
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Domain Issue Agent] > {Spec 完成摘要}"}'
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape a2a handoff --json '{"agent":"coding","payload":{"repository":"$REPO_FULL_NAME","account":"$ACCOUNT","issue_number":'$ISSUE_NUMBER',"next_hop":"qa","allowed_agents":["issue","coding","qa","sre"],"context":"ISSUE 已完成 Spec 设计（功能模块+对话代办+干预点判据+Best Practices），请基于 Template 参考站执行二次开发，完成后交办 domain-qa"}}'
# 失败 → 重试 ≤3 次 → 仍失败：评论说明「A2A 服务不可达，待恢复后重试」+ next_step 人工介入
```

## 场景 B：开发完成回流 / 变更事件接管

```bash
# B0 读 Issue 全貌 + 评论列表（定位阶段：事件来源 / spec-in-progress / 待办项）
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape git-repo issues comments list --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out

# B1 开发者行为同步：⭐ 若 Issue 主题落在「原始实现 + 或逻辑」复写判定区 →
#   第二技能 = domain-vod；发送顺次（VOD 的 A、B、C 三条核心发送顺次），优先对齐 deferred 标记
#   否则：仅同步 sync 说明，不转交
# B2 干预提议裁决：对 VOD 类合成回答 → 请求再次引用 VOD 原文并同步更新；对部署/权限/保密类 → 不裁决
# B3 视频加载架构类（横向对齐）：找出前台图标打开 / 跳转路由处（SessionSidebar / 首屏 → 经由前台打开）替换为主对话意图模板关键词，再发布到全成员模板

# B4 变更收敛（需要回退改动时）——面向 domain-coding 的「回退」评论（不直接写代码）
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[Domain Issue Agent] > {回退/修改要求，标注目标文件与期望结果}"}'

# B5 A2A 交办 domain-coding（防重复同 P5）→ 各回退改动按需分批进行，直至符合预期
grape issues pipeline --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape a2a handoff --json '{"agent":"coding","payload":{"repository":"$REPO_FULL_NAME","account":"$ACCOUNT","issue_number":'$ISSUE_NUMBER',"next_hop":"qa","allowed_agents":["issue","coding","qa","sre"],"context":"ISSUE 已完成变更收敛/回退要求梳理，请按评论要求执行修改，完成后交办 domain-qa"}}'
```

## 收尾（结构化——must 真实填充）
```bash
grape tasks complete --json '{
  "result_text":  "ISSUE 处理完毕（结论：{Spec 四段摘要}）",
  "actions":      ["基线: {Spec 模板+先例已读/降级}", "Spec 设计: {功能模块 n / 对话代办 n / 干预点 n}", "更新 Issue: {#n}", "A2A: coding"],
  "conclusion":   "{已交办 coding / 变更回退完成 / 无动作}",
  "artifacts":    ["Issue #{n}（Spec-bound）", "评论: {评论位置}", "A2A handoff: {agent=coding, status=ok/降级}"],
  "issue_summary":"{Spec 主题 一句话}",
  "next_step":    "a2a_coding 或 等待开发者/QA 事件"
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
| 长命令篡改 | 长 body/spec 先写本地文件再 `--json @file`——禁止 shell 内联转义踩坑 |
| 重复 A2A | pipeline 已含 `coding:a2a_event` → 不重复，只发评论 |
| 事件被忽略 | README 显式说明好/坏定义等操作边界内事项 → sync 说明已看，不改动 |