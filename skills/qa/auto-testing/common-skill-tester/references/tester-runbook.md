# 通用 Skill 三合一测试执行走查表（common-skill-tester runbook）

> 目的：把 common-skill-tester 每一步**要做什么 + 用哪条确切命令**固化下来，Agent **照着执行、不要查 `--help` / `grape commands`**。
> **命令纪律**：本技能为**本地只读测试器**——命令面 = 本地脚本（node）+ **唯一平台接口** 4.8 任务收尾 `tasks complete`。**禁止**尝试 grape 平台管理命令（issues/pulls/a2a/refresh——本技能无平台业务交互）。**禁止**修改被测 Skill 目录内任何文件（检测只读——唯一写操作是 4.7 报告文件）。

## Step 0 就绪（前置检查门）

| 检查 | 命令 | 通过标准 | 失败处理 |
|------|------|---------|---------|
| node | `node --version` | ≥ 12 | 尝试安装 → 重试 → 仍失败由 Agent 直接用 curl 拉规范继续，不阻塞 |
| 目标目录 | `test -d "<skill_path>"` | 存在目录 | 返回错误提示，不执行任何检查 |
| 可选：bash / python | `bash --version` / `python3 --version` | 存在 | 缺失则该类检查项 skip 注明原因 |

确认 mode（`all` 默认；非法值回退 all 并在报告注明）。任一失败 → 输出「前置检查未通过：<原因>」结束任务，不无限重试。

## Step 1 拉取三份规范

```bash
node common-skill-tester/scripts/fetch_specs.js                              # 全部三份，输出合并 JSON
node common-skill-tester/scripts/fetch_specs.js --type lint                  # 只拉 lint 检查点
node common-skill-tester/scripts/fetch_specs.js --type test                  # 只拉功能测试点
node common-skill-tester/scripts/fetch_specs.js --type audit                 # 只拉安全审计规则
node common-skill-tester/scripts/fetch_specs.js "https://...json" --type lint  # 自定义 URL
node common-skill-tester/scripts/fetch_specs.js -o /tmp/specs.json           # 保存到文件（断点续跑/复查）
```

- 拉取策略：raw URL 失败 → 自动回退 gitcode API v5（base64 解码）→ 仍失败该套件标记「未执行(原因)」其余照常
- **核心原则：以拉取到的实际 JSON 内容为准，不硬编码任何检查项/测试项/规则**——在线新增条目自动纳入
- 拉取后按 `references/spec-sources.md` 核对结构

## Step 2 收集目标 Skill 信息（一次收集，三套复用）

| # | 收集项 | 方法 |
|---|--------|------|
| 1 | 目录结构（文件/子目录/大小/扩展名——重点标记 .sh/.py/.js/.ts/.go/.rs）| Glob 列文件 |
| 2 | SKILL.md 全文 + Frontmatter（name/description/version）+ Workflow/inputSchema/outputSchema/读写声明 | Read |
| 3 | 脚本文件内容（所有 .sh/.py/.js/.ts——安全审计素材）| Read |
| 4 | 配置文件（.env 存在性；package.json/requirements.txt/pyproject.toml 依赖声明）| Glob + Read |
| 5 | 危险模式预扫描（一次 grep 三套复用）：凭据（AK/SK/密码/token）、内网 IP/域名、危险命令（sudo/rm -rf）、敏感路径（~/.ssh、~/.aws）、网络请求 URL、动态执行调用 | Grep |
| 6 | 文件统计（总大小/文件数/SKILL.md 行数/类型列表）| Bash 统计 |
| 7 | 跨引用与集成声明（引用其他具名 Skill/多 Skill 编排/数据传递）| Read SKILL.md 找声明 |

## Step 3 Lint 规范检查（mode 含 lint）

1. 对**每一个**检查项（`groups[].items[]`）按 `references/lint-methods.md` 方法映射执行
2. 判定 pass/fail/warn/skip——**客观证据**（文件存在/grep 命中/行列号/统计数字）
3. Lint 总分：`100 - (Critical×15 + High×8 + Medium×4 + Low×2 + warn×1)`
4. Critical fail = 必改项（附具体修改建议）；非 Critical fail/warn = 建议修改项
5. 输出「三、Lint 检查结果」章节

## Step 4 功能测试（mode 含 test）

1. 对每一条测试用例（`test_groups[].items[]`）按 `references/test-methods.md` 执行（触发词/工作流/Schema/读写语义/性能/兼容/可靠/编排）
2. 静态分析为主（验证 SKILL.md 是否声明必要机制），可运行时结合运行结果
3. 判定 pass/fail/warn/skip + 证据（引用章节/行号/内容）
4. 通过率：`pass / (总用例数 - skip) × 100%`；P0 必测项任一 fail 标记「建议打回」
5. 输出「四、功能测试结果」章节

## Step 5 安全审计（mode 含 audit）

1. 对每一条检测规则（`groups[].items[]` + CWE 模式）按 `references/audit-methods.md` 执行（网络请求/敏感文件/危险命令/注入/后门/混淆/依赖安全）
2. 判定 pass/fail/warn/skip；**fail 必须关联 CWE 编号**并引用文件/行号/代码片段
3. 安全分：`100 - (CRITICAL×20 + WARNING×8 + INFO×2 + warn×1)`；CRITICAL fail 一票否决
4. CWE 覆盖率：`已检测 CWE 数 / 总 CWE 数 × 100%`
5. 输出「五、安全审计结果」章节

## Step 6 汇总报告 + 综合判定 + 任务收尾

按 `references/report-template.md` 生成组合报告：

```bash
综合分 = round((Lint总分 + Test通过率 + Audit安全分) / 3)
```

| 判定 | 条件 |
|------|------|
| ✅ 通过 | 三套评分均 ≥ 95，且无 lint Critical fail、无 test P0 fail、无 audit CRITICAL 发现 |
| ⚠️ 有条件通过 | 无上述三类 fail，但存在 warn 或任一评分在 75-94 |
| ❌ 不通过 | 存在任一上述 fail 类型，或任一评分 < 75 |

输出两处：
- **对话输出**：Markdown 报告直接给用户
- **文件输出**：`{被测 Skill 父目录}/{skill-name}-tester-report-{YYYYMMDD-HHmmss}.md`（`{skill-name}` 从 skill_path 目录名提取；例 `skill_path=/repos/skills/dev/my-skill` → `/repos/skills/dev/my-skill-tester-report-20260916-120000.md`）

判定 ❌ → 对话明确列未达标项（fail 清单 + 未达 95 的套件 + 原因）+ 修复建议。报告使用中文输出。

### 平台任务收尾（唯一 grape 交互——必做）

业务动作全部完成后，**先调 tasks complete 关任务，再在最终答复末尾输出 JSON 块**：

```bash
grape tasks complete --json '{"result_text": "三合一测试完成：<skill 名称> 综合判定 <✅/⚠️/❌>", "actions": ["拉取规范/lint/test/audit/汇总报告"], "conclusion": "<综合判定与关键发现>", "artifacts": ["<报告文件路径>"], "next_step": "<按判定给用户的下一步（修复后重测/通过) 建议>"}'
```
```json
{
  "actions": ["拉取规范/lint/test/audit/汇总报告"],
  "conclusion": "综合判定与关键发现",
  "artifacts": ["<报告文件路径>"],
  "next_step": "按判定给用户的下一步建议",
  "issue_summary": "本次任务最新聚合结论（紧凑文本，用 | 分隔）"
}
```

## 错误排查速查

| 症状 | 原因 | 处理 |
|------|------|------|
| `node: command not found` | node 缺失 | Agent 直接用 curl/网络工具拉规范 JSON 继续（不阻塞）|
| skill_path 不存在/非目录 | 输入错 | 返回错误提示，不执行任何检查 |
| 某份规范拉取失败（网络断）| raw + API v5 双失败 | 该套件标记「未执行(原因)」其余照常；提示可指定本地 JSON（`-o` 保存的或手动路径当 URL 参数）|
| mode 非法值 | 参数错 | 回退 all，报告中注明 |
| 目标无脚本 | 无代码可审计 | audit 代码相关规则 skip；lint 脚本检查 skip/pass（注明原因）|
| 目标无写操作 | 无写 API 声明 | test 读写语义/幂等/资源清理用例 skip（注明原因）|
| 在线规范新增未知条目 | 规范更新 | 按 `rule`/`input`/`detection` 描述自行设计方法——不跳过 |
| 断点续跑 | 中断后恢复 | `-o` 保存的规范文件重新指定为 URL 参数（本地路径直接读取）|
| `grape tasks complete` 失败 | 非平台任务上下文 | 跳过收尾（无任务可关），照常交付报告 |
| 报告过长 | 目标大 | 按模板章节结构输出，详细记录表保留全部条目 |