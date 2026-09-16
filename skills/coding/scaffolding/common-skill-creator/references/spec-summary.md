# Specification Quick Reference

> Condensed reference for the Agent Skills specification. Use when verifying format requirements during skill creation.

## Directory Structure

```
skill-name/
├── SKILL.md          # Required: metadata + instructions
├── scripts/          # Optional: executable code
├── references/       # Optional: documentation
├── assets/           # Optional: templates, resources
└── ...               # Any additional files or directories
```

A skill is a directory containing, at minimum, a `SKILL.md` file.

## Frontmatter Fields

The `SKILL.md` file must contain YAML frontmatter (between `---` delimiters) followed by Markdown content.

| Field | Required | Constraints |
|-------|----------|-------------|
| `name` | Yes | Max 64 chars. Lowercase letters, numbers, hyphens only. Must not start/end with hyphen. Must match parent directory name. |
| `description` | Yes | Max 1024 chars. Non-empty. Describes what the skill does and when to use it. |
| `license` | No | License name or reference to a bundled license file. |
| `compatibility` | No | Max 500 chars. Environment requirements (product, system packages, network, etc.). |
| `metadata` | No | Arbitrary key-value mapping (string keys to string values). |
| `allowed-tools` | No | Space-separated string of pre-approved tools. (Experimental) |

### Minimal Example

```yaml
---
name: skill-name
description: A description of what this skill does and when to use it.
---
```

### Full Example

```yaml
---
name: pdf-processing
description: Extract PDF text, fill forms, merge files. Use when handling PDFs.
license: Apache-2.0
compatibility: Requires Python 3.14+ and uv
metadata:
  author: example-org
  version: "1.0"
allowed-tools: Bash(git:*) Read
---
```

## name Field Rules

- 1-64 characters
- Only unicode lowercase alphanumeric (`a-z`, `0-9`) and hyphens (`-`)
- Must not start or end with a hyphen
- Must not contain consecutive hyphens (`--`)
- **Must match the parent directory name**

**Valid:** `pdf-processing`, `data-analysis`, `code-review`

**Invalid:** `PDF-Processing` (uppercase), `-pdf` (starts with hyphen), `pdf--processing` (consecutive hyphens)

## description Field Rules

- 1-1024 characters
- Should describe both **what** the skill does and **when** to use it
- Should include specific keywords that help agents identify relevant tasks
- Use imperative phrasing ("Use this skill when...")
- Focus on user intent, not implementation

## Body Content

No format restrictions. Recommended sections:
- Step-by-step instructions
- Examples of inputs and outputs
- Common edge cases

## Progressive Disclosure

Agents load skills progressively:

1. **Metadata** (~100 tokens): `name` + `description` loaded at startup for all skills
2. **Instructions** (< 5000 tokens recommended): Full `SKILL.md` body loaded when skill is activated
3. **Resources** (as needed): Files in `scripts/`, `references/`, `assets/` loaded only when required

Keep SKILL.md under 500 lines. Move detailed reference material to separate files.

## File References

Use relative paths from the skill root:

```markdown
See [the reference guide](references/REFERENCE.md) for details.

Run the extraction script:
scripts/extract.py
```

Keep file references one level deep from SKILL.md. Avoid deeply nested reference chains.

## Optional Directories

### scripts/
- Self-contained or clearly documented dependencies
- Helpful error messages
- Graceful edge case handling
- Supported languages: Python, Bash, JavaScript (varies by agent)

### references/
- `REFERENCE.md` — Detailed technical reference
- Domain-specific files (`finance.md`, `legal.md`, etc.)
- Keep individual files focused — agents load on demand

### assets/
- Templates (document, configuration)
- Images (diagrams, examples)
- Data files (lookup tables, schemas)

## Validation

Validate skills with the reference library:

```bash
skills-ref validate ./my-skill
```

This checks frontmatter validity and naming conventions.
