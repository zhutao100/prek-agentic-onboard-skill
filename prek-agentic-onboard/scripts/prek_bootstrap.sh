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
- If `git config core.hooksPath` is set, `prek install` refuses to install hooks (as of `prek 0.3.x`).
  This script detects hooksPath and uses `prek prepare-hooks` instead.
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
  echo "Running prek across all files (auto-converge on fixable changes)..." >&2
  prek_run_all_files_converge
fi

maybe_prompt_workspace_mode() {
  # Best-effort polyglot detection to nudge agents toward workspace mode.
  local -a langs=()
  git ls-files -- '*.swift' 2>/dev/null | grep -q . && langs+=("Swift")
  git ls-files -- '*.ts' '*.tsx' '*.mts' '*.cts' 2>/dev/null | grep -q . && langs+=("TypeScript")
  git ls-files -- '*.js' '*.jsx' '*.mjs' '*.cjs' 2>/dev/null | grep -q . && langs+=("JavaScript")
  git ls-files -- '*.py' '*.pyi' 2>/dev/null | grep -q . && langs+=("Python")
  git ls-files -- '*.rs' 2>/dev/null | grep -q . && langs+=("Rust")

  if [[ "${#langs[@]}" -lt 2 ]]; then
    return 0
  fi

  # Only prompt if there are no nested configs yet.
  if find . -path './.git' -prune -o \
      \( -mindepth 2 \( -name '.pre-commit-config.yaml' -o -name '.pre-commit-config.yml' -o -name 'prek.toml' \) \) \
      -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi

  cat >&2 <<EOF
note: detected a likely polyglot repo (${langs[*]}).

Consider enabling prek workspace mode (thin root + per-subproject configs):
  bash "${script_dir}/scaffold_workspace_mode.sh" --repo "${repo_root}"

After adding nested configs, use \`--refresh\` to re-discover projects:
  prek --refresh list
  prek --refresh run --all-files
EOF
}

maybe_prompt_workspace_mode || true

echo "Done." >&2
