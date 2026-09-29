# 通用规范动态规则检查（skill-linter 集成）

Phase 4b 使用与 skill-linter / common-skill-tester lint 套件**同一套**在线检查点，对生成的 Skill 目录逐一执行，确保创建的通用 Skill 不违反通用规范。

## 检查点来源

| 项目 | 值 |
|------|-----|
| 在线地址（raw） | `https://raw.gitcode.com/developer-skill/skills-group-contribution/raw/update-audit-clearlist-20260924/tools/skills_checker/common_skillslinter.json` |
| 回退地址（API v5，base64） | `https://gitcode.com/api/v5/repos/developer-skill/skills-group-contribution/contents/tools/skills_checker/common_skillslinter.json?ref=update-audit-clearlist-20260924` |
| 拉取方式 | `node scripts/fetch_checks.js`（raw 失败自动回退 API v5；`-o` 可保存到文件用于断点续跑/复查） |

**核心原则：检查集完全动态，不硬编码任何检查项。** 在线 JSON 新增/变更条目时，按 `rule` 字段描述自动纳入。

## JSON 结构（以实际拉取为准，不假设固定字段）

```json
{
  "doc": "...", "scope": "...",
  "severity_legend": { "Critical": "...", "High": "...", "Medium": "...", "Low": "..." },
  "automation_legend": { "full": "...", "semi": "..." },
  "groups": [
    {
      "group": 1, "name": "目录与元数据结构", "item_count": 9,
      "items": [
        { "id": "GS-001", "check": "SKILL.md 存在", "severity": "Critical",
          "rule": "根目录下必须存在 SKILL.md", "failure_handling": "FAIL", "automation": "full" }
      ]
    }
  ],
  "summary": { ... }
}
```

## 最新规范概要（截至 2026-09 拉取，实际以动态拉取为准）

- 6 组共 31 项检查（27 检查项 + 3 安全评分子项 + 1 新增删除操作确认）
- 分组：目录与元数据结构(9) + 提交与隔离(4) + 脚本安全规范(5) + 资源限制与声明(6) + 安全扫描(4) + 安全评分(3)
- 严重级别分布：Critical(15) / High(4) / Medium(6) / Low(3)
- 关键变更：GS-002 目录路径升级为 Critical；GS-017 MCP 协议降级为 Low；GS-019 总大小限制改为 50MB；GS-020 文件数改为 40；新增 GS-024 删除操作确认声明(Critical)

## 检查方法映射

**根据检查项 `check`/`rule` 字段动态匹配，不硬编码 ID。** 未知检查项按 `rule` 描述自行设计方法。

| 检查类型（按 check/rule 关键词匹配） | 执行方式 |
|---|---|
| SKILL.md 存在 | Glob 检查根目录是否有 SKILL.md |
| 目录路径格式 | 检查目标路径是否匹配 `skills/{category}/{skill-name}/`（最新规范路径层级为 category/skill-name，无 subcategory） |
| Frontmatter 存在 | Read SKILL.md，检查顶部是否有 `---` 包裹的 YAML 块 |
| name/description/version 字段 | 解析 Frontmatter，检查字段是否存在及值是否合规 |
| name = 目录名 | 对比 Frontmatter name 值与目录名 |
| 命名规范 | 检查目录名是否符合 kebab-case |
| PR 单 Skill | 检查 git diff 涉及的 Skill 目录数量（如适用） |
| .env 文件 | Glob 搜索 `.env` 文件 |
| 危险脚本 | Grep 搜索 `sudo`、`rm -rf /` 等模式 |
| Skill 间调用 | Grep 搜索 SKILL.md 中是否引用其他具名 Skill |
| 明文 IP/域名 | Grep 搜索内网 IP 段（10.x, 172.16-31.x, 192.168.x）和内部域名 |
| 脚本 shebang | Read .sh 文件首行，检查是否为 `#!/usr/bin/env bash` |
| 脚本语法 | Bash 执行 `python -m py_compile` 或 `bash -n` |
| MCP 协议 | 如适用，检查 JSON-RPC 格式（最新规范为 Low 级别） |
| 异常处理 | Grep 搜索 `set -euo pipefail` 或 `try/except` |
| 总大小限制 | Bash 统计目录总大小，阈值以检查点 JSON 的 check 字段为准（最新为 50MB） |
| 文件数限制 | Glob 统计文件数量，阈值以检查点 JSON 的 check 字段为准（最新为 40） |
| SKILL.md 行数 | Bash `wc -l` 统计行数，阈值 500 行（以检查点 JSON 为准） |
| 文件类型白名单 | 检查所有文件扩展名是否在白名单内 |
| 写操作确认 | Grep 搜索 SKILL.md 是否提及写操作需确认 |
| 删除操作确认 | Grep 搜索 SKILL.md 是否提及删除操作需确认（Critical 级别，fail 处理为 FAIL） |
| 凭证硬编码与密钥泄露 | Grep 搜索 AK/SK/密码/token 模式，检查 configure set 传明文、读取/回显凭证文件 |
| 漏洞模式 | Grep 搜索已知漏洞代码模式 |
| 依赖安全 | 如有依赖文件，检查版本是否有已知漏洞 |
| 不安全配置 | Grep 搜索 http://（非 https）、弱密码等 |
| 安全评分子项 | 综合以上检查结果评分（敏感信息泄漏/命令注入/权限越权） |

## 判定逻辑

对每个检查项输出：**pass**（通过）/ **fail**（不通过，按 `failure_handling` 定严重性）/ **warn**（警告）/ **skip**（不适用，注明原因）。判定必须基于**客观证据**（文件存在、grep 命中、行列号、统计数字）。

## 评分与门禁

```
Lint 评分 = 100 - (Critical_fail × 15) - (High_fail × 8) - (Medium_fail × 4) - (Low_fail × 2) - (warn × 1)
```

星级/等级（与 linter 一致）：

- 90-100: ⭐⭐⭐⭐⭐ 优秀
- 75-89: ⭐⭐⭐⭐ 良好
- 60-74: ⭐⭐⭐ 合格
- 40-59: ⭐⭐ 需改进
- 0-39: ⭐ 不合格

**Phase 4b 门禁：**

1. **Critical fail 一票否决** — 任何 Critical 项 fail（含 `failure_handling=FAIL` 项）未修复前，禁止进入 Phase 5
2. **评分 ≥ 95 才合格** — 与质量门槛要求一致（三套检查评分全 ≥ 95）；< 95 时列出必改项/建议项，修复后重跑 `fetch_checks.js` 复查直到通过
3. 若生成的是极简 skill（单命令、无脚本/无 references），按规则实际判定（相关项 pass/skip），不许用"太简单"跳过检查

## 与 validate-skill.sh（Phase 4a）的关系

- **4a（validate-skill.sh）**：静态基线 — 基础字段、命名、结构、凭证扫描（本地固定检查）
- **4b（本文档）**：动态规范 — 最新通用规范全量检查点（在线动态加载）
- 两者互补，**都必须通过**。4a 覆盖底层的 11 项硬性约束，4b 覆盖最新规范的全部规则（含资源限制阈值、删除操作确认、安全评分等动态更新项）。