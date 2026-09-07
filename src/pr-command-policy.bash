
trim_spaces() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

append_diff_exclude() {
  local value="$1"
  value=$(trim_spaces "$value")
  if [ -n "$value" ]; then
    diff_excludes+=("$value")
  fi
}

append_diff_excludes_csv() {
  local value="$1"
  local -a parts
  IFS=',' read -r -a parts <<< "$value"
  [ "${#parts[@]}" -gt 0 ] || return 0
  for part in "${parts[@]}"; do
    append_diff_exclude "$part"
  done
}

load_git_pr_config() {
  if [ -z "$language" ]; then
    language=$(git -C "$repo_root" config --get git-pr.language 2>/dev/null || true)
  fi
  language="${language:-en}"
  case "$language" in
    en|ja)
      ;;
    *)
      die "Invalid language: $language (use en|ja)"
      ;;
  esac

  local configured_exclude
  while IFS= read -r configured_exclude; do
    append_diff_exclude "$configured_exclude"
  done < <(git -C "$repo_root" config --get-all git-pr.diffExclude 2>/dev/null || true)

  if [ -n "${GIT_PR_DIFF_EXCLUDES:-}" ]; then
    append_diff_excludes_csv "$GIT_PR_DIFF_EXCLUDES"
  fi

  local explicit_exclude
  if [ "${#diff_exclude_args[@]}" -gt 0 ]; then
    for explicit_exclude in "${diff_exclude_args[@]}"; do
      append_diff_exclude "$explicit_exclude"
    done
  fi
}

append_label_args() {
  local value="$1"
  local -a parts

  IFS=',' read -r -a parts <<< "$value"
  [ "${#parts[@]}" -gt 0 ] || return 0
  for part in "${parts[@]}"; do
    part=$(trim_spaces "$part")
    if [ -n "$part" ]; then
      label_args+=(--label "$part")
      edit_label_args+=(--add-label "$part")
    fi
  done
}

append_reviewer_args() {
  local value="$1"
  local -a parts

  IFS=',' read -r -a parts <<< "$value"
  [ "${#parts[@]}" -gt 0 ] || return 0
  for part in "${parts[@]}"; do
    part=$(trim_spaces "$part")
    if [ -n "$part" ]; then
      reviewer_args+=(--reviewer "$part")
      edit_reviewer_args+=(--add-reviewer "$part")
    fi
  done
}

append_assignee_args() {
  local value="$1"
  local -a parts

  IFS=',' read -r -a parts <<< "$value"
  [ "${#parts[@]}" -gt 0 ] || return 0
  for part in "${parts[@]}"; do
    part=$(trim_spaces "$part")
    if [ -n "$part" ]; then
      assignee_args+=(--assignee "$part")
      edit_assignee_args+=(--add-assignee "$part")
    fi
  done
}

has_pr_edit_metadata_updates() {
  local include_base="${1:-$base_branch_explicit}"

  [ "$include_base" = "true" ] || \
    [ ${#edit_label_args[@]} -gt 0 ] || \
    [ ${#edit_reviewer_args[@]} -gt 0 ] || \
    [ ${#edit_assignee_args[@]} -gt 0 ]
}

has_pr_edit_updates() {
  local include_title="$1"
  local include_body="$2"
  local include_base="$3"

  [ "$include_title" = "true" ] || \
    [ "$include_body" = "true" ] || \
    [ "$include_base" = "true" ] || \
    has_pr_edit_metadata_updates "$include_base"
}

append_pr_edit_metadata_args() {
  local include_base="$1"

  if [ "$include_base" = "true" ]; then
    pr_edit_cmd+=(--base "$base_branch")
  fi
  if [ ${#edit_label_args[@]} -gt 0 ]; then
    pr_edit_cmd+=("${edit_label_args[@]}")
  fi
  if [ ${#edit_reviewer_args[@]} -gt 0 ]; then
    pr_edit_cmd+=("${edit_reviewer_args[@]}")
  fi
  if [ ${#edit_assignee_args[@]} -gt 0 ]; then
    pr_edit_cmd+=("${edit_assignee_args[@]}")
  fi
}

append_pr_edit_content_args() {
  local include_title="$1"
  local include_body="$2"

  if [ "$include_title" = "true" ]; then
    pr_edit_cmd+=(--title "$title")
  fi
  if [ "$include_body" = "true" ]; then
    if [ "$body_file_explicit" = "true" ]; then
      pr_edit_cmd+=(--body-file "$body_file")
    else
      pr_edit_cmd+=(--body "$body")
    fi
  fi
}

join_summary_parts() {
  local part
  local joined=""

  for part in "$@"; do
    if [ -n "$joined" ]; then
      joined+=", "
    fi
    joined+="$part"
  done
  printf '%s' "$joined"
}

pr_edit_update_summary() {
  local include_base="$1"
  local include_title="$2"
  local include_body="$3"
  local -a parts=()

  if [ "$include_base" = "true" ]; then
    parts+=("base")
  fi
  if [ "$include_title" = "true" ]; then
    parts+=("title")
  fi
  if [ "$include_body" = "true" ]; then
    if [ "$use_copilot" = "true" ] && [ "$copilot_update_effective" = "true" ]; then
      parts+=("copilot section")
    elif [ "$body_file_explicit" = "true" ]; then
      parts+=("body file")
    else
      parts+=("body")
    fi
  fi
  if [ ${#edit_label_args[@]} -gt 0 ]; then
    parts+=("labels")
  fi
  if [ ${#edit_reviewer_args[@]} -gt 0 ]; then
    parts+=("reviewers")
  fi
  if [ ${#edit_assignee_args[@]} -gt 0 ]; then
    parts+=("assignees")
  fi

  if [ "${#parts[@]}" -gt 0 ]; then
    join_summary_parts "${parts[@]}"
  fi
}

log_pr_edit_summary() {
  local include_base="$1"
  local include_title="${2:-false}"
  local include_body="${3:-false}"
  local summary

  summary=$(pr_edit_update_summary "$include_base" "$include_title" "$include_body")
  if [ -n "$summary" ]; then
    log_info "Updated PR #$pr_number: $summary."
  fi
}

build_pr_edit_cmd() {
  local include_base="$1"
  local include_title="${2:-false}"
  local include_body="${3:-false}"

  pr_edit_cmd=(gh pr edit "$pr_number" --repo "$github_repo")
  append_pr_edit_metadata_args "$include_base"
  append_pr_edit_content_args "$include_title" "$include_body"
}

build_pr_create_cmd() {
  pr_create_cmd=(gh pr create --repo "$github_repo" --base "$base_branch" --head "$current_branch")

  if [ "$draft" = "true" ]; then
    pr_create_cmd+=(--draft)
  fi
  if [ ${#label_args[@]} -gt 0 ]; then
    pr_create_cmd+=("${label_args[@]}")
  fi
  if [ ${#reviewer_args[@]} -gt 0 ]; then
    pr_create_cmd+=("${reviewer_args[@]}")
  fi
  if [ ${#assignee_args[@]} -gt 0 ]; then
    pr_create_cmd+=("${assignee_args[@]}")
  fi
  if [ "$editor" = "true" ]; then
    pr_create_cmd+=(--editor)
  fi
}

append_pr_create_fill_args() {
  case "$fill_mode" in
    first)
      pr_create_cmd+=(--fill-first)
      ;;
    verbose)
      pr_create_cmd+=(--fill-verbose)
      ;;
    normal|*)
      pr_create_cmd+=(--fill)
      ;;
  esac
}

has_manual_content_option() {
  [ "$title_explicit" = "true" ] || [ "$body_explicit" = "true" ] || [ "$body_file_explicit" = "true" ]
}

has_copilot_scoped_option() {
  [ "$copilot_mode_explicit" = "true" ] || \
    [ "$copilot_detail_explicit" = "true" ] || \
    [ "$copilot_model_explicit" = "true" ]
}

has_copilot_config_option() {
  [ "$language_explicit" = "true" ] || [ "$diff_exclude_explicit" = "true" ]
}

has_metadata_option() {
  [ "$label_explicit" = "true" ] || \
    [ "$reviewer_explicit" = "true" ] || \
    [ "$assignee_explicit" = "true" ]
}

has_body_generation_option() {
  [ "$fill_explicit" = "true" ] || [ "$no_fill_explicit" = "true" ]
}

has_non_auto_merge_pr_option() {
  [ "$base_branch_explicit" = "true" ] || [ "$draft_explicit" = "true" ] || \
    [ "$open_web_explicit" = "true" ] || [ "$use_copilot" = "true" ] || \
    has_copilot_scoped_option || has_copilot_config_option || \
    [ "$title_explicit" = "true" ] || [ "$body_explicit" = "true" ] || \
    [ "$body_file_explicit" = "true" ] || [ "$template_file_explicit" = "true" ] || \
    [ "$editor" = "true" ] || has_metadata_option || has_body_generation_option || \
    [ "$skip_edit" = "true" ]
}

has_update_subcommand_pr_option() {
  has_non_auto_merge_pr_option || \
    [ "$merge_method_explicit" = "true" ] || \
    [ "$auto_merge_explicit" = "true" ] || \
    [ "$auto_merge_delete_branch" = "true" ] || \
    [ "$auto_merge_admin" = "true" ] || \
    [ "$auto_merge_disable" = "true" ] || \
    [ "$auto_merge_match_head_explicit" = "true" ]
}

has_disable_auto_merge_conflict() {
  [ "$merge_method_explicit" = "true" ] || \
    [ "$auto_merge_delete_branch" = "true" ] || \
    [ "$auto_merge_admin" = "true" ] || \
    [ -n "$auto_merge_match_head" ]
}

has_merge_modifier_without_context() {
  { [ "$merge_method_explicit" = "true" ] || \
    [ "$auto_merge_delete_branch" = "true" ] || [ "$auto_merge_admin" = "true" ] || \
    [ -n "$auto_merge_match_head" ]; } && \
    [ "$auto_merge" != "true" ] && [ "$action" != "auto-merge" ] && [ "$action" != "merge" ]
}
