# IaC 部署执行走查表（runbook）

> 目的：把 iac-sre 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> **CLI 纪律**：本表已覆盖本技能全部平台交互命令（issues / git-repo issues / git / tasks）——**禁止 curl 直连平台 API（读操作也一样）**；华为云资源操作走 terraform/hcloud/obsutil（云资源工具）——每个节点需要的命令已写在该节点——按节点照抄；命令失败才看「错误排查速查」。
> 环境变量直接使用：`$ACCOUNT`、`$REPO_NAME`（=`${REPO_FULL_NAME#*/}`）、`$ISSUE_NUMBER`、`$GRAPE_WORK_BRANCH`（默认 main）、`HW_ACCESS_KEY`/`HW_SECRET_KEY`（=`${HUAWEI_AK/SK}` 映射）。
> **评论前缀硬规**：所有评论 body 一律以 `[sre Agent]` 开头。

---

## Step 0 就绪检查（前置门——按序执行）

```bash
# ⚠️ CLI 前置自愈（最先）：`grape --version` ≥0.3.2；未装/版本过低 → 按 `references/grape-cli-installation.md` 自动安装/升级 → 装好再验；仍不可用 → 结束任务并说明
grape --version
# ⚠️ terraform 前置：≥1.7.5 且 ≤1.10.5；缺失/版本不符 → 按官方源安装到版本区间 → 再验；仍不可用 → 报告阻塞
terraform version
grape refresh 2>&1 && echo REFRESH_OK          # 契约保鲜；失败重试 ≤2 次后回退内置快照继续
grape tasks current --json-out
grape issues detail --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out 2>&1 | head -80
# AK/SK 前置校验（缺失 → STOP 提示在【场景详情页→高级选项→自定义配置】配 name=HUAWEI_AK/HUAWEI_SK 或【通用设置】配置华为云 AK/SK——不寻找不借用；HUAWEI_AK/SK 两入口取值，HW_ACCESS_KEY 为 A3 才派生，此处不查它）：
if [ -z "${HUAWEI_AK}" ] || [ -z "${HUAWEI_SK}" ]; then echo "AK_SK_MISSING"; else echo "AK_SK_OK"; fi
# 评论告知（缺失时必发——含完整恢复路径）——命令见「STOP 评论模板」
```

## 场景 A · 部署（A2A 交办 / PR 合并触发）

### A1 · 拉取代码（必做）

```bash
rm -rf /tmp/deploy-ws 2>/dev/null; git clone "https://gitcode.com/$ACCOUNT/$REPO_NAME.git" /tmp/deploy-ws && cd /tmp/deploy-ws   # GIT_ASKPASS 已注入（BOT_GITCODE_TOKEN）——普通 git clone 自动认证，不写 token
git checkout "$GRAPE_WORK_BRANCH" 2>&1 || git checkout main 2>&1
git log -1 --format=%H 2>&1   # 部署基线 commit（记录到清单）
```

### A2 · 资源查重（部署前必须——不可跳过）

```bash
# 1) 提取 Issue 资源命名与规格（VPC/ECS/RDS/OBS 名——从 issues detail）
# 2) terraform plan 验证资源规格可用性（调用 provider API 检查镜像/flavor）：
#    ⚠️ TF 代码在仓库 iac/ 子目录（与 iac-coding A4 约定一致）——必须在 iac/ 下执行：
cd /tmp/deploy-ws/iac && timeout 180 terraform init 2>&1 | tail -5
timeout 300 terraform plan 2>&1 | tail -40
# 3) 已有资源查询（环境变量凭证——不得用 hcloud CLI profile 里的）：
hcloud VPC ListVpcs 2>&1 | grep -i "{资源名}" || echo "无同名 VPC"   # 按资源类型对应查询 ECS/RDS/OBS
# 处理：已存在且属本 Issue → 复用；已存在非本 Issue → ⚠️ 立即停止 + 评论告知（不创建/不抢占）；不存在 → 继续 apply
# 查重结果记录到处理记录 pre_check
```

### A3 · 部署（必做——到 apply）

```bash
# 凭证映射（env——不写 .tf 不 printenv）：
export HW_ACCESS_KEY="${HUAWEI_AK}"; export HW_SECRET_KEY="${HUAWEI_SK}"
export AWS_ACCESS_KEY_ID="$HW_ACCESS_KEY"; export AWS_SECRET_ACCESS_KEY="$HW_SECRET_KEY"; export AWS_DEFAULT_REGION="cn-north-4"
# terraform 版本确认（1.7.5 ~ 1.10.5）：
terraform version 2>&1 | head -3
# 部署（init 已做——直接 plan + apply；长命令加 timeout；⚠️ 当前在 iac/ 目录）：
cd /tmp/deploy-ws/iac && timeout 300 terraform plan -out=tfplan 2>&1 | tail -40
timeout 600 terraform apply tfplan 2>&1 | tail -40
# OBS backend state 确认（无 errored.tfstate）：
ls .terraform/terraform.tfstate 2>/dev/null && echo "state OK" || echo "state 异常——按 build-debug-checklist OBS Backend 段排查"
```

### A4 · 部署验证（基础设施层——不做应用层）

```bash
# 仅验证基础设施资源状态（terraform state/output——不 SSH/不 HTTP/不查应用）：
terraform state list 2>&1 | head -30
terraform output -json 2>&1 | head -60
# 验证项：VPC/子网/安全组可用、ECS ACTIVE + EIP 绑定、RDS 可用（3306 内网放通）、OBS bucket 创建成功
```

### A5 · 资源清单输出（最高优先级——apply 成功后必须立即做）

```bash
# 1) inventory.json（terraform output -json——含 sensitive 密码；⚠️ 在 iac/ 目录执行）：
cd /tmp/deploy-ws/iac && terraform output -json > /tmp/inventory.json 2>&1
# 2) 上传 OBS（obsutil——不用 curl 签名）：
obsutil cp /tmp/inventory.json "obs://{bucket}/inventory/inventory.json" 2>&1 | tail -5
# 3) Issue 评论发布非敏感摘要（资源列表 IP/桶路径——不发布预签名 URL/不发布密码）：
cat > /tmp/sre-comment.json << 'JSONEOF'
{"body":"[sre Agent] 部署完成\n\n## 资源清单\n| 资源 | 信息 |\n|--|--|\n| ECS | {公网 IP} |\n| RDS | {私网 IP} |\n| VPC/子网/安全组 | {名称} |\n\n敏感凭证存储：obs://{bucket}/inventory/inventory.json（使用 AK/SK 通过 obsutil 或 OBS API 访问）\n基础设施验证：{ECS ACTIVE / RDS 可用 / OBS 上传成功}"}
JSONEOF
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json @/tmp/sre-comment.json --json-out
# ⚠️ 资源清单输出完成前，不得执行任何其他动作（含 A2A）
```

## STOP 评论模板（凭据缺失且需云部署——Step 0 分支——必发）

```bash
# body（完整恢复路径——用户按此操作即可继续流水线）：
#   [sre Agent] 部署前置检查未通过：华为云 AK/SK 未配置。
#   本次未执行任何云操作。
#   👉 恢复路径：
#   1. 在【项目场景 → 点击单个场景 → 场景详情页 → 高级选项 → 自定义配置】添加 name=HUAWEI_AK、name=HUAWEI_SK，或【通用设置】配置华为云 AK/SK
#   2. 配置完成后，在本 Issue 评论：『已配置 AK/SK，请重新部署』
#   3. 平台将自动重新触发本部署任务——无需其他操作
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[sre Agent] 部署前置检查未通过：华为云 AK/SK 未配置。本次未执行任何云操作。\n\n👉 恢复路径：\n1. 在【项目场景 → 点击单个场景 → 场景详情页 → 高级选项 → 自定义配置】添加 name=HUAWEI_AK、value=<AK> 与 name=HUAWEI_SK、value=<SK>（name 严格用约定名）；或【通用设置】配置华为云 AK/SK\n2. 配置完成后，在本 Issue 评论：『已配置 AK/SK，请重新部署』\n3. 平台将自动重新触发本部署任务——无需其他操作"}' --json-out
```

## 收尾（4.8 结构化——must 真实填充）

```bash
grape tasks complete --json '{
  "result_text":  "结论：Issue #'$ISSUE_NUMBER' 部署完成（{资源清单摘要}）",
  "actions":      ["资源查重: 检查 {n} 项", "部署: terraform init/plan/apply", "验证: state/output {结果}", "资源清单: 已输出（Issue 评论 + OBS 归档）"],
  "conclusion":   "部署完成——{资源列表}/{阻塞原因 + 恢复路径}",
  "artifacts":    ["资源清单: OBS obs://{bucket}/inventory/inventory.json", "Issue 评论: {位置}"],
  "issue_summary":"部署完成 | 资源 {列表摘要} | 验证 {结果}",
  "next_step":    "done 或 视下游交办"
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
| terraform init 超时 / provider 下载失败 | 按 `references/build-debug-checklist.md` 排查（镜像源/provider 缓存）|
| OBS backend 错误（errored.tfstate）| 按 build-debug-checklist 的「OBS Backend 故障排查」段定位 |
| terraform apply 失败（资源冲突/规格不可用）| 看完整错误 → 修后重试 ≤2 次 → 仍失败：评论报告原因和修复建议 |
| 资源冲突（查重发现同名非本 Issue 资源）| **立即停止**——评论告知「资源 <名称> 已被占用…请确认命名后重试」——不创建/不抢占 |
| obsutil 未安装 | 按华为云官方源安装（与 terraform CLI 安装同理——见 build-debug-checklist 镜像源段）→ 再验 |
| 401 凭据失效 | 说明「凭据已失效」即可，不换 token |
| 403 权限不足 | 说明需管理员配置——不绕行 |
| 报「契约过期/命令不识别」| 先 `grape refresh` 再重试 |