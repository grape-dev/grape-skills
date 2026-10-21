# MattPocock 开发场景

**内化 `github.com/mattpocock/skills` 核心方法论**，形成独立四节点流水线（无 sre）。

## 技能链路

1. **VOD** — 开发者声音分析（`vod-mattpocock`）：Grilling 澄清至无歧义 → 收敛结构需求单
2. **Issue** — Issue 运营（`issue-mattpocock`）：Triage 分诊 → Spec（用户故事）→ 垂直切片 tickets
3. **Coding** — 代码实现（`coding-mattpocock`）：seams 协商 → TDD 红-绿 → 可红反馈环 → 原型 → PR
4. **QA** — 代码审查（`qa-mattpocock`）：两轴审查（Standards vs Spec）→ merge-danger 门

> **sre 暂不包含**：qa 通过后合入/部署交人工；后续需要可扩展 sre 节点。

## 方法论

- **Grilling**：动手前逼问澄清，区分已确认/未确认/新问题，收敛到可执行
- **Spec 驱动**：Problem→Solution→User Stories→Implementation/Testing Decisions→Out of Scope
- **垂直切片**：每 ticket 一条完整可演示竖切片，声明 Blocked-by 阻断边
- **TDD**：先协商测试 seam → 一竖切片一测试 → 红-绿循环
- **先可红反馈环**：bug 先建能变红的测试，再复现最小化→多假设→插桩→修复→回归
- **两轴审查**：Standards（规范+异味）vs Spec（需求忠实度）并行分轴报告

## 适用场景

- 强澄清、严格 Spec/测试纪律的项目
- mattpocock 方法论实践团队