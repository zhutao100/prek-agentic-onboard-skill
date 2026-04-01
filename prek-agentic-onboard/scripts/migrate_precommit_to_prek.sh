#!/usr/bin/env bash
set -euo pipefail

repo="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: migrate_precommit_to_prek.sh [--repo <path>]" >&2
      exit 0
      ;;
    *) echo "error: unknown arg: $1" >&2; exit 2 ;;
  esac
done

cd "$repo"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  echo "error: not in a git repository: $repo" >&2
  exit 2
fi
cd "$repo_root"

config_files=()
[[ -f "prek.toml" ]] && config_files+=("prek.toml")
[[ -f ".pre-commit-config.yaml" ]] && config_files+=(".pre-commit-config.yaml")
[[ -f ".pre-commit-config.yml" ]] && config_files+=(".pre-commit-config.yml")
if [[ "${#config_files[@]}" -eq 0 ]]; then
  echo "error: no configuration file found (expected prek.toml or .pre-commit-config.yaml/.yml)" >&2
  exit 2
fi

ts="$(date +%Y%m%d-%H%M%S)"
hooks_dir="$(git rev-parse --git-path hooks)"
backup_dir="${hooks_dir}.backup.${ts}"

mkdir -p "${backup_dir}"
if [[ -d "${hooks_dir}" ]]; then
  cp -a "${hooks_dir}/." "${backup_dir}/"
fi
echo "Backed up hooks to: ${backup_dir}" >&2

if command -v pre-commit >/dev/null 2>&1; then
  echo "Running: pre-commit uninstall (best-effort)..." >&2
  pre-commit uninstall || true
fi

if ! command -v prek >/dev/null 2>&1; then
  echo "error: prek not found in PATH. Install it first (brew/uv/pipx/pip)." >&2
  exit 2
fi

echo "Validating config..." >&2
prek validate-config "${config_files[@]}"

hooks_path="$(git config --get core.hooksPath || true)"
if [[ -n "$hooks_path" ]]; then
  echo "Detected core.hooksPath=$hooks_path; skipping 'prek install' and only preparing hook envs." >&2
  prek prepare-hooks
else
  echo "Installing prek shims + preparing hook envs..." >&2
  prek install -f --prepare-hooks
fi

echo "Smoke test: prek run --all-files" >&2
prek run --all-files --show-diff-on-failure

cat >&2 <<EOF
Migration complete.

Rollback options:
- Restore hooks from: ${backup_dir}
- Re-run: pre-commit install (if you want to go back)
EOF
