# REST API Skill 生成执行走查表（rest-api-skill-creator runbook）

> 目的：把 rest-api-skill-creator 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> **CLI 纪律**：平台交互（查重/评论/A2A/任务）一律走 grape CLI——**禁止 curl 直连平台 API**；curl 仅用于**目标系统探测**（生成器执行域——被创建的 REST API skill 要管理的系统）——`curl -s --max-time 30`。
> **生成物纪律**：生成的 skill 按 `references/skill-spec.md` 规范（**生成物规范与平台技能框架是两个逻辑——不套平台统一框架段落**）；只生成 5 件套（SKILL.md / scripts/{name}.py / references/api-reference.md / templates/test-vars.json / requirements.txt）。
> 环境变量直接使用：`$ACCOUNT`、`$REPO_NAME`（= `${REPO_FULL_NAME#*/}`）、`$ISSUE_NUMBER`、`$PR_NUMBER`；目标系统凭据 `{PREFIX}_BASE_URL` 等（PREFIX = skill name 转大写下划线）。
> **评论前缀硬规**：所有评论 body 一律以 `[Coding Agent]` 开头。

---

## Step 0 · 任务上下文与就绪（必须最先，任何事件都做）

```bash
# ⚠️ CLI 前置自愈（最先）：`grape --version` ≥0.3.2；未装/版本过低 → 按 references/grape-cli-installation.md
#    自动安装/升级（timeout 300 pip install git+https://gitcode.com/grape-dev/grape-cli.git）→ 装好再验证一次
#    → 仍不可用 → 输出「前置检查未通过：<原因>」并结束任务（不降级直连）
grape --version
grape refresh 2>&1 && echo REFRESH_OK        # 契约保鲜；失败重试 ≤2 次后回退内置快照继续
python3 -c "import requests" 2>&1 && echo REQUESTS_OK   # Python 环境（≥3.8 + requests——生成物运行时依赖；缺 → pip install requests）
grape tasks current --json-out               # A2A payload 在这里（需求描述/目标系统信息/repository/account/issue_number/pr_number）
```

## Step 0 · 查重（必须最先——任何创建前）

```bash
# 检查目标仓库 skills/ 目录是否已有同名 skill：
grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --path skills --json-out | head -80
# 远程已存在 → 回复「已存在——可复用/更新」——不重复造；不存在 → 继续
```

## Step 1 · 需求澄清（4 维度——必须全覆盖且用户确认）

| 维度 | 内容 |
|------|------|
| 1. 目标系统 API 地址 | base_url（如 https://blog.example.com/api）|
| 2. 认证方式 | Basic Auth / Bearer Token / API Key（Header 或 Query）/ 无认证 |
| 3. API 文档形式 | OpenAPI/Swagger 文件 / Markdown 文档 / 口头描述 |
| 4. 需要哪些操作 | 用户期望的管理能力（发布/编辑/删除/查询/分类管理等）|

- 用户填了需求模板（`templates/requirement-template.md`）→ 直接从模板提取；否则按 4 维度逐一澄清
- 凭据变量前缀：skill name 转大写 + 下划线（`blog-manager` → `BLOG_MANAGER`）——Basic = `{PREFIX}_USERNAME`+`{PREFIX}_PASSWORD` / Bearer = `{PREFIX}_TOKEN` / API Key = `{PREFIX}_API_KEY`
- 覆盖全部维度 → 展示需求摘要表（含认证方式 + 凭据变量名）→ **等用户确认**
- 用户跳过提问直接说「开始」→ 提醒需求澄清必须先完成

## Step 2 · 技术调研（REST API 文档三级回退——详细见 references/api-research-guide.md）

```bash
# ① 优先 OpenAPI/Swagger（解析 paths 提取全部端点）：
python3 -c "
import json, sys
spec = json.load(open(sys.argv[1]))
for path, methods in spec.get('paths', {}).items():
    for method, info in methods.items():
        if method in ('get','post','put','patch','delete'):
            print(f'{method.upper()} {path}  op={info.get(\"operationId\",\"\")}  summary={info.get(\"summary\",\"\")}')
" openapi.json

# ② 回退 Markdown 文档（提取端点/参数/响应结构）
# ③ 最后 基础信息 + curl 逐个探测（只读端点；--max-time 30）：
curl -s --max-time 30 -u "${PREFIX}_USERNAME:${PREFIX}_PASSWORD" "${PREFIX}_BASE_URL/{用户描述的端点}" | python3 -m json.tool
curl -s --max-time 30 -H "Authorization: Bearer ${PREFIX}_TOKEN" "${PREFIX}_BASE_URL/api/" -w "\n%{http_code}"
```
- **端点只认可信来源**（OpenAPI paths / 文档明确描述 / curl 200）——严禁按命名模式猜测
- 时间盒：每端点 ≤5 分钟，超时标记 ⛔；**失败门控：所有端点都 ⛔ → 终止，不生成任何文件**
- 【真实 API 验证】：凭据可用时 curl 真实调用一次只读端点 → 成功记录返回结构；失败 → 标记 API 不可用走失败门控

## Step 3 · 骨架生成（生成前先读 `references/skill-spec.md`——生成物规范）

只生成 5 件套（目录 `skills/{name}/`，name = 小写连字符）：
```bash
mkdir -p skills/{name}/scripts skills/{name}/references skills/{name}/templates
```
| 产物 | 要求 |
|------|------|
| `SKILL.md` | ≤500 行；按 skill-spec.md 规范生成（必填段落：安全硬约束/评论规范/Configuration/场景/知识/步骤/判断标准/输出规范/参考文档/分析结论示例/任务结束）|
| `scripts/{name}.py` | Python 入口（端点 <10 单文件 / ≥10 入口+包目录模块化；`--format` 加到**每个子命令 parser**；用 requests 不用 urllib；结构按 `references/rest-api-skill-template.md`）|
| `references/api-reference.md` | API 端点文档（`{base_url}` 占位——不硬编码真实地址）|
| `templates/test-vars.json` | 测试用例（结构见下）|
| `requirements.txt` | 至少 `requests>=2.20.0` |

**脚本生成约束**：
1. `--format` 加每个子命令 parser（`add_common_args(子parser)`），不能加全局 parser
2. `requirements.txt` 用真实换行符（`\n`），不能写字面量 `\\n`
3. 按模板结构生成（`add_common_args` + `sub.add_parser` + `add_common_args(p_N)`）
4. 用 requests 库不能用 urllib；requirements.txt 声明 `requests>=2.20.0`
5. SKILL.md 中 API 地址一律 `{base_url}` 占位符（示例地址标注「(示例)」）；api-reference.md 同

**test-vars.json 结构**（只含测试用例+元数据，**不含真实地址/凭据值**）：
```json
{
  "skill_name": "{skill_name}",
  "entry_file": "scripts/{skill_name}.py",
  "test_cases": [
    {"id": "TC-01", "name": "health-check", "command": "python3 scripts/{skill_name}.py health-check", "expected": "{\"status\":\"ok\"}", "method": "GET", "category": "readonly", "description": "检查 API 可达性"},
    {"id": "TC-02", "name": "list-articles", "command": "python3 scripts/{skill_name}.py list-articles --page 1 --size 10", "expected": "{\"code\":200,\"data\":[...]}", "method": "GET", "category": "readonly", "description": "查询文章列表"},
    {"id": "TC-03", "name": "create-article", "command": "python3 scripts/{skill_name}.py create-article --title test --content hello", "expected": "{\"code\":200,\"data\":{\"id\":...}}", "method": "POST", "category": "mutable", "description": "创建文章", "cleanup": "执行 delete-article 删除刚创建的测试文章"}
  ],
  "env_vars_required": ["{CRED_PREFIX}_BASE_URL（API 地址）", "有认证时：{CRED_PREFIX}_TOKEN / {CRED_PREFIX}_USERNAME / {CRED_PREFIX}_PASSWORD（凭据）"],
  "notes": "凭据和 base_url 从环境变量或 .project-info/ 下 JSON 配置文件获取，不写入此文件"
}
```
- 字段必填：id/name/command/expected/method/category/description（cleanup 可选——mutable 用例必含描述性清理说明）
- **最低覆盖**：health-check（必填）+ 每类资源 ≥1 只读查询 + ≥1 写操作（mutable 含 cleanup）+ capability-list（必填）

**子命令生成规则**（由 API 文档动态决定）：GET /api/{r} → list-{r}；POST → create-{r}；GET /{id} → get-{r}；PUT/PATCH → update-{r}；DELETE → delete-{r}；特殊路径（restore/reply/heat/top）→ 语义段+动词；其他 → path 末段+method。拼写修正（如 lables）：子命令用正确拼写、脚本内请求用 API 实际路径、Core Commands 表格注明；Web 页面端点（返回 HTML）不生成子命令；文件上传 multipart 用 `files=`（单文件 dict 值=单个 file object；批量用元组列表）。

**生成的脚本凭据读取规范**（4 级）：项目知识（递归扫描 .project-info/ JSON secrets.{PREFIX}_*）→ 环境变量（{PREFIX}_*）→ 当前上下文（A2A 注入，含在 2）→ 交互输入；都缺 → **退出码 3**。代码模板见 rest-api-skill-template.md 的 `_load_credentials` + `_load_from_project_knowledge`。

**生成物命名/大小约束**：frontmatter name 必须跟目录名一致；扩展名白名单 .md/.txt/.json/.yaml/.yml/.py/.sh/.csv/.cfg/.conf/.xml/.html/.css/.svg；总内容 ≤40MB、文件数 ≤50、SKILL.md ≤500 行。

## Step 3.5 · 自测（生成后必做——三项全过才进 Step 4）

```bash
# ① 语法检查：
python3 skills/{name}/scripts/{name}.py --help
# ② 结构校验（16 项全过）：
bash {{SKILL_DIR}}/rest-api-skill-creator/scripts/validate-skill.sh skills/{name}/
# ③ 真实 API 调用一次（只读端点——API 可达）：
#    （设好 $SKILL_DIR 后 export {PREFIX}_BASE_URL/凭据 → 跑一个只读子命令看返回）
# 失败 → 修复后重试；无法修复 → Issue 评论说明，不创建 PR
```

## Step 4 · 创建 PR（脚本封装——幂等查重/补 body/base 校验）

```bash
# 环境变量就位后调脚本（脚本内部：git commit+push → pulls list 幂等查重 → pulls create → pulls update 补 body → pulls get base 校验）：
bash {{SKILL_DIR}}/rest-api-skill-creator/scripts/create_rest_api_skill_pr.sh "$SKILL_NAME"
```
⚠️ **创建 PR 后必须发 Issue 评论告知**（长 body 先写文件再 --json @file）：
```bash
printf '%s' '{"body":"[Coding Agent] ✅ Skill 已创建并提交 PR

**Skill 名称**：{name}
**功能摘要**：{一句话描述}
**API 端点数**：{N} 个
**认证方式**：{AUTH_TYPE}
**PR 链接**：{PR_URL}
**测试状态**：已 A2A 交棒 QA Agent，测试中

**下一步**：
- 测试通过后自动合并 → 发布"}' > /tmp/creator-comment.json
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" \
  --number "$ISSUE_NUMBER" --json @/tmp/creator-comment.json --json-out
```

## Step 5 · 清理

```bash
rm -rf /tmp/*-gen-* 2>/dev/null || true   # 删除临时调研产物（openapi.json 备份/探测临时文件等）
```

## Step 6 · A2A 交棒 tester（必做——创建 PR 后不可跳过）

```bash
# 先防重复：pulls list 同分支 open PR 已有（脚本已幂等）——A2A 交棒：
grape a2a handoff --json '{
  "agent": "qa",
  "payload": {
    "repository": "'"$REPO_FULL_NAME"'",
    "account": "'"$ACCOUNT"'",
    "issue_number": '"$ISSUE_NUMBER"',
    "pr_number": '"$PR_NUMBER"',
    "context": "Issue #'"$ISSUE_NUMBER"' skill 已创建，PR #'"$PR_NUMBER"' 已提交。请对 skill 进行功能验证。Skill 名称：{name}"
  }
}'
```

## 步骤 收尾 · 任务完成流程（必做——任何分支都必须执行到最后）

```bash
grape tasks complete --json '{
  "result_text": "<处理结论>",
  "actions": ["做了什么，如 created:rest-api-skill-xxx / submitted:PR#N / a2a:qa"],
  "conclusion": "<处理结论（skill 已创建/创建失败）>",
  "artifacts": ["产生的产物：PR#N / skill 目录 / 评论"],
  "next_step": "<下一步建议>"
}'
# 最终答复末尾输出结构化 JSON 块（actions/conclusion/artifacts/issue_summary must 真实填充）
```

> ⚠️ **结束信号**：complete 后立即结束任务，不要继续思考或等待输入。

---

## 错误排查速查（命令返回异常时）

> ⚠️ 出错时**先看完整错误**；runbook 命令照抄仍失败，才允许查 `grape commands` / API 文档。**不反复盲试同一命令**。

| 现象 | 处理 |
|------|------|
| 远程已有同名 skill | 回复「已存在——可复用/更新」——不重复造 |
| 凭据环境变量缺失/为空且 .project-info/ 无配置 | 提示用户提供；用户不提供 → 终止流程 |
| API 调研超 5 分钟未确认端点 | 标记 ⛔（API 不存在）→ 失败门控（全 ⛔ → 终止，不生成任何文件）|
| validate-skill.sh 有 FAIL | 按 FAIL 项修复后重跑；无法修复 → Issue 评论说明，不创建 PR |
| 创建 PR 失败（脚本无输出/无 number）| 脚本 exit 2——重试一次；仍失败 → Issue 评论说明 |
| PR base 校验不过 | 脚本 exit 2——检查 pulls create base 参数 |
| 命令 403/无权限 | 立即停止该操作并回复用户（硬约束③——不换 token 不绕行）|
| 401/凭据失效 | 说明凭据已失效（tk_ 短命属正常）——不替换不绕行 |
| 目标系统 API 404 | 端点不存在——标记 ⛔ 或按文档修正 |
| `comments create` 长 body 转义失败 | 改用 `--json @file`（body 先写文件）|
| 报「契约过期/命令不识别」| 先 `grape refresh` 再重试（前置门②）|