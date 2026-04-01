# prek agentic onboard skill repo

This repository is a **ready-to-install Agent Skill** for onboarding and migrating Git repositories from **pre-commit** to **prek**, with an emphasis on:

- **Polyglot / monorepo workspace mode** (multiple `.pre-commit-config.yaml` files)
- **Agent-friendly “one-shot” commits** (auto-format + auto-stage convergence)
- Copy/paste-ready **baseline configs** and **hook wrapper scripts** for common languages

## What’s inside

- `prek-agentic-onboard/` — the skill folder (contains `SKILL.md`, scripts, templates, and references)
- `AGENTS.md` — repo-level guidance for agentic maintenance of this skill repo

## Install

### Codex CLI

1. Put this repo (or just the `prek-agentic-onboard/` folder) somewhere stable.
2. Add it to your Codex skill search path (per your Codex CLI setup).
3. In Codex CLI, run `/skills` to verify it is discoverable, or reference it explicitly by name.

### Other agent tools

This skill follows the open Agent Skills standard: a folder containing `SKILL.md` with YAML frontmatter.

## Typical usage

Run from anywhere; pass `--repo <path-to-project>` (defaults to the current directory):

- Greenfield setup: run `prek-agentic-onboard/scripts/prek_bootstrap.sh --repo <path> --install-prek --config portable`
- Migration: run `prek-agentic-onboard/scripts/migrate_precommit_to_prek.sh --repo <path>`
- Agentic auto-stage (global shim): run `prek-agentic-onboard/scripts/setup_agentic_autostage_shim.sh --repo <path>`
- Per-language auto-stage wrappers: copy from `prek-agentic-onboard/scripts/hooks/` and wire via `repo: local` hooks

See `prek-agentic-onboard/references/` for the playbook and templates.
