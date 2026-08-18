
require_option_value() {
  local option="$1"
  local remaining="$2"

  if [ "$remaining" -lt 2 ]; then
    die "$option requires a value."
  fi
}

require_nonempty_option_value() {
  local option="$1"
  local value

  value=$(trim_spaces "$2")
  if [ -z "$value" ]; then
    die "$option requires a non-empty value."
  fi
}

validate_base_branch_name() {
  local branch="$1"
  local normalized

  if ! normalized=$(git check-ref-format --branch "$branch" 2>/dev/null); then
    die "Invalid base branch: $branch"
  fi
  if [ "$normalized" != "$branch" ]; then
    die "Invalid base branch: $branch"
  fi
}

cleanup_registered_paths() {
  local path

  [ "${#cleanup_paths[@]}" -gt 0 ] || return 0
  for path in "${cleanup_paths[@]}"; do
    if [ -n "$path" ]; then
      rm -rf "$path"
    fi
  done
}

register_cleanup_path() {
  cleanup_paths+=("$1")
  if [ "$cleanup_trap_registered" != "true" ]; then
    trap cleanup_registered_paths EXIT
    trap 'cleanup_registered_paths; exit 130' INT
    trap 'cleanup_registered_paths; exit 143' TERM
    cleanup_trap_registered="true"
  fi
}

unregister_cleanup_path() {
  local target="$1"
  local path
  local -a retained_paths=()

  [ "${#cleanup_paths[@]}" -gt 0 ] || return 0
  for path in "${cleanup_paths[@]}"; do
    if [ "$path" != "$target" ]; then
      retained_paths+=("$path")
    fi
  done
  cleanup_paths=()
  if [ "${#retained_paths[@]}" -gt 0 ]; then
    cleanup_paths=("${retained_paths[@]}")
  fi
}
