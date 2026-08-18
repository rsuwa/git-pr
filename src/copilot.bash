
log_copilot_debug() {
  if [ "$#" -ne 7 ]; then
    die "Internal error: log_copilot_debug expects 7 arguments."
  fi

  local reason="$1"
  local log_dir="$2"
  local log_tag="$3"
  local prompt_path="$4"
  local diff_path="$5"
  local response_text="$6"
  local log_content="$7"
  local base
  local log_dir_existed="false"

  [ -e "$log_dir" ] && log_dir_existed="true"
  if ! mkdir -p "$log_dir"; then
    log_warn "Skipping Copilot debug log because directory could not be created: $log_dir"
    return 0
  fi
  if ! chmod 700 "$log_dir" 2>/dev/null; then
    if [ "$log_dir_existed" != "true" ]; then
      rmdir "$log_dir" 2>/dev/null || true
    fi
    log_warn "Skipping Copilot debug log because directory could not be secured: $log_dir"
    return 0
  fi
  base="$log_dir/copilot-$log_tag"
  (
    umask 077
    printf '%s\n' "$reason" > "$base.reason"
    if [ -n "$log_content" ]; then
      printf '%s\n' "$response_text" > "$base.response"
      cp "$prompt_path" "$base.prompt" 2>/dev/null || true
      cp "$diff_path" "$base.diff" 2>/dev/null || true
    else
      printf 'Prompt, diff, and response content omitted. Set GIT_PR_COPILOT_LOG_CONTENT=1 to keep them.\n' > "$base.meta"
    fi
  )
  log_warn "Copilot debug log saved: $base.*"
}

set_title_body_from_copilot_marked_response() {
  if [ "$#" -ne 2 ]; then
    die "Internal error: set_title_body_from_copilot_marked_response expects 2 arguments."
  fi

  local title_path="$1"
  local body_path="$2"

  : > "$title_path"
  : > "$body_path"

  if awk -v tf="$title_path" -v bf="$body_path" '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    BEGIN { state=""; title_set=0 }
    $0 == "__GIT_PR_TITLE__" { state="title"; next }
    $0 == "__GIT_PR_BODY__" { if (!title_set) exit 2; state="body"; next }
    $0 == "__GIT_PR_END__" { exit }
    state == "title" {
      t = trim($0)
      if (t == "") next
      print t > tf
      title_set=1
      state="title_done"
      next
    }
    state == "body" { print $0 > bf }
    END { if (!title_set) exit 1 }
  '; then
    title=$(cat "$title_path")
    body=$(cat "$body_path")
  else
    title=""
    body=""
  fi
}

set_title_body_from_copilot_fallback_response() {
  if [ "$#" -ne 1 ]; then
    die "Internal error: set_title_body_from_copilot_fallback_response expects 1 argument."
  fi

  local response_file="$1"

  title=$(awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    BEGIN { IGNORECASE=1; want_next=0 }
    {
      if (want_next) {
        t = trim($0)
        if (t != "") {
          low_t = tolower(t)
          if (match(low_t, /^(>[[:space:]]*)?(#{1,6}[[:space:]]*)?(body|本文|ボディ)[[:space:]]*([:：-]|$)/)) {
            exit
          }
          print t
          exit
        }
      }
      line = $0
      low = tolower(line)
      if (match(low, /^[[:space:]]*(>[[:space:]]*)?(#{1,6}[[:space:]]*)?(title|タイトル)[[:space:]]*([:：-][[:space:]]*|$)/)) {
        rest = substr(line, RLENGTH + 1)
        rest = trim(rest)
        if (rest != "") {
          print rest
          exit
        }
        want_next = 1
      }
    }' "$response_file")
  body=$(awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    BEGIN { IGNORECASE=1; found=0 }
    {
      line = $0
      low = tolower(line)
      if (!found && match(low, /^[[:space:]]*(>[[:space:]]*)?(#{1,6}[[:space:]]*)?(body|本文|ボディ)[[:space:]]*([:：-][[:space:]]*|$)/)) {
        found = 1
        rest = substr(line, RLENGTH + 1)
        rest = trim(rest)
        if (length(rest) > 0) print rest
        next
      }
      if (found) print line
    }' "$response_file")
}

merge_copilot_update_body() {
  if [ "$#" -ne 2 ]; then
    die "Internal error: merge_copilot_update_body expects 2 arguments."
  fi

  local existing="$1"
  local generated="$2"
  local result=""
  local line
  local in_block="false"
  local saw_start="false"
  local saw_end="false"
  local block_has_content="false"

  append_result_line() {
    if [ -n "$result" ]; then
      result+=$'\n'
    fi
    result+="$1"
  }

  append_result_text() {
    local text="$1"
    local text_line

    while IFS= read -r text_line || [ -n "$text_line" ]; do
      append_result_line "$text_line"
    done <<< "$text"
  }

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$COPILOT_UPDATE_START_MARKER" ]; then
      if [ "$saw_start" = "true" ] || [ "$in_block" = "true" ]; then
        return 1
      fi
      saw_start="true"
      in_block="true"
      append_result_line "$line"
      continue
    fi

    if [ "$line" = "$COPILOT_UPDATE_END_MARKER" ]; then
      if [ "$in_block" != "true" ] || [ "$saw_end" = "true" ]; then
        return 1
      fi
      saw_end="true"
      in_block="false"
      if [ "$block_has_content" = "true" ] && [ -n "$generated" ]; then
        append_result_line ""
      fi
      append_result_text "$generated"
      append_result_line "$line"
      continue
    fi

    append_result_line "$line"
    if [ "$in_block" = "true" ]; then
      block_has_content="true"
    fi
  done <<< "$existing"

  if [ "$in_block" = "true" ] || [ "$saw_start" != "$saw_end" ]; then
    return 1
  fi

  if [ "$saw_start" != "true" ]; then
    if [ -n "$result" ]; then
      append_result_line ""
    fi
    append_result_line "$COPILOT_UPDATE_START_MARKER"
    append_result_text "$generated"
    append_result_line "$COPILOT_UPDATE_END_MARKER"
  fi

  printf '%s' "$result"
}

validate_copilot_update_markers() {
  if [ "$#" -ne 1 ]; then
    die "Internal error: validate_copilot_update_markers expects 1 argument."
  fi

  merge_copilot_update_body "$1" "" >/dev/null
}

validate_copilot_diff_max_bytes() {
  local max_bytes="$1"

  if ! [[ "$max_bytes" =~ ^[0-9]+$ ]]; then
    die "GIT_PR_COPILOT_DIFF_MAX_BYTES must be an integer."
  fi
}

ensure_copilot_private_temp_available() {
  local temp_dir

  if [ -n "$copilot_private_temp_dir" ]; then
    return 0
  fi

  temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/git-pr.XXXXXX") || die "Failed to create temporary directory."
  register_cleanup_path "$temp_dir"
  chmod 700 "$temp_dir" 2>/dev/null || die "Failed to secure temporary directory: $temp_dir"
  copilot_private_temp_dir="$temp_dir"
}

generate_title_body_with_copilot() {
  local max_bytes="${GIT_PR_COPILOT_DIFF_MAX_BYTES:-20000}"
  validate_copilot_diff_max_bytes "$max_bytes"

  local -a diff_pathspec
  diff_pathspec=(".")
  if [ "${#diff_excludes[@]}" -gt 0 ]; then
    for exclude_path in "${diff_excludes[@]}"; do
      diff_pathspec+=(":(exclude)$exclude_path")
    done
  fi

  if git -C "$repo_root" diff --quiet "$base_ref...HEAD" -- "${diff_pathspec[@]}"; then
    log_warn "No diff to summarize; falling back."
    return 1
  fi

  local temp_dir
  if [ -n "$copilot_private_temp_dir" ]; then
    temp_dir="$copilot_private_temp_dir"
  else
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/git-pr.XXXXXX") || die "Failed to create temporary directory."
    register_cleanup_path "$temp_dir"
    chmod 700 "$temp_dir" 2>/dev/null || die "Failed to secure temporary directory: $temp_dir"
    copilot_private_temp_dir="$temp_dir"
  fi

  local diff_file
  diff_file="$temp_dir/diff.txt"

  {
    printf "Diff stat:\n"
    git -C "$repo_root" diff --stat "$base_ref...HEAD" -- "${diff_pathspec[@]}"
    printf "\nDiff:\n"
    git -C "$repo_root" diff "$base_ref...HEAD" -- "${diff_pathspec[@]}"
  } > "$diff_file" || {
    log_warn "Failed to prepare Copilot prompt; falling back."
    return 1
  }

  local file_size
  file_size=$(wc -c < "$diff_file" | tr -d ' ') || {
    log_warn "Failed to prepare Copilot prompt; falling back."
    return 1
  }
  if [ "$file_size" -gt "$max_bytes" ]; then
    local truncated_diff_file
    truncated_diff_file="$temp_dir/diff-truncated.txt"
    truncate_utf8 "$max_bytes" < "$diff_file" > "$truncated_diff_file" || {
      log_warn "Failed to prepare Copilot prompt; falling back."
      return 1
    }
    mv "$truncated_diff_file" "$diff_file" || {
      log_warn "Failed to prepare Copilot prompt; falling back."
      return 1
    }
    printf "\n\n[Diff truncated to %s bytes]\n" "$max_bytes" >> "$diff_file" || {
      log_warn "Failed to prepare Copilot prompt; falling back."
      return 1
    }
  fi

  local prompt_file
  local state_home="${XDG_STATE_HOME:-${HOME:-$repo_root/.git}/.local/state}"
  local copilot_log_dir="${GIT_PR_COPILOT_LOG_DIR:-$state_home/git-pr/copilot-logs}"
  local copilot_log_always="${GIT_PR_COPILOT_LOG:-}"
  local copilot_log_content="${GIT_PR_COPILOT_LOG_CONTENT:-}"
  local copilot_log_tag
  copilot_log_tag="$(date +%Y%m%d-%H%M%S)-$$"
  local existing_note=""
  local template_note=""
  local template_content=""
  local language_instruction
  local detail_note="- Body: Use GitHub PR-style Markdown with headings and bullet lists."
  local verbose_note="- Include only relevant sections; avoid empty sections."
  local tests_note
  local section_note
  case "$language" in
    ja)
      language_instruction="You are writing a GitHub pull request title and body in Japanese based only on the provided diff."
      tests_note="- If tests are not found, include a テスト section with 「未実施」."
      section_note="- Use appropriate sections chosen from: 概要, 変更点, 影響範囲, テスト, 注意点, 補足."
      ;;
    en)
      language_instruction="You are writing a GitHub pull request title and body in English based only on the provided diff."
      tests_note="- If tests are not found, include a Tests section with \"Not run\"."
      section_note="- Use appropriate sections chosen from: Summary, Changes, Impact, Tests, Notes."
      ;;
  esac
  if [ "$copilot_detail" = "verbose" ]; then
    detail_note="- Body: Use GitHub PR-style Markdown with headings and bullet lists, and add more detail."
    verbose_note="- Include rationale, impact, and edge cases when visible in the diff."
  fi
  if [ "$copilot_update_effective" = "true" ]; then
    existing_note=$(cat <<EOF
- You are generating an update section for an existing PR body.
- Return only the new or changed details that should go in the generated update section.
- Do not repeat the full existing PR body.
- Avoid duplicate content.

Current PR title:
$copilot_existing_title

Current PR body:
$copilot_existing_body
EOF
)
  fi

  if [ -n "$template_file" ]; then
    template_content=$(cat "$template_file") || {
      log_warn "Failed to prepare Copilot prompt; falling back."
      return 1
    }
    template_note=$(cat <<EOF
- Follow the provided PR template structure and headings.
- Keep existing template text unless you are confident it should be replaced.
- If you cannot infer content for a section, leave it blank.

PR template:
$template_content
EOF
)
    tests_note="- If you cannot infer test information, leave the section blank."
    verbose_note="- Leave sections blank when the diff does not provide information."
    section_note=""
  fi

  prompt_file="$temp_dir/prompt.txt"

  {
    cat <<EOF
$language_instruction
- Title: single line, concise.
$detail_note
$section_note
$verbose_note
$tests_note
- Do not invent details not in the diff.
- Output exactly in the format below, with no extra text.
- Use the markers exactly as written (no extra characters on those lines).
$existing_note
$template_note

__GIT_PR_TITLE__
<title>
__GIT_PR_BODY__
<body>
__GIT_PR_END__

Input:
EOF
  } > "$prompt_file" || {
    log_warn "Failed to prepare Copilot prompt; falling back."
    return 1
  }
  cat "$diff_file" >> "$prompt_file" || {
    log_warn "Failed to prepare Copilot prompt; falling back."
    return 1
  }

  local response=""
  response=$(cd "$repo_root" && copilot -s --no-custom-instructions -p "@$prompt_file") || {
    log_warn "Copilot CLI failed; falling back. Run 'copilot' once to sign in or check access. See: $COPILOT_CLI_USAGE_URL"
    log_copilot_debug "copilot-cli-failed" "$copilot_log_dir" "$copilot_log_tag" "$prompt_file" "$diff_file" "$response" "$copilot_log_content"
    return 1
  }
  response=$(printf '%s\n' "$response" | sed 's/\r$//')

  local response_file
  response_file="$temp_dir/response.txt"
  printf '%s\n' "$response" > "$response_file"

  local title_file
  local body_file
  title_file="$temp_dir/title.txt"
  body_file="$temp_dir/body.txt"
  set_title_body_from_copilot_marked_response "$title_file" "$body_file" < "$response_file"
  rm -f "$title_file" "$body_file"

  if [ -z "$title" ] || [ -z "$body" ]; then
    set_title_body_from_copilot_fallback_response "$response_file"
  fi

  if [ -z "$title" ] || [ -z "$body" ]; then
    title=""
    body=""
    log_warn "Failed to parse Copilot output; falling back."
    log_copilot_debug "copilot-parse-failed" "$copilot_log_dir" "$copilot_log_tag" "$prompt_file" "$diff_file" "$response" "$copilot_log_content"
    return 1
  fi

  if [ -n "$copilot_log_always" ]; then
    log_copilot_debug "copilot-success" "$copilot_log_dir" "$copilot_log_tag" "$prompt_file" "$diff_file" "$response" "$copilot_log_content"
  fi
  return 0
}

can_run_copilot_generation() {
  if ! command -v copilot >/dev/null 2>&1; then
    log_warn "Copilot CLI not found; falling back. $(copilot_cli_install_message)"
    return 1
  fi

  local max_bytes="${GIT_PR_COPILOT_DIFF_MAX_BYTES:-20000}"
  validate_copilot_diff_max_bytes "$max_bytes"

  return 0
}

truncate_utf8() {
  local max_bytes="$1"

  if command -v python3 > /dev/null 2>&1; then
    python3 -c 'import sys

max_bytes = int(sys.argv[1])
data = sys.stdin.buffer.read()
if len(data) > max_bytes:
    data = data[:max_bytes]
sys.stdout.write(data.decode("utf-8", errors="ignore"))
' "$max_bytes"
    return 0
  fi

  if command -v iconv > /dev/null 2>&1; then
    head -c "$max_bytes" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null
    return 0
  fi

  head -c "$max_bytes"
}
