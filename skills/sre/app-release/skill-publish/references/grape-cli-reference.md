# grape CLI 参考（skill-publish 子集）

> 本文件是 **grape CLI 命令契约**（v0.3.x，经 `grape commands` 核对）。skill-publish 只用其中两族命令：**Issue 评论** + **任务管理**。外部平台（ClawHub API / GitHub / GitCode push）**不走 grape CLI**——ClawHub 见 SKILL 4.4「ClawHub payload 契约」，GitHub/GitCode 见 `scripts/sync_skill_platform.sh`。

## 1. 安装与自愈

前置检查发现 `grape` 未安装或版本过低（< 0.3.2）→ 按 `references/grape-cli-installation.md` 自动安装/升级，不直接报障。

## 2. 认证（自动，无需配置）

`grape` 自动读取服务端注入的 `$GRAPE_SESSION_TOKEN`——**严禁**寻找/读取其他 token 用于 grape 命令。

> ⚠️ 两套 token 严格区分：
> - **平台交互（评论/任务）** → grape CLI 自动读 `$GRAPE_SESSION_TOKEN`，什么都不用配
> - **外部平台（ClawHub/GitHub/GitCode）发布** → 按 SKILL 硬约束①分两类：GitCode = 运行时 GIT_ASKPASS（不接触值）；ClawHub/GitHub = 用户高级选项配置 name=CLAWHUB_TOKEN/GITHUB_TOKEN（平台按 name 直注同名 env，GitHub 另有 BOT_GITHUB_TOKEN 兜底），供 curl / sync 脚本使用，与 grape token 无关

## 3. 命令子集（本技能真实使用）

### 3.1 Issue 评论

```bash
# 发 Issue 评论（发布/下架完成告知、参数缺失、跳过原因、失败原因等一律走这里）
grape git-repo issues comments create \
  --owner "${REPO_FULL_NAME%/*}" --repo "${REPO_FULL_NAME#*/}" \
  --number "$ISSUE_NUMBER" \
  --json '{"body": "[SRE Agent] ✅ Skill 发布完成\n\n{评论内容}"}'
```

- `owner`/`repo` 从 `$REPO_FULL_NAME` 拆分（`%/*` 取 owner，`#*/` 取 repo）
- 评论 body 一律以 `[SRE Agent]` 开头（见 SKILL 4.6 输出格式）
- 失败平台汇总、跳过原因、安装命令等明细都放评论 body，格式见 SKILL 4.6 输出格式（发布结果表）

### 3.2 任务管理

```bash
grape tasks current          # 查看当前任务（可选，确认上下文）
grape tasks complete --json '{"result_text": "<处理结论>", "actions": [...], "conclusion": "...", "artifacts": [...], "next_step": "..."}'
# 收尾协议：发布/下架全部业务动作完成后，先调 tasks complete，再输出 JSON 块（见 SKILL 4.8 任务收尾）
```

## 4. ❌ 不存在的命令（防误用，禁止尝试）

| 命令 | 说明 |
|------|------|
| `grape tasks close / mine / start / status / clarify` | tasks 组仅有 complete/current/notify/wait |
| `grape git xxx`（透传） | git 操作不存在透传，发布/备份用原生 git（脚本封装） |
| `grape api` | 已移除（0.2.2 起），且平台禁止直连 API |
| `grape knowledge context/content` | 不存在，知识基线由 prompt 内联注入 |
| `grape events detail --seq` | --seq 平台不注入，勿用 |

## 5. 退出码 与 安全边界

- 命令失败：检查输出错误信息（401=token 无效 / 403=无权限），按 SKILL 硬约束④区分处理——**不重试、不用其他 token 绕行**
- 安全边界：不用 grape commands 之外的方式拼平台 API；token 不落盘/不进日志/不进评论/不进脚本文件