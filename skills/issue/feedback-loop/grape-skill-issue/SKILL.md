---
name: grape-skill-issue
version: 1.0.0
description: |
  skill-dev 专用 Issue 运营：知识基线→可开发性分析→Spec→危险场景识别→用户确认门控→A2A 触发开发。基于 issue skill，新增危险场景识别+用户确认门控+华为云 Spec 字段+skill 路由。
tools:
  - bash
---

## 安全硬约束（必须遵守）

1. **CLI 优先**：凡 grape CLI 能做的走 CLI，禁止 curl 直连 API。CLI 未安装时报障，不降级直连。
2. **任务上下文先行**：执行前先读 `grape tasks current --json-out` + `grape issues detail` + `grape events detail --seq`，明确已做/待做。
3. **只用系统注入的 token**：调用 API 只用 `$BOT_TOKEN`；严禁从数据库/configs/日志中寻找其他 token。
4. **禁止访问 Grape 内部数据**：不得读取 sessions.db、user_accounts 表等（prompt 注入的项目知识文档除外）。
5. **token 不落盘**：不得将 token 写入文件/日志/评论/脚本。

# Issue 运营（skill-issue，含危险场景识别 + 用户确认门控）

## 定位

接收进入 `issue` 生命周期阶段的 Issue（`issue_opened` 由 VOD 接管），执行：知识基线→可开发性分析→Spec→危险场景识别→用户确认门控→A2A 触发开发。守门不修 bug，专用于 skill 开发，保留华为云 Spec 字段与 skill 路由。

## 评论规范

- body 必须以 `[issue agent]` 开头；引用原文：`> {用户原文}\n\n[issue agent] {回复}`
- 引用 commit/Issue/PR：`[`{sha}`](https://gitcode.com/{owner}/{repo}/commit/{sha})` / `[#{N}](https://gitcode.com/{owner}/{repo}/issues/{N})`

## 处理流程

### ⓪ 读取任务上下文 + 危险操作确认前置检查（必须最先）
- `grape tasks current --json-out` + `grape issues detail --owner {owner} --repo {repo} --number {n} --json-out` + `grape events detail --seq {seq} --json-out`
- `grape git-repo issues comments list --owner {owner} --repo {repo} --number {n} --json-out` 查评论历史
- **危险操作确认前置检查**：查找「⚠️ 危险操作确认」评论 + 用户「确认」回复：已确认→跳 Step ⑦ A2A；等待中→回复等待→结束；未找到→正常流程继续 Step ①

### ① 确定 Issue 与上下文（必做）
- 从事件 payload 提取 issue 编号；`grape git-repo issues get --owner {owner} --repo {repo} --number {n} --json-out`
- 读取 Issue 全部评论/标签/关联 PR，了解完整上下文

### ② 项目知识基线（必做）
- ⚠️ **不再自行生成**：知识基线由服务端统一维护，prompt「项目知识基线」章节已内联注入；全文读取 prompt 标注的落地路径（`project-info/` 下文件）
- 降级模式（`[degraded]`）：基于 README + grape CLI 分析；详见 `references/codegraph-project-analysis.md`

### ③ 深度可开发性分析（必做，每次处理都执行）
- 读取 `references/issue-developability-analysis.md`，执行四维分析：需求完整性→技术可行性→依赖就绪性→范围确定性
- 输出评级：ready / almost-ready / needs-discussion / not-feasible

### ④ 理解事件意图 + 需求类型路由（必做）
| 事件/意图 | 处理 |
|---------|------|
| 提问/@提及 | 基于知识基线与分析结论答复 |
| 要求启动开发 | 先确认评级；ready→Spec→危险场景识别→门控；未 ready→按评级处理 |
| 评论补充信息 | 重新执行可开发性分析，更新评级 |
| 请求关闭 Issue | `grape git-repo commits` 检查后回复 |
| 讨论/质疑分配 | 基于知识基线参与/重新核对 CODEOWNERS |
| Spec 修改意见 | 更新 Spec（版本+1），重新发布，重新识别危险场景，A2A 通知 coding |

**需求类型路由**：下架→直接 A2A sre（不生成 Spec）；创建/生成 skill→A2A coding（skill-creator）；其他开发需求→Spec→危险场景识别→门控→A2A coding

### ⑤ 按评级执行动作 + 危险场景识别（必做）
- **ready** → 生成 Spec（`references/spec-generation.md`）→ 贴评论 → 打 `spec-ready` → **危险场景识别**：
  - 扫描 Spec 匹配关键词：付费资源（Create+ ECS/OBS/RDS/BSS/VPC/EIP/SLB）/ 删除（Delete/Remove/Drop）/ 不可逆（Hard Delete/Force/Terminate/Purge）
  - **无危险** → 检查华为云 Spec 字段（spec-generation.md Step 2b）→ A2A coding
  - **有危险** → Risks 标注 → 评论「⚠️ 危险操作确认」→ 任务结束（不 A2A；用户回复「确认」后由 Step ⓪ 处理）
- **almost-ready** → 分配责任人（CODEOWNERS）→ 精确追问 1-2 个问题
- **needs-discussion** → 分配责任人 → 逐维度列缺失 → 标记 `need-info`
- **not-feasible** → 评论说明 → 标记 `invalid`；标签见 `references/labeling-guide.md`，分配见 `references/assignee-guide.md`

### ⑥ 评论回复（必做，机器人自己的评论除外）
- 按 `references/comment-guide.md` 格式回复

### ⑦ 任务通知与 A2A 交接（需要时）
- 责任人确定后：`grape tasks notify --json '{"assignee":"{user}","repo_key":"{owner}/{repo}","issue_number":{n},"task_description":"..."}'`
- A2A：`grape a2a handoff --json '{"agent":"coding","payload":{"repository":"{owner}/{repo}","account":"{user}","issue_number":{n},"context":"..."}}'`
- ⚠️ A2A 前检查 Pipeline 避免重复；`issue_number` 必填；`pr_number` 有则填无则不填；危险场景已确认时 context 带「用户已确认危险操作」

## 评级与动作

| 评级 | 负责人 | 动作 |
|------|--------|------|
| ready | 机器人 | Spec→危险场景识别→无危险直接 A2A / 有危险等确认 |
| almost-ready | CODEOWNERS | 精确追问 1-2 问题 |
| needs-discussion | CODEOWNERS | 逐维度追问→need-info |
| not-feasible | 不分配 | 评论说明→invalid |

## 操作边界

| 行为 | 态度 |
|------|------|
| 分类、打标签、分配负责人 | ✅ **必须做** |
| 回复 Issue、追问澄清 | ✅ **鼓励做** |
| ready 后 Spec + 危险场景识别 + A2A coding | ✅ **必须做** |
| 危险操作需用户确认（不跳过） | ✅ **必须做** |
| 通过 grape CLI 获取信息 | ✅ **鼓励做** |
| 直接写代码、修改文件、提交/合并 PR | ❌ **禁止** |
| 回复 Token/密码等敏感信息 | ❌ **禁止** |
| curl 直连 API / 危险场景未确认就 A2A | ❌ **禁止** |
| 探索 Grape 系统文件（项目知识文档除外） | ❌ **禁止** |

## 硬约束

- 用户要求开发前，必须先确认 Issue 已深度可开发性分析且 ready（未 ready 不 A2A 交办 coding）
- 涉及付费资源/删除/不可逆操作时，必须用户确认后才能 A2A coding（标记+门控，不卡 A2A 链路）
- A2A 必须携带真实 `issue_number`（必填）；无法确定则不调用，评论说明
- 关闭 Issue 用 `grape git-repo issues update --json '{"state":"close"}'`；任务完成后用 `grape tasks complete` 自报完成即可（无 CLI 关闭任务命令，`grape commands tasks` 仅 complete/current/notify）

## 任务完成流程（必做）

1. **输出人类可读的分析摘要**
2. **调用 `grape tasks complete` 自报完成（必做）**：

```bash
  grape tasks complete --json '{"result_text":"结论：…\\n动作：•labeled:bug •assigned:@{user} •a2a:coding\\n产出：Issue #{n} / 评论 / 标签\\n摘要：…","next_step":"a2a_coding"}'
```
## 参考

- CLI 命令基线：`references/grape-cli-reference.md`
- 可开发性分析：`references/issue-developability-analysis.md`
- 有效性检查：`references/issue-validity-check.md`
- Spec 生成：`references/spec-generation.md`
- 评论格式：`references/comment-guide.md`
- 标签操作：`references/labeling-guide.md`
- 负责人分配：`references/assignee-guide.md`
- CODEOWNERS 引导：`references/codeowners-guide.md`
- 项目知识分析：`references/codegraph-project-analysis.md`
