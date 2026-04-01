#!/usr/bin/env bash
set -euo pipefail

# Assumes pnpm; swap "pnpm exec" to "npm exec", "yarn", or "bunx" as needed.
PRETTIER=(pnpm exec prettier)
echo "prettier-autostage PID=$$" >&2

files=()
while IFS= read -r -d '' f; do files+=("$f"); done < <(
  git diff --cached --name-only -z --diff-filter=ACMR -- \
    '*.js' '*.jsx' '*.ts' '*.tsx' '*.json' '*.yml' '*.yaml' '*.md' 2>/dev/null || true
)
if [[ "${#files[@]}" -eq 0 ]]; then
  exit 0
fi

"${PRETTIER[@]}" --write "${files[@]}"

git_dir="$(git rev-parse --git-dir)"
lock_dir="${git_dir}/.prettier-precommit.lockdir"

acquire_lock() {
  local attempts=0
  local max_attempts=200
  while ! mkdir "${lock_dir}" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ "${attempts}" -ge "${max_attempts}" ]]; then
      echo "error: could not acquire hook lock: ${lock_dir}" >&2
      return 1
    fi
    sleep 0.05
  done
  trap 'rmdir "${lock_dir}" 2>/dev/null || true' EXIT
}

git_add_with_retry() {
  local -a delays=(0.05 0.05 0.1 0.1 0.2 0.2 0.4 0.4 0.8 0.8 1 1)
  local out
  for d in "${delays[@]}"; do
    if out="$(git add -- "${files[@]}" 2>&1)"; then
      return 0
    fi
    if [[ "${out}" == *"index.lock"* ]]; then
      sleep "${d}"
      continue
    fi
    echo "${out}" >&2
    return 1
  done
  out="$(git add -- "${files[@]}" 2>&1)" || { echo "${out}" >&2; return 1; }
}

acquire_lock
git_add_with_retry

# Optional belt-and-suspenders gate:
"${PRETTIER[@]}" --check "${files[@]}"
