# 咨询需求流程（consult-flow）

> 适用：「这个项目是干什么的 / 有哪些功能 / 怎么安装 / 怎么部署 / 怎么使用」等项目信息询问。
> 核心：**VOD 阶段闭环**——只读查询 + Issue 评论答复，**不 A2A、不建 Issue**。

## 0. 边界

- ✅ 只读查询项目/仓库/能力信息 → 评论礼貌答复。
- ❌ 不修改任何状态、不建 Issue、不 A2A、不执行任务、**不做部署/启动/资源操作**。

## 1. 只读查询（用 grape CLI）

```bash
# 项目 / 仓库
grape repos project info --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out      # 知识基线（结构/能力摘要）
grape git-repo repo --owner "$REPO_OWNER" --repo "$REPO_NAME" --json-out           # 仓库元信息

# 结构 / 文件 / 能力
grape git-repo tree --owner "$REPO_OWNER" --repo "$REPO_NAME" --depth single --json-out
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path README.md --raw
grape git-repo contents --owner "$REPO_OWNER" --repo "$REPO_NAME" --path {docs/spec 等} --json-out   # 按需

# 状态（Issue/PR/commit 若问题涉及）
grape issues detail --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" --json-out
grape git-repo pulls get --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$PR_NUMBER" --json-out  # 按需
grape git-repo commits --owner "$REPO_OWNER" --repo "$REPO_NAME" --per_page 20 --json-out            # 按需
```

## 2. 组织答复（评论发布，VOD 闭环）

- 基于查到的事实答复，**先打开原对象核对**，不凭记忆/推断；未查到/403 → 如实说明。
- Issue 评论答复（body 以 `[VOD Agent]` 开头，Markdown 链接格式）：
```bash
grape git-repo issues comments create --owner "$REPO_OWNER" --repo "$REPO_NAME" --number "$ISSUE_NUMBER" \
  --json '{"body":"[VOD Agent] {答复内容，关键信息加粗、引用用 Markdown 链接}"}' --json-out
```
- **不建新 Issue、不 A2A**。

## 3. 收尾

回到 `vod-runbook.md` Step 4（tasks complete，next_step=`reply_comment`）。