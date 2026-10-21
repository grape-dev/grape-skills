# Spec 与切片 Tickets 指南（Issue-MattPocock）

> 内化 mattpocock `to-spec` 与 `to-tickets`。产出用于交棒 coding-mattpocock 实现。

## 一、Spec 模板

```markdown
# Spec: Issue #{n} — {title}

## Problem Statement
{用户视角的问题}

## Solution
{用户视角的解决方案}

## User Stories
1. As a {角色}, I want {能力}, so that {价值}
2. ...                    # 极详尽，覆盖所有场景

## Implementation Decisions
- 要新建/修改的模块及其接口
- 技术澄清 / 架构决策 / schema 变更 / API 契约
- 不写具体文件路径/代码片段（易过时）

## Testing Decisions
- 好测试标准：只测外部行为，不测实现细节
- 将测试的模块 + 仓库内先例（similar tests）

## Out of Scope
{明确不做}
```

## 二、垂直切片 Tickets 模板（每条一条）

```markdown
## Ticket {N}: {标题}

**What to build**：{端到端可演示行为，从用户视角，非分层实现清单}
**Blocked by**：{阻断它的 ticket 编号/标题；"None" 可立即开始}

- [ ] 验收标准 1
- [ ] 验收标准 2
```

### 竖切片规则
- 每条切片切穿每层（schema/API/UI/测试）完整路径（**垂直**，非单一层水平切片）。
- 完成的切片自身可演示/可验证。
- 切片大小 ≤ 单上下文窗。
- 前置重构单独 ticket。

### 宽重构例外（expand-contract）
- 一个机械改动（改列名/重命名共享符号）blast radius 横跨全库、单次改全 fail → 用 expand-contract：先新增并存 → 按 blast radius 分批迁移（每批一 ticket）→ 全迁移后删除旧形式（一 ticket）。

## 三、Blocked-by 与可释放前沿

- 每条 ticket 声明阻断它的 tickets（依赖）。
- 无阻断 → 立即可开始。
- 「可释放前沿」= 所有 blockers 完成的 tickets；coding 按此顺序取活。

## 四、Triage 注意事项

- **查重按域概念**：用 GLOSSARY 词汇搜索已有实现（不只按请求措辞），报告查找位置。
- **验证 claim**：bug 先复现/核对；无法验证标「未验证」。
- **先前拒绝**：对照 out-of-scope 规划，相似已拒绝 → wontfix。
- 状态机建议：`needs-triage → needs-info → ready-for-agent`；可加 `wontfix`。