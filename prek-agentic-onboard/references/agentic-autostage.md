# Agentic auto-stage: design notes and wiring examples

## Why this exists

Both pre-commit and prek fail a commit when a hook modifies files, requiring a manual `git add` and re-commit. For agentic workflows, this creates avoidable multi-turn tool churn.

At time of writing (2026-04), prek does not provide a built-in “auto-stage and continue” feature; implement it in your workflow.

## Strategy A: global self-healing shim (recommended)

### Properties

- Applies to *any* mutating hook (EOF fixer, formatter, etc.)
- Requires no per-tool wrappers
- Works best when you set `core.hooksPath` to `.githooks` and store the shim there

### Install

Use `scripts/setup_agentic_autostage_shim.sh`.

### Tuning

- `PREK_AUTOFIX_MAX_ROUNDS` controls convergence attempts.

## Strategy B: per-language wrappers

Wrappers provided:

- Swift: `precommit_swift_format_autostage.sh` (prefers first-party `swift-format`; can use `swiftformat`)
- Python: `ruff_autostage.sh`
- JS/TS: `prettier_autostage_pnpm.sh` (lockfile-driven; avoids stale mirror repos)
- Rust: `rustfmt_autostage.sh`
- Shell: `shfmt_autostage.sh`

### Wiring patterns

#### Swift

Notes:

- Default selection prefers first-party `swift-format` unless a legacy `.swiftformat*` config is detected.
- Override auto-detection: `SWIFT_FORMATTER_TOOL=swiftformat|swift-format`

```yaml
repos:
  - repo: local
    hooks:
      - id: swift-format-autostage
        name: swift-format / swiftformat (autostage)
        entry: ./scripts/precommit_swift_format_autostage.sh
        language: system
        pass_filenames: false
        files: \.swift$
        require_serial: true
```

#### Python (Ruff)

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

#### JS/TS (Prettier + ESLint)

Use local hooks so versions come from your lockfile:

```yaml
repos:
  - repo: local
    hooks:
      - id: prettier-autostage
        name: prettier (autostage)
        entry: ./scripts/prettier_autostage_pnpm.sh
        language: system
        pass_filenames: false
        require_serial: true
```

#### Rust

```yaml
repos:
  - repo: local
    hooks:
      - id: rustfmt-autostage
        name: cargo fmt (autostage)
        entry: ./scripts/rustfmt_autostage.sh
        language: system
        pass_filenames: false
        files: \.rs$
        require_serial: true
```

#### Shell

```yaml
repos:
  - repo: local
    hooks:
      - id: shfmt-autostage
        name: shfmt (autostage)
        entry: ./scripts/shfmt_autostage.sh
        language: system
        pass_filenames: false
        files: \.sh$
        require_serial: true
```

## Ordering and parallelism

- Keep mutators first.
- Avoid running multiple mutators concurrently (distinct priorities, or `require_serial`).

## Quick verify (Strategy A)

After installing the self-healing shim, confirm Git is actually using it:

```bash
git config --get core.hooksPath   # expect: .githooks
test -x .githooks/pre-commit
```

If `core.hooksPath` is empty (or points elsewhere), `git commit` is likely still using `.git/hooks/pre-commit`
(for example a prek-generated shim), and mutating hooks will stop the commit with “files were modified by this hook”.
