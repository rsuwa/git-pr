
default_update_checksum_url() {
  case "$1" in
    */*)
      printf '%s/SHA256SUMS\n' "${1%/*}"
      ;;
    *)
      printf 'SHA256SUMS\n'
      ;;
  esac
}

redact_url() {
  local url="$1"
  local redacted="$url"
  local scheme
  local rest
  local authority
  local path

  case "$redacted" in
    *'#'*)
      redacted="${redacted%%#*}#REDACTED"
      ;;
  esac
  case "$redacted" in
    *'?'*)
      redacted="${redacted%%\?*}?REDACTED"
      ;;
  esac
  case "$redacted" in
    *://*@*)
      scheme="${redacted%%://*}"
      rest="${redacted#*://}"
      authority="${rest%%/*}"
      path="${rest#*/}"
      authority="${authority#*@}"
      if [ "$path" != "$rest" ]; then
        redacted="$scheme://REDACTED@$authority/$path"
      else
        redacted="$scheme://REDACTED@$authority"
      fi
      ;;
  esac

  printf '%s' "$redacted"
}
