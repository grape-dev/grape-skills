# grape CLI 命令参考

## 1. 安装

```bash
pip install grape-cli
# 或从源码安装
pip install git+https://gitcode.com/grape-dev/grape-cli.git
```

验证安装：

```bash
grape --version
grape --help
```

## 2. 认证与配置

### Token 配置

grape CLI 支持三种认证方式（优先级从高到低）：

| 方式 | 参数 | 说明 |
|------|------|------|
| 命令行 | `--token tk_xxx` | 单次最高优先级 |
| 环境变量 | `GRAPE_API_TOKEN` | 会话级 |
| 配置文件 | `~/.grape/config.yaml` | 持久化 |

```bash
# 单次使用
grape --token "$BOT_TOKEN" --base-url https://api.gitcode.com tasks mine

# 或设置环境变量
export GRAPE_API_TOKEN="$BOT_TOKEN"
grape tasks mine
```

### Base URL

```bash
grape --base-url https://api.gitcode.com --token "$BOT_TOKEN" git-repo issues list --owner XOcto --repo grape-cli
```

## 3. 常用命令

### Issue 管理

| 命令 | 说明 |
|------|------|
| `grape git-repo issues list --owner <o> --repo <r>` | Issue 列表 |
| `grape git-repo issues get --owner <o> --repo <r> --number <n>` | Issue 详情 |
| `grape git-repo issues create --owner <o> --repo <r>` | 创建 Issue |
| `grape git-repo issues update --owner <o> --repo <r> --number <n>` | 更新 Issue |
| `grape git-repo issues comments list --owner <o> --repo <r> --number <n>` | Issue 评论列表 |
| `grape git-repo issues comments create --owner <o> --repo <r> --number <n>` | 创建 Issue 评论 |

### PR 管理

| 命令 | 说明 |
|------|------|
| `grape git-repo pulls list --owner <o> --repo <r>` | PR 列表 |
| `grape git-repo pulls create --owner <o> --repo <r>` | 创建 PR |
| `grape git-repo pulls get --owner <o> --repo <r> --number <n>` | PR 详情 |
| `grape git-repo pulls merge --owner <o> --repo <r> --number <n>` | 合并 PR |
| `grape git-repo pulls files --owner <o> --repo <r> --number <n>` | PR 变更文件 |

### 仓库操作

| 命令 | 说明 |
|------|------|
| `grape git-repo repo --owner <o> --repo <r>` | 仓库信息 |
| `grape git-repo branches --owner <o> --repo <r>` | 分支列表 |
| `grape git-repo commits --owner <o> --repo <r>` | 提交历史 |
| `grape git-repo contents --owner <o> --repo <r> --path <p>` | 文件内容 |
| `grape git-repo git credential --owner <o> --repo <r>` | 一次性 git 凭据 |

### Git 透传

```bash
grape git clone https://gitcode.com/owner/repo.git
grape git checkout feat/issue-5
grape git add .
grape git commit -m "feat: deploy skill refactor"
grape git push origin feat/issue-5
```

`grape git` 透传 git 原生命令，进程内注入凭据，token 不落盘。

### 任务管理

| 命令 | 说明 |
|------|------|
| `grape tasks create` | 新建任务（同步建 Issue） |
| `grape tasks start --task-id <id>` | 打开任务会话 |
| `grape tasks status get --task-id <id>` | 查询任务状态 |
| `grape tasks status --task-id <id> --status <s>` | 更新任务状态 |
| `grape tasks complete --json '{"result_text":"...","next_step":"done"}'` | 任务完成自报（会话 token 自动定位，无需 --task-id） |
| `grape tasks mine` | 我的任务列表 |
| `grape tasks wait --task-id <id> --timeout 120` | 轮询至终态 |
| `grape tasks close` | 关闭 Issue 的任务 |

### A2A 交办

```bash
grape a2a handoff --agent qa \
  --repository "$REPO_FULL_NAME" \
  --issue-number "$ISSUE_NUMBER" \
  --pr-number "$PR_NUMBER" \
  --context "部署完成，请验证"
```

### 通用 API 兜底

```bash
grape api GET /api/repos/XOcto/grape-cli
grape api POST /api/repos/XOcto/grape-cli/issues/5/comments -d '{"body":"评论内容"}'
```

### 其他

| 命令 | 说明 |
|------|------|
| `grape refresh` | 刷新契约缓存 |
| `grape commands` | 列出所有命令 |
| `grape skills list` | 技能列表 |
| `grape knowledge list` | 知识清单 |
| `grape events detail --seq <n>` | 事件详情 |

## 4. 命令限制

| 限制 | 说明 |
|------|------|
| 超时 | 默认 30s，可 `--timeout 120` 调整（git 透传不受限） |
| 分页 | `?page=1&per_page=20`，最大 per_page=100 |
| Rate Limit | VCS API: 400 req/min, 4000 req/hour |
| 契约依赖 | 契约命令从 `openapi.json` 动态生成，`grape refresh` 更新 |
| 凭据注入 | `grape git` 进程内注入，不写入 git config 或文件 |

## 5. 退出码

| 退出码 | 含义 |
|--------|------|
| 0 | 成功 |
| 1 | 通用/配置错误（缺 token、网络超时等） |
| 2 | 用法错误（click 参数错误） |
| =HTTP(≥400) | API 错误透传（如 401 鉴权失败） |
| 130 | Ctrl+C 用户中断 |

## 6. 安全与边界

1. **只用系统注入的 token**：`$BOT_TOKEN`，不得从数据库/配置文件/日志/历史中寻找其他 token。
2. **禁止访问 Grape 内部数据**：不得读取 data/、configs/、sessions.db、user_accounts 等。
3. **403 处理**：API 返回 403 时停止操作，回复用户「需要管理员/维护者权限」。
4. **token 不落盘**：`grape git` 进程内注入凭据，不写入 git config；其他命令通过 header 传递。
5. **超时必设**：所有 API 调用默认 30s 超时，超时判定失败不 hang。
