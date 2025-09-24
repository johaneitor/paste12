#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
if [ -z "$BASE" ]; then
  echo "Uso: $0 https://tu-app.onrender.com" >&2
  exit 1
fi
id="999999"

ok(){ printf "OK  - %s\n" "$*"; }
bad(){ printf "FAIL- %s\n" "$*" >&2; }

sc_like="$(curl -s -o /dev/null -w '%{http_code}\n' -X POST "$BASE/api/notes/$id/like" || true)"
[ "$sc_like" = "404" ] && ok "like 404" || bad "like => $sc_like"

sc_view="$(curl -s -o /dev/null -w '%{http_code}\n' -X POST "$BASE/api/notes/$id/view" || true)"
[ "$sc_view" = "404" ] && ok "view 404" || bad "view => $sc_view"

sc_report="$(curl -s -o /dev/null -w '%{http_code}\n' -X POST "$BASE/api/notes/$id/report" || true)"
[ "$sc_report" = "404" ] && ok "report 404" || bad "report => $sc_report"
