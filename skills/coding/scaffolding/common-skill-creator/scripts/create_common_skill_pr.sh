#!/usr/bin/env bash
# ============================================================================
# create_common_skill_pr.sh — Coding Agent 创建 GitCode PR 的脚本(grape CLI 版)
#
# 职责：git commit + push → grape pulls 幂等查重 → grape pulls create
#       (+ update 补 body，契约 PRCreateBody 已支持 body——update 补写为幂等双保险)
#       → base 校验 → 输出 PR URL
# 复用 worktree 已有分支 feat/issue-{N}，不另建分支。
#
# 用法：
#   create_common_skill_pr.sh <skill_name> [--base <branch>]
#
# 环境变量（已由系统注入，不用查 env）：
#   REPO_FULL_NAME     仓库全名 owner/repo（必填）
#   ISSUE_NUMBER       Issue 编号（必填）
#   平台认证：grape CLI 自动读取 $GRAPE_SESSION_TOKEN，无需手动配置
#
# 退出码：0=成功（创建或复用 PR）；1=参数/环境错误；2=调用失败
# ============================================================================
set -uo pipefail

SKILL_NAME="${1:-}"
if [[ -z "$SKILL_NAME" ]]; then
  echo "[create_common_pr] ERROR: skill_name 必填"
  exit 1
fi

# --base 覆盖（默认走仓库默认分支）
BASE_OVERRIDE=""
if [[ "${2:-}" == "--base" && -n "${3:-}" ]]; then
  BASE_OVERRIDE="$3"
fi

REPO_FULL="${REPO_FULL_NAME:-}"
ISSUE_NUM="${ISSUE_NUMBER:-}"

if [[ -z "$REPO_FULL" ]]; then
  echo "[create_common_pr] ERROR: REPO_FULL_NAME 未设置"
  exit 1
fi
if [[ -z "$ISSUE_NUM" ]]; then
  echo "[create_common_pr] ERROR: ISSUE_NUMBER 未设置"
  exit 1
fi
if ! command -v grape >/dev/null 2>&1; then
  echo "[create_common_pr] ERROR: grape CLI 未安装或不在 PATH（安装见 skill references/grape-cli-installation.md）"
  exit 1
fi

# 解析 owner/repo
OWNER="${REPO_FULL%%/*}"
REPO="${REPO_FULL#*/}"
BRANCH="feat/issue-${ISSUE_NUM}"

log() { echo "[create_common_pr] $*"; }

# ============================================================================
# 0. 获取仓库默认分支（不硬编码 main——目标仓库默认分支可能是 master）
# ============================================================================
if [[ -n "$BASE_OVERRIDE" ]]; then
  BASE_BRANCH="$BASE_OVERRIDE"
  log "base 覆盖: ${BASE_BRANCH}"
else
  log "获取仓库默认分支: grape git-repo repo"
  DEFAULT_BRANCH=$(grape git-repo repo --owner "$OWNER" --repo "$REPO" --json-out \
    | python3 -c "import json,sys; print((json.load(sys.stdin).get('default_branch') or ''))" 2>/dev/null || true)
  if [[ -z "$DEFAULT_BRANCH" ]]; then
    log "WARNING: 无法获取默认分支，回退 main"
    BASE_BRANCH="main"
  else
    BASE_BRANCH="$DEFAULT_BRANCH"
  fi
  log "默认分支: ${BASE_BRANCH}"
fi

# ============================================================================
# 1. git commit + push（在当前 worktree 执行，分支已是 feat/issue-{N}）
# ============================================================================
log "git add skills/${SKILL_NAME}/"
git add "skills/${SKILL_NAME}/" 2>/dev/null || {
  log "WARNING: git add skills/${SKILL_NAME}/ 没有变更（可能已提交）"
}

# 检查是否有待提交的变更
if git diff --cached --quiet 2>/dev/null; then
  log "无新变更待提交（可能已 commit 过），跳过 commit"
else
  log "git commit"
  git commit -m "feat(skill): 新增 ${SKILL_NAME}" || {
    log "ERROR: git commit 失败"
    exit 2
  }
fi

log "git push origin ${BRANCH}"
git push origin "$BRANCH" 2>&1 | sed 's/^/[create_common_pr] /' || {
  log "ERROR: git push 失败"
  exit 2
}

# ============================================================================
# 2. 幂等查重：同分支已有 open PR → 复用
# ============================================================================
log "查重: grape git-repo pulls list --state open"
PR_NUMBER=$(grape git-repo pulls list --owner "$OWNER" --repo "$REPO" --state open --per_page 100 --json-out \
  | python3 -c "
import json, sys
try:
    for pr in json.load(sys.stdin):
        head = pr.get('head') or {}
        ref = head.get('ref', '') if isinstance(head, dict) else ''
        if ref == '${BRANCH}':
            print(pr.get('number', ''))
            break
except Exception:
    pass
" 2>/dev/null)

if [[ -n "$PR_NUMBER" ]]; then
  PR_URL="https://gitcode.com/${OWNER}/${REPO}/merge_requests/${PR_NUMBER}"
  log "复用已有 open PR #${PR_NUMBER} (${PR_URL})"
  echo "PR_URL=${PR_URL}"
  echo "PR_NUMBER=${PR_NUMBER}"
  exit 0
fi

# ============================================================================
# 创建 PR（create 直接传契约字段 related_issue_nums/auto_close_issues；body 契约已支持——
#   下方 update 补写为幂等双保险，非必需）
# ============================================================================
log "创建 PR: grape git-repo pulls create  base=${BASE_BRANCH} head=${BRANCH}"
CREATE_RESP=$(grape git-repo pulls create \
  --owner "$OWNER" --repo "$REPO" \
  --json "{
    \"title\": \"feat(skill): 新增 ${SKILL_NAME}\",
    \"head\": \"${BRANCH}\",
    \"base\": \"${BASE_BRANCH}\",
    \"related_issue_nums\": [\"${OWNER}/${REPO}#${ISSUE_NUM}\"],
    \"auto_close_issues\": true
  }" 2>/dev/null)

if [[ -z "$CREATE_RESP" ]]; then
  echo "[create_common_pr] ERROR: 创建 PR 失败（grape 无输出）" >&2
  exit 2
fi
PR_NUMBER=$(echo "$CREATE_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('number',''))" 2>/dev/null || true)
if [[ -z "$PR_NUMBER" ]]; then
  log "ERROR: 创建响应无 PR number"
  echo "$CREATE_RESP" | head -c 500
  echo ""
  exit 2
fi

# 补 PR body（契约字段 related_issue_nums/auto_close_issues 已在 create 传入；update 补 body 为幂等双保险——失败不阻塞——PR 已创建）
PR_BODY="## 新增 Skill: ${SKILL_NAME}\n\n由 common-skill-creator 自动创建（五阶段流水线生成：需求/设计/生成/验证/eval）\n\nFixes #${ISSUE_NUM}"
if grape git-repo pulls update \
  --owner "$OWNER" --repo "$REPO" --number "$PR_NUMBER" \
  --json "{\"body\": \"${PR_BODY}\"}" >/dev/null 2>&1; then
  log "PR body 已补充"
else
  log "WARNING: PR body 补充失败（不影响 PR 创建，base 校验继续）"
fi

PR_URL="https://gitcode.com/${OWNER}/${REPO}/merge_requests/${PR_NUMBER}"
log "PR 已创建 #${PR_NUMBER} (${PR_URL})"

# ============================================================================
# 4. base 校验（防 base 写错）
# ============================================================================
log "base 校验: grape git-repo pulls get"
ACTUAL_BASE=$(grape git-repo pulls get --owner "$OWNER" --repo "$REPO" --number "$PR_NUMBER" --json-out \
  | python3 -c "import json,sys; print(((json.load(sys.stdin).get('base') or {}).get('ref','')) or '')" 2>/dev/null || true)
if [[ "$ACTUAL_BASE" != "$BASE_BRANCH" ]]; then
  log "ERROR: PR base 校验不过: 期望 ${BASE_BRANCH}, 实际 ${ACTUAL_BASE:-未知}"
  exit 2
fi
log "base 校验通过: base=${ACTUAL_BASE}"

# ============================================================================
# 5. 设置审查人 —— ⚠️ grape CLI 0.3.3 无 assignees 接口，跳过
#    （审查人缺省不影响 PR 创建与 tester 测试，如需要请人工在平台指派）
# ============================================================================

# ============================================================================
# 6. 输出
# ============================================================================
echo ""
echo "PR_URL=${PR_URL}"
echo "PR_NUMBER=${PR_NUMBER}"
log "完成: ${PR_URL}  (base=${BASE_BRANCH}, 分支=${BRANCH})"