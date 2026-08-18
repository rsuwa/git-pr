
get_current_pr_number() {
  local output

  if ! output=$(gh pr list --repo "$github_repo" --head "$current_branch" --state open \
    --json number,headRepositoryOwner \
    --jq "map(select(.headRepositoryOwner.login == \"$github_owner\")) | .[0].number // \"\"" 2>&1); then
    die "Failed to query pull request for current branch: $output"
  fi
  printf '%s' "$output"
}

get_pr_field() {
  local pr_number="$1"
  local field="$2"
  local output

  if ! output=$(gh pr view "$pr_number" --repo "$github_repo" --json "$field" --jq ".$field // \"\"" 2>&1); then
    die "Failed to read PR #$pr_number field '$field': $output"
  fi
  printf '%s' "$output"
}

resolve_default_base_branch() {
  local default_ref

  base_branch=$(git -C "$repo_root" config --get "branch.$current_branch.gh-merge-base" || true)
  if [ -z "$base_branch" ]; then
    base_branch=$(gh repo view "$github_repo" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)
  fi
  if [ -z "$base_branch" ]; then
    default_ref=$(git -C "$repo_root" symbolic-ref -q --short refs/remotes/origin/HEAD || true)
    if [ -n "$default_ref" ]; then
      base_branch="${default_ref#origin/}"
    fi
  fi
  if [ -z "$base_branch" ]; then
    die "Base branch not specified and default branch could not be determined. Use --base or set branch.$current_branch.gh-merge-base."
  fi
}

validate_create_base_branch() {
  validate_base_branch_name "$base_branch"
  if [ "$current_branch" = "$base_branch" ]; then
    die "You are on '$base_branch'. Create a feature branch first."
  fi
}

resolve_create_base_branch() {
  if [ "$base_branch_explicit" = "false" ]; then
    resolve_default_base_branch
  fi

  validate_create_base_branch
}

resolve_existing_generation_base_branch() {
  if [ "$base_branch_explicit" = "true" ]; then
    return 0
  fi

  base_branch=$(get_pr_field "$pr_number" baseRefName)
  if [ -z "$base_branch" ]; then
    resolve_default_base_branch
  fi
  validate_base_branch_name "$base_branch"
}

ensure_base_ref_for_generation() {
  local fetch_refspec

  validate_base_branch_name "$base_branch"
  fetch_refspec="refs/heads/$base_branch:refs/remotes/origin/$base_branch"
  git -C "$repo_root" fetch origin "$fetch_refspec" >/dev/null 2>&1 || \
    die "Failed to fetch origin/$base_branch."

  if git -C "$repo_root" show-ref --verify --quiet "refs/remotes/origin/$base_branch"; then
    base_ref="origin/$base_branch"
  elif git -C "$repo_root" show-ref --verify --quiet "refs/heads/$base_branch"; then
    base_ref="$base_branch"
  else
    die "Base branch '$base_branch' not found."
  fi
}

ensure_base_branch_exists_for_retarget() {
  local output
  local line
  local ref

  validate_base_branch_name "$base_branch"
  if ! output=$(git -C "$repo_root" ls-remote --exit-code --heads origin "$base_branch" 2>/dev/null); then
    die "Base branch '$base_branch' was not found on origin. Create it or choose an existing branch with --base."
  fi

  while IFS= read -r line; do
    ref="${line#*$'\t'}"
    if [ "$ref" = "refs/heads/$base_branch" ]; then
      return 0
    fi
  done <<< "$output"

  die "Base branch '$base_branch' was not found on origin. Create it or choose an existing branch with --base."
}

count_commits_since_base() {
  commit_count=$(git -C "$repo_root" rev-list --count "$base_ref..HEAD") || die "Failed to count commits between $base_ref and HEAD."
}

is_valid_github_repo_path() {
  local owner
  local repo

  case "$1" in
    ""|/*|*/*/*)
      return 1
      ;;
    */*)
      owner="${1%/*}"
      repo="${1#*/}"
      is_valid_github_repo_part "$owner" && is_valid_github_repo_part "$repo"
      ;;
    *)
      return 1
      ;;
  esac
}

is_valid_github_repo_part() {
  case "$1" in
    ""|.|..|*[^A-Za-z0-9._-]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

is_valid_github_host() {
  local host="$1"
  local label

  case "$host" in
    ""|.*|*.|*..*|*[^A-Za-z0-9.-]*)
      return 1
      ;;
  esac

  while :; do
    label="${host%%.*}"
    case "$label" in
      ""|-*|*-)
        return 1
        ;;
    esac
    [ "$host" != "$label" ] || break
    host="${host#*.}"
  done

  return 0
}

parse_github_origin_url() {
  local url="$1"
  local host=""
  local path=""
  local repo
  local rest

  url="${url%%#*}"
  url="${url%%\?*}"

  case "$url" in
    git@*:*)
      rest="${url#git@}"
      host="${rest%%:*}"
      path="${rest#*:}"
      ;;
    ssh://git@*/*)
      rest="${url#ssh://git@}"
      host="${rest%%/*}"
      host="${host%%:*}"
      path="${rest#*/}"
      ;;
    https://*/*/*)
      rest="${url#https://}"
      host="${rest%%/*}"
      host="${host##*@}"
      path="${rest#*/}"
      ;;
    http://*/*/*)
      rest="${url#http://}"
      host="${rest%%/*}"
      host="${host##*@}"
      path="${rest#*/}"
      ;;
    *)
      return 1
      ;;
  esac

  [ -n "$host" ] || return 1
  is_valid_github_host "$host" || return 1

  path="${path%.git}"
  is_valid_github_repo_path "$path" || return 1

  if [ "$host" != "github.com" ]; then
    repo="$host/$path"
  else
    repo="$path"
  fi

  printf '%s\t%s' "$host" "$repo"
}

github_repo_from_origin_url() {
  local parsed

  parsed=$(parse_github_origin_url "$1") || return 1
  printf '%s' "${parsed#*$'\t'}"
}

github_host_from_origin_url() {
  local parsed

  parsed=$(parse_github_origin_url "$1") || return 1
  printf '%s' "${parsed%%$'\t'*}"
}

github_owner_from_repo() {
  local repo="$1"
  local owner_part

  owner_part="${repo%/*}"
  printf '%s' "${owner_part##*/}"
}

merge_flag_for_method() {
  case "$merge_method" in
    merge)
      printf '%s' "--merge"
      ;;
    squash)
      printf '%s' "--squash"
      ;;
    rebase)
      printf '%s' "--rebase"
      ;;
  esac
}

expected_merge_head() {
  if [ -n "$auto_merge_match_head" ]; then
    printf '%s' "$auto_merge_match_head"
  else
    git -C "$repo_root" rev-parse HEAD
  fi
}

run_gh_pr_merge() {
  local pr_number="$1"
  local use_auto="$2"
  local expected_head
  local pr_head
  local merge_flag
  local -a merge_cmd

  expected_head=$(expected_merge_head)
  pr_head=$(get_pr_field "$pr_number" headRefOid)
  if [ "$pr_head" != "$expected_head" ]; then
    die "PR #$pr_number head SHA ($pr_head) does not match expected head SHA ($expected_head). Push the current branch or pass --match-head-commit."
  fi

  merge_flag=$(merge_flag_for_method)
  merge_cmd=(gh pr merge "$pr_number" --repo "$github_repo")
  if [ "$use_auto" = "true" ]; then
    merge_cmd+=(--auto)
  fi
  merge_cmd+=("$merge_flag" --match-head-commit "$expected_head")
  if [ "$auto_merge_delete_branch" = "true" ]; then
    merge_cmd+=(--delete-branch)
  fi

  "${merge_cmd[@]}"
}

enable_auto_merge() {
  local pr_number="$1"

  run_gh_pr_merge "$pr_number" "true"
  log_info "Auto-merge requested for PR #$pr_number. GitHub CLI may merge immediately or add the PR to a merge queue when requirements are already met."
}

merge_pull_request() {
  local pr_number="$1"

  run_gh_pr_merge "$pr_number" "false"
  log_info "Merge requested for PR #$pr_number. GitHub CLI may merge immediately or add the PR to a merge queue when required."
}

push_current_branch() {
  local upstream_ref
  local push_refspec="HEAD:refs/heads/$current_branch"

  if upstream_ref=$(git -C "$repo_root" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null); then
    if [ "$upstream_ref" != "origin/$current_branch" ]; then
      die "Existing upstream must be origin/$current_branch for this origin-only workflow; found $upstream_ref."
    fi
    log_info "Pushing current branch"
    git -C "$repo_root" push origin "$push_refspec"
  else
    log_info "Pushing and setting upstream to origin/$current_branch"
    git -C "$repo_root" push -u origin "$push_refspec"
  fi
}
