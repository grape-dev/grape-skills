# Instruction Patterns Catalog

> Reusable techniques for structuring skill content. Read during Phase 2 pattern selection. Not every skill needs all of them — use the ones that fit.

## 1. Gotchas Sections

**When to use:** When there are environment-specific facts that defy reasonable assumptions.

The highest-value content in many skills. Not general advice ("handle errors appropriately") but concrete corrections to mistakes the agent will make without being told:

```markdown
## Gotchas

- The `users` table uses soft deletes. Queries must include
  `WHERE deleted_at IS NULL` or results will include deactivated accounts.
- The user ID is `user_id` in the database, `uid` in the auth service,
  and `accountId` in the billing API. All three refer to the same value.
- The `/health` endpoint returns 200 as long as the web server is running,
  even if the database connection is down. Use `/ready` to check full
  service health.
```

**Placement:** Keep gotchas in SKILL.md where the agent reads them before encountering the situation. A separate reference file works only if you tell the agent when to load it — but for non-obvious issues, the agent may not recognize the trigger.

**Tip:** When an agent makes a mistake you correct, add the correction to the gotchas section. This is the most direct way to improve a skill iteratively.

## 2. Output Format Templates

**When to use:** When the agent must produce output in a specific format.

Templates are more reliable than prose descriptions because agents pattern-match well against concrete structures.

```markdown
## Report structure

Use this template, adapting sections as needed:

```markdown
# [Analysis Title]

## Executive summary
[One-paragraph overview of key findings]

## Key findings
- Finding 1 with supporting data
- Finding 2 with supporting data

## Recommendations
1. Specific actionable recommendation
2. Specific actionable recommendation
```
```

**Placement:** Short templates inline in SKILL.md. Longer templates, or templates only needed in certain cases, store in `assets/` and reference from SKILL.md so they load only when needed.

## 3. Checklists for Multi-Step Workflows

**When to use:** When steps have dependencies or validation gates.

Helps the agent track progress and avoid skipping steps:

```markdown
## Form processing workflow

Progress:
- [ ] Step 1: Analyze the form (run `scripts/analyze_form.py`)
- [ ] Step 2: Create field mapping (edit `fields.json`)
- [ ] Step 3: Validate mapping (run `scripts/validate_fields.py`)
- [ ] Step 4: Fill the form (run `scripts/fill_form.py`)
- [ ] Step 5: Verify output (run `scripts/verify_output.py`)
```

## 4. Validation Loops

**When to use:** When the agent should verify its own work before proceeding.

Pattern: do the work → run validator → fix issues → repeat until validation passes.

```markdown
## Editing workflow

1. Make your edits
2. Run validation: `python scripts/validate.py output/`
3. If validation fails:
   - Review the error message
   - Fix the issues
   - Run validation again
4. Only proceed when validation passes
```

A reference document can also serve as the "validator" — instruct the agent to check its work against the reference before finalizing.

## 5. Plan-Validate-Execute

**When to use:** For batch or destructive operations.

Have the agent create an intermediate plan in a structured format, validate it against a source of truth, and only then execute:

```markdown
## PDF form filling

1. Extract form fields: `python scripts/analyze_form.py input.pdf` → `form_fields.json`
   (lists every field name, type, and whether it's required)
2. Create `field_values.json` mapping each field name to its intended value
3. Validate: `python scripts/validate_fields.py form_fields.json field_values.json`
   (checks that every field name exists in the form, types are compatible,
   and required fields aren't missing)
4. If validation fails, revise `field_values.json` and re-validate
5. Fill the form: `python scripts/fill_form.py input.pdf field_values.json output.pdf`
```

The key ingredient is step 3: a validation script that checks the plan against the source of truth. Errors like "Field 'signature_date' not found — available fields: customer_name, order_total, signature_date_signed" give the agent enough information to self-correct.

## 6. Bundling Reusable Scripts

**When to use:** When the agent independently reinvents the same logic each run.

If you notice the agent building charts, parsing a specific format, or validating output in the same way across test cases, write a tested script once and bundle it in `scripts/`.

Signals that a script is needed:
- Same helper logic appears in multiple execution traces
- The agent struggles to get a complex command right on first try
- Output formatting is inconsistent across runs

## Pattern Selection Guide

| Task Characteristic | Recommended Patterns |
|---------------------|---------------------|
| Has non-obvious pitfalls | Gotchas |
| Requires specific output format | Output Template |
| Multi-step with dependencies | Checklist |
| Output must be verified | Validation Loop |
| Destructive or batch operations | Plan-Validate-Execute |
| Repeated logic across runs | Bundled Script |
| Simple single-step task | None (keep it minimal) |

## Control Calibration

Match specificity to fragility:

**Give freedom** when multiple approaches are valid:
```markdown
## Code review process

1. Check all database queries for SQL injection (use parameterized queries)
2. Verify authentication checks on every endpoint
3. Look for race conditions in concurrent code paths
```

**Be prescriptive** when operations are fragile or consistency matters:
```markdown
## Database migration

Run exactly this sequence:

```bash
python scripts/migrate.py --verify --backup
```

Do not modify the command or add additional flags.
```

Most skills have a mix. Calibrate each part independently.

## Provide Defaults, Not Menus

When multiple tools could work, pick a default and mention alternatives briefly:

```markdown
<!-- Too many options -->
You can use pypdf, pdfplumber, PyMuPDF, or pdf2image...

<!-- Clear default with escape hatch -->
Use pdfplumber for text extraction:

```python
import pdfplumber
```

For scanned PDFs requiring OCR, use pdf2image with pytesseract instead.
```

## Favor Procedures Over Declarations

Teach the agent *how to approach* a class of problems, not *what to produce* for a specific instance:

```markdown
<!-- Specific answer — only useful for this exact task -->
Join the `orders` table to `customers` on `customer_id`, filter where
`region = 'EMEA'`, and sum the `amount` column.

<!-- Reusable method — works for any analytical query -->
1. Read the schema from `references/schema.yaml` to find relevant tables
2. Join tables using the `_id` foreign key convention
3. Apply any filters from the user's request as WHERE clauses
4. Aggregate numeric columns as needed and format as a markdown table
```

The *approach* should generalize even when individual details are specific.
