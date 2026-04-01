#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd -- "${script_dir}/.." && pwd)"
templates_dir="${skill_dir}/assets/templates"

usage() {
  cat >&2 <<'USAGE'
Usage:
  prek_bootstrap.sh [--repo <path>] [--install-prek] [--config portable|builtin] [--run-all-files]

Defaults:
  --repo          current working directory
  --config        portable

Notes:
- If `git config core.hooksPath` is set, `prek install` may refuse or install to an unexpected location.
  This script will detect hooksPath and fall back to `prek prepare-hooks` in that case.
USAGE
}

repo="."
install_prek=false
config="portable"
run_all=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --install-prek) install_prek=true; shift ;;
    --config) config="$2"; shift 2 ;;
    --run-all-files) run_all=true; shift ;;
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

ensure_prek() {
  if command -v prek >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$install_prek" != "true" ]]; then
    echo "error: prek not found in PATH. Re-run with --install-prek or install prek first." >&2
    exit 2
  fi

  echo "prek not found; attempting install..." >&2
  if command -v brew >/dev/null 2>&1; then
    brew install prek
    return 0
  fi
  if command -v uv >/dev/null 2>&1; then
    uv tool install prek
    return 0
  fi
  if command -v pipx >/dev/null 2>&1; then
    pipx install prek
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -m pip install --user prek
    return 0
  fi

  echo "error: no supported installer found (brew/uv/pipx/python3)." >&2
  exit 2
}

install_baseline_config_if_missing() {
  if [[ -f ".pre-commit-config.yaml" || -f ".pre-commit-config.yml" || -f "prek.toml" ]]; then
    return 0
  fi

  case "$config" in
    portable)
      cp "${templates_dir}/pre-commit-config.portable.yaml" ".pre-commit-config.yaml"
      ;;
    builtin)
      cp "${templates_dir}/pre-commit-config.builtin.yaml" ".pre-commit-config.yaml"
      ;;
    *)
      echo "error: unknown --config: $config (expected portable|builtin)" >&2
      exit 2
      ;;
  esac
  echo "Created .pre-commit-config.yaml ($config baseline)." >&2
}

ensure_prek

install_baseline_config_if_missing

config_files=()
[[ -f "prek.toml" ]] && config_files+=("prek.toml")
[[ -f ".pre-commit-config.yaml" ]] && config_files+=(".pre-commit-config.yaml")
[[ -f ".pre-commit-config.yml" ]] && config_files+=(".pre-commit-config.yml")
if [[ "${#config_files[@]}" -eq 0 ]]; then
  echo "error: no configuration file found (expected prek.toml or .pre-commit-config.yaml/.yml)" >&2
  exit 2
fi

echo "Validating config..." >&2
prek validate-config "${config_files[@]}"

hooks_path="$(git config --get core.hooksPath || true)"
if [[ -n "$hooks_path" ]]; then
  echo "Detected core.hooksPath=$hooks_path; skipping 'prek install' and only preparing hook envs." >&2
  prek prepare-hooks
else
  echo "Installing git shims + preparing hook envs..." >&2
  prek install --prepare-hooks
fi

if [[ "$run_all" == "true" ]]; then
  echo "Running prek across all files (may be slow on first run)..." >&2
  prek run --all-files --show-diff-on-failure
fi

echo "Done." >&2
