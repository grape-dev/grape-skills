# Script Design Guide for Agentic Use

> How to design scripts that agents can use effectively. Read when generating scripts in Phase 3.

## One-Off Commands

When an existing package does what you need, reference it directly in SKILL.md without a `scripts/` directory.

| Tool | Ecosystem | Example |
|------|-----------|---------|
| `uvx` | Python | `uvx ruff@0.8.0 check .` |
| `pipx` | Python | `pipx run 'black==24.10.0' .` |
| `npx` | Node.js | `npx eslint@9 --fix .` |
| `bunx` | Bun | `bunx eslint@9 --fix .` |
| `deno run` | Deno | `deno run npm:eslint@9 -- --fix .` |
| `go run` | Go | `go run golang.org/x/tools/cmd/goimports@v0.28.0 .` |

**Tips:**
- Pin versions (`npx eslint@9.0.0`) for reproducibility
- State prerequisites in SKILL.md ("Requires Node.js 18+")
- Use `compatibility` frontmatter for runtime-level requirements
- Move complex commands into scripts when they're hard to get right on first try

## Referencing Scripts from SKILL.md

Use relative paths from the skill directory root:

```markdown
## Available scripts

- **`scripts/validate.sh`** — Validates configuration files
- **`scripts/process.py`** — Processes input data

## Workflow

1. Run validation:
   ```bash
   bash scripts/validate.sh "$INPUT_FILE"
   ```
2. Process results:
   ```bash
   python3 scripts/process.py --input results.json
   ```
```

## Self-Contained Scripts

Bundle scripts that declare their own dependencies inline.

### Python (PEP 723)

```python scripts/extract.py
# /// script
# dependencies = [
#   "beautifulsoup4>=4.12,<5",
# ]
# ///

from bs4 import BeautifulSoup

html = '<html><body><h1>Welcome</h1></body></html>'
print(BeautifulSoup(html, "html.parser").select_one("h1").get_text())
```

Run with uv (recommended):
```bash
uv run scripts/extract.py
```

### Deno

```typescript scripts/extract.ts
#!/usr/bin/env -S deno run

import * as cheerio from "npm:cheerio@1.0.0";

const html = `<html><body><h1>Welcome</h1></body></html>`;
console.log(cheerio.load(html)("h1").text());
```

```bash
deno run scripts/extract.ts
```

### Bun

```typescript scripts/extract.ts
#!/usr/bin/env bun

import * as cheerio from "cheerio@1.0.0";

const html = `<html><body><h1>Welcome</h1></body></html>`;
console.log(cheerio.load(html)("h1").text());
```

```bash
bun run scripts/extract.ts
```

## Designing Scripts for Agentic Use

When an agent runs your script, it reads stdout and stderr to decide next steps. These design choices make scripts dramatically easier for agents to use.

### 1. Avoid Interactive Prompts (Hard Requirement)

Agents operate in non-interactive shells. A script blocking on interactive input **will hang indefinitely**.

Accept all input via flags, env vars, or stdin:

```
# Bad: hangs waiting for input
$ python scripts/deploy.py
Target environment: _

# Good: clear error with guidance
$ python scripts/deploy.py
Error: --env is required. Options: development, staging, production.
Usage: python scripts/deploy.py --env staging --tag v1.2.3
```

### 2. Document Usage with --help

`--help` is the primary way an agent learns your script's interface:

```
Usage: scripts/process.py [OPTIONS] INPUT_FILE

Process input data and produce a summary report.

Options:
  --format FORMAT    Output format: json, csv, table (default: json)
  --output FILE      Write output to FILE instead of stdout
  --verbose          Print progress to stderr

Examples:
  scripts/process.py data.csv
  scripts/process.py --format csv --output report.csv data.csv
```

Keep it concise — the output enters the agent's context window.

### 3. Write Helpful Error Messages

An opaque "Error: invalid input" wastes a turn. Say what went wrong, what was expected, and what to try:

```
Error: --format must be one of: json, csv, table.
       Received: "xml"
```

### 4. Use Structured Output

Prefer JSON, CSV, TSV over free-form text. Structured formats are consumable by both agents and standard tools (`jq`, `cut`, `awk`).

```
# Bad — hard to parse
NAME          STATUS    CREATED
my-service    running   2025-01-15

# Good — unambiguous
{"name": "my-service", "status": "running", "created": "2025-01-15"}
```

**Separate data from diagnostics:** structured data → stdout; progress/warnings → stderr.

### 5. Further Considerations

| Principle | Guidance |
|-----------|----------|
| **Idempotency** | "Create if not exists" is safer than "create and fail on duplicate" — agents may retry |
| **Input constraints** | Reject ambiguous input with clear errors; use enums and closed sets |
| **Dry-run support** | For destructive ops, `--dry-run` lets the agent preview |
| **Meaningful exit codes** | Distinct codes for different failure types; document in `--help` |
| **Safe defaults** | Destructive operations may require `--confirm` or `--force` |
| **Predictable output size** | Default to summary or limit; support `--offset` for pagination. For large output, require `--output FILE` or `-` for stdout opt-in |
