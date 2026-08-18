
init_action_state() {
  action="create"
  doctor_with_copilot="false"
}

init_pr_content_state() {
  base_branch=""
  base_branch_explicit="false"
  draft="false"
  draft_explicit="false"
  open_web="false"
  open_web_explicit="false"
  fill="true"
  fill_explicit="false"
  fill_mode="normal"
  fill_mode_explicit="false"
  fill_mode_conflict="false"
  no_fill_explicit="false"
  skip_edit="false"
  editor="false"
  template_file=""
  template_file_explicit="false"
  template_resolved="false"
  title=""
  title_explicit="false"
  body=""
  body_explicit="false"
  body_file=""
  body_file_explicit="false"
}

init_metadata_state() {
  label_explicit="false"
  reviewer_explicit="false"
  assignee_explicit="false"
  label_args=()
  reviewer_args=()
  assignee_args=()
  edit_label_args=()
  edit_reviewer_args=()
  edit_assignee_args=()
}

init_merge_state() {
  merge_method="merge"
  merge_method_explicit="false"
  auto_merge="false"
  auto_merge_explicit="false"
  auto_merge_delete_branch="false"
  auto_merge_admin="false"
  auto_merge_disable="false"
  auto_merge_match_head=""
  auto_merge_match_head_explicit="false"
}

init_copilot_state() {
  use_copilot="false"
  copilot_mode="auto"
  copilot_mode_explicit="false"
  copilot_detail="normal"
  copilot_detail_explicit="false"
  language="${GIT_PR_LANGUAGE:-}"
  language_explicit="false"
  diff_exclude_explicit="false"
  copilot_existing_title=""
  copilot_existing_body=""
  copilot_existing_body_loaded="false"
  copilot_update_effective="false"
  copilot_mode_effective="auto"
  diff_exclude_args=()
  diff_excludes=()
}

init_parser_state() {
  parse_option_shift=0
}

init_option_defaults() {
  init_action_state
  init_pr_content_state
  init_metadata_state
  init_merge_state
  init_copilot_state
  init_parser_state
}

parse_action_argument() {
  # Parser helpers set parse_option_shift before returning success.
  parse_option_shift=0

  case "${1-}" in
    create|auto-merge|merge|copilot|doctor|update)
      action="$1"
      parse_option_shift=1
      return 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --version)
      version
      exit 0
      ;;
  esac

  return 1
}

set_fill_mode() {
  local mode="$1"

  fill="true"
  fill_explicit="true"
  if [ "$fill_mode_explicit" = "true" ] && [ "$fill_mode" != "$mode" ]; then
    fill_mode_conflict="true"
  fi
  fill_mode="$mode"
  fill_mode_explicit="true"
}

parse_pr_content_option() {
  parse_option_shift=0

  case "${1-}" in
      -b|--base)
        require_option_value "$1" "$#"
        base_branch="$2"
        base_branch_explicit="true"
        parse_option_shift=2
        return 0
        ;;
      --base=*)
        base_branch="${1#*=}"
        base_branch_explicit="true"
        parse_option_shift=1
        return 0
        ;;
      -t|--title)
        require_option_value "$1" "$#"
        title="$2"
        title_explicit="true"
        fill="false"
        parse_option_shift=2
        return 0
        ;;
      --title=*)
        title="${1#*=}"
        title_explicit="true"
        fill="false"
        parse_option_shift=1
        return 0
        ;;
      -d|--body)
        require_option_value "$1" "$#"
        body="$2"
        body_explicit="true"
        fill="false"
        parse_option_shift=2
        return 0
        ;;
      --body=*)
        body="${1#*=}"
        body_explicit="true"
        fill="false"
        parse_option_shift=1
        return 0
        ;;
      -F|--body-file)
        require_option_value "$1" "$#"
        body_file="$2"
        body_file_explicit="true"
        fill="false"
        parse_option_shift=2
        return 0
        ;;
      --body-file=*)
        body_file="${1#*=}"
        body_file_explicit="true"
        fill="false"
        parse_option_shift=1
        return 0
        ;;
      -e|--editor)
        editor="true"
        parse_option_shift=1
        return 0
        ;;
      -T|--template)
        require_option_value "$1" "$#"
        template_file="$2"
        template_file_explicit="true"
        parse_option_shift=2
        return 0
        ;;
      --template=*)
        template_file="${1#*=}"
        template_file_explicit="true"
        parse_option_shift=1
        return 0
        ;;
  esac

  return 1
}

parse_metadata_option() {
  parse_option_shift=0

  case "${1-}" in
      --label)
        require_option_value "$1" "$#"
        label_explicit="true"
        append_label_args "$2"
        parse_option_shift=2
        return 0
        ;;
      --label=*)
        label_explicit="true"
        append_label_args "${1#*=}"
        parse_option_shift=1
        return 0
        ;;
      --reviewer)
        require_option_value "$1" "$#"
        reviewer_explicit="true"
        append_reviewer_args "$2"
        parse_option_shift=2
        return 0
        ;;
      --reviewer=*)
        reviewer_explicit="true"
        append_reviewer_args "${1#*=}"
        parse_option_shift=1
        return 0
        ;;
      --assignee)
        require_option_value "$1" "$#"
        assignee_explicit="true"
        append_assignee_args "$2"
        parse_option_shift=2
        return 0
        ;;
      --assignee=*)
        assignee_explicit="true"
        append_assignee_args "${1#*=}"
        parse_option_shift=1
        return 0
        ;;
  esac

  return 1
}

parse_copilot_option() {
  parse_option_shift=0

  case "${1-}" in
      --mode)
        require_option_value "$1" "$#"
        copilot_mode="$2"
        copilot_mode_explicit="true"
        parse_option_shift=2
        return 0
        ;;
      --mode=*)
        copilot_mode="${1#*=}"
        copilot_mode_explicit="true"
        parse_option_shift=1
        return 0
        ;;
      --detail)
        require_option_value "$1" "$#"
        copilot_detail="$2"
        copilot_detail_explicit="true"
        parse_option_shift=2
        return 0
        ;;
      --detail=*)
        copilot_detail="${1#*=}"
        copilot_detail_explicit="true"
        parse_option_shift=1
        return 0
        ;;
      --language)
        require_option_value "$1" "$#"
        language="$2"
        language_explicit="true"
        parse_option_shift=2
        return 0
        ;;
      --language=*)
        language="${1#*=}"
        language_explicit="true"
        parse_option_shift=1
        return 0
        ;;
      --diff-exclude)
        require_option_value "$1" "$#"
        diff_exclude_args+=("$2")
        diff_exclude_explicit="true"
        parse_option_shift=2
        return 0
        ;;
      --diff-exclude=*)
        diff_exclude_args+=("${1#*=}")
        diff_exclude_explicit="true"
        parse_option_shift=1
        return 0
        ;;
  esac

  return 1
}

parse_fill_option() {
  parse_option_shift=0

  case "${1-}" in
      --fill)
        set_fill_mode "normal"
        parse_option_shift=1
        return 0
        ;;
      --fill-first)
        set_fill_mode "first"
        parse_option_shift=1
        return 0
        ;;
      --fill-verbose)
        set_fill_mode "verbose"
        parse_option_shift=1
        return 0
        ;;
      --no-fill)
        fill="false"
        no_fill_explicit="true"
        parse_option_shift=1
        return 0
        ;;
  esac

  return 1
}

parse_merge_option() {
  parse_option_shift=0

  case "${1-}" in
      -a|--enable-auto-merge)
        auto_merge="true"
        auto_merge_explicit="true"
        parse_option_shift=1
        return 0
        ;;
      -m|--merge-method)
        require_option_value "$1" "$#"
        merge_method="$2"
        merge_method_explicit="true"
        parse_option_shift=2
        return 0
        ;;
      --merge-method=*)
        merge_method="${1#*=}"
        merge_method_explicit="true"
        parse_option_shift=1
        return 0
        ;;
      --delete-branch)
        auto_merge_delete_branch="true"
        parse_option_shift=1
        return 0
        ;;
      --admin)
        auto_merge_admin="true"
        parse_option_shift=1
        return 0
        ;;
      --match-head-commit)
        require_option_value "$1" "$#"
        auto_merge_match_head="$2"
        auto_merge_match_head_explicit="true"
        parse_option_shift=2
        return 0
        ;;
      --match-head-commit=*)
        auto_merge_match_head="${1#*=}"
        auto_merge_match_head_explicit="true"
        parse_option_shift=1
        return 0
        ;;
      --disable-auto-merge)
        auto_merge_disable="true"
        parse_option_shift=1
        return 0
        ;;
  esac

  return 1
}

parse_misc_option() {
  parse_option_shift=0

  case "${1-}" in
      --no-edit|--skip-edit)
        skip_edit="true"
        parse_option_shift=1
        return 0
        ;;
      --with-copilot)
        doctor_with_copilot="true"
        parse_option_shift=1
        return 0
        ;;
      --draft)
        draft="true"
        draft_explicit="true"
        parse_option_shift=1
        return 0
        ;;
      -w|--web)
        open_web="true"
        open_web_explicit="true"
        parse_option_shift=1
        return 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --version)
        version
        exit 0
        ;;
  esac

  return 1
}

parse_option_argument() {
  parse_pr_content_option "$@" || \
    parse_metadata_option "$@" || \
    parse_copilot_option "$@" || \
    parse_fill_option "$@" || \
    parse_merge_option "$@" || \
    parse_misc_option "$@"
}

parse_arguments() {
  if [ $# -gt 0 ] && parse_action_argument "$1"; then
    shift "$parse_option_shift"
  fi

  while [ $# -gt 0 ]; do
    if ! parse_option_argument "$@"; then
      die "Unknown argument: $1"
    fi
    shift "$parse_option_shift"
  done
}

apply_copilot_action_defaults() {
  if [ "$action" = "copilot" ]; then
    use_copilot="true"
    fill="false"
  fi
}

apply_auto_merge_action_defaults() {
  if [ "$action" = "auto-merge" ]; then
    auto_merge="true"
  fi
}
