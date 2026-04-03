#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

swiftformat_config=""
if [[ -f "${repo_root}/.swiftformat" ]]; then
  swiftformat_config="${repo_root}/.swiftformat"
elif [[ -f "${repo_root}/.swiftformat.json" ]]; then
  swiftformat_config="${repo_root}/.swiftformat.json"
fi

swift_format_config=""
for p in \
  "${repo_root}/.swift-format" \
  "${repo_root}/.swift-format.json" \
  "${repo_root}/swift-format.json" \
  "${repo_root}/.swift-format.yml" \
  "${repo_root}/.swift-format.yaml"
do
  if [[ -f "${p}" ]]; then
    swift_format_config="${p}"
    break
  fi
done

tool_hint="$(printf '%s' "${SWIFT_FORMATTER_TOOL:-}" | tr '[:upper:]' '[:lower:]')"
if [[ -z "${tool_hint}" ]]; then
  if [[ -n "${swiftformat_config}" && -z "${swift_format_config}" ]]; then
    tool_hint="swiftformat"
  elif [[ -n "${swift_format_config}" && -z "${swiftformat_config}" ]]; then
    tool_hint="swift-format"
  elif [[ -n "${swift_format_config}" && -n "${swiftformat_config}" ]]; then
    echo "error: both swiftformat and swift-format config files detected; set SWIFT_FORMATTER_TOOL=swiftformat|swift-format." >&2
    exit 2
  elif command -v swift-format >/dev/null 2>&1; then
    # Prefer first-party `swift-format` for modern Swift codebases when there is no legacy config.
    tool_hint="swift-format"
  elif command -v xcrun >/dev/null 2>&1 && xcrun --find swift-format >/dev/null 2>&1; then
    tool_hint="swift-format"
  elif command -v swiftformat >/dev/null 2>&1; then
    tool_hint="swiftformat"
  else
    echo "error: no Swift formatter found. Install `swift-format` (preferred) or `swiftformat`, or set SWIFT_FORMATTER_TOOL=swiftformat|swift-format." >&2
    exit 2
  fi
fi

tool_kind=""
declare -a tool=()
declare -a tool_config_args=()

case "${tool_hint}" in
  swiftformat)
    if ! command -v swiftformat >/dev/null 2>&1; then
      echo "error: swiftformat not found in PATH. Install SwiftFormat (e.g. 'brew install swiftformat')." >&2
      exit 2
    fi
    tool_kind="swiftformat"
    tool=(swiftformat)
    [[ -n "${swiftformat_config}" ]] && tool_config_args+=(--config "${swiftformat_config}")
    ;;
  swift-format|swift_format)
    tool_kind="swift-format"
    if command -v swift-format >/dev/null 2>&1; then
      tool=(swift-format)
    elif command -v xcrun >/dev/null 2>&1; then
      swift_format_path="$(xcrun --find swift-format 2>/dev/null || true)"
      if [[ -n "${swift_format_path}" ]]; then
        tool=("${swift_format_path}")
      else
        echo "error: swift-format not found (neither in PATH nor via xcrun). Install swift-format." >&2
        exit 2
      fi
    else
      echo "error: swift-format not found (no swift-format in PATH, and xcrun unavailable)." >&2
      exit 2
    fi
    [[ -n "${swift_format_config}" ]] && tool_config_args+=(--configuration "${swift_format_config}")
    ;;
  *)
    echo "error: invalid SWIFT_FORMATTER_TOOL=${SWIFT_FORMATTER_TOOL:-} (expected: swiftformat|swift-format)." >&2
    exit 2
    ;;
esac

echo "swift-format-autostage tool=${tool_kind} PID=$$ args=$*" >&2

# --- file collection helpers (NUL-delimited for safety) ---
collect_staged_swift_files() {
  # staged A/C/M/R only; NUL-delimited
  git diff --cached --name-only -z --diff-filter=ACMR -- '*.swift' 2>/dev/null || true
}

collect_all_tracked_swift_files() {
  git ls-files -z -- '*.swift' 2>/dev/null || true
}

read_nul_list_into_files_array() {
  files=()
  local f
  while IFS= read -r -d '' f; do
    files+=("$f")
  done
}

declare -a files=()
# Prefer staged files (commit flow). If none, fall back to all tracked (manual/all-files flow).
read_nul_list_into_files_array < <(collect_staged_swift_files)
if [[ "${#files[@]}" -eq 0 ]]; then
  read_nul_list_into_files_array < <(collect_all_tracked_swift_files)
fi

if [[ "${#files[@]}" -eq 0 ]]; then
  exit 0
fi

# --- formatting ---
autostage="${SWIFT_FORMAT_AUTOSTAGE:-${SWIFTFORMAT_AUTOSTAGE:-1}}"
ignore_unparsable="${SWIFT_FORMAT_IGNORE_UNPARSABLE:-${SWIFTFORMAT_IGNORE_UNPARSABLE:-0}}"

# Chunk to avoid argv limits on very large repos.
run_in_chunks() {
  local -a cmd=("$@")  # includes tool + args, files appended per chunk
  local chunk_size=80
  local i=0
  while [[ $i -lt ${#files[@]} ]]; do
    "${cmd[@]}" "${files[@]:i:chunk_size}"
    i=$((i + chunk_size))
  done
}

if [[ "${tool_kind}" == "swiftformat" ]]; then
  run_in_chunks "${tool[@]}" "${tool_config_args[@]}"
else
  # Optional: set SWIFT_FORMAT_IGNORE_UNPARSABLE=1 (or SWIFTFORMAT_IGNORE_UNPARSABLE=1) to avoid blocking on WIP syntax breaks.
  format_args=(format --in-place --parallel)
  format_args+=("${tool_config_args[@]}")
  if [[ "${ignore_unparsable}" == "1" ]]; then
    format_args+=(--ignore-unparsable-files)
  fi
  run_in_chunks "${tool[@]}" "${format_args[@]}"
fi

# --- autostage (safe) ---
# Hooks that modify files require re-staging; do it here and avoid index lock contention.
git_dir="$(git rev-parse --git-dir)"
lock_dir="${git_dir}/.swift-formatter-precommit.lockdir"

acquire_lock() {
  local attempts=0
  local max_attempts=200
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ $attempts -ge $max_attempts ]]; then
      echo "error: could not acquire hook lock: $lock_dir" >&2
      return 1
    fi
    sleep 0.05
  done
  trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
}

git_add_with_retry() {
  local -a delays=(0.05 0.05 0.1 0.1 0.2 0.2 0.4 0.4 0.8 0.8 1 1)
  local out
  for d in "${delays[@]}"; do
    if out="$(git add -- "${files[@]}" 2>&1)"; then
      return 0
    fi
    if [[ "$out" == *"index.lock"* ]]; then
      sleep "$d"
      continue
    fi
    echo "$out" >&2
    return 1
  done

  # last attempt (print output if still failing)
  if ! out="$(git add -- "${files[@]}" 2>&1)"; then
    echo "$out" >&2
    return 1
  fi
}

# Optional: set SWIFTFORMAT_AUTOSTAGE=0 to disable staging (useful in CI/manual runs).
if [[ "${autostage}" == "1" ]]; then
  acquire_lock
  git_add_with_retry
fi

# --- lint (strict gate) ---
if [[ "${tool_kind}" == "swiftformat" ]]; then
  run_in_chunks "${tool[@]}" --lint "${tool_config_args[@]}"
else
  lint_args=(lint --strict --parallel)
  lint_args+=("${tool_config_args[@]}")
  if [[ "${ignore_unparsable}" == "1" ]]; then
    lint_args+=(--ignore-unparsable-files)
  fi
  run_in_chunks "${tool[@]}" "${lint_args[@]}"
fi
