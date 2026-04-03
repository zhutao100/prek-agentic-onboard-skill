---
name: prek-agentic-onboard
description: Onboard or migrate repositories from pre-commit to prek, including workspace-mode polyglot setup and agent-friendly auto-format+auto-stage commit convergence (global shim or per-language wrapper hooks).
license: MIT
compatibility: Designed for Codex CLI and other Agent Skills clients. Requires git and a POSIX shell; optional tools per language (ruff, pnpm, cargo, shfmt, swiftformat/swift-format). Internet access recommended for installing/updating hooks.
metadata:
  version: "1.0.1"
  updated: "2026-04-03"
---

# prek agentic onboard

## When to use this skill

Use this skill when you need to:

- set up **prek** in a repo (greenfield), or migrate from **pre-commit**
- structure hooks for **polyglot repos** (workspace / multi-config)
- eliminate agent churn from formatter hooks by achieving **commit convergence**:
  - run formatters/fixers
  - auto-stage updates
  - re-run until stable, then proceed

## Decision tree

1. **Greenfield** vs **Migration**
   - Greenfield: create or adopt `.pre-commit-config.yaml`, then `prek install --prepare-hooks`.
   - Migration: keep existing `.pre-commit-config.yaml` initially; switch runner to prek; optionally add prek-only features later.

2. **Single-config** vs **Workspace mode**
   - Single-config: one root `.pre-commit-config.yaml` with path scoping.
   - Workspace mode: multiple `.pre-commit-config.yaml` files per subproject. Preferred for monorepos.

3. **Agentic auto-stage strategy**
   - **Strategy A (recommended): global self-healing `pre-commit` shim**
     - A Git hook script loops `prek run` + `git add` until stable (or max rounds).
     - Pros: works for *any* mutating hooks (EOF fixers, formatters, etc.).
   - **Strategy B: per-language wrapper hooks**
     - Each formatter wrapper formats staged files, stages them, then runs a strict gate.
     - Pros: portable to pre-commit too, but requires more wrappers.

## Step-by-step procedures

All scripts support `--repo <path>` (default: current working directory) and locate templates relative to the script, so you do **not** need to copy this skill folder into the target repo.

### A) Greenfield bootstrap (portable YAML baseline)

Run:

```bash
bash prek-agentic-onboard/scripts/prek_bootstrap.sh --repo <path-to-repo> --install-prek --config portable
```

This will:

- ensure `prek` exists (optionally install via brew/uv/pipx/python)
- install a baseline `.pre-commit-config.yaml` if missing
- validate configuration file(s) (e.g. `prek validate-config .pre-commit-config.yaml`)
- install git shims + prepare hook envs

### B) Migrate pre-commit → prek (keep config unchanged)

Run:

```bash
bash prek-agentic-onboard/scripts/migrate_precommit_to_prek.sh --repo <path-to-repo>
```

This will back up `.git/hooks/`, run `pre-commit uninstall` if present, then install prek shims (or run `prek prepare-hooks` if `core.hooksPath` is set).

Then (recommended):

- Review the existing `.pre-commit-config.yaml` and ensure **all major languages** in the repo have appropriate hooks (format + checks).
- If the repo is polyglot, switch to **workspace mode** (thin root + per-subproject configs) and verify:
  - scaffold missing subproject configs: `bash prek-agentic-onboard/scripts/scaffold_workspace_mode.sh --repo <path-to-repo>`
  - confirm discovery: `prek list`
  - end-to-end run: `prek run --all-files`

### C) Enable agent-friendly commit convergence (Strategy A)

Run:

```bash
bash prek-agentic-onboard/scripts/setup_agentic_autostage_shim.sh --repo <path-to-repo>
```

This will:

- create `.githooks/pre-commit` that runs `prek run` in a loop and auto-stages if hooks changed staged files
- set `git config core.hooksPath .githooks`

### D) Per-language auto-stage wrappers (Strategy B)

Copy a wrapper from:

- `prek-agentic-onboard/scripts/hooks/`

Wire it into your `.pre-commit-config.yaml` via `repo: local` hooks (examples in `references/agentic-autostage.md`).

## References and templates

- `references/playbook.md` — end-to-end playbook
- `assets/templates/` — baseline configs, workspace templates, `.prekignore`, and the self-healing hook shim
- `scripts/hooks/` — language wrappers (Swift/Python/JS/Rust/Shell)
