# 上传流程与触发点

> 本文件描述 skill-uploader 的触发点判定、token 前置检查、ZIP 打包规范与失败处理。
> 命令以 `grape skills upload --help` 实际输出为准。

---

## §一 触发点判定

skill-uploader 在 skill 创建流水线末端被触发，存在两个触发点：

| 触发点 | 时机 | 触发方式 | 上传性质 |
|--------|------|---------|---------|
| (b) | QA Agent 审查通过后 | QA 通过 A2A 交棒（context 含「审查通过」「skill ready」） | 预注册（便于合并前联调验证） |
| (c) | PR 合并后 | PR merge 事件 / SRE 合并后 A2A（context 含「PR merged」） | 正式注册（合并后最终内容） |

### 判定规则（按顺序）

1. 读取 A2A context / 事件 payload 中的关键词：
   - 含「审查通过」/「QA passed」/「skill ready」→ 触发点 (b)
   - 含「PR merged」/「已合并」/「merge」→ 触发点 (c)
2. 触发点 (c) 时，先用 `grape git-repo pulls get --owner {owner} --repo {repo} --number {pr} --json-out` 确认 PR 状态为 `merged`；未合并 → 停止，不重复上传。
3. 触发点 (b) 时，确认 QA 评论中含「审查通过」；未通过 → 停止。
4. 同一 skill 已在 (b) 上传过、(c) 再次触发 → 视为更新覆盖上传（服务端按 skill_name + scope 去重覆盖）。

### skill 目录定位

- 从 PR 变更文件清单（`grape git-repo pulls files`）中筛出 `skills/` 前缀的目录路径。
- 目录路径形态二选一：
  - `skills/{agent_type}/{name}/`（如 `skills/coding/implementation/`）
  - `skills/{name}/`（如 `skills/grape-cli-guidance/`）
- agent_type 取值：vod / issue / coding / qa / sre；若 skill 直接位于 `skills/{name}/`（无 agent_type 层），`--agent_type` 传该 skill 主要使用方，缺省 `sre`。

---

## §二  ZIP 打包规范

### 打包命令

```bash
cd {worktree_root}                        # worktree 根（含 skills/ 目录）
zip -r /tmp/{skill_name}.zip skills/{path}/   # path = agent_type/name 或 name
```

### ZIP 结构要求

服务端解包后需在根层看到 SKILL.md。正确结构：

```
{name}.zip
└── skills/{path}/
    ├── SKILL.md
    └── references/
        ├── ...
```

- **不要**把 worktree 外层目录（如 repo 根的 README.md、src/）打进 ZIP。
- **不要**从 skill 目录内部打包（会导致 ZIP 内无 `skills/` 前缀，服务端可能无法定位）。
- 打包后校验：`unzip -l /tmp/{name}.zip | head` 确认首层为 `skills/{path}/SKILL.md`。

### agent_type 推断

| skill 目录路径 | --agent_type 取值 |
|---------------|------------------|
| `skills/coding/{name}/` | `coding` |
| `skills/qa/{name}/` | `qa` |
| `skills/sre/{name}/` 或 `skills/sre/` | `sre` |
| `skills/issue/{name}/` | `issue` |
| `skills/vod/{name}/` | `vod` |
| `skills/{name}/`（无 agent_type 层） | 从 A2A context 取；缺省 `sre` |

---

## §三 失败处理

| 错误 | 含义 | 处理 |
|------|------|------|
| HTTP 422 | 请求体/ZIP 格式错误 | 检查 ZIP 结构（§三）；评论附 `detail` 错误信息，A2A 回 coding 排查 skill 内容 |
| HTTP 500 / 502 / 503 | 服务端异常 | 重试 1 次（间隔 5s）；仍失败 → 评论报障，任务结束 |
| 上传 200 但验证未命中 | 上传可能未生效 | 重试上传 1 次；仍不命中 → 评论报障，附 skill_id（若有）|
| ZIP 打包失败（zip 命令缺失） | 环境无 zip | 改用 `python -c "import shutil; shutil.make_archive(...)"`；仍失败报障 |

### 失败后 A2A（非 token 原因）

```bash
grape a2a handoff --json '{"agent":"coding","payload":{"repository":"{owner}/{repo}","account":"{user}","issue_number":{n},"pr_number":{pr},"context":"skill {name} 上传失败：{错误摘要}，请排查 skill 目录/ZIP 格式"}}'
```
