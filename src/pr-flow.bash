
copilot_fallback() {
  if [ "$copilot_update_effective" = "true" ]; then
    log_warn "Copilot failed; leaving existing PR title/body unchanged."
    use_copilot="false"
    fill="false"
    return 0
  fi

  if [ -n "$template_file" ]; then
    log_warn "Falling back to template for PR body."
    use_copilot="false"
    fill="false"
  else
    log_warn "Falling back to --fill."
    use_copilot="false"
    fill="true"
    fill_mode="normal"
  fi
}

require_pr_flow_commands() {
  require_cmd git
  require_gh_cli
}

load_git_repository_context() {
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die "Not a git repository."
  current_branch=$(git -C "$repo_root" branch --show-current)
  [ -n "$current_branch" ] || die "Detached HEAD. Checkout a branch first."
}

load_github_remote_context() {
  if ! origin_url=$(git -C "$repo_root" remote get-url origin 2>/dev/null); then
    die "Remote 'origin' not found."
  fi
  github_repo=$(github_repo_from_origin_url "$origin_url") || die "Remote 'origin' is not a supported GitHub repository URL: $(redact_url "$origin_url")"
  github_host=$(github_host_from_origin_url "$origin_url") || die "Remote 'origin' is not a supported GitHub repository URL: $(redact_url "$origin_url")"
  github_owner=$(github_owner_from_repo "$github_repo")
}

ensure_github_auth_context() {
  if ! gh auth status --hostname "$github_host" >/dev/null 2>&1; then
    die "GitHub CLI is not authenticated for $github_host. $(github_cli_auth_message "$github_host")"
  fi
}

load_repository_context() {
  require_pr_flow_commands
  load_git_repository_context
  if [ "$use_copilot" = "true" ]; then
    load_git_pr_config
  fi
  load_github_remote_context
  ensure_github_auth_context
}

refresh_current_pr_context() {
  pr_number=$(get_current_pr_number)
}

reset_pr_generation_context() {
  base_ref=""
  commit_count=0
}

handle_merge_action() {
  if [ "$action" != "auto-merge" ] && [ "$action" != "merge" ]; then
    return 0
  fi

  refresh_current_pr_context
  [ -n "$pr_number" ] || die "No open PR found for current branch."

  if [ "$action" = "auto-merge" ] && [ "$auto_merge_disable" = "true" ]; then
    gh pr merge "$pr_number" --repo "$github_repo" --disable-auto
    log_info "Auto-merge disabled for PR #$pr_number."
    exit 0
  fi

  if [ "$action" = "auto-merge" ]; then
    enable_auto_merge "$pr_number"
  else
    merge_pull_request "$pr_number"
  fi
  exit 0
}

resolve_pr_flow_copilot_mode() {
  if [ "$use_copilot" != "true" ]; then
    return 0
  fi

  copilot_mode_effective="$copilot_mode"
  if [ "$copilot_mode_effective" = "auto" ]; then
    if [ -n "$pr_number" ]; then
      copilot_mode_effective="update"
    else
      copilot_mode_effective="create"
    fi
  fi
  if [ "$copilot_mode_effective" = "update" ] && [ -z "$pr_number" ]; then
    die "--mode=update requires an existing PR. Use --mode=create."
  fi
  if [ "$copilot_mode_effective" = "create" ] && [ -n "$pr_number" ]; then
    die "--mode=create requires no existing PR. Use --mode=update."
  fi
  if [ "$copilot_mode_effective" = "update" ]; then
    copilot_update_effective="true"
  else
    copilot_update_effective="false"
  fi
}

validate_pr_flow_body_file() {
  if [ -n "$body_file" ] && [ "$body_file" != "-" ] && [ ! -f "$body_file" ]; then
    die "Body file not found: $body_file"
  fi
}

prepare_existing_pr_before_push() {
  if [ "$editor" = "true" ] || [ -n "$template_file" ]; then
    die "--editor/--template are only supported when creating a PR."
  fi
  if [ "$draft_explicit" = "true" ]; then
    die "--draft is only supported when creating a PR."
  fi
  if [ "$base_branch_explicit" = "true" ] && [ "$base_branch" = "$current_branch" ]; then
    die "You are on '$base_branch'. Create a feature branch first."
  fi
  if [ "$base_branch_explicit" = "true" ]; then
    ensure_base_branch_exists_for_retarget
  fi
  if [ "$copilot_update_effective" = "true" ]; then
    copilot_existing_body=$(get_pr_field "$pr_number" body)
    copilot_existing_body_loaded="true"
    validate_copilot_update_markers "$copilot_existing_body" || \
      die "Existing PR body has an invalid git-pr Copilot update marker block."
  fi
}

prepare_create_pr_before_push() {
  if [ "$base_branch_explicit" = "true" ]; then
    validate_create_base_branch
  fi

  resolve_template_file

  if [ -n "$template_file" ] && [ "$template_resolved" != "true" ]; then
    die "Template file not found: $template_file"
  fi

  if [ "$base_branch_explicit" = "false" ]; then
    resolve_create_base_branch
  fi

  ensure_base_ref_for_generation
  count_commits_since_base
}

prepare_pr_flow_before_push() {
  refresh_current_pr_context
  reset_pr_generation_context

  resolve_pr_flow_copilot_mode

  if [ -n "$pr_number" ]; then
    prepare_existing_pr_before_push
  else
    prepare_create_pr_before_push
  fi

  if [ -z "$pr_number" ] && [ "$commit_count" -eq 0 ]; then
    die "No commits to open a PR (branch is up to date with $base_branch)."
  fi

  if [ "$use_copilot" = "true" ] && command -v copilot >/dev/null 2>&1; then
    validate_copilot_diff_max_bytes "${GIT_PR_COPILOT_DIFF_MAX_BYTES:-20000}"
    ensure_copilot_private_temp_available
  fi

  if ! git -C "$repo_root" diff --quiet || ! git -C "$repo_root" diff --cached --quiet; then
    log_warn "Working tree has uncommitted changes. They won't be included in the PR."
  fi
}

run_existing_pr_update() {
  local existing_body
  local update_base="$base_branch_explicit"
  local update_body="false"
  local update_title="false"

  if [ "$use_copilot" = "true" ]; then
    if has_manual_content_option; then
      die "git pr copilot cannot be combined with --title/--body/--body-file."
    fi
    if [ "$copilot_update_effective" = "true" ]; then
      copilot_existing_title=$(get_pr_field "$pr_number" title)
      if [ "$copilot_existing_body_loaded" != "true" ]; then
        copilot_existing_body=$(get_pr_field "$pr_number" body)
        copilot_existing_body_loaded="true"
      fi
      update_title="false"
      update_body="true"
    else
      update_title="true"
      update_body="true"
    fi
    if can_run_copilot_generation; then
      resolve_existing_generation_base_branch
      ensure_base_ref_for_generation
      if ! generate_title_body_with_copilot; then
        copilot_fallback
        update_title="false"
        update_body="false"
      elif [ "$copilot_update_effective" = "true" ]; then
        body=$(merge_copilot_update_body "$copilot_existing_body" "$body") || \
          die "Existing PR body has an invalid git-pr Copilot update marker block."
      fi
    else
      copilot_fallback
      update_title="false"
      update_body="false"
    fi
  fi

  if [ "$use_copilot" != "true" ]; then
    if [ "$title_explicit" = "true" ]; then
      update_title="true"
    fi

    if [ "$body_file_explicit" = "true" ]; then
      update_body="true"
    elif [ "$body_explicit" = "true" ]; then
      update_body="true"
    elif [ "$fill" = "true" ]; then
      existing_body=$(get_pr_field "$pr_number" body)
      if [ "$fill_explicit" != "true" ] && [ -n "$existing_body" ]; then
        log_info "Existing PR body is not empty. Skipping auto-update; use --fill to replace it."
      else
        resolve_existing_generation_base_branch
        ensure_base_ref_for_generation
        count_commits_since_base
      fi

      if [ "$fill_explicit" != "true" ] && [ -n "$existing_body" ]; then
        :
      elif [ "$commit_count" -eq 0 ]; then
        log_info "No new commits compared to $base_branch. Skipping auto-update."
      else
        if [ "$fill_explicit" = "true" ]; then
          log_info "Replacing existing PR body because a fill option was specified."
        fi
        generate_body_from_commits
        update_body="true"
      fi
    fi
  fi

  if has_pr_edit_updates "$update_title" "$update_body" "$update_base"; then
    build_pr_edit_cmd "$update_base" "$update_title" "$update_body"
    "${pr_edit_cmd[@]}"
    log_pr_edit_summary "$update_base" "$update_title" "$update_body"
  else
    log_info "No PR fields to update."
  fi
}

run_existing_pr_flow() {
  log_info "Existing PR #$pr_number found for $current_branch."

  if [ "$editor" = "true" ] || [ -n "$template_file" ]; then
    die "--editor/--template are only supported when creating a PR."
  fi

  if [ "$skip_edit" = "true" ]; then
    log_info "Skipping PR title/body update (--no-edit)."
    if has_pr_edit_metadata_updates; then
      build_pr_edit_cmd "$base_branch_explicit"
      "${pr_edit_cmd[@]}"
      log_pr_edit_summary "$base_branch_explicit"
    fi
  else
    run_existing_pr_update
  fi

  if [ "$open_web" = "true" ]; then
    gh pr view "$pr_number" --repo "$github_repo" --web
  fi

  if [ "$auto_merge" = "true" ]; then
    enable_auto_merge "$pr_number"
  fi
}

append_create_content_args() {
  if [ "$use_copilot" = "true" ]; then
    if has_manual_content_option; then
      die "git pr copilot cannot be combined with --title/--body/--body-file."
    fi

    if ! can_run_copilot_generation || ! generate_title_body_with_copilot; then
      copilot_fallback
    fi
  fi

  if [ "$use_copilot" = "true" ]; then
    pr_create_cmd+=(--title "$title" --body "$body")
  elif [ -n "$template_file" ]; then
    if [ -z "$title" ]; then
      title=$(git -C "$repo_root" log -1 --pretty=%s)
    fi
    pr_create_cmd+=(--title "$title" --template "$template_file")
  elif [ "$fill" = "true" ] && [ "$title_explicit" != "true" ] && [ "$body_explicit" != "true" ] && [ "$body_file_explicit" != "true" ] && [ "$template_file_explicit" != "true" ]; then
    append_pr_create_fill_args
  else
    if [ -z "$title" ]; then
      title=$(git -C "$repo_root" log -1 --pretty=%s)
    fi

    if [ "$body_explicit" != "true" ] && [ "$body_file_explicit" != "true" ] && [ "$template_file_explicit" != "true" ]; then
      generate_body_from_commits
    fi

    if [ "$body_file_explicit" = "true" ]; then
      pr_create_cmd+=(--title "$title" --body-file "$body_file")
    elif [ -n "$template_file" ]; then
      pr_create_cmd+=(--title "$title")
    else
      pr_create_cmd+=(--title "$title" --body "$body")
    fi
  fi
}

run_create_pr_flow() {
  build_pr_create_cmd
  append_create_content_args

  "${pr_create_cmd[@]}"

  if [ "$auto_merge" = "true" ] || [ "$open_web" = "true" ]; then
    refresh_current_pr_context
    [ -n "$pr_number" ] || die "Failed to find PR after creation."
  fi

  if [ "$auto_merge" = "true" ]; then
    enable_auto_merge "$pr_number"
  fi

  if [ "$open_web" = "true" ]; then
    gh pr view "$pr_number" --repo "$github_repo" --web
  fi
}

run_pr_flow() {
  local pr_number_before_push

  prepare_pr_flow_before_push
  pr_number_before_push="$pr_number"
  push_current_branch

  if [ -z "$pr_number" ]; then
    refresh_current_pr_context
    if [ -z "$pr_number_before_push" ] && [ -n "$pr_number" ]; then
      resolve_pr_flow_copilot_mode
      prepare_existing_pr_before_push
    fi
  fi

  if [ -n "$pr_number" ]; then
    run_existing_pr_flow
    return 0
  fi

  run_create_pr_flow
}
