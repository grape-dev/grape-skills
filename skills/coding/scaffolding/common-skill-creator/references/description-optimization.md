# Description Optimization Guide

> How to write effective skill descriptions and optimize trigger accuracy. Read during Phase 4b.

## How Skill Triggering Works

Agents use **progressive disclosure** to manage context:

1. At startup, only `name` + `description` are loaded for each skill (~100 tokens)
2. When a user's task matches a description, the full `SKILL.md` body loads into context
3. The agent follows the instructions

The description carries the **entire burden of triggering**. If it doesn't convey when the skill is useful, the agent won't activate it.

**Important nuance:** Agents only consult skills for tasks requiring knowledge or capabilities beyond what they handle alone. A simple one-step request may not trigger even a perfectly described skill. Specialized knowledge tasks are where descriptions matter most.

## Writing Effective Descriptions

| Principle | Guidance | Example |
|-----------|----------|---------|
| **Imperative phrasing** | Frame as instruction to the agent | "Use this skill when..." not "This skill does..." |
| **User intent, not implementation** | Describe what the user wants, not internal mechanics | "analyze CSV data" not "invoke pandas read_csv" |
| **Be pushy** | List implicit scenarios, not just explicit ones | "even if they don't mention 'CSV' or 'analysis'" |
| **Concise** | Few sentences to a short paragraph | Hard limit: 1024 characters |

### Before / After

```yaml
# Before — too vague
description: Process CSV files.

# After — specific and pushy
description: >
  Analyze CSV and tabular data files — compute summary statistics,
  add derived columns, generate charts, and clean messy data. Use this
  skill when the user has a CSV, TSV, or Excel file and wants to
  explore, transform, or visualize the data, even if they don't
  explicitly mention "CSV" or "analysis."
```

## Designing Trigger Eval Queries

Aim for ~20 queries: 8-10 should-trigger, 8-10 should-not-trigger.

### Should-Trigger Queries

Vary along several axes:

- **Phrasing**: formal, casual, with typos/abbreviations
- **Explicitness**: some name the domain directly, others describe the need without naming it
- **Detail**: mix terse prompts with context-heavy ones (file paths, column names, backstory)
- **Complexity**: single-step tasks alongside multi-step workflows

The most useful should-trigger queries are ones where the skill would help but the connection isn't obvious from the query alone.

### Should-Trigger Examples

```json
[
  { "query": "I've got a spreadsheet in ~/data/q4_results.xlsx with revenue in col C and expenses in col D — can you add a profit margin column and highlight anything under 10%?", "should_trigger": true },
  { "query": "my boss wants a chart from this data file but I'm not sure what tool to use", "should_trigger": true },
  { "query": "hey can you clean up this csv real quick", "should_trigger": true }
]
```

### Should-Not-Trigger Queries

**Near-misses** are the most valuable — queries sharing keywords/concepts but needing something different.

Weak negatives (test nothing):
- `"Write a fibonacci function"` — obviously irrelevant
- `"What's the weather today?"` — no keyword overlap

Strong negatives (near-misses):
- `"I need to update the formulas in my Excel budget spreadsheet"` — shares "spreadsheet" but needs Excel editing, not analysis
- `"can you write a python script that reads a csv and uploads each row to our postgres database"` — involves CSV but task is database ETL

### Should-Not-Trigger Examples

```json
[
  { "query": "I need to update the formulas in my Excel budget spreadsheet", "should_trigger": false },
  { "query": "can you write a python script that reads a csv and uploads each row to our postgres database", "should_trigger": false }
]
```

### Tips for Realism

Include in queries:
- File paths (`~/Downloads/report_final_v2.xlsx`)
- Personal context (`"my manager asked me to..."`)
- Specific details (column names, company names, data values)
- Casual language, abbreviations, occasional typos

## Avoiding Overfitting

Split queries into two sets:

- **Train set (~60%)**: Used to identify failures and guide improvements
- **Validation set (~40%)**: Set aside, only used to check generalization

Keep the split fixed across iterations. Make sure both sets have a proportional mix of should-trigger and should-not-trigger.

## Testing Trigger Rates

Run each query through the agent with the skill installed. Observe whether the agent loads the `SKILL.md`.

A query **passes** if:
- `should_trigger` is `true` AND skill was invoked, OR
- `should_trigger` is `false` AND skill was NOT invoked

Run each query **3 times** (model behavior is nondeterministic). Compute **trigger rate** = fraction of runs where skill was invoked.

- should-trigger passes if trigger rate > 0.5
- should-not-trigger passes if trigger rate < 0.5

## The Optimization Loop

1. **Evaluate** current description on both train and validation sets
2. **Identify failures** in the train set:
   - Should-trigger not triggering → description too narrow
   - Should-not-trigger false-firing → description too broad
3. **Revise** (generalize, don't overfit):
   - Broaden scope or add context for narrow failures
   - Add specificity or boundaries for broad failures
   - **Don't** add specific keywords from failed queries — find the general category
   - If stuck after several iterations, try a structurally different approach
   - Check description stays < 1024 characters
4. **Repeat** until all train queries pass or improvement plateaus
5. **Select best iteration** by validation pass rate (may not be the last one)

Five iterations is usually enough.

## Applying the Result

1. Update the `description` field in SKILL.md frontmatter
2. Verify < 1024 characters
3. Test with 5-10 fresh queries (never part of optimization) as a sanity check
