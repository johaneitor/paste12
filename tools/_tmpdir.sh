mkd() {
  local base="${TMPDIR:-$HOME}"
  mkdir -p "$base/.tmp_p12" 2>/dev/null || true
  mktemp -d "$base/.tmp_p12/p12.XXXXXX"
}
