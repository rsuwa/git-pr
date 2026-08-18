
generate_body_from_commits() {
  local first_commit
  case "$fill_mode" in
    first)
      first_commit=$(git -C "$repo_root" rev-list --reverse --max-count=1 "$base_ref..HEAD")
      if [ -n "$first_commit" ]; then
        body=$(git -C "$repo_root" log -1 --pretty='%s%n%n%b' "$first_commit")
      else
        body=""
      fi
      ;;
    verbose)
      body=$(git -C "$repo_root" log --pretty='- %s%n%n%b' "$base_ref..HEAD")
      ;;
    normal|*)
      body=$(git -C "$repo_root" log --pretty='- %s' "$base_ref..HEAD")
      ;;
  esac
}

resolve_template_file() {
  local candidate=""

  if [ -z "$template_file" ]; then
    return 0
  fi

  case "$template_file" in
    /*|./*|../*|*/*)
      if [ -f "$template_file" ]; then
        template_resolved="true"
        return 0
      fi
      if [ -f "$repo_root/$template_file" ]; then
        template_file="$repo_root/$template_file"
        template_resolved="true"
        return 0
      fi
      die "Template file not found: $template_file"
      ;;
  esac

  candidate="$repo_root/$template_file"
  if [ -f "$candidate" ]; then
    template_file="$candidate"
    template_resolved="true"
    return 0
  fi

  candidate="$repo_root/.github/$template_file"
  if [ -f "$candidate" ]; then
    template_file="$candidate"
    template_resolved="true"
    return 0
  fi

  candidate="$repo_root/.github/PULL_REQUEST_TEMPLATE/$template_file"
  if [ -f "$candidate" ]; then
    template_file="$candidate"
    template_resolved="true"
    return 0
  fi

  case "$template_file" in
    *.md)
      ;;
    *)
      candidate="$repo_root/${template_file}.md"
      if [ -f "$candidate" ]; then
        template_file="$candidate"
        template_resolved="true"
        return 0
      fi
      candidate="$repo_root/.github/${template_file}.md"
      if [ -f "$candidate" ]; then
        template_file="$candidate"
        template_resolved="true"
        return 0
      fi
      candidate="$repo_root/.github/PULL_REQUEST_TEMPLATE/${template_file}.md"
      if [ -f "$candidate" ]; then
        template_file="$candidate"
        template_resolved="true"
        return 0
      fi
      ;;
  esac

  return 0
}
