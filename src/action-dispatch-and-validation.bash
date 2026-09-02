
handle_update_action() {
  if [ "$action" != "update" ]; then
    return 0
  fi

  if [ "$doctor_with_copilot" = "true" ] || has_update_subcommand_pr_option; then
    die "update subcommand does not accept PR options."
  fi
  update_self
  exit 0
}

handle_doctor_action() {
  if [ "$action" != "doctor" ]; then
    if [ "$doctor_with_copilot" = "true" ]; then
      die "--with-copilot requires 'git pr doctor'."
    fi
    return 0
  fi

  if has_update_subcommand_pr_option; then
    die "doctor subcommand only accepts --with-copilot."
  fi

  if run_doctor "$doctor_with_copilot"; then
    exit 0
  fi
  exit 1
}

validate_common_options() {
  local diff_exclude_arg

  if [ "$base_branch_explicit" = "true" ]; then
    require_nonempty_option_value "--base" "$base_branch"
  fi
  if [ "$title_explicit" = "true" ]; then
    require_nonempty_option_value "--title" "$title"
  fi
  if [ "$body_file_explicit" = "true" ]; then
    require_nonempty_option_value "--body-file" "$body_file"
  fi
  if [ "$template_file_explicit" = "true" ]; then
    require_nonempty_option_value "--template" "$template_file"
  fi
  if [ "$label_explicit" = "true" ] && [ "${#label_args[@]}" -eq 0 ]; then
    die "--label requires a non-empty value."
  fi
  if [ "$reviewer_explicit" = "true" ] && [ "${#reviewer_args[@]}" -eq 0 ]; then
    die "--reviewer requires a non-empty value."
  fi
  if [ "$assignee_explicit" = "true" ] && [ "${#assignee_args[@]}" -eq 0 ]; then
    die "--assignee requires a non-empty value."
  fi
  if [ "$copilot_mode_explicit" = "true" ]; then
    require_nonempty_option_value "--mode" "$copilot_mode"
  fi
  if [ "$copilot_detail_explicit" = "true" ]; then
    require_nonempty_option_value "--detail" "$copilot_detail"
  fi
  if [ "$copilot_model_explicit" = "true" ]; then
    require_nonempty_option_value "--model" "$copilot_model"
  fi
  if [ "$language_explicit" = "true" ]; then
    require_nonempty_option_value "--language" "$language"
  fi
  if [ "${#diff_exclude_args[@]}" -gt 0 ]; then
    for diff_exclude_arg in "${diff_exclude_args[@]}"; do
      require_nonempty_option_value "--diff-exclude" "$diff_exclude_arg"
    done
  fi
  if [ "$merge_method_explicit" = "true" ]; then
    require_nonempty_option_value "--merge-method" "$merge_method"
  fi

  if [ "$body_explicit" = "true" ] && [ "$body_file_explicit" = "true" ]; then
    die "--body and --body-file cannot be used together."
  fi

  if [ "$template_file_explicit" = "true" ] && { [ "$body_explicit" = "true" ] || [ "$body_file_explicit" = "true" ]; }; then
    die "--template cannot be combined with --body/--body-file."
  fi

  if [ "$fill_mode_conflict" = "true" ]; then
    die "Choose only one of --fill, --fill-first, --fill-verbose."
  fi

  if [ "$no_fill_explicit" = "true" ] && [ "$fill_explicit" = "true" ]; then
    die "--no-fill cannot be combined with --fill/--fill-first/--fill-verbose."
  fi

  if has_copilot_scoped_option && [ "$use_copilot" != "true" ]; then
    die "--mode/--detail/--model require 'git pr copilot'."
  fi

  if has_copilot_config_option && [ "$use_copilot" != "true" ]; then
    die "--language/--diff-exclude require 'git pr copilot'."
  fi

  if [ "$copilot_mode_explicit" = "true" ]; then
    case "$copilot_mode" in
      create|update|auto)
        ;;
      *)
        die "Invalid --mode: $copilot_mode (use create|update|auto)"
        ;;
    esac
  fi

  if [ "$copilot_detail_explicit" = "true" ]; then
    case "$copilot_detail" in
      normal|verbose)
        ;;
      *)
        die "Invalid --detail: $copilot_detail (use normal|verbose)"
        ;;
    esac
  fi

  if [ "$use_copilot" = "true" ] && has_manual_content_option; then
    die "git pr copilot cannot be combined with --title/--body/--body-file."
  fi

  if [ "$use_copilot" = "true" ] && has_body_generation_option; then
    die "git pr copilot cannot be combined with --fill/--no-fill."
  fi

  if [ "$fill_explicit" = "true" ] && has_manual_content_option; then
    die "--fill/--fill-first/--fill-verbose cannot be combined with --title/--body/--body-file."
  fi

  if [ "$fill_explicit" = "true" ] && [ -n "$template_file" ]; then
    die "--fill/--fill-first/--fill-verbose cannot be combined with --template."
  fi

  if [ "$skip_edit" = "true" ] && { [ "$use_copilot" = "true" ] || has_manual_content_option || has_body_generation_option; }; then
    die "--no-edit cannot be combined with options that modify the PR body/title."
  fi

  if [ "$skip_edit" = "true" ] && { [ "$editor" = "true" ] || [ -n "$template_file" ]; }; then
    die "--no-edit cannot be combined with --editor/--template."
  fi
}

validate_merge_options() {
  if [ "$action" = "auto-merge" ]; then
    if [ "$auto_merge_explicit" = "true" ]; then
      die "Use 'git pr auto-merge' without --enable-auto-merge."
    fi
    if has_non_auto_merge_pr_option; then
      die "auto-merge subcommand only accepts auto-merge options."
    fi
    if [ "$auto_merge_disable" = "true" ] && has_disable_auto_merge_conflict; then
      die "--disable-auto-merge cannot be combined with merge options."
    fi
  fi

  if [ "$action" = "merge" ]; then
    if [ "$auto_merge_explicit" = "true" ]; then
      die "Use 'git pr merge' without --enable-auto-merge."
    fi
    if has_non_auto_merge_pr_option; then
      die "merge subcommand only accepts merge options."
    fi
    if [ "$auto_merge_disable" = "true" ]; then
      die "--disable-auto-merge is only supported with 'git pr auto-merge'."
    fi
  fi

  if [ "$auto_merge_disable" = "true" ] && [ "$action" != "auto-merge" ]; then
    die "--disable-auto-merge is only supported with 'git pr auto-merge'."
  fi

  if [ "$auto_merge_disable" = "true" ] && [ "$auto_merge_explicit" = "true" ]; then
    die "--disable-auto-merge cannot be combined with --enable-auto-merge."
  fi

  if [ "$auto_merge_admin" = "true" ] && { [ "$auto_merge" = "true" ] || [ "$action" = "auto-merge" ] || [ "$action" = "merge" ]; }; then
    die "--admin cannot be used with git-pr merge operations because it bypasses merge requirements. Use gh pr merge --admin directly if you intend to bypass them."
  fi

  if [ "$auto_merge_match_head_explicit" = "true" ] && [ -z "$auto_merge_match_head" ]; then
    die "--match-head-commit requires a commit SHA."
  fi

  if has_merge_modifier_without_context; then
    die "Merge options require --enable-auto-merge, 'git pr auto-merge', or 'git pr merge'."
  fi

  case "$merge_method" in
    merge|squash|rebase)
      ;;
    *)
      die "Invalid merge method: $merge_method (use merge|squash|rebase)"
      ;;
  esac
}
