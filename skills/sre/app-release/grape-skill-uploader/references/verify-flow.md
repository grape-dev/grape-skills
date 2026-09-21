# 上传后验证流程

> 上传成功后必须验证 skill 已注册且内容可读。

---

## §一 验证步骤

### 1. skills list 确认已注册

```bash
grape skills list --scope repo --repo {owner}/{repo} --json-out
```

- 在返回列表中按 `name` 字段匹配待上传 skill 名称。
- 命中 → 记录 `skill_id`，进入步骤 2。
- 未命中 → 上传可能未生效，重试上传 1 次（回 SKILL.md 步骤④）；仍未命中 → 报障。

### 2. skills detail 确认 SKILL.md 可读

```bash
grape skills detail --skill_id {id} --json-out
```

- 返回应包含 `skill_md`（SKILL.md 原文）或 `content` 字段。
- 校验要点：
  - frontmatter 的 `name` 与目录名一致
  - SKILL.md 非空、非截断
  - references 引用路径在 detail 返回的 sub-skills 列表中存在（若有）
- 内容异常 → 评论说明，A2A 回 coding 排查。

### 3. （可选）skills sub list 确认 references 完整

```bash
grape skills sub list --skill_id {id} --json-out
```

- 列出 skill 包 references/ 下的子文件，确认上传的 reference 文件齐全。
- 缺失 → 重新打包上传（ZIP 可能遗漏 references/）。

---

## §二 验证结果判定

| 结果 | 判定 | 动作 |
|------|------|------|
| list 命中 + detail SKILL.md 可读 + references 齐全 | ✅ 上传成功 | Issue 评论告知，任务完成 |
| list 命中 + detail SKILL.md 异常 | ⚠️ 内容问题 | 评论附异常，A2A coding 修复后重传 |
| list 未命中 | ❌ 上传未生效 | 重试上传 1 次；仍失败报障 |
| detail 404 | ❌ skill_id 无效 | 重新 list 获取最新 skill_id |

---

## §三 成功评论模板

```
[Skill Uploader Agent] skill {name} 已上传注册为仓库级 skill。
- scope: repo
- repo: {owner}/{repo}
- agent_type: {agent_type}
- skill_id: {id}
```

---

## §四 幂等说明

- 同名 skill（scope=repo + repo + skill_name）重复上传时服务端按覆盖更新处理，不会产生重复记录。
- 触发点 (b) 上传后，(c) 再触发视为更新覆盖（内容为合并后最终版本）。
- 验证以最新 `skill_id` 为准（覆盖后 skill_id 可能不变或更新，以 list 返回为准）。
