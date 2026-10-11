# Contributing to Grape Skills

Thanks for considering contributing to the official **Grape Skills** content repository. This repo maintains two kinds of content consumed by the Grape platform:

- **Skills** (`skills/`) — organized as `agent_type / sub_scene / skill` three-level directories.
- **Scenes** (`scenes/`) — one directory per scene, with `scene.json` workflow definitions.

Read the [README](README.md) first for the full taxonomy, registration rules, and scene semantics.

## Getting Started

1. Fork the repository and create a feature branch: `feat/xxx`, `fix/xxx`, `docs/xxx`, `chore/xxx`.
2. Make your changes, following the rules below.
3. Verify locally (validate JSON, check links), then submit a PR back to `main`.

## Adding or Modifying a Skill

A skill lives at `skills/<agent_type>/<sub_scene>/<skill>/`:

```
<skill>/
├── SKILL.md           # frontmatter: name / description / version
├── references/        # optional reference material
├── scripts/           # optional helper scripts
└── templates/         # optional templates
```

- Pick a correct `agent_type` (`vod/issue/coding/qa/sre/chat`) and `sub_scene`; if none fits, confirm with maintainers before creating a new `sub_scene`.
- **Register the skill** in `skill-description.json`; the `path` must match the actual three-level directory.
- Skills that interact with the Grape platform (GitCode / Issue / Task / Skills / A2A) **must use the `grape` CLI** — never `curl` platform APIs directly, and never commit tokens.

## Adding or Modifying a Scene

- Each scene is a directory under `scenes/` with `scene.json` + `README.md`.
- Workflow nodes mount **registered** skills via the `skill` field. Referencing an unregistered skill requires registering it **in the same PR**.
- **Edit only `scenes/<scene>/scene.json`** — it is the single source of truth synced to the scene marketplace. Do not edit `pipelines.json` (legacy snapshot).
- `next` must point to an existing node id; `handoff` must be a valid enum (`a2a`/`complete`); no dangling references.

## Commit Messages

Use **English** and follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short subject>
```

| type | Purpose |
|------|---------|
| `feat` | New skill / scene / feature |
| `fix` | Bugfix |
| `docs` | Documentation |
| `refactor` | Non-behavioral refactor |
| `chore` | Maintenance, tooling |

## Pull Requests

- Describe what and why, and how it was verified.
- Keep the PR focused on one change.
- Ensure no secrets or internal information are introduced (see [SECURITY](SECURITY.md)).

## Versioning

- Default branch: `main`.
- Tags are semver (`v1.0.0`); breaking changes bump the major version.

## Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md).