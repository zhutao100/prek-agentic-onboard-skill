#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd -- "${script_dir}/.." && pwd)"
templates_dir="${skill_dir}/assets/templates"

repo="."
max_rounds="${PREK_AUTOFIX_MAX_ROUNDS:-5}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --max-rounds) max_rounds="$2"; shift 2 ;;
    -h|--help)
      cat >&2 <<'USAGE'
Usage:
  setup_agentic_autostage_shim.sh [--repo <path>] [--max-rounds N]

What it does:
- Installs a self-healing pre-commit hook under .githooks/pre-commit.
- Sets git config core.hooksPath .githooks so `git commit` uses it.

Notes:
- After setting `core.hooksPath`, `prek install` refuses to install hooks (as of `prek 0.3.x`).
  Use `prek prepare-hooks` to warm environments; this shim calls `prek run` on commit.
USAGE
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

mkdir -p .githooks
cp "${templates_dir}/githooks.pre-commit.self-heal.sh" .githooks/pre-commit
chmod +x .githooks/pre-commit

# Bake max rounds into hook via env var in hook execution context:
# (User can still override per-invocation by setting PREK_AUTOFIX_MAX_ROUNDS.)
echo "export PREK_AUTOFIX_MAX_ROUNDS=${max_rounds}" > .githooks/.prek-autostage-env
chmod 0644 .githooks/.prek-autostage-env

# Ensure the hook sources env if present (idempotent).
if ! grep -q "prek-autostage-env" .githooks/pre-commit; then
  tmp="$(mktemp)"
  first_line="$(head -n 1 .githooks/pre-commit || true)"
  if [[ "${first_line}" == "#!"* ]]; then
    {
      printf '%s\n' "${first_line}"
      echo '# shellcheck disable=SC1091'
      echo '[[ -f "$(dirname "$0")/.prek-autostage-env" ]] && source "$(dirname "$0")/.prek-autostage-env"'
      sed -n '2,$p' .githooks/pre-commit
    } > "$tmp"
  else
    {
      echo '# shellcheck disable=SC1091'
      echo '[[ -f "$(dirname "$0")/.prek-autostage-env" ]] && source "$(dirname "$0")/.prek-autostage-env"'
      cat .githooks/pre-commit
    } > "$tmp"
  fi
  mv "$tmp" .githooks/pre-commit
  chmod +x .githooks/pre-commit
fi

git config core.hooksPath .githooks
echo "Configured: git config core.hooksPath .githooks" >&2

if command -v prek >/dev/null 2>&1; then
  echo "Warming hook environments (optional): prek prepare-hooks" >&2
  prek prepare-hooks || true
else
  echo "Note: prek not found in PATH. Install prek so the hook can run." >&2
fi

echo "Done. Next: run 'git commit' to verify convergence." >&2
