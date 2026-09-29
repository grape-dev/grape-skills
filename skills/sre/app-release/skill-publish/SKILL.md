---
name: skill-publish
version: 2.1.0
description: |
  将 skill 发布/下架到外部平台（ClawHub/GitHub/GitCode）：
  幂等探测 → bump 重试（≤3 次）→ 多平台发布/下架 → 校验 → 汇总回复。
  ClawHub 支持组织发布（ownerHandle，可选）；403/404/401 严格区分，防止误判。
tools:
  - curl
  - git
---

# Skill 发布管理（skill-publish v2.1 · 外部平台发布）

## 一、安全硬约束（必须遵守）

1. **令牌获取（凭据走平台通道，分两类）**：**GitCode 发布** → 运行时 **GIT_ASKPASS 自动认证**（任务进程 env 已设 GIT_ASKPASS——平台生成的 askpass 脚本内部 echo BOT_GITCODE_TOKEN）——git clone/push 自动通过，**技能不接触 token 值**（对齐平台 token 停注入 → CLI/git 内化方向，无需用户配置）。**外部平台发布**（GitHub / ClawHub）→ 在【项目场景 → 点击单个场景 → 场景详情页 → 高级选项 → 自定义配置】添加 `name=GITHUB_TOKEN` / `name=CLAWHUB_TOKEN`（name 严格用约定名）→ 平台**按 name 直接注入同名环境变量**（GitHub 发布另有平台 `BOT_GITHUB_TOKEN` 兜底——GitHub 托管仓库任务自动注入）。⚠️ 服务端不向 `.project-info/` 物化凭据（member 凭据文件被显式过滤）——**读取 secrets 字段是空转路径，已废弃**；配置（GITHUB/GITCODE_PUBLISH_REPO / CLAWHUB_OWNER_HANDLE）从 `.project-info/` config（member 文档）解析。⚠️ sync_skill_platform.sh 直接读取同名环境变量/askpass，agent 无需手动 export（export 不跨 shell 生效）。
2. **禁止直连业务数据库**（repo_platform_tokens 等）、读取 Grape 运行目录（data/、configs/、sessions.db）或日志寻找 token；允许的 token 获取仅限：GitCode = 运行时 GIT_ASKPASS（不接触值）；GitHub/ClawHub = custom_fields 按 name 直注的同名环境变量（GITHUB_TOKEN / CLAWHUB_TOKEN）。
3. **严禁遍历系统目录考古**（/usr/local/lib/hermes-agent、/opt/grape 等）——只读 custom_fields 直注的同名凭据变量或项目知识 `.project-info/` 非敏感配置（member 文档；凭据类文件平台不物化）。
4. **401/403 严格区分**：401 = 令牌无效/过期 → 报告「{平台} 令牌无效或过期，请到设置页更新」→ 跳过该平台；403 = 令牌无权限 → 报告「{平台} 令牌对目标无权限，请检查 token 权限或目标归属」→ 跳过该平台；两者都**立即停止该平台任务，不重试、不用其他 token 绕行**。
5. **token 绝不落盘**：不写入任何文件、日志、评论、脚本（项目知识库 JSON 由上层业务维护，本技能只读不写）。
6. **所有 curl / git 调用设 30s 超时**（curl `--max-time 30`；git 用 `timeout 30`）——超时判定该平台任务失败，不 hang。
7. **命令以参考文件为准，不凭记忆拼写**：平台评论/任务一律以 `references/grape-cli-reference.md` 为准（严禁根据经验/记忆/猜测自行拼写命令或 API 路径）；ClawHub 外部 API 以本文档 4.4「ClawHub payload 契约」为准；GitHub/GitCode 以 `scripts/sync_skill_platform.sh` 为准。
8. **重试策略**：401/403/配置缺失 → 不重试，直接跳过该平台；5xx/连接超时/DNS 失败 → 最多 3 次指数退避重试（1s、2s、4s）；版本冲突 bump → 最多 3 次（已有规则）。
   ```bash
   for i in 1 2 3; do
     resp=$(curl -s -w "\n%{http_code}" --max-time 30 -X POST ... )
     http_code=$(echo "$resp" | tail -1)
     if [[ "$http_code" =~ ^2 ]]; then break; fi
     if [[ "$http_code" =~ ^[45][0-9][0-9]$ ]] && [[ "$http_code" != "5"* ]]; then break; fi
     echo "retry $i/3 (HTTP $http_code)"
     sleep "$i"
   done
   ```
9. **平台职责分离**：ClawHub/GitHub/GitCode = 外部平台——curl/脚本直连**合法**（本技能执行器域）；Grape 平台（评论/任务）交互**必须走 grape CLI**（references/grape-cli-reference.md）——禁止 curl 直连 grape 平台 API。

## 二、环境变量表

| 变量 | 来源 | 说明 | 域 |
|------|------|------|-----|
| `GRAPE_SESSION_TOKEN` | 系统注入（grape 自动读取）| 平台评论/任务用，**无需手动配置** | grape 平台 |
| `REPO_FULL_NAME` | 系统注入 | 当前仓库全名（评论拆 owner/repo）| grape 平台 |
| `ACCOUNT` / `REPO_NAME` | 派生（`${REPO_FULL_NAME%/*}` / `${REPO_FULL_NAME#*/}`）| 评论 --owner/--repo 参数 | grape 平台 |
| `ISSUE_NUMBER` | 系统注入 | Issue 编号 | grape 平台 |
| `PR_NUMBER` | 系统注入（A2A 时）| PR 编号追溯 | 有 PR 时 |
| `GITHUB_TOKEN` | 场景高级选项 custom_fields 配置 name=GITHUB_TOKEN（平台按 name 直注同名 env）；GitHub 托管任务由平台 `BOT_GITHUB_TOKEN` 自动兜底 | GitHub PAT（x-access-token 格式）| 外部 GitHub |
| `CLAWHUB_TOKEN` | 场景高级选项 custom_fields 配置 name=CLAWHUB_TOKEN（平台按 name 直注同名 env）| ClawHub API Bearer token | 外部 ClawHub |
| `CLAWHUB_OWNER_HANDLE` | 项目知识 `.project-info/` config（member 文档）→ 用户指令 | ClawHub 组织 handle（可选，空=个人发布）| 外部 ClawHub |
| `GITHUB_PUBLISH_REPO` | 项目知识 `.project-info/` config（member 文档）→ 用户指令 | GitHub 目标仓库 namespace/repo | 外部 GitHub |
| `GITCODE_PUBLISH_REPO` | 项目知识 `.project-info/` config（member 文档）→ 用户指令 | GitCode 目标仓库 namespace/repo | 外部 GitCode |

敏感变量（token 类）**绝不 printenv、不落盘**。

> **平台 token 取值（分两类通道）**：**GitCode 发布**走运行时 GIT_ASKPASS（技能 0 接触，无需取值）；**GitHub/ClawHub 发布**读同名环境变量（custom_fields 按 name 直注；GITHUB 另有平台 `BOT_GITHUB_TOKEN` 兜底）：

```bash
GITHUB_TOKEN="${GITHUB_TOKEN:-${BOT_GITHUB_TOKEN:-}}"; CLAWHUB_TOKEN="${CLAWHUB_TOKEN:-}"
```
（凭据值只进 env 不进 prompt——不回显到日志/评论）

## 三、前置检查门（自愈 → 重试 → STOP）

| 检查项 | 判定命令 | 通过标准 | 失败动作 |
|--------|---------|---------|---------|
| grape CLI 可用 | `grape --version` | ≥0.3.2 | 按 `references/grape-cli-installation.md` 自愈 → 仍不可用 → 输出「前置检查未通过：<原因>」并结束任务 |
| 契约刷新 | `grape refresh` | 成功 | 重试 ≤2 次；仍失败 → 继续（回退内置快照）|
| 执行器脚本存在 | `ls scripts/sync_skill_platform.sh` | 文件存在且有执行权限 | 缺失 → STOP（GitHub/GitCode 平台无法执行——报告配置问题）|
| 入参齐全 | A2A payload（action/skill_name/issue_number/publish 还需 pr_number+skill_dir）| 必填项全有 | 缺失 → 终止任务，Issue 评论返回参数缺失（4.2 路由）|
| 目标平台令牌 | GitCode=运行时 askpass 自动；GitHub/ClawHub=custom_fields 按 name 直注同名 env（GITHUB_TOKEN/CLAWHUB_TOKEN；GITHUB 另有 BOT 兜底）| 外部平台至少一个有值（GitCode 恒可用）| 外部平台全缺或 401/403 → 按硬约束①/④ 跳过该平台（不中断其他平台）|

## 四、技能定义与执行

### 4.1 定位与职责边界

**职责**：将已创建并测试通过的 skill 发布/下架到外部平台（ClawHub/GitHub/GitCode）——幂等探测 → bump 重试（≤3 次）→ 多平台发布/下架 → 校验 → 汇总回复。不负责创建 skill/测试 skill（那是 Coding Agent/QA Agent 的职责）。

**依赖前序**：通过 A2A 被调用时，prompt 包含 tester 的处理摘要（skill 名称/PR 编号/合并状态）；skill 产物在当前 worktree 的 `skills/{name}/` 目录。

| 行为 | 态度 |
|------|------|
| 幂等探测 → bump 重试（≤3 次）→ 多平台发布/下架 → 校验 | ✅ **必须做** |
| 令牌读取：同名 env 直读（custom_fields 按 name 直注）；项目知识仅读非敏感 config | ✅ **必须做** |
| 发布/下架完成后必须发 Issue 评论告知 | ✅ **必须做，不可跳过**（事件未完成处理）|
| 一个平台失败不中断其他平台 | ✅ **必须做** |
| 跳过平台时说明**真实原因**（令牌缺失/403 无权限/仓库 404/push 失败）| ✅ **必须做（不得用「未配置」兜底）** |
| 创建 skill、测试 skill（coding/qa 职责）| ❌ **禁止** |
| 查询数据库/配置文件/日志寻找 token | ❌ **禁止**（硬约束②）|
| 遍历系统目录考古（/usr/local/lib、/opt/grape 等）| ❌ **禁止**（硬约束③）|
| token 写入文件/日志/评论/脚本 | ❌ **禁止**（硬约束⑤）|
| 401/403 后用其他 token 绕行 | ❌ **禁止**（硬约束④）|
| 自行拼写平台 API 路径 / 用 VCS API 手册 | ❌ **禁止**（硬约束⑦——已废弃，见 git 历史）|
| curl 直连 grape 平台 API | ❌ **禁止**（硬约束⑨——grape 交互走 CLI）|

### 4.2 场景路由（入口 → 路径）

| 入口/入参 | 处理路径 |
|---------|---------|
| A2A action=publish（tester 交办）| 4.3 发布路径（敏感扫描 → 幂等探测 → bump → 多平台发布 → 校验 → 汇总）|
| A2A action=unpublish | 4.3 下架路径（远端指纹前置校验 → 多平台下架 → 汇总）|
| 同步/发布/下架/撤回 skill 请求 | 本技能（按 action 分流）|
| 非 skill 发布类请求 | 不处理，回复说明范围（4.8 收尾）|

**入参契约**（A2A payload）：

| 参数 | 必填 | 说明 |
|------|------|------|
| action | 是 | publish / unpublish |
| skill_name | 是 | skill 名称 |
| issue_number | 是 | Issue 编号，用于评论和 commit message |
| pr_number | 是（publish）| PR 编号，用于追溯（= `$PR_NUMBER`，平台 A2A 注入）|
| skill_dir | 是（publish）| skill 源目录路径 |
| version | 否（publish）| 版本号，默认从 frontmatter 读取 |

### 4.3 处理流程（统一骨架）

#### 发布路径（action=publish）

1. **敏感文件扫描（发布前必执行）**——扫描 skill 目录，发现以下文件直接终止该平台发布并 Issue 评论告警：`.env` / `.env.*`；`id_rsa` / `id_ed25519` / `*.pem` / `*.p12` / `*.keystore`；文件名含 key/secret 但实际非密钥（如 keyboard-config.json）→ grep 文件内容检测 AK/SK/token 模式，命中才拦截。
2. **定位 skill + 读 frontmatter**：仓库内 `skills/{name}/` 或根目录 `{name}/`（含 SKILL.md）；version 取 SKILL.md frontmatter（默认 0.1.0）；slug = name 转小写连字符；**文件指纹 SHA-256**：skill 目录全部文件**按文件路径字典序排序**后读取拼接，计算哈希（排除 `.git/`、`__pycache__/`、`*.pyc`——包含会导致指纹不一致）。
3. **读取各平台令牌**（分两类）：**GitCode** → 无需读取（GIT_ASKPASS 运行时自动）；**GitHub/ClawHub** → 同名 env 直读（custom_fields 按 name 直注；GITHUB 用 `${GITHUB_TOKEN:-${BOT_GITHUB_TOKEN:-}}` 兜底）：缺失 → 报告「未配置 {平台} 令牌，请在【项目场景 → 点击单个场景 → 场景详情页 → 高级选项 → 自定义配置】添加 name={平台}_TOKEN、value=<token> 后重试」→ 跳过该平台；401/403 → 按硬约束④区分报告 → 跳过（不中断其他平台）。
4. **幂等探测**：
   - 计算 skill 文件指纹 SHA-256（字典序排序拼接）
   - ClawHub: `GET /api/v1/skills/{slug}`（组织配置时带 `?ownerHandle=`）——200（skill 存在）→ 比对版本/指纹——内容未变 → 跳过（报告「已是最新，无需发布」）——变了 → bump 后发布；404（不存在）→ 直接发布
   - GitHub/GitCode: `git ls-remote` 目标仓库 `skills/{name}/` 是否已存在——已存在且内容一致 → 跳过——不同 → 覆盖 push
5. **版本 bump 规则**：patch 段两位数上限 99 → 进位（1.0.99 → 1.1.0）；"already exists"/版本冲突 → bump 重试，**最大 3 次，超限直接失败终止**；POST 返回 "slug already exists"（slug 级别占用）→ 报告「skill slug 被软删除占用，请等待 30 天或联系 ClawHub 支持」→ 该平台失败，不重试；⚠️ bump 仅本次执行内存生效，**不回写 SKILL.md**（版本号下次发布时从 frontmatter 重新读取）。
6. **按平台发布**：
   - ClawHub: `POST https://clawhub.ai/api/v1/skills`（multipart payload+files，Bearer $CLAWHUB_TOKEN，payload 可带 ownerHandle——见 4.4 契约）
   - GitHub/GitCode: 调脚本封装 clone→备份→覆盖→1 次 commit→push：
     ```bash
     bash {{SKILL_DIR}}/skill-publish/scripts/sync_skill_platform.sh \
       --action publish --platform github \
       --skill-name {name} --skill-dir {skill_dir} --version {version}
     bash {{SKILL_DIR}}/skill-publish/scripts/sync_skill_platform.sh \
       --action publish --platform gitcode \
       --skill-name {name} --skill-dir {skill_dir} --version {version}
     ```
     脚本输出 JSON：`{"PUSHED":1/0, "BACKUP_BRANCH":"", "TARGET_URL":"", "MESSAGE":""}`；一个平台失败不中断其他平台。
7. **脚本内置安全备份**：目录已存在且内容不同时自动建 `backup/pre-sync-{skill_name}` 分支并推远端（用 skill name 命名，覆盖旧备份，每个 skill 只保留 1 个备份分支）；内容一致时跳过，不建备份；备份分支推送失败不阻断主流程。
8. **校验**：SHA256 逐字节比对 + 平台 API 确认状态；ClawHub 校验时从 `GET /api/v1/skills/{slug}` 返回的 `owner.handle` 拼接页面 URL（`https://clawhub.ai/{owner.handle}/skills/{slug}`）。
9. **目标仓库解析（GitHub/GitCode）**：默认从项目知识 `.project-info/` config（member 文档——非凭据文件）解析 `GITCODE_PUBLISH_REPO` / `GITHUB_PUBLISH_REPO`（格式 namespace/repo）；用户指令指定目标仓库 → **只接受 namespace/repo 格式，拒绝完整 git URL**（用户指令优先级高于环境变量）；未配置 → 报告「未配置发布目标仓库，请到设置页配置」→ 跳过该平台。
10. **多平台发布 + 汇总回复**：一个平台失败不中断其他平台；按 4.6 发布结果表格式发 Issue 评论（**必须发——见 4.8**）。

#### 下架路径（action=unpublish）

1. **前置校验（下架前必执行）**：从目标仓库拉取远端 skill 目录 → 计算远端 SHA-256 指纹 → 与本地预期指纹比对——不匹配 → Issue 评论告警「远端版本与预期不一致，请人工确认」→ 终止下架；匹配 → 继续。
2. **读取各平台令牌**（同发布步骤 3——缺失/401/403 → 跳过该平台并输出提示）。
3. **按平台下架**：
   - ClawHub: `DELETE /api/v1/skills/{slug}`（组织配置时带 `?ownerHandle=`）——软删除 30 天；**扫描中不可删除：遇到该状态直接失败不重试**
   - GitHub/GitCode: 调脚本封装 clone→备份→删除→1 次 commit→push：
     ```bash
     bash {{SKILL_DIR}}/skill-publish/scripts/sync_skill_platform.sh \
       --action unpublish --platform github \
       --skill-name {name} --issue-num {issue_number}
     bash {{SKILL_DIR}}/skill-publish/scripts/sync_skill_platform.sh \
       --action unpublish --platform gitcode \
       --skill-name {name} --issue-num {issue_number}
     ```
     目录不存在时脚本输出 `{"PUSHED":0, "MESSAGE":"无需下架"}`（非失败）；脚本内置 `backup/pre-delist-{skill_name}` 备份分支（覆盖旧备份，只保留 1 个）。
4. **执行后校验平台状态，汇总回复**（同发布结果表格格式）。

#### ClawHub OwnerHandle（组织发布——发布/下架共用）

1. ownerHandle 来源优先级：**用户指令指定 > `.project-info/` config 的 CLAWHUB_OWNER_HANDLE（member 文档）> 空（个人账号发布）**
2. SKILL.md 不存储 ownerHandle——归属完全由 API 入参控制
3. 探测 GET / 下架 DELETE 必须带 `?ownerHandle={ownerHandle}`（配置了组织时）——不带只查个人命名空间，会误判组织 skill 不存在（404）
4. POST payload 可选字段 ownerHandle：非空 = 发布到指定组织；token 必须具备该组织 publisher 角色，否则 403
5. **不支持变更已有 skill 归属**（个人→组织迁移官方有 bug）；slug 在同一个 publisher 下唯一
6. 组织 skill 对外完整引用格式：`@{ownerHandle}/{slug}`；个人：`{slug}`
7. 回复安装命令：有 owner → `clawhub install @{owner}/{slug}`；无 → `clawhub install {slug}`
8. **ClawHub 页面 URL 格式**（已验证）：`https://clawhub.ai/{ownerHandle}/skills/{slug}`
   - 个人发布：`https://clawhub.ai/{用户名}/skills/{slug}`；组织发布：`https://clawhub.ai/{org}/skills/{slug}`
   - ⚠️ **不是** `https://clawhub.ai/skills/{slug}`（307 重定向到 `/skills/skills/{slug}`，页面空 skeleton）
   - ⚠️ **不是** `https://clawhub.ai/{用户名}/{slug}`（少了 `/skills/` 段，307 重定向）
   - ownerHandle 获取优先级：a. 发布时使用的（用户指令 / `.project-info/` config）→ b. `GET /api/v1/skills/{slug}` 返回的 `owner.handle` → c. `GET /api/v1/whoami` 返回的 `user.handle`（个人发布兜底——用 Bearer $CLAWHUB_TOKEN 调）
   - 拼好 URL 后必须 `GET /api/v1/skills/{slug}` 确认 skill 存在（200=URL 正确，404=发布失败）
   - **不得自己拼 URL**——必须用上述优先级获取 ownerHandle

### 4.4 命令标准（子集与坑点）

**grape CLI（grape 平台交互——评论/任务）**：见 `references/grape-cli-reference.md`（完整子集 + ❌ 不存在命令警示表）。核心：

```bash
grape --version / grape refresh                                  # 前置门自愈
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json '{"body":"[SRE Agent] ..."}'  # 评论（长 body 用 --json @file）
grape tasks complete --json '{"result_text":"...","actions":[...],"conclusion":"...","artifacts":[...],"next_step":"..."}'   # 收尾（4.8）
```

**外部平台（curl/脚本——合法域）**：

```bash
# ClawHub：GET https://clawhub.ai/api/v1/skills/{slug}（?ownerHandle= 组织时）；POST https://clawhub.ai/api/v1/skills（multipart）；DELETE /api/v1/skills/{slug}（软删 30 天）；GET /api/v1/whoami（user.handle 兜底）
# 全部带 --max-time 30 + Bearer $CLAWHUB_TOKEN；401/403 按硬约束④区分
bash {{SKILL_DIR}}/skill-publish/scripts/sync_skill_platform.sh --action publish --platform {github|gitcode} --skill-name {name} --skill-dir {dir} --version {ver}
bash {{SKILL_DIR}}/skill-publish/scripts/sync_skill_platform.sh --action unpublish --platform {github|gitcode} --skill-name {name} --issue-num {number}
```

**ClawHub payload 契约**（已验证，协议存档）：
- POST /api/v1/skills（multipart: payload JSON + files[]）
- payload 字段: slug(必填) / displayName(必填) / version(必填) / changelog(必填) / tags(数组) / acceptLicenseTerms(true) / ownerHandle(可选)
- **changelog 生成方式**：从 SKILL.md description 字段提取，或从 git log 最近变更生成（如 "v0.2.0: 修复 base_url 交互输入 + 新增文件上传支持"）。**不得填空字符串**——ClawHub 会返回 400
- files[]: 每个文件带 contentType（SKILL.md + 支持文件——整个 skill 目录）
- 发布提交成功 = ok（平台异步安全扫描——通过后公开——被拒可修正重发）
- ⚠️ **评论里 ClawHub 状态应报「✅ 已提交（安全扫描中，通过后公开）」而不是「✅ 成功」**——扫描中用户还不能安装
- 撤销: DELETE /api/v1/skills/{slug}（软删除 30 天——扫描中不可删——扫描完成可删）

**❌ 不存在的命令（警示）**：见 `references/grape-cli-reference.md` §4（grape tasks close/status、grape api 兜底、knowledge context、events detail --event_id、git 透传、curl 直连 grape 平台 API）。

### 4.5 故障决策表

| 现象 | 处理 |
|------|------|
| 401（平台令牌无效/过期）| 报告「{平台} 令牌无效或过期，请到设置页更新」→ 跳过该平台（不重试、不用其他 token 绕行——硬约束④）|
| 403（平台令牌无权限）| 报告「{平台} 令牌对目标无权限，请检查 token 权限或目标归属」→ 跳过该平台（硬约束④）|
| 5xx/连接超时/DNS 失败 | 最多 3 次指数退避重试（1s、2s、4s——硬约束⑧）|
| ClawHub POST "slug already exists" | slug 被软删除占用——报告「请等待 30 天或联系 ClawHub 支持」→ 该平台失败，不重试 |
| ClawHub DELETE 扫描中 | 直接失败不重试（等扫描完成才能删）|
| 版本冲突 / "already exists" | bump 重试 ≤3 次——超限直接失败终止，禁止无限循环 |
| Grape 评论/任务命令报错 | 先 `grape refresh` 再重试（前置门②）；仍失败核对 cli-reference |
| 跳过平台原因不明 | 按真实原因区分（令牌缺失/403 无权限/仓库 404/push 失败）——**不得用「未配置」兜底** |
| 下架前置校验指纹不匹配 | Issue 评论告警「远端版本与预期不一致，请人工确认」→ 终止下架 |
| ClawHub URL 拼接不确定 | 不得自己拼——按 4.3 OwnerHandle 优先级取（whoami 兜底）+ GET 确认 200 |

### 4.6 输出格式（固定产物）

**发布结果表**（评论模板——发布/下架通用，⚠️ 必须发 Issue 评论，跳过 = 事件未完成处理）：

```
[SRE Agent] ✅ Skill 发布完成

## 发布结果：{name}

| 平台 | 状态 | 版本 | URL | 安装命令 |
|------|------|------|-----|----------|
| ClawHub | ✅ 已提交（安全扫描中）/ 🔴 失败 | v{clawhub_version} | https://clawhub.ai/{ownerHandle}/skills/{slug} | `clawhub install {slug}` |
| GitHub | ✅ 成功/⚠️ 跳过 | v{github_version} | {url} | — |
| GitCode | ✅ 成功/⚠️ 跳过 | v{gitcode_version} | {url} | — |

**文件指纹**：{SHA-256 前 8 位}
**发布时间**：{UTC ISO}
**PR 追溯**：#{pr_number}（发布来源，见 tester 交办）

**版本号说明**：ClawHub 可能因版本占用自动 bump，版本号与其他平台不同。跳过的平台版本填「—」。
```

- 评论 body 前缀固定 `[SRE Agent]`；引用用户原文：`> {用户评论}\n\n[SRE Agent] {回复}`
- ⚠️ ClawHub URL 必须用 ownerHandle 拼接（`https://clawhub.ai/{ownerHandle}/skills/{slug}`）——不得用 API URL（`/api/v1/skills/{slug}`）兜底，不得漏 `/skills/` 段，不得自己拼 URL
- 失败平台加行：`| ClawHub | 🔴 失败 | — | — | 令牌无效，请到设置页更新 |`

**处理结论 JSON 块**（最终答复末尾输出——平台读取，只输出一个）：

```json
{
  "actions": ["做了什么，如 published:skill-xxx:clawhub / published:skill-xxx:github / skipped:gitcode"],
  "conclusion": "处理结论（发布成功/部分失败/全部失败）",
  "artifacts": ["产生的产物：ClawHub URL / GitHub URL / GitCode URL / 评论"],
  "next_step": "下一步建议；如需重试失败平台则说明",
  "issue_summary": "Issue 最新聚合结论（紧凑文本，用 | 分隔）"
}
```

**不得用长流程叙述替代 JSON 块**；无法确定动作/结论 → 相应字段填空数组/空字符串，不伪造。

### 4.7 写操作协议

| 动作 | 确认要求 |
|------|---------|
| 发布 skill 到 ClawHub/GitHub/GitCode | 流程内（A2A publish 交办——直接执行）|
| 下架 skill | 流程内（A2A unpublish 交办 + 前置指纹校验通过——直接执行）|
| 备份分支创建/推送（pre-sync / pre-delist）| 脚本内置（自动）——不影响主流程 |
| Issue 评论（汇总/告警/参数缺失说明）| **必做**——发布/下架完成必须发（4.6 模板）|
| bump 版本（内存生效）| 流程内——**不回写 SKILL.md** |
| 敏感文件命中即终止该平台发布 | 流程内（4.3 发布路径步骤 1）——评论告警 |

### 4.8 任务收尾（必做）

1. **先调 `grape tasks complete` 关闭当前任务**（任务中心闭环）：
   ```bash
   grape tasks complete --json '{"result_text": "<发布/下架处理结论>", "actions": ["做了什么，如 published:skill-xxx:clawhub / published:skill-xxx:github / skipped:gitcode"], "conclusion": "处理结论（发布成功/部分失败/全部失败）", "artifacts": ["产生的产物：ClawHub URL / GitHub URL / GitCode URL / 评论"], "next_step": "下一步建议；如需重试失败平台则说明"}'
   ```
2. **再在最终答复末尾输出结构化 JSON 块**（4.6 格式——actions/conclusion/artifacts/issue_summary must 真实填充）。
3. 结束信号：complete 后立即结束任务，不要继续思考或等待输入。

## 五、参考文件清单

| 文件 | 内容 | 何时用 |
|------|------|--------|
| `references/grape-cli-reference.md` | grape 命令全表 + ❌ 不存在命令警示表 | 平台评论/任务 |
| `references/grape-cli-installation.md` | CLI 安装/升级指引 | 前置门 CLI 自愈 |
| `scripts/sync_skill_platform.sh` | GitHub/GitCode 发布/下架执行器（自动读 .project-info/ 令牌）| 外部 GitHub/GitCode 操作 |
| `references/skill-publish-runbook.md` | 执行走查表（命令固化——照着执行不查 help）| 全流程 |

## 六、Best Practices（实践积累区）

> 以下为实际执行中遇到的问题（历史实测），后续执行注意规避。

1. **sync 脚本环境变量不跨 shell**（2026-08-23 实测）：agent 用 read tool 读到 token 后 export，但执行 sync 脚本时是独立 shell，export 不生效——脚本已改为环境变量缺失时自己从 `.project-info/` 读取（agent 无需手动 export）。
2. **GitCode 私有仓库 clone URL 必须 `oauth2:` 前缀**（2026-08-23 实测）：`https://{token}@gitcode.com` 格式对私有仓库报 `could not read Password`，必须用 `https://oauth2:{token}@gitcode.com`。
3. **GitHub PAT 用 `x-access-token:{token}` 前缀**（2026-08-23 实测）：`https://{token}@github.com` 能工作但不够标准，GitHub 官方推荐 `https://x-access-token:{token}@github.com`。
4. **ClawHub 安全扫描中不可删除**（实测）：DELETE 遇到 scanning 状态直接失败不重试，等扫描完成才能删。
5. **ClawHub 页面 URL 不能漏 `/skills/` 段**（实测）：`https://clawhub.ai/{user}/{slug}` 会 307 重定向到空页面，必须用 `https://clawhub.ai/{ownerHandle}/skills/{slug}`。
6. **ClawHub slug 软删除占用 30 天**（实测）：DELETE 后 30 天内同名 slug 不能重新发布，POST 返回 "slug already exists"。