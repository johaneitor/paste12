pick_download() {
  for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do
    [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }
  done
  mkdir -p "$HOME/downloads"; echo "$HOME/downloads"
}
mkd() {
  local base="${TMPDIR:-$HOME}"
  mkdir -p "$base/.tmp_p12" 2>/dev/null || true
  mktemp -d "$base/.tmp_p12/p12.XXXXXX"
}
stamp_utc(){ date -u +%Y%m%d-%H%M%SZ; }
