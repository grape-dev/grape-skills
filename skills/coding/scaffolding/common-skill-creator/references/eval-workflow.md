# Eval-Driven Iteration Workflow

> Full workflow for testing skill output quality through structured evaluation. Read during Phase 5.

## Designing Test Cases

A test case has three parts:

- **Prompt**: a realistic user message
- **Expected output**: human-readable description of what success looks like
- **Input files** (optional): files the skill needs

Store in `evals/evals.json`:

```json
{
  "skill_name": "csv-analyzer",
  "evals": [
    {
      "id": 1,
      "prompt": "I have a CSV of monthly sales data in data/sales_2025.csv. Can you find the top 3 months by revenue and make a bar chart?",
      "expected_output": "A bar chart image showing the top 3 months by revenue, with labeled axes and values.",
      "files": ["evals/files/sales_2025.csv"]
    },
    {
      "id": 2,
      "prompt": "there's a csv in my downloads called customers.csv, some rows have missing emails — can you clean it up and tell me how many were missing?",
      "expected_output": "A cleaned CSV with missing emails handled, plus a count of how many were missing.",
      "files": ["evals/files/customers.csv"]
    }
  ]
}
```

**Tips:**
- Start with 2-3 test cases — expand after first results
- Vary phrasings (casual, precise, terse, context-heavy)
- Cover edge cases (malformed input, unusual requests, ambiguous instructions)
- Use realistic context (file paths, column names, personal context)

## Workspace Structure

```
skill-name/
├── SKILL.md
└── evals/
    └── evals.json
skill-name-workspace/
└── iteration-1/
    ├── eval-top-months-chart/
    │   ├── with_skill/
    │   │   ├── outputs/
    │   │   ├── timing.json
    │   │   └── grading.json
    │   └── without_skill/
    │       ├── outputs/
    │       ├── timing.json
    │       └── grading.json
    ├── eval-clean-missing-emails/
    │   ├── with_skill/
    │   │   ├── outputs/
    │   │   ├── timing.json
    │   │   └── grading.json
    │   └── without_skill/
    │       ├── outputs/
    │       ├── timing.json
    │       └── grading.json
    └── benchmark.json
```

## Running Evals

Each eval run starts with **clean context** — no leftover state. Use subagents or separate sessions.

For each run, provide:
- The skill path (or no skill for baseline)
- The test prompt
- Any input files
- The output directory

```
Execute this task:
- Skill path: /path/to/skill-name
- Task: I have a CSV of monthly sales data...
- Input files: evals/files/sales_2025.csv
- Save outputs to: skill-name-workspace/iteration-1/eval-top-months-chart/with_skill/outputs/
```

For baseline, same prompt without skill path, saving to `without_skill/outputs/`.

When improving an existing skill, snapshot the previous version:
```bash
cp -r <skill-path> <workspace>/skill-snapshot/
```
Point baseline at snapshot, save to `old_skill/outputs/`.

## Capturing Timing Data

```json
{
  "total_tokens": 84852,
  "duration_ms": 23332
}
```

Timing lets you compare cost vs benefit — a skill that triples tokens for 2% improvement may not be worth it.

## Writing Assertions

Add assertions **after** the first run — you often don't know what "good" looks like until you see output.

**Good assertions:**
- `"The output file is valid JSON"` — programmatically verifiable
- `"The bar chart has labeled axes"` — specific and observable
- `"The report includes at least 3 recommendations"` — countable

**Weak assertions:**
- `"The output is good"` — too vague
- `"The output uses exactly the phrase 'Total Revenue: $X'"` — too brittle

```json
{
  "id": 1,
  "prompt": "I have a CSV of monthly sales data...",
  "expected_output": "A bar chart image showing the top 3 months by revenue.",
  "files": ["evals/files/sales_2025.csv"],
  "assertions": [
    "The output includes a bar chart image file",
    "The chart shows exactly 3 months",
    "Both axes are labeled",
    "The chart title or caption mentions revenue"
  ]
}
```

## Grading Outputs

Evaluate each assertion against actual outputs. Record PASS/FAIL with **concrete evidence**.

```json
{
  "assertion_results": [
    {
      "text": "The output includes a bar chart image file",
      "passed": true,
      "evidence": "Found chart.png (45KB) in outputs directory"
    },
    {
      "text": "Both axes are labeled",
      "passed": false,
      "evidence": "Y-axis is labeled 'Revenue ($)' but X-axis has no label"
    }
  ],
  "summary": {
    "passed": 3,
    "failed": 1,
    "total": 4,
    "pass_rate": 0.75
  }
}
```

**Grading principles:**
- Require concrete evidence for PASS — no benefit of the doubt
- Review assertions themselves — fix ones that are too easy, too hard, or unverifiable

For comparing two versions, try **blind comparison**: present both outputs to an LLM judge without revealing which is which.

## Aggregating Results

```json
{
  "run_summary": {
    "with_skill": {
      "pass_rate": { "mean": 0.83, "stddev": 0.06 },
      "time_seconds": { "mean": 45.0, "stddev": 12.0 },
      "tokens": { "mean": 3800, "stddev": 400 }
    },
    "without_skill": {
      "pass_rate": { "mean": 0.33, "stddev": 0.10 },
      "time_seconds": { "mean": 32.0, "stddev": 8.0 },
      "tokens": { "mean": 2100, "stddev": 300 }
    },
    "delta": {
      "pass_rate": 0.50,
      "time_seconds": 13.0,
      "tokens": 1700
    }
  }
}
```

The `delta` tells you what the skill costs (time, tokens) and what it buys (pass rate).

## Analyzing Patterns

- **Remove assertions that always pass in both configs** — no discrimination, inflate pass rate
- **Investigate assertions that always fail in both** — broken assertion, too-hard test, or checking wrong thing
- **Study assertions that pass with skill but fail without** — this is where the skill adds value; understand why
- **Tighten instructions when results are inconsistent** — high stddev means ambiguous instructions; add examples or specificity
- **Check time/token outliers** — read execution transcripts to find bottlenecks

## Human Review

Record specific feedback per test case:

```json
{
  "eval-top-months-chart": "The chart is missing axis labels and the months are in alphabetical order instead of chronological.",
  "eval-clean-missing-emails": ""
}
```

Empty feedback = passed review. "looks bad" is not actionable; "missing axis labels" is.

## Iterating

Three sources of signal:
1. **Failed assertions** — specific gaps (missing step, unclear instruction)
2. **Human feedback** — broader quality issues
3. **Execution transcripts** — why things went wrong (ignored instructions = ambiguous; wasted steps = remove instructions)

Give all three + current SKILL.md to an LLM. Guidelines for proposed changes:
- **Generalize from feedback** — fixes should address underlying issues, not patch specific examples
- **Keep the skill lean** — fewer, better instructions often outperform exhaustive rules
- **Explain the why** — reasoning-based instructions ("Do X because Y tends to cause Z") beat rigid directives
- **Bundle repeated work** — if every run reinvents similar logic, bundle a script into `scripts/`

### The Loop

1. Give eval signals + current SKILL.md to LLM → propose improvements
2. Review and apply changes
3. Rerun all test cases in new `iteration-<N+1>/` directory
4. Grade and aggregate
5. Human review
6. Repeat until satisfied or no meaningful improvement
