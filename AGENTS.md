# AGENTS.md

## Purpose of this repository

This repo is a **skill bundle**. Treat it as a product artifact that other agents will copy into their environments to reliably onboard **prek** in real codebases.

## Non-negotiables

- Keep `prek-agentic-onboard/SKILL.md` frontmatter valid:
  - `name` must match the folder name (`prek-agentic-onboard`).
  - `description` must remain explicit about trigger conditions.
- Prefer **templates + scripts** over long prose.
- Do not proliferate many small docs. If adding reference material, consolidate into the existing reference files unless a new file is clearly justified.

## Editing workflow

1. Make changes in small commits (one conceptual change per commit).
2. When adding a script:
   - `#!/usr/bin/env bash`
   - `set -euo pipefail`
   - NUL-delimited filename handling for Git file lists
   - Avoid non-portable bashisms where feasible; assume macOS and Linux.
3. When adding templates:
   - Put them under `prek-agentic-onboard/assets/templates/`
   - Provide a short “how to apply” note in `references/playbook.md`.

## Verification checklist (manual)

- Repo structure is intact (root files + single skill directory).
- `SKILL.md` YAML frontmatter parses and matches folder name.
- Scripts are executable where intended.
- Wrapper hooks do not assume unstaged files; they should operate on **staged** files by default and re-stage changes.

## Intended scope

- Onboarding / migration: `pre-commit` → `prek`
- Workspace mode polyglot best practices
- Agent-friendly commit convergence patterns (auto-format + auto-stage)
