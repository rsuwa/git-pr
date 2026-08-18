
doctor_command_status() {
  local command_name="$1"
  local label="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    log_info "$label: found"
    return 0
  fi

  log_warn "$label: missing"
  return 1
}

doctor_detect_github_host() {
  local doctor_repo_root
  local doctor_origin_url
  local doctor_github_host

  doctor_repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    printf '%s\n%s' \
      'github.com' \
      'No git repository found; checking GitHub CLI auth for github.com.'
    return 0
  }

  doctor_origin_url=$(git -C "$doctor_repo_root" remote get-url origin 2>/dev/null) || {
    printf '%s\n%s' \
      'github.com' \
      "Remote 'origin' not found; checking GitHub CLI auth for github.com."
    return 0
  }

  if ! github_repo_from_origin_url "$doctor_origin_url" >/dev/null; then
    log_warn "Remote 'origin' is not a supported GitHub repository URL: $(redact_url "$doctor_origin_url")"
    return 1
  fi

  doctor_github_host=$(github_host_from_origin_url "$doctor_origin_url") || {
    log_warn "Remote 'origin' is not a supported GitHub repository URL: $(redact_url "$doctor_origin_url")"
    return 1
  }

  printf '%s' "$doctor_github_host"
}

run_doctor() {
  local with_copilot="$1"
  local status=0
  local git_ok="false"
  local gh_ok="false"
  local github_host="github.com"
  local doctor_host_note=""
  local doctor_host_output

  log_info "Checking git-pr dependencies"

  if doctor_command_status git "git"; then
    git_ok="true"
  else
    status=1
  fi

  if doctor_command_status gh "GitHub CLI"; then
    gh_ok="true"
  else
    log_warn "GitHub CLI setup: install gh from $GITHUB_CLI_INSTALL_URL"
    status=1
  fi

  if [ "$gh_ok" = "true" ]; then
    if [ "$git_ok" = "true" ]; then
      if ! doctor_host_output=$(doctor_detect_github_host); then
        status=1
        github_host="github.com"
      else
        github_host="${doctor_host_output%%$'\n'*}"
        if [ "$doctor_host_output" != "$github_host" ]; then
          doctor_host_note="${doctor_host_output#*$'\n'}"
        fi
      fi
      if [ -n "$doctor_host_note" ]; then
        log_info "$doctor_host_note"
      fi
    fi

    if gh auth status --hostname "$github_host" >/dev/null 2>&1; then
      log_info "GitHub CLI auth: ok ($github_host)"
    else
      log_warn "GitHub CLI auth: failed ($github_host). $(github_cli_auth_message "$github_host")"
      status=1
    fi
  fi

  if command -v copilot >/dev/null 2>&1; then
    log_info "Copilot CLI: found on PATH"
  elif [ "$with_copilot" = "true" ]; then
    log_warn "Copilot CLI: missing. $(copilot_cli_install_message)"
    status=1
  else
    log_info "Copilot CLI: not found (optional; needed only for 'git pr copilot'). $(copilot_cli_install_message)"
  fi

  if [ "$status" -eq 0 ]; then
    log_info "Doctor checks passed."
  fi

  return "$status"
}
