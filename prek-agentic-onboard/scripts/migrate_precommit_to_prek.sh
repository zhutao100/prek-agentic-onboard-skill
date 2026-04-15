#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

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

hash_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | awk '{print $2}'
    return 0
  fi
  wc -c | awk '{print $1}'
}

git_diff_fingerprint() {
  {
    git diff --no-ext-diff
    git diff --cached --no-ext-diff
  } | hash_stream
}

prek_run_all_files_converge() {
  local max_rounds="${PREK_AUTOFIX_MAX_ROUNDS:-5}"
  local round
  local before after status

  for round in $(seq 1 "${max_rounds}"); do
    before="$(git_diff_fingerprint)"
    set +e
    prek run --all-files --show-diff-on-failure
    status=$?
    set -e

    if [[ "${status}" -eq 0 ]]; then
      return 0
    fi

    after="$(git_diff_fingerprint)"
    if [[ "${before}" == "${after}" ]]; then
      return "${status}"
    fi

    echo "note: prek modified files; retrying for convergence (${round}/${max_rounds})..." >&2
  done

  echo "error: prek did not converge after ${max_rounds} rounds (possible formatter ping-pong)" >&2
  return 1
}

ts="$(date +%Y%m%d-%H%M%S)"
git_dir="$(git rev-parse --git-dir)"
hooks_dir="$(git rev-parse --git-path hooks)"
backup_dir="${git_dir}/hooks.backup.${ts}"

mkdir -p "${backup_dir}"
if [[ -d "${hooks_dir}" ]]; then
  cp -pR "${hooks_dir}/." "${backup_dir}/"
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

echo "Smoke test: prek run --all-files (auto-converge on fixable changes)" >&2
prek_run_all_files_converge

cat >&2 <<EOF
Migration complete.

Rollback options:
- Restore hooks from: ${backup_dir}
- Re-run: pre-commit install (if you want to go back)

Next steps (recommended):
- Review your existing config(s) for coverage across languages and hook intent.
- If this is a polyglot repo, consider prek workspace mode (thin root + per-subproject configs):
  bash "${script_dir}/scaffold_workspace_mode.sh" --repo "${repo_root}"
- Verify discovery and end-to-end:
  prek --refresh list
  prek run --all-files
EOF
