---
name: domain-deploy
version: 2.1.0
description: |
  面向 jiuwenswarm 领域模板仓库的华为云部署技能：自动构建项目并部署到华为云 ECS——项目结构识别 → 代码获取构建 → hcloud CLI 部署 → HTTP 验证 → 资源释放。
  Use when：部署、上线、deploy、更新华为云服务、释放/销毁云资源、PR 合并触发自动部署、domain-deploy；
  经 A2A 触发（部署/资源释放）或 PR 合并 main/master 事件触发。
tools:
  - grape
  - bash
---

# 华为云部署 v2.1（grape CLI）

## 一、安全硬约束（必须遵守）

1. **CLI 优先 + git 透传**：平台操作走 grape CLI；git 操作（clone/checkout/push）用 `grape git` 透传（内部认证）——禁止绕过 CLI 直连平台 API。
   grape CLI 未装/版本过低 → **自动安装/升级**（官方源/签名包优先）→ 装好继续；仅安装失败/环境不可用才报障说明（不降级直连）。⚠️ 安装指引请参考：`references/grape-cli-installation.md`。
2. **凭据纪律**：GitCode 凭据（平台注入 `$GRAPE_SESSION_TOKEN`）由 grape git 透传内部消费——**技能不直接读取/不打印/不写文件/不写评论**；严禁从数据库/configs/日志/历史中寻找其他 token。
3. 严禁读取 data/、configs/、sessions.db、user_accounts 等 Grape 内部数据（data/workspaces/ 项目知识文档除外）。
4. **403/无权限**：立即停止并回复「该操作需要管理员/维护者权限，请在 GitCode 仓库设置中手动配置后重试」，严禁其他 token 或绕行。
5. **401（凭据失效）**：任务级 token（tk_）短命，失效属正常机制——说明「凭据已失效」即可，不尝试替换/绕行。
6. **AK/SK 纪律**：`HUAWEI_AK/SK` 两个配置入口——①【项目场景 → 点击单个场景 → 场景详情页 → 高级选项 → 自定义配置】添加 `name=HUAWEI_AK`/`name=HUAWEI_SK`（name 严格用约定名——平台按 name 直接注入同名环境变量）；② 通用设置配置华为云 AK/SK（注入 `HUAWEICLOUD_SDK_AK/SK`，取值片段自动兜底）。未配置 → 前置门 STOP 提示配置（完整路径见 4.3），严禁硬编码或从他处寻找凭证。
7. **hcloud profile 隔离**：严禁 `hcloud configure set` 改 default profile——必须 `--cli-profile="task-$$"` 隔离，部署结束清理。
8. **操作确认**：变更现有配置（安全组/资源配置等）与删除/释放云资源前，必须告知用户并取得确认；仅 A2A/PR 合并显式触发的部署写操作可自动执行。
9. **长命令/常驻命令纪律**（sre 执行类必守）：构建/安装（npm/pip 编译）可能无输出 → 加 `timeout` 限制、一次只装必要依赖；`http.server` 等常驻验证命令严禁前台执行（用后台+curl 验证+kill 或一次 SSH 内完成）。

## 二、环境变量表（平台注入，按 sre Agent 类型）

| 变量 | 语义 | 用在哪 | 何时有 |
|------|------|--------|--------|
| `GRAPE_SERVER_URL` / `GRAPE_SESSION_TOKEN` | 服务端地址 / 会话 token（tk_）| grape CLI 自动读取 | 全部任务 |
| `REPO_FULL_NAME` | 仓库全名（owner/repo） | A2A 交办 `repository`；repo_key 拼装 | 全部 |
| `REPO_OWNER` | 仓库属主（owner，不含 /repo） | CLI 用 --owner | 全部 |
| `REPO_NAME` | 仓库名 | CLI 用 --repo | 全部 |
| `ACCOUNT` | 个人账号（触发人 actor，与仓库属主解耦） | A2A payload `account`（一般不用作 --owner） | 全部 |
| `REPO_NAME` | 仓库名（派生：`${REPO_FULL_NAME#*/}`）| --repo 参数 | 全部 |
| `ISSUE_NUMBER` | Issue 编号 | 评论/A2A payload | 事件任务 |
| `PR_NUMBER` | PR 编号（PR 合并触发时）| 部署来源标记/汇报评论 | PR 合并时 |
| `GRAPE_WORK_BRANCH` | 目标合入分支/工作基线（缺省仓库默认分支）| `grape git checkout` 部署分支 | 场景任务 |
| `DEVOPS_EVENT_TYPE` | 事件类型（A2A 部署/资源释放/PR 合并）| 场景路由判断 | 全部 |
| `HUAWEI_AK` / `HUAWEI_SK` | 华为云 AK/SK（用户按本技能文档在【项目场景 → 点击单个场景 → 场景详情页 → 高级选项 → 自定义配置】配置 name=HUAWEI_AK/HUAWEI_SK，平台按 name 直注同名 env；`HUAWEICLOUD_SDK_AK/SK` 旧名兜底）| hcloud CLI 认证（`--cli-profile="task-$$"` 隔离）| SRE 任务 |
| `GRAPE_LINKED_REPOS` | 关联仓库列表 JSON（场景高级选项配置）| 多仓库构建部署（见 §4.9） | 场景配置了关联仓库时 |
| `GRAPE_LINKED_WORKTREES` | 关联仓库 worktree 路径列表 JSON（平台自动初始化）| 读取关联仓库代码 | SRE/coding 任务且有 linked_repos 时 |

派生变量：`REPO_NAME` = `${REPO_FULL_NAME#*/}`。敏感变量（token/AK/SK 类）**不 printenv、不落盘、不写评论**。

> **华为云凭据取值**：用户在【项目场景 → 点击单个场景 → 场景详情页 → 高级选项 → 自定义配置】添加 name=HUAWEI_AK/name=HUAWEI_SK → 平台**按 name 直注**同名环境变量 → 技能直接读取（兼容通用设置旧名 `HUAWEICLOUD_SDK_AK/SK` 兜底）：

```bash
HUAWEI_AK="${HUAWEI_AK:-${HUAWEICLOUD_SDK_AK:-}}"; HUAWEI_SK="${HUAWEI_SK:-${HUAWEICLOUD_SDK_SK:-}}"
```
（凭据值只进 env 不进 prompt——不回显到日志/评论）
本技能不涉及 `USER_GITCODE_TOKEN`（Chat 域）。流程内变量（`$ECS_IP`/`$INSTANCE_NAME` 等）为部署产物，非平台注入。

## 三、前置检查门（自愈 → 重试 → STOP）

| 检查项 | 判定命令 | 通过标准 | 失败动作 |
|--------|---------|---------|---------|
| CLI 可用 | `grape --version` | ≥0.3.2 | **自愈**：按 `references/grape-cli-installation.md` 自动安装/升级（`timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git`）→ 再验证；仍不可用 → 输出「前置检查未通过：<原因>」结束 |
| 契约刷新 | `grape refresh` | 拉取最新契约成功 | **重试** ≤2 次；仍失败 → 继续（回退快照）|
| 认证变量就绪 | `${VAR:+ok}` 校验（不打印值）| token/repo/issue 有值 | 缺失 → STOP「前置检查未通过」|
| **华为云 AK/SK 就绪** | `${HUAWEI_AK:+ok}` 且 `${HUAWEI_SK:+ok}` | 均有值 | **STOP**：提示用户在【项目场景 → 点击单个场景 → 场景详情页 → 高级选项 → 自定义配置】添加 `name=HUAWEI_AK`、`value=<AK>` 与 `name=HUAWEI_SK`、`value=<SK>`（name 严格用约定名）；或【通用设置】配置华为云 AK/SK——后重试——不硬编码、不找替代 |
| hcloud 可用 | `hcloud version --cli-profile="task-$$"` | 命令可用 | **自愈**：按 `references/deploy-guide.md` §2 自动安装（架构判定→下载→隐私确认）→ 再验 |
| 瞬时失败（网络/限流）| — | — | **重试**：≤3 次（退避 1s/2s/4s）|

## 四、技能定义与执行

### 4.1 定位与职责边界

**职责**：**部署执行者**——把构建产物部署到华为云 ECS 并验证（或释放资源）——项目结构识别 → 构建 → hcloud 部署 → HTTP 验证 → 汇报。
**不越界**：不修改仓库代码/不删除分支；变更现有云配置与释放资源需用户确认。

| 操作 | 允许 | 说明 |
|------|------|------|
| 创建/更新云资源（ECS/EIP/安全组）| ✅ 自动 | A2A 或 PR 合并触发时执行 |
| 部署代码到 ECS | ✅ 自动 | 构建后部署 |
| 变更现有配置（安全组/资源配置等）| ⚠️ 需确认 | 用户确认后执行 |
| 删除/释放云资源 | ⚠️ 需确认 | 资源释放场景 |
| 修改仓库代码 | ❌ 禁止 | — |
| 删除仓库分支 | ❌ 禁止 | — |
| 读取 Grape 内部数据 | ❌ 禁止 | — |

### 4.2 场景路由（触发 → 路径）

| 触发特征 | 场景 | 路径 |
|---------|------|------|
| A2A 含「部署/上线/deploy」| 部署 | ① 项目结构 → ② 获取构建 → ③ hcloud 部署 → ④ 验证 → ⑥ 收尾 |
| A2A 含「释放/销毁/destroy」| 资源释放 | `references/deploy-guide.md` §6（先查再删，逐个验证）→ ⑥ 收尾 |
| PR 合并到 main/master | 自动部署 | ①→②→③→④→⑥ 收尾 |
| 其他事件 | 跳过 | 输出 SKIP（非 merge/非 A2A 的 PR 事件、非 main 分支 push——不处理）|

### 4.3 处理流程（统一骨架）

**流程总览（一行）**：⓪ 上下文（A2A payload/PR 合并事件）→ ① 项目结构识别（根目录文件 → 构建方式）→ ② `grape git` 获取代码 + 构建 → ③ 部署 ECS（hcloud 幂等检查→认证隔离→SSH 部署）→ ④ 验证（HTTP 200）→ ⑤ 资源释放（仅释放场景）→ ⑥ 收尾（4.8）

**关联仓库（多仓库构建部署）**：当 `$GRAPE_LINKED_REPOS` 非空时，表示本需求涉及多个关联仓库（如前端+后端）。平台会自动为每个关联仓库初始化 worktree（`$GRAPE_LINKED_WORKTREES`）。SRE Agent 需要对每个关联仓库分别构建并部署到同一 ECS（或不同端口），详见 §4.9。

**执行规则**：
- 部署细节照 `references/deploy-guide.md` 执行（hcloud 安装/ECS 创建/SSH 部署/验证/资源释放——命令照抄不探索）
- hcloud 全部 `--cli-profile="task-$$"` 隔离使用；ECS 幂等检查（已有实例复用——不重复创建）
- 部署后必做 HTTP 验证（期望 200）；失败 → 按故障决策表处理，不静默跳过
- 资源释放：先查再删、逐个验证
- 变更现有配置/释放资源 → 用户确认后再执行（安全硬约束⑧）

### 4.4 命令标准（子集与坑点）

完整命令见 `references/domain-deploy-runbook.md`（执行走查表）与 `references/grape-cli-reference.md`（命令参考）；云资源操作见 `references/deploy-guide.md`。坑点：

| 坑点 | 正确做法 |
|------|---------|
| hcloud profile 污染 | 严禁改 default——全程 `--cli-profile="task-$$"`，结束清理 |
| ECS 重复创建 | 先查已有实例（幂等检查）→ 复用或新建；动态选规格、AZ=cn-north-4a/4b |
| 长命令静默 | npm/pip 构建加 `timeout 300` 并等待——不因无输出误判卡死 |
| 常驻命令 | `python -m http.server` 类严禁前台——后台+curl 验证+kill 或一次 SSH 内完成 |
| AK/SK 泄露 | 不 echo/不写文件/不写评论——只用于 `--cli-profile` 认证 |
| SSH 部署 | 单条 SSH 完成依赖安装+启动（不逐条往返）|
| 验证 | 端口 `ss -tlnp` + HTTP `curl` 期望 200 + 公网可达（安全组放行 22/80/5000）；**monorepo/多进程：前端页面与后端每个进程端口分别验证——只验前端端口 = 部署失败** |
| 命令失败 | 先看完整 stderr（去 `\| tail`）→ 按故障决策表 → 不反复盲试 |
| monorepo 误判单工程 | 识别到前端子目录 / `python -m` 非 WSGI 入口时禁止照搬 `gunicorn app:app` → 走 §4.10 / deploy-guide §4.3 |

### 4.5 故障决策表

| 故障 | 分类 | 动作 |
|------|------|------|
| 403/权限不足（Required 操作）| Required | **STOP**：按安全硬约束④回复用户，等待配置 |
| 401/凭据失效 | Optional | 说明「凭据已失效」即可——不尝试替换/绕行 |
| AK/SK 未配置 | Required | **STOP**：提示在【场景详情页 → 高级选项 → 自定义配置】配置 name=HUAWEI_AK/HUAWEI_SK，或【通用设置】配置华为云 AK/SK——不硬编码不找替代 |
| hcloud 缺失 | Required | **自愈**：按 deploy-guide §2 自动安装 → 再验 → 仍失败 STOP |
| 命令失败（报错/参数/字段）| — | **先看完整 stderr** → 按 deploy-guide 排查 → 不反复盲试 |
| 部署后 HTTP 非 200 | Required | 查端口/进程/安全组 → 修复重试（≤2 次）→ 仍失败 Issue 评论说明 + next_step 人工介入 |
| ECS SSH 不可达 | Required | 查 EIP/安全组放行（22）→ 重试（≤2 次）→ 仍失败评论说明 |
| 资源释放失败 | Required | 先查再删逐个验证——失败项列出并评论（不静默跳过）|
| 瞬时失败（网络/限流）| — | **重试** ≤3 次（退避 1s/2s/4s）|

### 4.6 输出格式（固定产物）

1. **验证清单**（决策依据）：
   - [ ] hcloud 可用且 profile 隔离
   - [ ] ECS 创建/复用成功，SSH 可达
   - [ ] 部署后 HTTP 返回 200
   - [ ] 资源释放后查询返回空/404（释放场景）
   - [ ] Issue 评论已发送
2. **Issue 评论**：部署/释放结果（访问 URL/验证码/或失败原因）——用户可见汇报
3. **任务完成**（tasks complete）：结构见 4.8

### 4.7 写操作协议

| 操作 | 确认要求 |
|------|---------|
| 读操作（查仓库/查 ECS/查配置）| 自动执行，无需确认 |
| 部署流水线（创建 ECS+部署+验证+评论）| **流程内声明**（A2A/PR 合并触发）——直接执行 |
| 变更现有配置（安全组/资源配置）| **用户确认后**执行 |
| 删除/释放云资源 | **用户确认后**执行 |
| 会话结束 | 列出本次变更（部署/释放/评论）——无变更声明「只读会话」|

### 4.8 任务收尾（必做）

业务动作完成后：输出人类可读摘要（部署/释放结果 + 验证码）→ 调用：

```bash
grape tasks complete --json '{
  "result_text":  "结论：Issue #{n} 部署/资源释放完成。",
  "actions":      ["构建并部署到华为云 ECS", "验证部署结果", "在 Issue 评论告知"],
  "conclusion":   "部署完成，http {http_code}",
  "artifacts":    ["ECS {ecs_ip}", "Issue 评论"],
  "issue_summary":"部署完成 | 访问 {url} | 验证 {http_code}",
  "next_step":    "done 或 视下游交办"
}'
```

⚠️ **结构化字段必填**（结尾 = 下一节点的输入）：`actions[]`/`conclusion`/`artifacts[]`/`issue_summary` must 真实填充——只传 `result_text` 会丢结构化归档；下游/A2A 接收方以结构化字段为主消费，`result_text` 作为人类可读补充参考。部署失败也如实填写（`conclusion` 注明 http_code/原因），不伪造。

**立即结束**，不继续思考或等待输入。

### 4.9 关联仓库多仓库构建部署

当场景配置了关联仓库（`$GRAPE_LINKED_REPOS` 非空）时，SRE Agent 需要对主仓库和每个关联仓库分别构建并部署。

#### 环境变量

| 变量 | 格式 | 说明 |
|------|------|------|
| `GRAPE_LINKED_REPOS` | `[{"repo_key":"gitcode:owner/repo","branch":"main"},...]` | 场景高级选项中配置的关联仓库列表 |
| `GRAPE_LINKED_WORKTREES` | `[{"repo_key":"gitcode:owner/repo","branch":"main","dir":"/path/to/worktree"},...]` | 平台自动初始化的 worktree 路径 |

> 如果 `GRAPE_LINKED_WORKTREES` 为空（worker 端未自动初始化），SRE Agent 需自行 `grape git clone` 每个关联仓库到临时目录。

#### 构建部署流程

1. **读取关联仓库列表**：解析 `$GRAPE_LINKED_REPOS`（或 `$GRAPE_LINKED_WORKTREES` 获取 worktree 目录）
2. **主仓库构建部署**：按 §4.3 正常流程构建主仓库并部署到 ECS
3. **关联仓库构建部署**：对每个关联仓库：
   - 读取 worktree 目录（`$GRAPE_LINKED_WORKTREES` 中的 `dir` 字段）或 clone 到 `/tmp/deploy-linked-<repo_name>`
   - 识别项目类型并构建（同 §4.3 ①②）
   - 部署到同一 ECS 的不同路径（如 `/opt/<repo_name>`）或不同端口
4. **统一验证**：所有仓库部署完成后，逐个验证 HTTP 可达性

#### 示例（双仓库：前端 + 后端）

```bash
# 解析关联仓库 worktree 列表
LINKED_WORKTREES="$GRAPE_LINKED_WORKTREES"
if [ -n "$LINKED_WORKTREES" ]; then
  echo "$LINKED_WORKTREES" | python3 -c "
import json,sys
for w in json.load(sys.stdin):
    print(f\"{w['repo_key']} {w['branch']} {w['dir']}\")
" | while read rk br dir; do
    REPO_SHORT="${rk#gitcode:}"
    REPO_NAME="${REPO_SHORT#*/}"
    echo "=== 构建关联仓库: $REPO_SHORT (branch=$br) ==="
    cd "$dir" 2>/dev/null || { echo "worktree 不存在，clone"; grape git clone "https://gitcode.com/$REPO_SHORT.git" /tmp/deploy-linked-$REPO_NAME && cd /tmp/deploy-linked-$REPO_NAME; }
    # 识别项目类型并构建（同主仓库流程）
    # ... npm install && npm run build / pip install / mvn package 等
    # 部署到 ECS 的 /opt/$REPO_NAME 目录
    ssh -o StrictHostKeyChecking=no root@\"$ECS_IP\" \"mkdir -p /opt/$REPO_NAME\"
    scp -o StrictHostKeyChecking=no -r ./* root@\"$ECS_IP\":/opt/$REPO_NAME/
    # 按项目类型启动服务（不同端口）
  done
fi
```

#### 关键约束

- 每个关联仓库独立构建，不混淆构建产物
- 部署到同一 ECS 不同目录/端口，避免冲突
- 前后端项目需确认端口不冲突（如前端 80/3000，后端 5000/8080）
- 验证时逐个仓库检查 HTTP 可达性
- 收尾时 `actions[]` 中分别列出每个仓库的构建部署结果

### 4.10 单仓库多工程（monorepo/前后端一体）构建部署

当仓库为**单仓库多工程**时（子目录含独立工程标记，如 `<pkg>/channels/web/frontend/package.json` 前端工程 + Python 包后端），按 `references/deploy-guide.md` §4.3「多工程部署」执行：

1. **识别**（runbook A3）：根目录无单一顶层工程标记，或单工程模板不可用（`app.py` 无 WSGI `app` 对象 / 入口为 `python -m <pkg>.xxx` / 子目录存在 `package.json`、`pyproject.toml`）→ 判定 monorepo。
   - 子目录含 `package.json` / `vite.config.*` → **前端子工程**：`cd <子目录> && npm install && npm run build`（产出 `dist/`）
   - 子目录含 `pyproject.toml` / 包目录 → **后端子工程**：`pip install -e .`
2. **构建**（§4.3 ①②）：前端与后端分别构建，产物分离。
3. **部署**（§4.3 ③）：同一 ECS **多进程/多端口**启动——前端静态托管（nginx/AppServer，建议 80/5173）+ **后端每个独立进程逐一 nohup 启动**（gateway/agentserver/API，端口不冲突）；禁止只起前端（如仅 `app_web` 静态+反代进程）而不起后端进程。
4. **验证**（§4.3 ④）：**前端页面 URL 与后端接口 URL 分别 HTTP 200**（仅 curl :5173 / :5000 不足以证明后端可用）；后端多进程时逐端口 `ss -tlnp` 核对监听并 curl 探测。**若验证环节只测到前端端口而未验证后端端口/进程 → 判定部署失败**（对应故障决策表「部署后 HTTP 非 200 → 修复重试 → 仍失败评论说明」），禁止 `tasks complete`。
5. **收尾**：`actions[]` 分别列出前端/后端构建部署结果。

> ⚠️ **与 §4.9 的区别**：§4.9 是「多仓库」（每个关联仓库独立 git 仓库、独立 clone 部署）；本段是「单仓库内多工程」（一次 clone，按子目录分别构建部署，前端嵌在仓库内部、非独立仓库）。

## 五、参考文件清单

| 文件 | 用途 | 先读 |
|------|------|------|
| `references/domain-deploy-runbook.md` | **执行走查表：Step 就绪→场景 A/B/C 命令→收尾→错误排查——平台交互命令照抄** | ⭐ 最先 |
| `references/deploy-guide.md` | **部署领域手册：hcloud 安装/ECS 创建/SSH 部署/验证/资源释放（云资源操作照抄）** | runbook A4/A5 引用时 |
| `references/grape-cli-installation.md` | grape CLI 安装/升级指引（前置门自愈用）| CLI 未装时 |
| `references/grape-cli-reference.md` | grape CLI 命令参考（git 透传/平台命令）| 命令不确定时 |
| `references/contracts.md` | 输入/输出参数契约（inputSchema/outputSchema）| 接口校验时 |
| `references/performance-and-version.md` | 性能与版本约束 | 约束核对时 |

## 六、Best Practices（实践积累区）

> 暂无，后续沉淀后更新补充。