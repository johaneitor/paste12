#!/usr/bin/env bash
set -euo pipefail
restore_one () {
  local tgt="$1"
  local cand
  cand="$(ls -1t "$tgt".*.bak 2>/dev/null | head -n1 || true)"
  if [ -z "$cand" ]; then
    echo "✗ No .bak found for $tgt"; return 1
  fi
  local bak="${tgt}.pre_v7rollback.bak"
  [ -f "$bak" ] || cp -f "$tgt" "$bak"
  cp -f "$cand" "$tgt"
  echo "✓ Restored $tgt from $(basename "$cand") | prev -> $(basename "$bak")"
}
restore_one backend/static/index.html
restore_one frontend/index.html
echo "== sizes =="
wc -c backend/static/index.html frontend/index.html || true
