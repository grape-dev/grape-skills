# TDD 与 Bug 诊断指南（Coding-MattPocock）

> 内化 mattpocock `tdd` 与 `diagnosing-bugs`。供实现与排障使用。

## 一、好测试标准

- 通过**公共接口**验证行为；代码可整体重写，测试不应变。
- 测试读起来像规格："用户携带有效购物车可结算"。
- **只在预协商的 seam 上测试**；不在未确认的 seam 上写测试。

### 反模式
- **实现耦合**：mock 内部协作者 / 测私有方法 / 走旁路校验 → 重构时误报。
- **同义反复**：断言按代码同方式重算期望值（`expect(add(a,b)).toBe(a+b)`）→ 永远通过。
- **水平切片**：先写全部测试再全部实现 → 测的是臆想的行为；用垂直切片（一测试→一实现→重复）。

## 二、TDD 循环规则

- **红在前**：先写失败测试，再写刚够通过的代码；不加未来/投机功能。
- **一竖切片一次**：一个 seam、一个测试、一个最小实现。
- **重构不属于循环**：属于 code-review 阶段（qa-mattpocock 两轴审查）。

## 三、Bug 诊断（diagnosing-bugs）

> 没有能对该 bug 变红的测试，任何假设都是瞎猜。**先建可红反馈环**，bug 就 90% 修了。

### Phase 1 · 建可红反馈环（本技能核心）
目标：一个命令/脚本，能驱动该 bug 并对其症状断言，可红可绿，确定、快、agent 可跑。
优先顺序：
1. 失败测试（unit/integration/e2e，取能触达 bug 的最高 seam）
2. curl/HTTP 脚本对 dev server
3. CLI 调用 + diff 标准输出
4. headless 浏览器脚本（Playwright）
5. 重放捕获的网络/日志
6. 一次性最小 harness（单服务/mock 依赖）
7. property/fuzz（"偶发错"时 1000 随机输入）
8. bisection harness（两个状态间 `git bisect run`）
9. differential（新旧版本跑同输入 diff）
10. HITL 脚本（最后手段，结构化记录）

**重建标准**：一个能复现用户所述 bug 的 tight loop；不追求 clean repro（对偶发 bug 是提高复现率）。

### Phase 2 · 复现 + 最小化
- 跑 loop，确认出现用户描述的症状（不是旁边别的 bug）。
- 逐个裁减输入/调用/配置，最小到仍红；剩下每个元素都是 load-bearing。

### Phase 3 · 多假设排名
- 列 3-5 个可证伪假设（"若 X 是因，改变 Y 会让 bug 消失/更糟"），修复前给用户看（可能重排）；用户 AFK 则按自己排名继续。

### Phase 4 · 插桩
- 每个探针对应一个假设；一次只变一个变量。
- 偏好 debugger/REPL 一次断点 > 十条日志；日志打唯一前缀 `[DEBUG-xxxx]`（便于清理）。
- 性能回归：先量基线再二分，不靠日志。

### Phase 5 · 修复 + 回归测试
- 有正确 seam：最小化复现 → 转成失败测试 → 让它红 → 修复 → 绿 → 重跑原始 loop。
- 无正确 seam（单调用者浅 seam）→ 这是发现本身：注明，flag 到下一步。

### Phase 6 · 清理（声明完成前）
- 原始 bug 不再复现；回归测试通过（或注明无 seam）；`[DEBUG-*]` 全删；一次性原型移除；提交/PR message 写对 hypotheses 中命中那一条。

## 四、原型（prototype，设计不确定时）

- 状态/逻辑问题 → 单可分享 HTML 文件；UI 变化问题 → 几版可切换变体。
- 产物服务于决策：STale 短，结论纳入 Spec/决策；不留入交付（或显式 prototype/ 标记）。