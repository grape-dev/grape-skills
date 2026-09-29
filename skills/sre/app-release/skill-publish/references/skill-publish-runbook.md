# Skill 发布执行走查表（skill-publish runbook）

> 目的：把 skill-publish 每一步**要做什么 + 用哪条确切命令 + 各平台 API 契约**固化下来，Agent **照着执行、不要查 `--help`**。
> **域界纪律**：ClawHub/GitHub/GitCode = 外部平台——curl/脚本直连**合法**（本技能执行器域）；Grape 平台（评论/任务）交互**必须走 grape CLI**——**禁止 curl 直连 grape 平台 API**。
> 任务变量：`$ACCOUNT`、`$REPO_NAME`、`$ISSUE_NUMBER`、`$PR_NUMBER` 平台注入；token 分两类——**GitCode 发布**走运行时 GIT_ASKPASS（平台 askpass 内部 echo BOT_GITCODE_TOKEN，技能 0 接触，无需配置）；**GitHub/ClawHub 发布**从场景 custom_fields 获取（name=GITHUB_TOKEN/CLAWHUB_TOKEN → 平台按 name 直注同名 env；sync 脚本直接读 env，agent 无需 export）；发布配置（`CLAWHUB_OWNER_HANDLE`/`GITHUB_PUBLISH_REPO`/`GITCODE_PUBLISH_REPO`）从 `.project-info/` config（member 文档）解析。
> **评论前缀硬规**：所有评论 body 一律以 `[SRE Agent]` 开头。

---

## Step 0 · 任务上下文与就绪（必须最先，任何事件都做）

```bash
# ⚠️ CLI 前置自愈（最先）：`grape --version` ≥0.3.2；未装/版本过低 → 按 references/grape-cli-installation.md
#    自动安装/升级（timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git）→ 装好再验证一次
#    → 仍不可用 → 输出「前置检查未通过：<原因>」并结束任务（不降级直连）
grape --version
grape refresh 2>&1 && echo REFRESH_OK        # 契约保鲜；失败重试 ≤2 次后回退内置快照继续
ls -la scripts/sync_skill_platform.sh        # 执行器脚本必须存在且有执行权限——缺失 → STOP
grape tasks current --json-out               # A2A payload 在这里（action/skill_name/issue_number/pr_number/skill_dir/version）
# 入参齐全检查（A2A payload）：action / skill_name / issue_number 必填；publish 还需 pr_number + skill_dir
```

## 发布路径（action=publish——按顺序执行，上一步未完成不得进入下一步）

### P1 · 敏感文件扫描（发布前必执行）

```bash
# 扫描 skill 目录：.env / .env.* / id_rsa / id_ed25519 / *.pem / *.p12 / *.keystore → 直接终止该平台发布
# 文件名含 key/secret 但实际非密钥（如 keyboard-config.json）→ grep 内容检测 AK/SK/token 模式，命中才拦截
find skills/{name}/ -name ".env*" -o -name "id_rsa*" -o -name "id_ed25519*" -o -name "*.pem" -o -name "*.p12" -o -name "*.keystore" 2>/dev/null
# 命中 → Issue 评论告警 → 终止该平台发布
```

### P2 · 定位 skill + 读 frontmatter

- 仓库内 `skills/{name}/` 或根目录 `{name}/`（含 SKILL.md）
- version 取 SKILL.md frontmatter（默认 0.1.0）；slug = name 转小写连字符
- **文件指纹 SHA-256**：skill 目录全部文件**按文件路径字典序排序**后读取拼接计算哈希（排除 `.git/`、`__pycache__/`、`*.pyc`——包含会导致指纹不一致）

### P3 · 读取各平台令牌

- 凭据分两类：**GitCode** → 运行时 GIT_ASKPASS（不接触值，无需读取）；**GitHub/ClawHub** → 同名 env 直读（场景高级选项配置 name=GITHUB_TOKEN/CLAWHUB_TOKEN → 平台按 name 直注；GITHUB 另有 BOT_GITHUB_TOKEN 兜底——服务端不向 .project-info 物化凭据）
- 配置：项目知识 `.project-info/` 下 JSON 配置文件 config 字段（GITHUB_PUBLISH_REPO / GITCODE_PUBLISH_REPO / CLAWHUB_OWNER_HANDLE——member 非凭据文档），缺失 → 询问用户 / 用默认
- 均缺失 → 报告「未配置 {平台} 令牌，请到设置页配置」→ **跳过该平台**（不中断其他平台）
- 401/403 → 按硬约束④区分报告 → 跳过该平台

### P4 · 幂等探测

```bash
# ClawHub：GET skill 详情（组织配置时带 ?ownerHandle=——不带只查个人命名空间会误判 404）：
curl -s --max-time 30 -H "Authorization: Bearer $CLAWHUB_TOKEN" \
  "https://clawhub.ai/api/v1/skills/{slug}${CLAWHUB_OWNER_HANDLE:+?ownerHandle=$CLAWHUB_OWNER_HANDLE}"
# 200 → 比对版本/指纹：内容未变 → 跳过（报告「已是最新，无需发布」）；变了 → bump 后发布
# 404 → 不存在 → 直接发布
# GitHub/GitCode：ls-remote 目标仓库 skills/{name}/ 是否已存在（已存在且一致 → 跳过；不同 → 覆盖 push）：
git ls-remote "https://oauth2:{token}@gitcode.com/$GITCODE_PUBLISH_REPO" 2>/dev/null | grep -c "skills/{name}/" || true
```

### P5 · 版本 bump 规则

- patch 段两位数上限 99 → 进位（1.0.99 → 1.1.0）
- "already exists"/版本冲突 → bump 重试，**最大 3 次，超限直接失败终止**
- POST 返回 "slug already exists"（slug 级别占用）→ 报告「skill slug 被软删除占用，请等待 30 天或联系 ClawHub 支持」→ 该平台失败，不重试
- ⚠️ bump **仅本次执行内存生效——不回写 SKILL.md**（版本号下次发布时从 frontmatter 重新读取）

### P6 · 按平台发布

```bash
# ClawHub（multipart payload+files，Bearer；payload 可带 ownerHandle——见 SKILL 4.4 契约）：
curl -s --max-time 30 -X POST "https://clawhub.ai/api/v1/skills" \
  -H "Authorization: Bearer $CLAWHUB_TOKEN" \
  -F "payload={\"slug\":\"{slug}\",\"displayName\":\"{name}\",\"version\":\"{version}\",\"changelog\":\"{非空——从 description/git log 生成}\",\"tags\":[\"{tag}\"],\"acceptLicenseTerms\":true${CLAWHUB_OWNER_HANDLE:+,\"ownerHandle\":\"$CLAWHUB_OWNER_HANDLE\"}}" \
  -F "files[]=@skills/{name}/SKILL.md;type=text/markdown" \
  -F "files[]=@skills/{name}/references/{file}.md;type=text/markdown" ...

# GitHub/GitCode（脚本封装 clone→备份→覆盖→1 次 commit→push——版本冲突 bump ≤3 次）：
bash {{SKILL_DIR}}/skill-publish/scripts/sync_skill_platform.sh \
  --action publish --platform github \
  --skill-name {name} --skill-dir {skill_dir} --version {version}
bash {{SKILL_DIR}}/skill-publish/scripts/sync_skill_platform.sh \
  --action publish --platform gitcode \
  --skill-name {name} --skill-dir {skill_dir} --version {version}
# 脚本输出 JSON：{"PUSHED":1/0, "BACKUP_BRANCH":"", "TARGET_URL":"", "MESSAGE":""}；一个平台失败不中断其他平台
```

### P7 · 脚本内置安全备份

- 目录已存在且内容不同 → 自动建 `backup/pre-sync-{skill_name}` 分支并推远端（覆盖旧备份，每 skill 只保留 1 个）
- 内容一致 → 跳过，不建备份；备份分支推送失败不阻断主流程
- ⚠️ 私有仓库 clone URL 必须 `oauth2:` 前缀（`https://oauth2:{token}@gitcode.com`——`https://{token}@` 私有仓库报 could not read Password）

### P8 · 校验

- SHA256 逐字节比对 + 平台 API 确认状态
- ClawHub 校验：`GET /api/v1/skills/{slug}` 返回 200 → 从 `owner.handle` 拼接页面 URL（`https://clawhub.ai/{owner.handle}/skills/{slug}`）
- ⚠️ URL 不得自己拼——ownerHandle 获取优先级：发布时使用的 → GET 返回的 `owner.handle` → GET /api/v1/whoami 的 `user.handle`（个人兜底）；拼好必须 GET 确认 200

### P9 · 目标仓库解析（GitHub/GitCode）

- 默认从 `.project-info/` config 解析 `GITHUB_PUBLISH_REPO` / `GITCODE_PUBLISH_REPO`（格式 namespace/repo）
- 用户指令指定 → **只接受 namespace/repo 格式，拒绝完整 git URL**（用户指令优先级高于环境变量）
- 未配置 → 报告「未配置发布目标仓库，请到设置页配置」→ 跳过该平台

### P10 · 汇总回复（必做——发布/下架完成后必须发 Issue 评论）

```bash
# 长 body 先写文件再 --json @file：
printf '%s' '{"body":"[SRE Agent] ✅ Skill 发布完成

## 发布结果：{name}

| 平台 | 状态 | 版本 | URL | 安装命令 |
|------|------|------|-----|----------|
| ClawHub | ✅ 已提交（安全扫描中） | v{version} | https://clawhub.ai/{ownerHandle}/skills/{slug} | clawhub install {slug} |
| GitHub | ✅ 成功 | v{version} | {url} | — |
| GitCode | ✅ 成功 | v{version} | {url} | — |

**文件指纹**：{SHA-256 前 8 位}
**发布时间**：{UTC ISO}
**PR 追溯**：#{pr_number}

**版本号说明**：ClawHub 可能因版本占用自动 bump，版本号与其他平台不同。跳过的平台版本填「—」。"}' \
  > /tmp/skill-publish-comment.json
grape git-repo issues comments create --owner "$ACCOUNT" --repo "$REPO_NAME" \
  --number "$ISSUE_NUMBER" --json @/tmp/skill-publish-comment.json --json-out
# ⚠️ ClawHub 状态报「✅ 已提交（安全扫描中，通过后公开）」而不是「✅ 成功」——扫描中用户还不能安装
# 失败平台加行：| ClawHub | 🔴 失败 | — | — | 令牌无效，请到设置页更新 |
```

## 下架路径（action=unpublish——按顺序执行）

### U1 · 前置校验（下架前必执行）

```bash
# 从目标仓库拉取远端 skill 目录 → 计算远端 SHA-256 指纹 → 与本地预期指纹比对
# 不匹配 → Issue 评论告警「远端版本与预期不一致，请人工确认」→ 终止下架
# 匹配 → 继续
```

### U2 · 读取各平台令牌（同 P3——缺失/401/403 → 跳过该平台并输出提示）

### U3 · 按平台下架

```bash
# ClawHub（软删除 30 天；⚠️ 扫描中不可删除——遇到该状态直接失败不重试；组织配置时带 ?ownerHandle=）：
curl -s --max-time 30 -X DELETE -H "Authorization: Bearer $CLAWHUB_TOKEN" \
  "https://clawhub.ai/api/v1/skills/{slug}${CLAWHUB_OWNER_HANDLE:+?ownerHandle=$CLAWHUB_OWNER_HANDLE}"

# GitHub/GitCode（脚本封装：clone→备份→删除→1 次 commit→push；目录不存在输出 {"PUSHED":0,"MESSAGE":"无需下架"}——非失败）：
bash {{SKILL_DIR}}/skill-publish/scripts/sync_skill_platform.sh \
  --action unpublish --platform github \
  --skill-name {name} --issue-num {issue_number}
bash {{SKILL_DIR}}/skill-publish/scripts/sync_skill_platform.sh \
  --action unpublish --platform gitcode \
  --skill-name {name} --issue-num {issue_number}
# 脚本内置 backup/pre-delist-{skill_name} 备份分支（覆盖旧备份，只保留 1 个）
```

### U4 · 执行后校验平台状态，汇总回复（同 P10 发布结果表格式）

## ClawHub OwnerHandle（组织发布——发布/下架共用）

| 要点 | 规则 |
|------|------|
| 来源优先级 | **用户指令指定 > `.project-info/` config 的 CLAWHUB_OWNER_HANDLE（member 文档）> 空（个人账号发布）** |
| 存储 | SKILL.md 不存储 ownerHandle——归属完全由 API 入参控制 |
| 探测/下架 | 必须带 `?ownerHandle=`（配置了组织时）——不带只查个人命名空间会误判 404 |
| POST payload | 可选 ownerHandle——非空 = 发布到组织；token 须具备该组织 publisher 角色否则 403 |
| 归属变更 | **不支持变更已有 skill 归属**（个人→组织迁移官方有 bug）|
| 引用格式 | 组织：`@{ownerHandle}/{slug}`；个人：`{slug}`。安装命令：有 owner → `clawhub install @{owner}/{slug}`；无 → `clawhub install {slug}` |
| 页面 URL | `https://clawhub.ai/{ownerHandle}/skills/{slug}`——**不是** `/skills/{slug}`（307 到空页）**不是** `{用户名}/{slug}`（少 /skills/ 段）|

## 步骤 收尾 · 任务完成流程（必做——任何分支都必须执行到最后）

```bash
grape tasks complete --json '{
  "result_text": "<发布/下架处理结论>",
  "actions": ["做了什么，如 published:skill-xxx:clawhub / published:skill-xxx:github / skipped:gitcode"],
  "conclusion": "<处理结论（发布成功/部分失败/全部失败）>",
  "artifacts": ["产生的产物：ClawHub URL / GitHub URL / GitCode URL / 评论"],
  "next_step": "<下一步建议；如需重试失败平台则说明>"
}'
# 最终答复末尾输出结构化 JSON 块（actions/conclusion/artifacts/issue_summary must 真实填充）
```

> ⚠️ **结束信号**：complete 后立即结束任务，不要继续思考或等待输入。

---

## 错误排查速查（命令返回异常时）

> ⚠️ 出错时**先看完整错误**；runbook 命令照抄仍失败，才允许查 `grape commands` / 平台 API 文档。**不反复盲试同一命令**。

| 现象 | 处理 |
|------|------|
| `401`（平台令牌无效/过期）| 报告「{平台} 令牌无效或过期，请到设置页更新」→ 跳过该平台（不重试、不用其他 token 绕行——硬约束④）|
| `403`（平台令牌无权限）| 报告「{平台} 令牌对目标无权限，请检查 token 权限或目标归属」→ 跳过该平台（硬约束④）|
| `5xx`/连接超时/DNS 失败 | 最多 3 次指数退避重试（1s、2s、4s——硬约束⑧）|
| ClawHub POST "slug already exists" | slug 被软删除占用——报告「请等待 30 天或联系 ClawHub 支持」→ 该平台失败，不重试 |
| ClawHub DELETE 扫描中 | 直接失败不重试（等扫描完成才能删）|
| 版本冲突 / "already exists" | bump 重试 ≤3 次——超限直接失败终止，禁止无限循环 |
| 私仓 clone 报 could not read Password | URL 必须 `https://oauth2:{token}@gitcode.com`（不能 `https://{token}@`）|
| Grape 评论/任务命令报错 | 先 `grape refresh` 再重试；仍失败核对 cli-reference |
| 跳过平台原因不明 | 按真实原因区分（令牌缺失/403 无权限/仓库 404/push 失败）——不得用「未配置」兜底 |
| 下架前置校验指纹不匹配 | Issue 评论告警「远端版本与预期不一致，请人工确认」→ 终止下架 |
| sync 脚本报「{PLATFORM}_TOKEN 未设置」| 凭据需在场景高级选项 custom_fields 配置 name={PLATFORM}_TOKEN（平台按 name 直注同名 env）——`.project-info/` 不读凭据（平台不物化）校对 name 后重试 |