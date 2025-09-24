#!/usr/bin/env bash
set -euo pipefail
REV=$(git rev-parse --short=12 HEAD)
inject() {
  f="$1"; [ -f "$f" ] || return 0
  if grep -Fqi 'name="p12-rev"' "$f"; then
    sed -i "s/\(<meta name=\"p12-rev\" content=\"\)[^\"]\+\"/\1$REV\"/I" "$f"
  else
    awk -v r="$REV" 'BEGIN{d=0} {print} /<head[^>]*>/ && !d {print "<meta name=\"p12-rev\" content=\"" r "\">"; d=1}' "$f" > "$f.__tmp" && mv "$f.__tmp" "$f"
  fi
  echo "OK: p12-rev=$REV en $f"
}
inject backend/static/index.html
inject frontend/index.html
