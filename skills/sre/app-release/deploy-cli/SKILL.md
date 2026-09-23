---
name: deploy-cli
version: 2.0.0
description: |
  Huawei Cloud deployment skill (CLI 版). Supports two entry points:
  1. A2A direct deployment (a2a_event) — triggered by Issue/Coding Agent handing off a deploy task, no PR merge required.
  2. PR merge on master/main — full build→deploy→verify pipeline.
  Automatically determines build method from project files,
  deploys to Huawei Cloud using hcloud CLI, and verifies deployment.
  NOT for: non-merge, non-A2A PR events; pushes to non-master branches.
  全部 Grape/GitCode 操作使用 grape CLI 命令行（含 grape git）。
tools:
  - grape
---
# Cloud Deploy (deploy-cli)

## 安全硬约束（必须遵守）

1. 调用 Grape/GitCode 平台一律只用 `grape` CLI 与系统注入的 `$GRAPE_SESSION_TOKEN`，严禁从数据库/configs/日志/历史中寻找其他 token，也**不得改用 curl 直连 VCS API**。命令参考见 `references/grape-cli-reference.md`。注意 token 有调用范围：会话级 `tk_` 覆盖本技能全部日常操作；「账户/平台管理」类端点对 `tk_` 返回 403（需 `grape_` API Key 或 Web JWT）——本技能一般用不到，如遇 403 按指引说明即可，不要更换 token 或绕行。
2. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据。
3. API 返回 403/无权限时：立即停止该操作并回复用户「该操作需要管理员/维护者权限，请在仓库设置中手动配置后重试」，严禁尝试其他 token 或绕行手段。
4. token 不得写入任何文件/日志/评论。
5. AK/SK 必须从 Grape 控制台配置获取（`$HUAWEICLOUD_SDK_AK`/`$HUAWEICLOUD_SDK_SK` 由服务端注入），严禁从数据库/configs/日志/历史/其他文件中寻找或硬编码凭证。
6. 如 Grape 控制台未配置 AK/SK，立即停止操作并回复用户「请在 Grape 控制台中配置华为云 AK/SK 后重试」，严禁尝试其他来源或绕行手段。
7. ⚠️ **严禁 `hcloud configure set` 改 default profile**（seq#2493 事故）：必须用 `--cli-profile="task-$$"` 创建 task 专属 profile，所有 hcloud 命令通过 `hc()` 包装函数带 `--cli-profile` 执行，部署结束后 `hcloud configure delete` 清理。obsutil 同理用 `-i/-k` 直接传 AK/SK，不写全局 .obsutilconfig。

## Prerequisites（执行前必检，通过后才进入处理流程）

> 动手前先确认工具链就绪；**grape CLI 是公开可安装的**（`gitcode.com/grape-dev/grape-cli`），未装/版本过低时**自行安装**（`pip install git+https://gitcode.com/grape-dev/grape-cli.git`）。

1. **grape CLI 版本满足**：`grape --version`（过低/未装 → 自装/升级，再验证）。
2. **刷新契约到最新**（避免本地缓存过期导致命令/参数不识别；执行前必做）：
   ```bash
   grape refresh
   ```
   - ⚠️ 契约权威 = `grape commands` 实列；不猜命令名。
3. **认证与环境变量就绪**：
   ```bash
   echo "token=${GRAPE_SESSION_TOKEN:+ok} repo=$REPO_NAME issue=$ISSUE_NUMBER ak=${HUAWEICLOUD_SDK_AK:+ok}"
   ```
   - 缺华为云 AK/SK → 回复「请在 Grape 控制台配置华为云 AK/SK 后重试」，结束。
4. **安装后仍不可用 / 认证缺失** → 输出「前置检查未通过：<原因>」并结束；通过后才读取 `deploy-runbook.md` 进入处理流程。

## 环境变量（服务端已注入，直接使用）

| 变量 | 语义 | 用途 |
|------|------|------|
| `GRAPE_SERVER_URL` | 服务端地址 | `grape` 自动读取 |
| `GRAPE_SESSION_TOKEN` | 会话级临时 token（`tk_`） | `grape` 自动认证 |
| `REPO_FULL_NAME` | `owner/repo` | A2A `repository` / 知识基线 / 场景 |
| `ACCOUNT` | owner | `--owner "$ACCOUNT"` |
| `REPO_NAME` | repo 名 = `${REPO_FULL_NAME#*/}` | `--repo "$REPO_NAME"` |
| `ISSUE_NUMBER` | Issue 编号 | `--number` / A2A |
| `PR_NUMBER` | PR 编号（可选） | PR 分支定位 / A2A |
| `HUAWEICLOUD_SDK_AK` / `HUAWEICLOUD_SDK_SK` | 华为云凭证 | hcloud 认证 |
| `GRAPE_SCENE_ID` | 当前场景 ID（可选） | `grape scenes detail` 取节点 |
| `GRAPE_WORK_BRANCH` | 目标合入分支（缺省取仓库默认分支，如 main/master） | 入口判定与获取代码的分支基准；runbook 解析为 `$WORK_BRANCH` |
| `DEVOPS_EVENT_TYPE` | 事件类型 | 入口判定 |

> ⚠️ **`GRAPE_WORK_BRANCH` 语义（重要，避免误判）**：它是**整个仓库/场景的开发基线分支**，可能叫长期分支（`dev`/`weekly-xx`）**或 `feat/issue-N`（N 不一定等于当前 Issue 编号，是场景配置的基线名）**——不是"当前 Issue 的专属分支"。
> - **默认采用服务端注入值作为拉取/部署的代码分支基准**，即使它叫别的 Issue 分支名，也不要因名字含其它 Issue 号就丢弃/改写为 main。
> - 优先级：`GRAPE_WORK_BRANCH`（权威）> 仓库默认分支 > `main` 探测（不存在则 `master`）。

> ⚠️ token/URL/华为云 AK-SK 为敏感信息：**不要 printenv/写日志/写评论/写文件**。

## 评论前缀规范

所有 Issue 评论 body 一律以 `[SRE Agent]` 开头：
```bash
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body": "[SRE Agent] 这是 SRE 的答复内容。"}'
```

## 处理流程

> ⚠️ **先读 `references/deploy-runbook.md`**：按走查表逐步执行（入口判定 → 部署流程 Step 1-4 或资源释放流程 → 收尾）。步骤命令 runbook 已给出，**照抄执行，不要逐条探索**。
>
> ⚠️ **本技能收尾一律用 `grape tasks complete`（情形一）**：部署/释放完成 + 评论告知后**必须**调用，**评论发完 ≠ 任务完成**；调完即结束，不再输出 JSON 块。

**入口判定**：A2A 直接触发（部署/资源释放） / `pull_request_merged`（目标合入分支，runbook 解析为 `$WORK_BRANCH`）→ 部署流程；其他事件 → `SKIP`。（详见 runbook「入口判定」）

## 部署流程（hcloud 实测详细命令与坑位，runbook 引用）

> 完整走查见 `deploy-runbook.md`。下方为 SKILL 级保留的实测命令与坑位，执行时以 runbook 步骤顺序为准：

### 3.0 确保 hcloud 已安装（缺失自动装）
```bash
if ! command -v hcloud >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64|amd64) APP_ARCH="amd64";; aarch64|arm64) APP_ARCH="arm64";;
    *) echo "unsupported arch"; exit 1;; esac
  DL_URL="https://cn-north-4-hdn-koocli.obs.cn-north-4.myhuaweicloud.com/cli/latest/huaweicloud-cli-linux-${APP_ARCH}.tar.gz"
  curl -fsSL --max-time 300 -o /tmp/hcloud.tar.gz "$DL_URL" && mkdir -p /tmp/hcloud-x \
    && tar -xzf /tmp/hcloud.tar.gz -C /tmp/hcloud-x \
    && find /tmp/hcloud-x -type f -name hcloud -exec install -m 0755 {} /usr/local/bin/hcloud \;
  echo y | hcloud configure set --cli-agree-privacy-statement=true
fi
hcloud version
```
> ⚠️ 架构定包名（错则 Exec format error）；首次必须同意隐私声明；`--max-time 300`。

### 3.1 配置 task 专属 profile（严禁 default）
```bash
HC_PROFILE="task-$$"
hcloud configure set --cli-profile="$HC_PROFILE" \
  --cli-access-key="$HUAWEICLOUD_SDK_AK" --cli-secret-key="$HUAWEICLOUD_SDK_SK" \
  --cli-region=cn-north-4 --cli-mode=AKSK
hc() { hcloud "$@" --cli-profile="$HC_PROFILE"; }
obs() { obsutil "$@" -i "$HUAWEICLOUD_SDK_AK" -k "$HUAWEICLOUD_SDK_SK" -e obs.cn-north-4.myhuaweicloud.com; }
trap 'hcloud configure delete --cli-profile="$HC_PROFILE" 2>/dev/null || true' EXIT
```

### 3.2 ECS 幂等检查 + 创建（坑位要点）
- **先查已有**：按名称前缀 `deploy-<repo>` 过滤 `hc ECS ListServersDetails`，有 ACTIVE 实例则复用 `$ECS_IP`，绝不重复新建。
- **可用区**：显式 `cn-north-4a`/`cn-north-4b`，绝不用 `cn-north-4g`（DPDK 网卡 SSH 连不上）。
- **规格**：硬编码 flavor 会 Ecs.0019/0707，用 `ListFlavors` + `ListFlavorSellPolicies` 动态取最小可用按量规格。
- **keypair + EIP 自动创建**：必须带 keypair（否则 SSH 连不上）；EIP 用 `--server.publicip.eip.*` 自动关联，勿手动关联。

### 3.3 部署代码 + 启动（坑位要点）
- scp 上传到 `/opt/<repo>`；`ssh-copy-id` 免密；**单条 SSH 会话**跑完（防超时）。
- 先修 DNS（`echo 'nameserver 8.8.8.8' > /etc/resolv.conf`）；apt/pip 用华为云国内镜像并重试。
- 启动 `nohup venv/bin/gunicorn -w 2 -b 0.0.0.0:5000 app:app`。
- 清理旧进程按端口精确操作（`ss -tlnp | grep ':5000'`），**严禁 `pkill -f gunicorn/app.py`**（误杀 agent）。

### 3.4 验证
```bash
curl -s -o /dev/null -w '%{http_code}' "http://$ECS_IP:5000/"   # 期望 200
```
失败 → 输出错误 + 建议回滚（不自动回滚）。

## 资源释放流程

按 `deploy-runbook.md`「资源释放流程」执行：收集资源（ECS/RDS/OBS/EIP）→ 先查再删 → 验证 → Issue 回帖汇总（`[SRE Agent]` 开头）。要点：ECS 先删再删 EIP；OBS 桶先清空再删；RDS 删除异步稍后验证；幂等。

## 硬约束

- ❌ 禁止直接修改仓库代码 / 删除仓库分支
- ❌ **禁止 `hcloud configure set` 改 default profile**（用 `--cli-profile` + `hc()`）
- ❌ `pkill -f` 清理进程（按端口精确 kill）
- ❌ 部署失败自动回滚（输出错误 + 建议）
- ✅ 下载优先国内镜像加速（apt/pip/npm/docker）
- ✅ 部署前先理解项目结构

## 参考

- **执行走查表（先读）**：`references/deploy-runbook.md`
- Grape CLI 全命令：`references/grape-cli-reference.md`
- 华为云 KooCLI（hcloud）用法以 `hcloud --help` / `hcloud ECS --help` 实测为准

> ⚠️ **任务结束**：完成所有业务动作（部署/释放 + 评论告知）后，**必须按 runbook 收尾先输出摘要并调用 `grape tasks complete` 自报完成，然后**结束任务**，不要继续思考或等待输入。