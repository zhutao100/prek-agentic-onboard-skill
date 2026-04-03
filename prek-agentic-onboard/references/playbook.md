# Playbook: prek onboarding for agentic workflows

This document is written to be used by agents operating in a real codebase.

## 0) Pre-flight questions (decide before changing anything)

1. Do you need **strict upstream pre-commit compatibility**?
   - Yes: stick to `.pre-commit-config.yaml` and avoid prek-only features (`repo: builtin`, TOML, workspace-only extensions).
   - No / willing to adopt prek fully: consider `repo: builtin` for baseline hygiene and consider TOML.

2. Is the repo a **polyglot monorepo**?
   - Yes: prefer **workspace mode**: a thin root config + per-subproject configs.
   - No: a single root config is fine.

3. Do you want **commit convergence** (auto-format + auto-stage) for agents?
   - Yes: pick Strategy A (global shim) or Strategy B (wrappers).

## 1) Greenfield bootstrap (minimal safe path)

Commands:

```bash
prek validate-config .pre-commit-config.yaml  # or: prek validate-config prek.toml
prek install --prepare-hooks
prek run --all-files --show-diff-on-failure
```

If there is no config file yet, create one:

- Portable: copy `assets/templates/pre-commit-config.portable.yaml` → `.pre-commit-config.yaml`
- Prek-only fast path: copy `assets/templates/pre-commit-config.builtin.yaml` → `.pre-commit-config.yaml`

Or generate from prek itself:

```bash
prek sample-config --format yaml --file .pre-commit-config.yaml
```

## 2) Migration from pre-commit

Lowest risk migration:

- do not rewrite `.pre-commit-config.yaml`
- switch runner to `prek`
- run a parity check branch in CI (or locally with `--all-files`)

Use `scripts/migrate_precommit_to_prek.sh`.

Follow-up (what agents commonly miss):

- **Review the existing `.pre-commit-config.yaml`** for language coverage and hook intent.
  - For polyglot repos, ensure Rust/Python/JS/Shell/etc have *both* formatting and checks as appropriate.
- If the repo is a **polyglot monorepo**, consider moving to **workspace mode** (thin root + per-subproject configs).
  - Safe scaffold: `scripts/scaffold_workspace_mode.sh` (creates missing subproject configs without rewriting existing ones).
  - Then run `prek --refresh list` to confirm multiple projects are discovered and `prek run --all-files` to validate end-to-end.

## 3) Workspace mode (polyglot repos)

Recommended layout (“thin root, thick leaves”):

- Root `.pre-commit-config.yaml`: only repo-wide hygiene and security checks
- Subprojects: each has its own `.pre-commit-config.yaml` for language-local toolchains/lockfiles
  - Omit `orphan: true` by default so root hygiene hooks still apply inside subprojects.

Templates:

- `assets/templates/workspace.*.pre-commit-config.yaml`
- `assets/templates/workspace.bash.pre-commit-config.yaml`
- `assets/templates/prekignore`
- For JS/TS formatting, prefer lockfile-driven Prettier (or `npm exec prettier@...`) rather than `pre-commit/mirrors-prettier`, which can lag behind upstream.

Run patterns:

```bash
prek run                 # from workspace root
prek run -C frontend     # focus one subtree
prek run --directory frontend
```

Tip: workspace discovery is cached; after adding/removing nested configs, use `--refresh` (for example `prek --refresh list`).

## 4) Agentic commit convergence

### Strategy A (recommended): global self-healing shim

- Install `.githooks/pre-commit` and set `core.hooksPath` to `.githooks`.
- The hook loops: `prek run` → if it changed staged files, `git add` and retry.

Use `scripts/setup_agentic_autostage_shim.sh`.

Quick verify:

```bash
git config --get core.hooksPath   # expect: .githooks
test -x .githooks/pre-commit
```

### Strategy B: per-language wrappers

Wrappers in `scripts/hooks/` format the staged set, stage changes, then run strict gates.

Example wiring:

```yaml
repos:
  - repo: local
    hooks:
      - id: ruff-autostage
        name: ruff (autostage)
        entry: ./scripts/ruff_autostage.sh
        language: system
        pass_filenames: false
        files: \.pyi?$
        require_serial: true
```

## 5) Concurrency and ordering rules

- Keep **mutating hooks** from running concurrently.
- If you use `priority` parallelism, do not put two mutators in the same priority group.
- Use `require_serial: true` for hooks with global locks or toolchains that do not tolerate parallel execution.

## 6) CI guidance

- Prefer `prek run --all-files` in CI for determinism.
- Cache `PREK_HOME` to avoid cold starts.
