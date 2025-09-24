#!/usr/bin/env bash
set -euo pipefail
sizes() {
  local p="$1"
  printf "%8s  %s\n" "$(wc -c < "$p" 2>/dev/null | tr -d ' ' || echo 0)" "$p"
}
echo "== working tree =="
for f in backend/static/index.html frontend/index.html; do [ -f "$f" ] && sizes "$f" || true; done
echo "== HEAD =="
for f in backend/static/index.html frontend/index.html; do git show HEAD:"$f" >/dev/null 2>&1 && \
  printf "%8s  %s (HEAD)\n" "$(git show HEAD:"$f" | wc -c | tr -d ' ')" "$f"; done
echo "== origin/main =="
git fetch -q origin main
for f in backend/static/index.html frontend/index.html; do git show origin/main:"$f" >/dev/null 2>&1 && \
  printf "%8s  %s (origin/main)\n" "$(git show origin/main:"$f" | wc -c | tr -d ' ')" "$f"; done
