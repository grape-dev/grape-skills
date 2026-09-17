---
name: common-skill-creator
description: >
  Create, validate, and iterate on generic Agent Skills following the official Agent Skills
  specification. Use when the user wants to create a new skill, scaffold a skill
  directory, write or improve a SKILL.md, optimize skill descriptions for triggering,
  validate skill compliance, or set up eval-driven skill iteration — even if they
  don't explicitly mention "skill" or "specification." Triggers include: "create skill",
  "new skill", "skill creator", "common skill creator", "scaffold a skill", "write SKILL.md",
  "optimize skill description", "validate skill", "skill eval", "创建skill", "新建skill",
  "skill脚手架", "帮我创建一个skill", "生成skill", "skill创建器", "通用skill创建器",
  "build skill", "make a skill".
---

# Common Skill Creator

> **Five-Phase Pipeline** — Each phase depends on the previous phase's output and cannot be skipped.

---

## Overview

The Common Skill Creator guides you through creating generic Agent Skills that conform to the official Agent Skills specification. It uses a five-phase pipeline: requirements analysis (Socratic Q&A), skill design, content generation, validation, and eval-driven iteration — producing a complete, compliant skill package. Phase 4 validation enforces the specification **and** the dynamically-loaded generic lint rules (skill-linter check set, `common_skillslinter.json`), so created skills never violate the common skill spec. Use it for any domain; for Huawei Cloud–specific skills, use `huawei-cloud-skill-creator` instead.

---

## Workflow — Five-Phase Pipeline

```
Phase 1 (Requirements) → Phase 2 (Design) → Phase 3 (Generate) → Phase 4 (Validate) → Phase 5 (Iterate)
```

**Strict Rules:**
- Each phase **must** output a phase summary (`phase-N-summary.json`)
- Before starting each phase, **must** verify that the previous phase's summary exists
- Skipping any phase is strictly prohibited
- After all phases complete, perform a final completeness check; if any phase is missing, restart from that phase

---

### Phase 1: Requirements Analysis (Socratic Q&A)

**Goal:** Clarify what skill to create through one-question-at-a-time dialogue.

Ask **one question** at a time, covering these dimensions:

| # | Dimension | Key Questions |
|---|-----------|---------------|
| 1 | **Domain / Purpose** | What problem does this skill solve? What domain is it in? |
| 2 | **Feature Scope** | What exactly does the skill do? What does it NOT do? (Design coherent units — not too narrow, not too broad) |
| 3 | **Trigger Scenarios** | When should an agent activate this skill? What would a user say? Include cases where the user doesn't name the domain directly. |
| 4 | **Input / Output** | What goes in? What format should the output be? |
| 5 | **Complexity** | Single-file skill, or does it need `scripts/`, `references/`, `assets/`? |
| 6 | **Environment Prerequisites** | What languages, tools, or packages does it depend on? (Goes into `compatibility` field) |
| 7 | **Source Material** | Are there existing docs, code, runbooks, or incident reports to use as domain knowledge input? |

- After every 5 questions or when all dimensions are covered → Display requirements summary table → Wait for user confirmation
- **Do NOT proceed to Phase 2 until the user has explicitly confirmed**

**Best practice reminder:** Effective skills are grounded in real expertise. If the user has existing project artifacts (runbooks, API specs, code review comments, incident reports), encourage them to provide these as source material rather than relying on generic knowledge.

**Output:** `phase-1-summary.json` — User-confirmed requirements

---

### Phase 2: Skill Design

**Goal:** Design the skill skeleton based on Phase 1 conclusions.

1. **Name the skill** — Validate against spec constraints:
   - 1-64 characters, only lowercase `a-z`, `0-9`, and hyphens `-`
   - Must not start or end with a hyphen
   - Must not contain consecutive hyphens (`--`)
   - **Must match the parent directory name**

2. **Draft the description** — Follow these principles (see `references/description-optimization.md` for details):
   - Use imperative phrasing: "Use this skill when..." not "This skill does..."
   - Focus on user intent, not implementation
   - Err on the side of being pushy — list implicit scenarios where the skill applies
   - Keep concise — hard limit of 1024 characters

3. **Plan token budget** (progressive disclosure):
   - SKILL.md body: < 5000 tokens, < 500 lines
   - Move detailed reference material to `references/`
   - Resources load on demand — tell the agent *when* to load each file

4. **Select instruction patterns** — Based on task characteristics (see `references/instruction-patterns.md`):
   - **Gotchas** — environment-specific facts that defy assumptions
   - **Output templates** — concrete format structures
   - **Checklists** — multi-step workflows with dependencies
   - **Validation loops** — self-check before proceeding
   - **Plan-validate-execute** — batch or destructive operations

5. **Decide on scripts** (see `references/script-design-guide.md`):
   - If a one-off command suffices (uvx/npx/pipx/go run) → write directly in SKILL.md
   - If reusable logic is needed → bundle in `scripts/` as self-contained scripts

6. **Create directory skeleton**

7. **Determine control calibration**:
   - Fragile operations (specific sequence, consistency critical) → prescriptive instructions
   - Flexible tasks (multiple valid approaches) → give freedom + explain *why*

**Output:** `phase-2-summary.json` — Design document + directory structure

---

### Phase 3: Content Generation

**Goal:** Write SKILL.md and all supporting files.

**SKILL.md generation rules:**

| Part | Requirements |
|------|-------------|
| YAML frontmatter | `name` (required) + `description` (required) + optional `license`, `compatibility`, `metadata`, `allowed-tools` |
| Body core principle | **Only write what the agent wouldn't know** — project conventions, domain-specific procedures, non-obvious edge cases. Don't explain what a PDF is or how HTTP works. |
| Instruction granularity | Match specificity to fragility — fragile = prescriptive; flexible = freedom + reasoning |
| Tool selection | Provide a **default** with a brief escape hatch, not equal-weight menus |
| Methodology | Teach the **approach** (reusable method), not the **instance** (specific answer). Procedures > declarations. |

**SKILL.md recommended sections:**

| Section | Purpose |
|---------|---------|
| Overview | What the skill does, when to use it |
| Prerequisites | Environment requirements, dependencies |
| Workflow / Steps | Step-by-step instructions |
| Core Commands / Patterns | Command or code examples grouped by function |
| Gotchas | Environment-specific pitfalls (highest-value content) |
| Edge Cases | How to handle unusual situations |
| Available Scripts | List bundled scripts with one-line descriptions |
| Reference Documents | Links to files under `references/` with when to load them |

**Supporting files (per Phase 2 decisions):**

- `scripts/` — Must follow agentic design principles: no interactive input, `--help` output, structured output (JSON/CSV), helpful errors, idempotent, `--dry-run` for destructive ops, meaningful exit codes
- `references/` — Focused single-topic files. In SKILL.md, state **when** to load each: "Read `references/api-errors.md` if the API returns a non-200 status code"
- `assets/` — Templates, data files, schemas

**Output:** `phase-3-summary.json` — Generated file list + structure validation

---

### Phase 4: Validation

**Goal:** Ensure the skill conforms to the specification and the dynamically-loaded generic lint rules, then optimize trigger accuracy.

#### 4a. Specification Compliance Check

Run `scripts/validate-skill.sh` to verify:

| Check Item | Level | Verification Method |
|------------|-------|---------------------|
| SKILL.md exists | Critical | File existence |
| name matches `^[a-z0-9]+(-[a-z0-9]+)*$` | Critical | Regex match |
| name ≤ 64 characters | Critical | Length check |
| name == parent directory name | Critical | Directory name comparison |
| description non-empty and ≤ 1024 chars | Critical | Character count |
| Frontmatter is valid YAML | Critical | YAML parse |
| SKILL.md ≤ 500 lines | High | Line count |
| File references are relative, one level deep | Medium | Path analysis |
| No hardcoded credentials | Critical | Pattern scan |
| Scripts have no interactive input | Critical | Code review |
| Scripts provide `--help` | High | Run `--help` |

If validation fails, fix issues before proceeding to 4b.

#### 4b. Generic Lint Rule Check (skill-linter Integration)

**Purpose:** Run the same dynamically-loaded check points as skill-linter / common-skill-tester's lint track against the generated skill, so it never violates the common skill spec. The check set is **dynamic** — never hardcode or rely on memory; always fetch the latest version.

1. **Fetch the latest check points** (raw URL → gitcode API v5 fallback):

```bash
node common-skill-creator/scripts/fetch_checks.js                       # 拉取在线检查点
node common-skill-creator/scripts/fetch_checks.js -o /tmp/checks.json   # 保存到文件（断点续跑/复查）
node common-skill-creator/scripts/fetch_checks.js "https://..."         # 自定义检查点 URL
```

2. **Execute every check item** against the generated skill directory — judge each as **pass / fail / warn / skip** based on **objective evidence** (file existence, grep hits, line numbers, statistics), following the method mapping in `references/lint-checks.md` (structure, frontmatter, naming, .env, dangerous scripts, resource limits, credential scan, security score, delete-op confirmation, etc.).

3. **Score and gate:**

```
Lint 评分 = 100 - (Critical_fail × 15) - (High_fail × 8) - (Medium_fail × 4) - (Low_fail × 2) - (warn × 1)
```

- **Critical fail → blocking gate**: any Critical fail (incl. `failure_handling=FAIL`) must be fixed before proceeding to Phase 5
- **Score ≥ 95 → pass** (matches the quality gate: lint/tester/auditor all ≥ 95); score < 95 → list must-fix/suggested items, fix, re-fetch and re-run until pass
- Do not skip checks for "simple" skills — judge each item by actual evidence

4. **Record** in `phase-4-summary.json`: total / pass / fail / warn / skip, Lint 评分, stars/grade, full fail & warn list with fix suggestions and check-point version (`doc` field).

#### 4c. Description Trigger Optimization

Guide the user through optimizing the `description` field (see `references/description-optimization.md`):

1. **Design ~20 trigger eval queries:**
   - 8-10 should-trigger (vary phrasing, explicitness, detail, complexity)
   - 8-10 should-not-trigger (**near-misses** preferred — share keywords but need something different)

2. **Split into train/validation sets** (60/40) to avoid overfitting

3. **Test trigger rates** (if environment supports):
   - Run each query 3 times, compute trigger rate
   - should-trigger passes if rate > 0.5
   - should-not-trigger passes if rate < 0.5

4. **Revise based on failures:**
   - Should-trigger failing → broaden scope or add context about when the skill is useful
   - Should-not-trigger false-firing → add specificity about what the skill does NOT do
   - Avoid adding specific keywords from failed queries (overfitting) — find the general category

5. **Verify revised description** is still < 1024 characters

6. **Select best iteration** by validation pass rate

**Output:** `phase-4-summary.json` — Validation report (4a + 4b results, Lint 评分) + optimized description

---

### Phase 5: Eval-Driven Iteration (Recommended)

**Goal:** Verify the skill produces good outputs and improve systematically.

This phase is **recommended** for complex skills. Simple skills (single command, obvious output) may skip it.

Follow the eval-driven iteration workflow (see `references/eval-workflow.md`):

1. **Design test cases** → `evals/evals.json`:
   - Start with 2-3 cases (prompt + expected_output + optional input files)
   - Vary phrasings, cover edge cases, use realistic context

2. **Run evals** — each test case twice:
   - **with_skill**: agent has the skill loaded
   - **without_skill**: baseline, no skill (or previous skill version)
   - Use clean context per run (subagent or separate session)
   - Record timing data (tokens, duration)

3. **Write assertions** (after first run, when you know what "good" looks like):
   - Programmatically verifiable (valid JSON, file exists, correct count)
   - Specific and observable, not vague

4. **Grade outputs** → `grading.json`:
   - Each assertion: PASS/FAIL + concrete evidence
   - Require concrete evidence for PASS — no benefit of the doubt

5. **Aggregate** → `benchmark.json`:
   - Compute pass_rate, time, tokens for with_skill vs without_skill
   - Calculate delta — what the skill costs and what it buys

6. **Analyze patterns:**
   - Remove assertions that always pass in both configs (no discrimination)
   - Investigate assertions that always fail in both (broken assertion or too-hard test)
   - Study assertions that pass with skill but fail without (skill's value)
   - Tighten instructions when results are inconsistent (high stddev)

7. **Human review** → `feedback.json`:
   - Record specific, actionable feedback per test case

8. **Iterate:**
   - Give three signals (failed assertions + human feedback + execution transcripts) + current SKILL.md to LLM
   - Propose improvements: generalize from feedback, keep skill lean, explain the why, bundle repeated work
   - Apply changes → new iteration → rerun all cases
   - Stop when satisfied or no meaningful improvement

**Output:** `phase-5-summary.json` — Eval results + benchmark + final SKILL.md

---

## Final Completeness Check

```
Check phase-1-summary.json exists → If missing, restart from Phase 1
Check phase-2-summary.json exists → If missing, restart from Phase 2
Check phase-3-summary.json exists → If missing, restart from Phase 3
Check phase-4-summary.json exists → If missing, restart from Phase 4
Check phase-5-summary.json exists → If missing, restart from Phase 5 (or mark as skipped for simple skills)
```

All phases complete → Creation done. Missing phases → Restart from the missing phase.

After completeness check passes, clean up phase summary files:
```bash
rm -f {skill-path}/phase-*.json
```

---

## Available Scripts

- **`scripts/validate-skill.sh`** — Validates a skill directory against the Agent Skills specification (frontmatter, naming, structure, credential scan). Used in Phase 4a.
- **`scripts/fetch_checks.js`** — Fetches the latest generic lint check points (skill-linter rule set, `common_skillslinter.json`) with raw→API v5 fallback. Used in Phase 4b.
- **`scripts/init-skill.py`** — Scaffolds a new skill directory with SKILL.md template and optional subdirectories

---

## Reference Documents

- **`references/spec-summary.md`** — Quick reference for SKILL.md format, frontmatter fields, and naming constraints. Read when you need to verify format requirements.
- **`references/lint-checks.md`** — The dynamically-loaded generic lint rules (skill-linter integration): check-point source, JSON structure, method mapping, scoring formula, and the Phase 4b gate. Read during Phase 4b.
- **`references/description-optimization.md`** — Detailed guide for writing effective descriptions and optimizing trigger accuracy. Read during Phase 4c.
- **`references/script-design-guide.md`** — Principles for designing scripts for agentic use (no interactive input, --help, structured output, error messages). Read when generating scripts in Phase 3.
- **`references/eval-workflow.md`** — Full eval-driven iteration workflow with workspace structure, assertion examples, and grading templates. Read during Phase 5.
- **`references/instruction-patterns.md`** — Catalog of instruction patterns (gotchas, templates, checklists, validation loops, plan-validate-execute) with examples. Read during Phase 2 pattern selection.

---

## Edge Cases

| Scenario | Handling |
|----------|---------|
| User says "just create it" without details | Remind: requirements analysis is required; start from Phase 1 questions |
| User wants to skip Phase 5 (eval iteration) | Allow for simple skills; recommend strongly for complex skills |
| Skill name conflicts with existing skill | Suggest alternative names or a category prefix |
| description exceeds 1024 chars after optimization | Trim redundant phrasing; merge overlapping scenarios; prioritize pushy triggers |
| SKILL.md exceeds 500 lines | Move detailed content to `references/`; keep only core instructions in SKILL.md |
| Script requires interactive input | Reject — rewrite to accept flags, env vars, or stdin. Interactive input hangs agents. |
| Validation fails on credential scan | Replace hardcoded credentials with environment variable references |
| 4b lint check: Critical fail found | Blocking gate — fix before Phase 5; list file + line + fix suggestion per fail |
| 4b lint check: score < 95 | List all fail/warn items, fix, re-fetch check points and re-run until ≥ 95 |
| 4b check-point fetch fails (network down) | Fallback: reuse a locally saved JSON (`node fetch_checks.js -o` output) by passing its path as the URL; if none exists, run 4a checks, note 4b as pending, and retry fetch before finalizing Phase 4 |
| 4b JSON contains unknown/new check items | Execute per the item's `rule` description; never skip unknown items |
| Trigger eval shows poor trigger rate | Revise description per Phase 4c; broaden (should-trigger failing) or add boundaries (should-not-trigger failing) |
| Eval shows skill adds no value (pass rate same as baseline) | The skill may not be needed; consider whether the agent already handles the task well without it |
| Phase 5 finds missing phases | Restart from the missing phase until all phases are complete |

---

## Best Practices

- During Phase 1, encourage users to provide existing project artifacts as domain knowledge source
- In Phase 2, keep skills scoped as coherent units — not too narrow (forces multiple skills for one task) or too broad (hard to activate precisely)
- In Phase 3, ask "Would the agent get this wrong without this instruction?" for each piece of content — if no, cut it
- In Phase 3, provide defaults not menus — pick one approach and mention alternatives briefly
- In Phase 4, use near-miss queries as should-not-trigger tests — they are the most valuable negative cases
- In Phase 4b, fix Critical fails first, then re-run the lint checks until score ≥ 95 — never ship a skill that fails the common spec gate
- In Phase 5, focus on assertions that discriminate — remove those that pass in both configs
- Keep the skill lean — fewer, better instructions often outperform exhaustive rules

---

## Design Principles

- **Five-Phase Pipeline** — Phases are chain-dependent and cannot be skipped
- **Spec-Conformant** — Every generated skill follows the official Agent Skills specification
- **Progressive Disclosure** — SKILL.md stays under 500 lines / 5000 tokens; detail goes to references/
- **Real Expertise** — Skills are grounded in user-provided domain knowledge, not generic LLM knowledge
- **Eval-Driven** — Quality is verified through structured evaluation, not assumed
- **Token Economy** — Only include what the agent wouldn't know; omit what it already knows
- **Control Calibration** — Match instruction specificity to task fragility
