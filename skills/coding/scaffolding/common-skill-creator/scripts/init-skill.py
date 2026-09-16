#!/usr/bin/env python3
# /// script
# dependencies = []
# ///
"""
init-skill.py — Scaffold a new skill directory with SKILL.md template.

Usage:
    python3 scripts/init-skill.py <skill-name> [--output <parent-dir>] [--with-scripts] [--with-references] [--with-assets] [--with-evals]

Creates a skill directory with:
    <skill-name>/
    ├── SKILL.md          (from template)
    ├── scripts/          (if --with-scripts)
    ├── references/       (if --with-references)
    ├── assets/           (if --with-assets)
    └── evals/            (if --with-evals)

The SKILL.md is generated from the bundled template with the skill name substituted.

Examples:
    python3 scripts/init-skill.py pdf-processing --with-scripts --with-references
    python3 scripts/init-skill.py data-analysis --output ./skills --with-evals

Exit codes:
    0 = success
    1 = skill name validation failed
    2 = usage error
"""
import argparse
import os
import re
import sys


NAME_PATTERN = re.compile(r'^[a-z0-9]+(-[a-z0-9]+)*$')


SKILL_TEMPLATE = '''---
name: {name}
description: >
  {description}
---

# {title}

## Overview

Briefly describe what this skill does and when an agent should use it.

## Prerequisites

List any environment requirements, dependencies, or tools needed.

## Workflow

1. Step one
2. Step two
3. Step three

## Core Commands / Patterns

```bash
# Example command or pattern
```

## Gotchas

- Non-obvious fact or pitfall the agent would not know without being told

## Edge Cases

| Scenario | Handling |
|----------|---------|
| Unusual situation | How to handle it |

## Available Scripts

- **`scripts/example.py`** — Description of what it does

## Reference Documents

- **`references/example.md`** — Description and when to read it
'''


EVALS_TEMPLATE = '''{
  "skill_name": "{{SKILL_NAME}}",
  "evals": [
    {
      "id": 1,
      "prompt": "A realistic user prompt that should trigger this skill.",
      "expected_output": "Human-readable description of what success looks like.",
      "files": [],
      "assertions": [
        "A specific, verifiable assertion about the output"
      ]
    }
  ]
}
'''


def validate_name(name: str) -> tuple[bool, str]:
    """Validate skill name against spec constraints."""
    if not name:
        return False, "name is empty"
    if len(name) > 64:
        return False, f"name exceeds 64 characters ({len(name)} chars)"
    if not NAME_PATTERN.match(name):
        return False, (
            "name must be lowercase a-z, 0-9, and hyphens only; "
            "must not start/end with hyphen; no consecutive hyphens"
        )
    return True, ""


def title_from_name(name: str) -> str:
    """Convert kebab-case name to Title Case."""
    return ' '.join(word.capitalize() for word in name.split('-'))


def description_from_name(name: str) -> str:
    """Generate a placeholder description from the skill name."""
    title = title_from_name(name)
    return (
        f"Use this skill when the user wants to {title.lower()}. "
        f"Describe what this skill does, when to use it, and the key "
        f"scenarios where it applies — even if the user doesn't explicitly "
        f"mention '{name}'."
    )


def main():
    parser = argparse.ArgumentParser(
        prog='init-skill.py',
        description='Scaffold a new skill directory with SKILL.md template.'
    )
    parser.add_argument(
        'name',
        help='Skill name (lowercase a-z, 0-9, hyphens; no leading/trailing/consecutive hyphens)'
    )
    parser.add_argument(
        '--output', '-o',
        default='.',
        help='Parent directory to create the skill in (default: current directory)'
    )
    parser.add_argument(
        '--with-scripts',
        action='store_true',
        help='Create a scripts/ subdirectory'
    )
    parser.add_argument(
        '--with-references',
        action='store_true',
        help='Create a references/ subdirectory'
    )
    parser.add_argument(
        '--with-assets',
        action='store_true',
        help='Create an assets/ subdirectory'
    )
    parser.add_argument(
        '--with-evals',
        action='store_true',
        help='Create an evals/ subdirectory with evals.json template'
    )
    parser.add_argument(
        '--description', '-d',
        default=None,
        help='Custom description (default: auto-generated placeholder)'
    )
    parser.add_argument(
        '--force',
        action='store_true',
        help='Overwrite existing directory if it exists'
    )

    args = parser.parse_args()

    # Validate name
    valid, error = validate_name(args.name)
    if not valid:
        print(f"Error: invalid skill name '{args.name}': {error}", file=sys.stderr)
        return 1

    # Resolve output path
    parent = os.path.abspath(args.output)
    if not os.path.isdir(parent):
        print(f"Error: output directory does not exist: {parent}", file=sys.stderr)
        return 2

    skill_dir = os.path.join(parent, args.name)

    # Check if exists
    if os.path.exists(skill_dir):
        if not args.force:
            print(f"Error: directory already exists: {skill_dir}", file=sys.stderr)
            print(f"  Use --force to overwrite", file=sys.stderr)
            return 2
        elif os.path.isfile(os.path.join(skill_dir, 'SKILL.md')):
            # Don't destroy, just warn
            print(f"Warning: SKILL.md already exists in {skill_dir}, will not overwrite it", file=sys.stderr)

    # Create directories
    os.makedirs(skill_dir, exist_ok=True)
    print(f"Created: {skill_dir}")

    subdirs = []
    if args.with_scripts:
        os.makedirs(os.path.join(skill_dir, 'scripts'), exist_ok=True)
        subdirs.append('scripts')
    if args.with_references:
        os.makedirs(os.path.join(skill_dir, 'references'), exist_ok=True)
        subdirs.append('references')
    if args.with_assets:
        os.makedirs(os.path.join(skill_dir, 'assets'), exist_ok=True)
        subdirs.append('assets')
    if args.with_evals:
        os.makedirs(os.path.join(skill_dir, 'evals'), exist_ok=True)
        subdirs.append('evals')

    for sd in subdirs:
        print(f"  Created: {sd}/")

    # Generate SKILL.md
    skill_md_path = os.path.join(skill_dir, 'SKILL.md')
    if not os.path.exists(skill_md_path) or args.force:
        description = args.description or description_from_name(args.name)
        title = title_from_name(args.name)
        content = SKILL_TEMPLATE.format(
            name=args.name,
            description=description,
            title=title
        )
        with open(skill_md_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"  Created: SKILL.md")

    # Generate evals.json if requested
    if args.with_evals:
        evals_path = os.path.join(skill_dir, 'evals', 'evals.json')
        if not os.path.exists(evals_path) or args.force:
            with open(evals_path, 'w', encoding='utf-8') as f:
                f.write(EVALS_TEMPLATE.replace('{{SKILL_NAME}}', args.name))
            print(f"  Created: evals/evals.json")

    # Summary
    print(f"\nSkill '{args.name}' scaffolded successfully.")
    print(f"Path: {skill_dir}")
    print(f"\nNext steps:")
    print(f"  1. Edit SKILL.md — replace placeholder content with your skill instructions")
    print(f"  2. Write an effective description (see references/description-optimization.md)")
    print(f"  3. Add scripts, references, or assets as needed")
    print(f"  4. Validate: bash scripts/validate-skill.sh {skill_dir}")

    return 0


if __name__ == '__main__':
    sys.exit(main())
