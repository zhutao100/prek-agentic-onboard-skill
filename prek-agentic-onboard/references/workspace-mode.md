# Workspace mode: polyglot best practices

Workspace mode is the prek feature that allows multiple `.pre-commit-config.yaml` files within one repository.

## Core operating model

- There is a **workspace root** (the nearest ancestor directory containing a config).
- Under that root, prek discovers **nested configs**; each directory with a config becomes a **project**.
- A project is executed in its own directory context; it typically cannot see files outside its subtree.

## Recommended structure

- Root config: cross-cutting checks only.
- Per-subproject configs: language-local hooks that rely on local toolchains and lockfiles.
- Use `orphan: true` to prevent duplicated processing from parent configs.

## Discovery exclusions

- `.gitignore` is honored.
- `.prekignore` adds additional workspace discovery exclusions.
- After modifying ignore rules, use `--refresh`.

## Targeted runs

- Run all: `prek run` from workspace root
- Focus subtree: `prek run -C <dir>` or `cd <dir> && prek run`
- Focus directory: `prek run --directory <dir>`

## Common mistake

Avoid configuring a hook in a subproject that needs to see files outside its subtree; place cross-cutting hooks at a common ancestor instead.
