#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE}"
ID="999999999"
TMP="${HOME}/.p12tmp.$$"; mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT
code(){ curl -sS -X "$1" -o /dev/null -w "%{http_code}" "$BASE$2"; }
like="$(code POST  "/api/notes/$ID/like")"
view_get="$(code GET  "/api/notes/$ID/view")"
view_post="$(code POST "/api/notes/$ID/view")"
report="$(code POST "/api/notes/$ID/report")"
ok_like=$([ "$like" = 404 ] && echo ok || echo ko)
ok_view=$({ [ "$view_get" = 404 ] || [ "$view_post" = 404 ]; } && echo ok || echo ko)
ok_report=$([ "$report" = 404 ] && echo ok || echo ko)
echo "negativos: like=$like view(GET/POST)=$view_get/$view_post report=$report"
[[ "$ok_like" = ok && "$ok_view" = ok && "$ok_report" = ok ]]
