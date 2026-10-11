<h1 align="center">Grape Skills</h1>

<p align="center">English | <a href="README.zh.md">中文</a></p>

<p align="center">Official Grape Skills Repository</p>

<p align="center">
  <a href="#overview">Overview</a> ·
  <a href="#repository-structure">Repository Structure</a> ·
  <a href="#skills">Skills</a> ·
  <a href="#scenes">Scenes</a> ·
  <a href="#grape-cli-convention">Grape CLI Convention</a> ·
  <a href="#contributing">Contributing</a>
</p>

---

## Overview

Grape Skills spans the full DevOps lifecycle, equipping Agents with best-practice playbooks across every scenario. Under AI-native DevOps, these playbooks encode the operating rules and methodologies for human–Agent and organization–Agent collaboration, making AI-native best practices easy to apply to any project.

Grape Skills is the official skills repository of Grape. It maintains two kinds of content, pulled by the Grape platform at build/deploy time:

- **Skills (`skills/`)** — organized as `agent_type / sub_scene / skill` three-level directories, fetched via build-time clone / volume-mount.
- **Scenes (`scenes/`)** — one directory per scene; its `scene.json` defines the workflow (mounting registered skills) and is the **single source of truth** synced to the frontend scene marketplace.

## Repository Structure

```
grape-skills/
├── skill-description.json   # Skill registry (key → name/agent_type/sub_scene/path/description)
├── pipelines.json           # Legacy scene snapshot — do not edit
├── scenes/<scene>/          # Scene definitions (unique sync source)
│   ├── scene.json           # Workflow nodes (mount registered skills)
│   └── README.md
└── skills/
    ├── <agent_type>/        # vod | issue | coding | qa | sre | chat
    │   └── <sub_scene>/     # e.g. feedback-loop / scaffolding / auto-testing
    │       └── <skill>/     # SKILL.md + optional references/ | scripts/ | templates/
    └── _template/           # Bootstrap template for new skills
```

## Skills

### Skill Format

Each skill is a directory containing `SKILL.md` (frontmatter: `name` / `description` / `version`) plus optional `references/`, `scripts/`, `templates/`.

### Taxonomy

`agent_type` is one of `vod | issue | coding | qa | sre | chat`, each mapping to a stage of the
development workflow — voice → requirements → implementation → review → deploy & ops:

| agent_type | Primary role |
|---|---|
| vod | Collect developer feedback, cluster insights, seed & guide Issues |
| issue | Issue lifecycle ops (triage, label, assign, trigger coding) |
| coding | AI code implementation, PR creation, publish-content generation |
| qa | PR review, automated testing, security scans |
| sre | Build & deploy, release management, ops diagnostics |
| chat | IM dialogue / notification |

Skills are then grouped by `sub_scene`:

| sub_scene | Scope | agent_type |
|---|---|---|
| feedback-loop | Requirement gathering, Issue ops | vod, issue |
| ai-coding-review | AI code implementation & PR | coding |
| scaffolding | Skill generators | coding |
| app-release | Build / release / publish | coding, sre |
| code-quality | Code / PR review | qa |
| auto-testing | Automated testing | qa |
| ci | Build debug | sre |
| observability | Incident triage | sre |
| container-deploy | Runtime install | sre |
| log-diagnostics | Log diagnosis | sre |
| im | IM dialogue / notification | chat |
| meeting / other / code-hosting / browser-verify | Reserved (no skills yet) | — |

> Reserved rows: `.git`-tracked as empty placeholder dirs; the first skill added goes directly into that sub_scene.

### Registration

Every skill **must** be registered in `skill-description.json`, with `path` matching its three-level directory:

```json
{
  "<skill-name>": {
    "name": "Display name",
    "agent_type": "coding",
    "sub_scene": "scaffolding",
    "path": "coding/scaffolding/<skill-name>",
    "description": "One-line purpose & how to invoke"
  }
}
```

> The authoritative list of registered skills (name/agent_type/sub_scene/path/description) lives in `skill-description.json` — not maintained here.

## Scenes

- Sync reads **only** `scenes/<scene>/scene.json` (unique sync source; `pipelines.json` is legacy).
- Workflow nodes mount registered skills via the `skill` field.
- Referencing an unregistered skill requires **registering it in the same PR** (register & reference in one PR).

## Grape CLI Convention

Skills that interact with the Grape platform (GitCode / Issue / Task / Skills / A2A) **must use the `grape` CLI** — no `curl` against APIs:

- Use `grape <group> <verb> [--args]`; discover commands via `grape commands`, `grape <group> --help`.
- Tokens are auto-injected by the CLI — never in command lines, files, logs, or comments.
- Use `grape git` for platform git ops (credentials injected via `GIT_CONFIG`, zero exposure).
- See `grape-cli-guidance` for usage recipes. Local-only / third-party services skills are exempt.

Install (local agent):

```bash
pip install git+https://gitcode.com/grape-dev/grape-cli.git
```

## Contributing

1. Plan the three-level directory for new/modified skills (`<agent_type>/<sub_scene>/<skill>`).
2. Register new skills in `skill-description.json`.
3. Platform-interactive skills must follow the Grape CLI convention.
4. New/modified scenes mount registered skills (or register them in the same PR).
5. Submit the PR — maintainers review and decide.

## Versioning

- Default branch: `main`.
- Version tags are semver (e.g. `v1.0.0`); breaking changes bump the major version. Grape releases pin a `tag` or `commit`.

## Usage

The Grape system periodically syncs skills from this repo; developers then run them by selecting the corresponding scene and skills for their project in Grape.