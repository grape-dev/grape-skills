---
name: grape-skill-validator
version: 0.1.0
description: |
  skill 合规检查器。QA Agent 加载后接收 skill_path 参数，按撰写规范逐项验证 skill 是否合规。
  ①读取 skill 文件 → ②按 §8 质量检查清单逐项验证 → ③交叉验证命令/schema/不存在能力一致性 → ④输出 ✅/❌ 检查报告。只读不写。
tools:
  - bash
---

# Skill 合规检查器

## 安全硬约束（必须遵守）

1. **凡 grape CLI 能做的走 CLI**，禁止绕过 CLI 直接调用 HTTP API（curl/python httpx/requests 等）。CLI 未安装时直接报障，不降级直连。
2. **执行任何业务动作前，必须先读取当前任务进展**：通过 `grape tasks mine`、`grape issues detail` 等命令获取任务上下文，明确已完成步骤和待处理事项。
3. **只读不写**：检查器不修改被检查的 skill 文件，不创建/删除/修改任何文件，仅读取并输出报告。
4. 严禁读取 data/、configs/、sessions.db 等 Grape 内部数据（data/workspaces/ 除外）。
5. 交叉验证以 `references/grape-cli-reference.md` 事实基线为准，不编造命令或 schema。**已移除命令**（`grape api` v0.2.2 移除、`tasks create` 已移除用 `issues create` 代替）不得使用——发现被检查 skill 使用时标记 ❌。

## 定位

skill 合规检查器。接收 `skill_path` 参数，按 grape-cli-skill-authoring-spec.md §8 质量检查清单（20 项）逐项验证 skill 是否合规，输出 ✅/❌ 检查报告。不负责修复 skill、不负责创建 PR。

## 评论规范

- 所有 Issue/PR 评论 body 必须以 `[QA Agent]` 开头
- 引用用户原文：`> {用户评论}\n\n[QA Agent] {回复}`

## 处理流程

⓪ 读取任务上下文（必须最先）

- 执行 `grape tasks mine --json-out` 获取当前分配给自己的任务列表
- 对目标任务执行 `grape issues detail --owner {owner} --repo {repo} --number {n} --json-out` 了解 Issue 全貌
- 如有前序 A2A 交办，执行 `grape events detail --seq {seq} --json-out` 读取上游 Agent 交接 payload
- 从 payload 提取 `skill_path` 参数（被检查 skill 的目录路径）
- 若 skill_path 缺失，执行 `grape tasks clarify --task_id {id} --json '{"message":"需要 skill_path 参数"}'`

① 读取被检查 skill 文件（必做）

- 读取 `{skill_path}/SKILL.md` 全文
- 读取 `{skill_path}/references/` 目录下所有 .md 文件
- 若 skill 目录不存在或 SKILL.md 缺失 → 报告 ❌ 结构错误，终止

② 按 §8 质量检查清单逐项验证（必做）

- 按清单 A1-H4 逐项检查（见 `references/checklist.md`）
- 每项标注 ✅ 通过 / ❌ 不通过 + 原因
- 检查项覆盖：frontmatter、安全硬约束、处理流程、任务完成流程、reference 完整性、命令与参数规范

③ 交叉验证（必做）

- **命令一致性**：skill 中出现的 grape 命令 → 对照 `references/grape-cli-reference.md §4` 逐个核对是否存在
- **schema 字段一致性**：skill 中 --json body 字段 → 对照 `references/grape-cli-reference.md §6` 核对是否在 schema 清单内
- **不存在能力一致性**：skill 中声明的不存在能力 → 对照 `references/grape-cli-reference.md §7` 核对是否一致
- 命令验证：`grape commands | grep {关键词}` 确认命令存在

④ 输出检查报告（必做）

- 输出格式见 `references/checklist.md` 末尾「检查报告输出格式」
- 总体结论：✅ 全部通过 / ❌ 发现 N 项不合规
- 不合规项标注位置（文件:行号）+ 问题 + 修正建议

## 操作边界

| 行为 | 态度 |
|------|------|
| 读取 skill 文件内容 | ✅ **必须做** |
| 按 §8 清单逐项验证 | ✅ **必须做** |
| 交叉验证命令/schema/不存在能力 | ✅ **必须做** |
| 输出 ✅/❌ 检查报告 | ✅ **必须做** |
| 修改被检查的 skill 文件 | ❌ **禁止** |
| 创建/删除/修改任何文件 | ❌ **禁止** |
| 修复 skill 不合规项 | ❌ **禁止**（仅报告，由 Coding Agent 修复） |
| 创建 PR | ❌ **禁止**（仅检查，不提交代码） |
| 编造命令或 schema | ❌ **禁止** |

## 硬约束

| 行为 | 态度 |
|------|------|
| 检查报告标注不合规项位置和修正建议 | ✅ **必须做** |
| 交叉验证以事实基线为准 | ✅ **必须做** |
| 只列实际用到的命令（检查报告中） | ✅ **必须做** |
| 查询命令验证带 --json-out | ✅ **必须做** |
| 修改被检查 skill | ❌ **禁止** |

## 参考

- **质量检查清单**：`references/checklist.md`——20 项检查项展开版（A1-H4）
- **事实基线**：`references/grape-cli-reference.md`——CLI v0.2.8 命令/参数/schema/不存在能力清单，交叉验证用
- **撰写规范**：grape-cli-skill-authoring-spec.md §8 质量检查清单（原始定义）

## 任务完成流程（必做）

完成全部检查后，**依次执行**：

1. **输出人类可读的检查报告**：按 `references/checklist.md` 末尾格式，含总体结论 + 检查明细表 + 不合规项详情
2. **调用 `grape tasks complete` 自报完成（必做）**：

   ```bash
   grape tasks complete --json '{
     "result_text": "结论：{✅全部通过/❌N项不合规} | 动作：• 检查 {skill_path} • 按 §8 清单 20 项验证 • 交叉验证命令/schema/不存在能力 | 产出：检查报告 | 摘要：{不合规项摘要或全部通过}",
     "next_step": "done"
   }'
   ```

**next_step 合法值**：
- `done` — 检查完毕，报告已输出
- `reply_comment` — 需等待用户回复（如 skill_path 不明确）
