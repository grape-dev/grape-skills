# 部署执行走查表（runbook）

> 目的：把 cloud-deploy 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> 环境变量直接使用：`$ACCOUNT`（owner）、`$REPO_NAME`（repo 名 = `${REPO_FULL_NAME#*/}`）、`$ISSUE_NUMBER`、`$PR_NUMBER`（有则填）、`$DEVOPS_EVENT_TYPE`、`$GRAPE_WORK_BRANCH`（部署拉取分支）、`$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> 云资源操作（hcloud/华为云 REST）走 `references/deploy-guide.md`（领域手册）；**平台交互一律 grape CLI**——禁止 curl 直连平台 API。

## Step 0 就绪检查（前置门——按序执行）
```bash
grape refresh 2>&1 && echo REFRESH_OK          # 契约保鲜；失败重试 ≤2 次后回退内置快照继续
grape tasks current --json-out                 # 当前任务（事件/Issue/Spec 指引）
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out 2>&1 | head -80
# AK/SK 未配置（HUAWEI_AK/SK 为空）且任务需要云资源部署
# → STOP：提示在【场景详情页 → 高级选项 → 自定义配置】配 name=HUAWEI_AK/HUAWEI_SK 或【通用设置】配置华为云 AK/SK 后重试——不硬编码、不找替代（安全硬约束⑥/前置门）
#   并发出阻塞评论（含完整恢复路径——见场景 A「STOP 评论模板」）
# 任务仅需构建验证（无需云资源）→ 走场景 A A4（构建+验证——不触云）
```

## 场景 A：A2A 部署（a2a_event——issue/coding/qa 交办）
```bash
# A1 读任务上下文与基线（先读 runbook 与部署指南——不跳过）
# 项目知识基线已由服务端 prompt 内联（0.3.3 移除 knowledge context 命令——不存在，勿用）
# A2 拉代码（grape git 透传）——部署用分支：$GRAPE_WORK_BRANCH（默认 main）
grape git clone "https://gitcode.com/$ACCOUNT/$REPO_NAME.git" /tmp/deploy-ws && cd /tmp/deploy-ws
git checkout "$GRAPE_WORK_BRANCH" 2>&1 || git checkout main
# A3 识别项目类型（package.json→Node/pyproject→Python/go.mod→Go/Dockerfile→容器）与子目录（Issue/Spec 指定）
# A4 本地构建（流程必需——产出可部署产物；不触云）：
#   Node：npm install && npm run build；Python：pip install && 构建；Go：go build
#   → 构建通过后按 Step 0 判断：任务需要云资源（部署到 ECS/OBS 等）→ AK/SK 已配置 → A5；
#     任务需要云资源但 AK/SK 未配置 → STOP（按 Step 0 提示配置——不找替代）
# A5 云资源部署（仅当：AK/SK 已配置 且 需求明确要求）→ deploy-guide.md：hcloud 安装→profile 隔离→幂等检查→建 ECS→SSH 上传→启动→验证
# A5.1 关联仓库部署（当 $GRAPE_LINKED_REPOS 非空时）→ deploy-guide.md §4.0：遍历关联仓库 worktree→构建→部署到同 ECS 不同目录/端口→验证
# A6 发验证结论评论（唯一通道——禁止 curl）：
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[SRE Agent] 部署验证结论：{验证清单表格 + 结论 / 阻塞原因 + 恢复路径}"}' --json-out
```

## STOP 评论模板（凭据缺失且需云部署——Step 0 分支——必发）

```bash
# body（完整恢复路径——用户按此操作即可继续流水线）：
#   [SRE Agent] 部署前置检查未通过：华为云 AK/SK 未配置。
#   本次未执行任何云操作。
#   👉 恢复路径：
#   1. 在【项目场景 → 点击单个场景 → 场景详情页 → 高级选项 → 自定义配置】添加 name=HUAWEI_AK、value=<AK> 与 name=HUAWEI_SK、value=<SK>（name 严格用约定名）；或【通用设置】配置华为云 AK/SK
#   2. 配置完成后，在本 Issue 评论：『已配置 AK/SK，请重新部署』
#   3. 平台将自动重新触发本部署任务——无需其他操作
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[SRE Agent] 部署前置检查未通过：华为云 AK/SK 未配置。本次未执行任何云操作。\n\n👉 恢复路径：\n1. 在【项目场景 → 点击单个场景 → 场景详情页 → 高级选项 → 自定义配置】添加 name=HUAWEI_AK、value=<AK> 与 name=HUAWEI_SK、value=<SK>（name 严格用约定名）；或【通用设置】配置华为云 AK/SK\n2. 配置完成后，在本 Issue 评论：『已配置 AK/SK，请重新部署』\n3. 平台将自动重新触发本部署任务——无需其他操作"}' --json-out
```

## 场景 B：PR 合并自动部署（pull_request_merged）
```bash
# B1 确认触发（$DEVOPS_EVENT_TYPE=pull_request_merged 或事件上下文）——构建产物版本 = PR 合并 commit
# B2 同 A2-A5（checkout main/$GRAPE_WORK_BRANCH 拉到合并后代码）
```

## 场景 C：资源释放（回收实例——用户明确要求）
```bash
# C1 先查再删（幂等）：deploy-guide.md 释放段——列出资源→确认→删除（不开默认释放）
# C2 评论回帖释放结果（grape git-repo issues comments create——同上）
```

## 收尾（4.8 结构化——must 真实填充）
```bash
grape tasks complete --json '{
  "actions": ["做了什么：构建命令/验证结果/评论 id"],
  "conclusion": "部署结论（通过/阻塞+原因）",
  "artifacts": ["产物：dist/ / ECS IP / 评论id"],
  "next_step": "done 或下一步建议",
  "issue_summary": "Issue 最新聚合理（管道他节点状态 | 本次动作 | 结果）"
}'
# 结束任务——不继续思考/不追加内容
```

## 错误排查速查（先看完整 stderr，不截断不盲试）
| 现象 | 处理 |
|------|------|
| `No such command` | 命令名抄错 → 核对本 runbook / reference；仍不确定 `grape commands <关键词>` |
| `unknown request field(s)` | `--json` 有契约不允许字段 → `grape <group> <verb> --help` 看 Body fields |
| 401 | token 失效（tk_ 短命正常）→ 说明已失效即可，不替换不绕行 |
| 403 | 权限不足 → STOP：按安全硬约束④回复用户等待配置 |
| HTTP 非 200（dev/服务验证） | 看 /tmp/*.log 定位（端口占用/构建失败）→ 修后重试 ≤2 次 |
| AK/SK 为空但需求要云部署 | STOP：提示配置 AK/SK——严禁其他来源/绕行 |
| hcloud 未安装 | deploy-guide.md §1 自动安装（官方源优先）；装不上才报障 |
| git clone/push 失败 | 凭据问题 → `grape git credential` 检查；仓库无权限 → STOP 说明 |
| 长命令/常驻服务 | 一律后台 + 日志文件 + sleep 探测——禁止前台长时间阻塞 |