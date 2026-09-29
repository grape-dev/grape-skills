#!/usr/bin/env bash
#
# validate-skill.sh — Validate a skill directory against the Agent Skills specification
#
# Usage: bash scripts/validate-skill.sh <skill-path> [--fix]
#
# Checks:
#   1. SKILL.md exists
#   2. name field: valid format, <=64 chars, matches parent directory
#   3. description field: non-empty, <=1024 chars
#   4. Frontmatter is valid YAML
#   5. SKILL.md <= 500 lines
#   6. File references are relative, one level deep
#   7. No hardcoded credential patterns
#   8. Scripts have no interactive input (basic scan)
#   9. Scripts provide --help (optional check)
#
# Exit codes:
#   0 = all critical checks passed (warnings allowed)
#   1 = one or more critical checks failed
#   2 = usage error
#
set -euo pipefail

# --- Functions ---

print_pass() {
    echo "  [PASS] $1"
}

print_warn() {
    echo "  [WARN] $1"
}

print_fail() {
    echo "  [FAIL] $1"
    FAILED=1
}

# --- Argument parsing ---

if [ $# -lt 1 ]; then
    echo "Usage: bash scripts/validate-skill.sh <skill-path> [--fix]"
    echo ""
    echo "Validate a skill directory against the Agent Skills specification."
    echo ""
    echo "Arguments:"
    echo "  <skill-path>  Path to the skill directory to validate"
    echo "  --fix         Attempt to auto-fix minor issues (not implemented for all checks)"
    echo ""
    echo "Exit codes:"
    echo "  0 = all critical checks passed"
    echo "  1 = one or more critical checks failed"
    echo "  2 = usage error"
    exit 2
fi

SKILL_PATH="$1"
DO_FIX=false
if [ "${2:-}" = "--fix" ]; then
    DO_FIX=true
fi

FAILED=0
WARN_COUNT=0

# --- Resolve paths ---

if [ ! -d "$SKILL_PATH" ]; then
    echo "Error: directory does not exist: $SKILL_PATH"
    exit 2
fi

SKILL_PATH="$(cd "$SKILL_PATH" && pwd)"
SKILL_MD="$SKILL_PATH/SKILL.md"
DIR_NAME="$(basename "$SKILL_PATH")"

echo "============================================"
echo "  Skill Validation Report"
echo "  Path: $SKILL_PATH"
echo "============================================"
echo ""

# --- Check 1: SKILL.md exists ---

echo "1. File existence"
if [ -f "$SKILL_MD" ]; then
    print_pass "SKILL.md exists"
else
    print_fail "SKILL.md not found at $SKILL_MD"
    echo ""
    echo "Cannot continue without SKILL.md."
    exit 1
fi
echo ""

# --- Extract frontmatter ---

# Find the first and second '---' delimiters
FRONTMATTER_START=$(grep -n '^---$' "$SKILL_MD" | head -1 | cut -d: -f1)
FRONTMATTER_END=$(grep -n '^---$' "$SKILL_MD" | head -2 | tail -1 | cut -d: -f1)

if [ -z "$FRONTMATTER_START" ] || [ -z "$FRONTMATTER_END" ] || [ "$FRONTMATTER_START" = "$FRONTMATTER_END" ]; then
    echo "2. Frontmatter"
    print_fail "YAML frontmatter not found (missing '---' delimiters)"
    echo ""
    echo "SKILL.md must start with '---' and have a closing '---' delimiter."
    exit 1
fi

# Extract frontmatter content (between the delimiters, exclusive)
FRONTMATTER=$(sed -n "$((FRONTMATTER_START+1)),$((FRONTMATTER_END-1))p" "$SKILL_MD")

# --- Check 2: name field ---

echo "2. name field"
NAME=$(echo "$FRONTMATTER" | grep -E '^name:' | head -1 | sed 's/^name:[[:space:]]*//' | tr -d '"' | tr -d "'")

if [ -z "$NAME" ]; then
    print_fail "name field is missing from frontmatter"
else
    # Check format: only a-z, 0-9, hyphens; no leading/trailing/consecutive hyphens
    if echo "$NAME" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
        print_pass "name format is valid: $NAME"
    else
        print_fail "name format is invalid: '$NAME' — must be lowercase a-z, 0-9, hyphens only; no leading/trailing/consecutive hyphens"
    fi

    # Check length
    NAME_LEN=${#NAME}
    if [ "$NAME_LEN" -gt 64 ]; then
        print_fail "name exceeds 64 characters ($NAME_LEN chars)"
    fi

    # Check matches parent directory
    if [ "$NAME" = "$DIR_NAME" ]; then
        print_pass "name matches parent directory name"
    else
        print_fail "name '$NAME' does not match parent directory name '$DIR_NAME'"
    fi
fi
echo ""

# --- Check 3: description field ---

echo "3. description field"
# Description may span multiple lines (YAML block scalar or folded scalar)
# Try to extract it robustly — description 起始行 + 后续缩进行（block scalar 内容），
# 剥指示符（> | 及 -/+ 折叠标记）逐行拼内容；遇下一顶层键（非缩进行）即停
DESC_RAW=$(echo "$FRONTMATTER" | awk '/^description:/{sub(/^description:[[:space:]]*/,""); sub(/^[>|][-+]?[[:space:]]*/,""); a=$0; next} /^[[:space:]]/{line=$0; sub(/^[[:space:]]*/,"",line); if(line!="") a=a" "line; next} a!=""{exit} END{print a}')
if [ -z "$DESC_RAW" ]; then
    # Try single-line extraction
    DESC_RAW=$(echo "$FRONTMATTER" | grep -E '^description:' | head -1 | sed 's/^description:[[:space:]]*//')
fi

# Strip YAML block scalar indicators and quotes
DESC=$(echo "$DESC_RAW" | sed 's/^[>|][[:space:]]*//' | tr -d '"' | tr -d "'" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

if [ -z "$DESC" ] || [ "$DESC" = " " ]; then
    print_fail "description field is empty or missing"
else
    DESC_LEN=${#DESC}
    if [ "$DESC_LEN" -gt 1024 ]; then
        print_fail "description exceeds 1024 characters ($DESC_LEN chars)"
    else
        print_pass "description is non-empty and within 1024 chars ($DESC_LEN chars)"
    fi

    # Check for imperative phrasing (soft check)
    if echo "$DESC" | grep -qiE '(use |when |trigger )'; then
        print_pass "description contains trigger/imperative phrasing"
    else
        print_warn "description may lack imperative phrasing (consider 'Use this skill when...')"
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
fi
echo ""

# --- Check 4: Frontmatter YAML validity (basic) ---

echo "4. Frontmatter YAML"
# Basic check: no unquoted colons in values (common YAML error)
if echo "$FRONTMATTER" | grep -E '^[a-z]+:[[:space:]]+.+: ' | grep -v '^[a-z]+:[[:space:]]*("|'\'')' | grep -qv '^[a-z]+:[[:space:]]*$'; then
    print_warn "possible unquoted colon in frontmatter values (may cause YAML parse errors)"
    WARN_COUNT=$((WARN_COUNT + 1))
else
    print_pass "no obvious YAML issues detected"
fi
echo ""

# --- Check 5: SKILL.md line count ---

echo "5. SKILL.md size"
TOTAL_LINES=$(wc -l < "$SKILL_MD" | tr -d ' ')
if [ "$TOTAL_LINES" -gt 500 ]; then
    print_warn "SKILL.md has $TOTAL_LINES lines (recommended max: 500) — consider moving detail to references/"
    WARN_COUNT=$((WARN_COUNT + 1))
else
    print_pass "SKILL.md is $TOTAL_LINES lines (within 500-line recommendation)"
fi
echo ""

# --- Check 6: File references ---

echo "6. File references"
# Look for references to files and check they're relative, one level deep
REF_ISSUES=0
while IFS= read -r line; do
    # Check for absolute paths
    if echo "$line" | grep -qE '(\/[a-zA-Z]:\\|^[A-Z]:\\|/home/|/Users/)'; then
        print_warn "possible absolute path reference: $line"
        WARN_COUNT=$((WARN_COUNT + 1))
        REF_ISSUES=1
    fi
done < <(grep -nE '\]\(|scripts/|references/|assets/' "$SKILL_MD" 2>/dev/null || true)

if [ "$REF_ISSUES" -eq 0 ]; then
    print_pass "no absolute path references found"
fi
echo ""

# --- Check 7: Credential patterns ---

echo "7. Credential scan"
CRED_PATTERNS='(AKID[A-Za-z0-9]{16}|AKIA[A-Z0-9]{16}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|xox[baprs]-[A-Za-z0-9]{10,})'
if grep -rEi "$CRED_PATTERNS" "$SKILL_PATH" --include='*.md' --include='*.py' --include='*.sh' --include='*.ts' --include='*.js' --include='*.json' 2>/dev/null | grep -v '.gitleaksignore' | grep -v 'CRED_PATTERNS' | head -5 | grep -q .; then
    print_fail "potential hardcoded credentials detected:"
    grep -rEi "$CRED_PATTERNS" "$SKILL_PATH" --include='*.md' --include='*.py' --include='*.sh' --include='*.ts' --include='*.js' --include='*.json' 2>/dev/null | grep -v '.gitleaksignore' | grep -v 'CRED_PATTERNS' | head -5 | while IFS= read -r match; do
        echo "         $match"
    done
else
    print_pass "no obvious credential patterns detected"
fi
echo ""

# --- Check 8: Scripts interactive input ---

echo "8. Scripts — interactive input"
SCRIPTS_DIR="$SKILL_PATH/scripts"
if [ -d "$SCRIPTS_DIR" ]; then
    INTERACTIVE_FOUND=0
    for script in "$SCRIPTS_DIR"/*.py "$SCRIPTS_DIR"/*.sh "$SCRIPTS_DIR"/*.ts "$SCRIPTS_DIR"/*.js; do
        [ -f "$script" ] || continue
        script_name=$(basename "$script")
        # Check for common interactive patterns
        if grep -qE '(input\(|read\s+-p|read\s+var|getpass|inquirer\.|prompt\(|confirm\()' "$script" 2>/dev/null; then
            print_warn "$script_name may use interactive input (agents cannot respond to prompts)"
            WARN_COUNT=$((WARN_COUNT + 1))
            INTERACTIVE_FOUND=1
        fi
    done
    if [ "$INTERACTIVE_FOUND" -eq 0 ]; then
        print_pass "no interactive input patterns detected in scripts"
    fi
else
    echo "  [SKIP] no scripts/ directory"
fi
echo ""

# --- Check 9: Scripts --help ---

echo "9. Scripts — --help support"
if [ -d "$SCRIPTS_DIR" ]; then
    HELP_MISSING=0
    for script in "$SCRIPTS_DIR"/*.py "$SCRIPTS_DIR"/*.sh "$SCRIPTS_DIR"/*.ts "$SCRIPTS_DIR"/*.js; do
        [ -f "$script" ] || continue
        script_name=$(basename "$script")
        if ! grep -qE '(--help|-h|argparse|ArgumentParser)' "$script" 2>/dev/null; then
            print_warn "$script_name may not support --help"
            WARN_COUNT=$((WARN_COUNT + 1))
            HELP_MISSING=1
        fi
    done
    if [ "$HELP_MISSING" -eq 0 ]; then
        print_pass "all scripts appear to support --help"
    fi
else
    echo "  [SKIP] no scripts/ directory"
fi
echo ""

# --- Check optional: references/ files ---

echo "10. References"
REFS_DIR="$SKILL_PATH/references"
if [ -d "$REFS_DIR" ]; then
    REF_COUNT=$(find "$REFS_DIR" -name '*.md' -type f | wc -l | tr -d ' ')
    print_pass "references/ directory exists with $REF_COUNT markdown file(s)"
    # Check for kebab-case naming
    BAD_NAMES=$(find "$REFS_DIR" -type f ! -name '*.md' -o -name '*[A-Z]*' -o -name '*_*' 2>/dev/null | head -5)
    if [ -n "$BAD_NAMES" ]; then
        print_warn "some reference files may not follow kebab-case naming"
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
else
    echo "  [SKIP] no references/ directory (optional)"
fi
echo ""

# --- Check optional: evals/ ---

echo "11. Evals"
EVALS_FILE="$SKILL_PATH/evals/evals.json"
if [ -f "$EVALS_FILE" ]; then
    print_pass "evals/evals.json exists"
else
    echo "  [SKIP] no evals/evals.json (optional, recommended for complex skills)"
fi
echo ""

# --- Summary ---

echo "============================================"
if [ "$FAILED" -eq 0 ]; then
    echo "  RESULT: PASS"
    if [ "$WARN_COUNT" -gt 0 ]; then
        echo "  ($WARN_COUNT warning(s) — review above)"
    fi
    echo "============================================"
    exit 0
else
    echo "  RESULT: FAIL"
    echo "  Critical issues must be fixed before proceeding."
    if [ "$WARN_COUNT" -gt 0 ]; then
        echo "  ($WARN_COUNT warning(s) — review above)"
    fi
    echo "============================================"
    exit 1
fi
