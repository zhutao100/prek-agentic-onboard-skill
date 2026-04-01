#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd -- "${script_dir}/.." && pwd)"
templates_dir="${skill_dir}/assets/templates"

usage() {
  cat >&2 <<'USAGE'
Usage:
  scaffold_workspace_mode.sh [--repo <path>] [--force] [--no-prekignore]

What it does (safe by default):
- Creates missing subproject configs for workspace mode (without rewriting existing ones):
  - python/.pre-commit-config.yaml
  - rust/.pre-commit-config.yaml
  - bash/.pre-commit-config.yaml
  - frontend/.pre-commit-config.yaml
  - ios/.pre-commit-config.yaml or swift/.pre-commit-config.yaml
- Optionally creates a baseline `.prekignore` at the repo root.

Notes:
- This script does NOT migrate an existing single root config into a “thin root”.
  After scaffolding, you still need to review `.pre-commit-config.yaml` and decide
  which hooks belong in root vs subprojects.
USAGE
}

repo="."
force=false
with_prekignore=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --force) force=true; shift ;;
    --no-prekignore) with_prekignore=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

cd "$repo"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  echo "error: not in a git repository: $repo" >&2
  exit 2
fi
cd "$repo_root"

config_exists_in_dir() {
  local d="$1"
  [[ -f "${d}/prek.toml" || -f "${d}/.pre-commit-config.yaml" || -f "${d}/.pre-commit-config.yml" ]]
}

maybe_copy() {
  local src="$1"
  local dst="$2"

  if [[ -f "$dst" && "$force" != "true" ]]; then
    echo "skip: exists: ${dst}" >&2
    return 0
  fi
  mkdir -p "$(dirname -- "$dst")"
  cp "$src" "$dst"
  echo "created: ${dst}" >&2
}

created_configs=()

if [[ "$with_prekignore" == "true" ]]; then
  if [[ -f ".prekignore" && "$force" != "true" ]]; then
    echo "skip: exists: .prekignore" >&2
  else
    maybe_copy "${templates_dir}/prekignore" ".prekignore"
  fi
fi

scaffold_dir() {
  local d="$1"
  local template="$2"

  if [[ ! -d "$d" ]]; then
    return 0
  fi
  if config_exists_in_dir "$d" && [[ "$force" != "true" ]]; then
    echo "skip: config exists in ${d}/" >&2
    return 0
  fi
  maybe_copy "${templates_dir}/${template}" "${d}/.pre-commit-config.yaml"
  created_configs+=("${d}/.pre-commit-config.yaml")
}

scaffold_dir "python" "workspace.python.pre-commit-config.yaml"
scaffold_dir "rust" "workspace.rust.pre-commit-config.yaml"
scaffold_dir "bash" "workspace.bash.pre-commit-config.yaml"
scaffold_dir "frontend" "workspace.frontend.pre-commit-config.yaml"

if [[ -d "ios" ]]; then
  scaffold_dir "ios" "workspace.swift.pre-commit-config.yaml"
elif [[ -d "swift" ]]; then
  scaffold_dir "swift" "workspace.swift.pre-commit-config.yaml"
fi

if command -v prek >/dev/null 2>&1; then
  configs=()
  [[ -f "prek.toml" ]] && configs+=("prek.toml")
  [[ -f ".pre-commit-config.yaml" ]] && configs+=(".pre-commit-config.yaml")
  [[ -f ".pre-commit-config.yml" ]] && configs+=(".pre-commit-config.yml")
  configs+=("${created_configs[@]}")

  if [[ "${#configs[@]}" -gt 0 ]]; then
    echo "Validating config(s)..." >&2
    prek validate-config "${configs[@]}"
  fi
else
  echo "note: prek not found in PATH; skipping config validation." >&2
fi

echo "Done. Next: run 'prek list' and 'prek run --all-files'." >&2
