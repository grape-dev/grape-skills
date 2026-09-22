# Deploy-CLI 执行走查表（runbook）

> 目的：把 SRE Agent 部署/资源释放的**每一步要做什么 + 用哪条命令**固化下来，Agent **照着执行、不要逐条探索**。
> 环境变量：`$ACCOUNT` / `$REPO_NAME` / `$REPO_FULL_NAME` / `$ISSUE_NUMBER` / `$PR_NUMBER`（可选）/ `$HUAWEICLOUD_SDK_AK`/`$HUAWEICLOUD_SDK_SK`（华为云）/ `$GRAPE_SESSION_TOKEN`/`$GRAPE_SERVER_URL`（grape 自动读取）。
> **评论前缀硬规**：Issue/PR 评论 body 一律以 `[SRE Agent]` 开头。

---

## 入口判定（先判定操作类型，再走对应流程）

### 操作类型识别
读取 A2A context / Issue 正文，按关键词：
- **资源释放**：含「释放/销毁/删除/回收/destroy/release/teardown/cleanup/清退」→ 走「资源释放流程」
- **部署**：其他（创建/部署/上线/更新/deploy）→ 走「部署流程」

### 入口
| 入口 | 判断 | 处理 |
|------|------|------|
| `a2a_event` | 由 Issue/Coding 交办 | 有 `pr_number`→拉 PR 分支；无→默认分支；资源释放→跳过构建直接释放 |
| `pull_request_merged` | 分支为 master/main | 走完整部署流程 |
| 其他事件 | — | 输出 `SKIP` 并返回 |

---

## 流程（部署）

### Step 1 · 理解项目结构（判断构建方式）
```bash
grape repos project info --owner "$ACCOUNT" --repo "$REPO_NAME" --json-out   # 项目知识基线（优先）
grape git-repo tree --owner "$ACCOUNT" --repo "$REPO_NAME" --ref main --depth 2 --json-out
grape git-repo contents --owner "$ACCOUNT" --repo "$REPO_NAME" --path README.md --raw
```
| 文件标记 | 推断 |
|----------|------|
| `package.json` | Node.js（npm/yarn） |
| `requirements.txt`/`pyproject.toml`/`Pipfile` | Python（pip/poetry） |
| `go.mod` | Go（go build） |
| `pom.xml`/`build.gradle` | Java（mvn/gradle） |
| `Dockerfile` | 容器化（构建镜像推送） |
| `Makefile` | 自定义（读 Makefile 目标） |
| `app.py`/`main.py` | Python Flask |

### Step 2 · 获取代码并构建
```bash
# git 一律用 grape git（凭据自动注入、token 零暴露）：
# A2A + 有 pr_number → grape git clone <repo_url> && grape git checkout <pr_branch>
# A2A + 无 pr_number → grape git clone <repo_url>
# PR 合并触发 → grape git checkout master|main && grape git pull
cd /path/to/repo
# 按需：npm install && npm run build / pip install -r requirements.txt / go build ./...
```

### Step 3 · 部署（hcloud 华为云；详见 SKILL「部署流程」实测命令与坑位）
1. **确保 hcloud 已安装**（缺失自动装：按 uname -m 选 amd64/arm64 包，`--max-time 300`，首次 `echo y | hcloud configure set --cli-agree-privacy-statement=true`）。
2. **任务专属 profile 隔离**（⚠️ 严禁改 default profile）：
   ```bash
   HC_PROFILE="task-$$"
   hcloud configure set --cli-profile="$HC_PROFILE" \
     --cli-access-key="$HUAWEICLOUD_SDK_AK" --cli-secret-key="$HUAWEICLOUD_SDK_SK" \
     --cli-region=cn-north-4 --cli-mode=AKSK
   hc() { hcloud "$@" --cli-profile="$HC_PROFILE"; }
   trap 'hcloud configure delete --cli-profile="$HC_PROFILE" 2>/dev/null || true' EXIT
   ```
3. **ECS 幂等检查 + 创建**：先按名称前缀查已有 ECS（`hc ECS ListServersDetails` 过滤 `deploy-<repo>`）→ 有则复用；无则动态选最小可用按量规格（ListFlavors + ListFlavorSellPolicies）创建，必须带 keypair / 指定可用区 cn-north-4a|b / EIP 自动创建。
4. **部署代码 + 一次性启动**：scp 仓库文件到 ECS → 单条 SSH 会话（DNS 修复 + apt/pip 国内镜像 + venv + gunicorn 启动，端口 5000）。
5. **清理旧进程**：`ss -tlnp | grep ':5000'` 按端口 kill，**严禁 `pkill -f gunicorn/app.py`**（会误杀 agent 自身）。

### Step 4 · 验证
```bash
curl -s -o /dev/null -w '%{http_code}' "http://$ECS_IP:5000/"          # 期望 200
curl -s -o /dev/null -w '%{http_code}' "http://$ECS_IP:5000/post/1"
```
- 端口监听 `ss -tlnp | grep 5000` + 公网可达。
- 失败 → 输出错误信息并建议回滚（不自动回滚）。

---

## 资源释放流程

### Step 1 · 收集资源信息
从 Issue 正文/评论提取：ECS 名称/IP、RDS 实例名、OBS 桶名、安全组/密钥对/EIP。
```bash
grape git-repo issues comments list --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
```
仍无法确定 → Issue 回帖追问用户。

### Step 2 · 查询并释放（先查再删，释放后验证）
```bash
# 同部署：task 专属 profile 隔离（hc()/obs() 包装 + trap 清理）
# 2.1 ECS: hc ECS ListServersDetails（按名称筛）→ 确认 → hc ECS DeleteServer --server_id=<ID> → 复查不存在
# 2.2 RDS: hc RDS ListInstances → hc RDS DeleteInstance --instance_id=<ID>（删除可能异步，稍后验证）
# 2.3 OBS: obs rm <bucket> -r -f 清空 → obs rm <bucket> -b / hc OBS DeleteBucket --bucket=<NAME>
# 2.4 EIP: hc EIP ListPublicIps → hc EIP DeletePublicIp --publicip_id=<ID>
```

### Step 3 · 验证与报告
- 逐个确认已释放（查询空或 404）。
- Issue 回帖汇总（资源名 → 状态：已释放/未找到/释放失败），body 以 `[SRE Agent]` 开头。

---

## 收尾（必做，任何分支都必须执行到最后）

> ⚠️ **本技能收尾 = 调 `grape tasks complete`（情形一）**：部署/释放完成 + 评论告知后**必须调用**，**评论发完 ≠ 任务完成**；只调 complete，不再输出 JSON 块。

```bash
grape tasks complete --json '{
  "result_text": "结论：Issue #'"$ISSUE_NUMBER"' 部署/资源释放完成。",
  "next_step": "done",
  "actions": ["构建并部署到华为云 ECS / 释放资源", "验证部署结果", "在 Issue #'"$ISSUE_NUMBER"' 评论告知"],
  "conclusion": "部署完成，http {http_code} / 资源 {状态}",
  "artifacts": ["ECS {ecs_ip}", "Issue #'"$ISSUE_NUMBER"' 评论（comment id=XXXXXX）"],
  "issue_summary": "部署完成 | 访问 {url} | 验证 {http_code} / 资源 {状态}"
}'
```
> `already:true` 忽略。**然后结束任务**，不要继续思考或等待输入。

---

## 错误排查速查

| 现象 | 处理 |
|------|------|
| `No such command 'X'` | 命令名错，核对 runbook / reference；仍不确定才 `grape commands <关键词>` |
| 401 凭据失效 | 说明"凭据已失效"，不换 token |
| 403 账户/平台类 | 说明需 `grape_`/JWT |
| AK/SK 缺失 | 回复「请在 Grape 控制台配置华为云 AK/SK 后重试」，不自行寻找 |
| hcloud Exec format error | 架构包名选错（arm64 下 -arm64- / amd64 下 -amd64-） |
| Ecs.0707 / flavor 找不到 | 动态查询 ListFlavors + ListFlavorSellPolicies，勿硬编码 |

## 明确禁止

- ❌ `hcloud configure set` 改 default profile——用 `task-$$` 专属 profile。
- ❌ `pkill -f gunicorn/app.py`——按端口精确 kill。
- ❌ 直接修改仓库代码 / 删除仓库分支。
- ❌ 部署失败自动回滚——输出错误并建议，不自动执行。
- ❌ 不因任意原因跳过收尾（tasks complete）。