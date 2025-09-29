#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE}"
TMP="${HOME}/.p12tmp.$$"; mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; ok(){ echo "OK  - $1"; PASS=$((PASS+1)); }; ko(){ echo "FAIL- $1"; FAIL=$((FAIL+1)); }
code(){ curl -sS -o /dev/null -w "%{http_code}" "$@"; }
body(){ curl -sS "$@"; }
headers(){ curl -sSI "$@"; }

[[ "$(code "$BASE")" == "200" ]] && ok "/ 200" || ko "/ 200"
IDX="$(body "$BASE")"
grep -qi 'name="p12-commit"' <<<"$IDX" && ok "index p12-commit" || ko "index p12-commit"
grep -qi 'p12-safe-shim' <<<"$IDX" && ok "p12-safe-shim presente" || ko "p12-safe-shim ausente"
( grep -qi 'data-single="' <<<"$IDX" || grep -qi 'name="p12-single"' <<<"$IDX" ) && ok "single detector" || ko "single detector"
[[ "$(code "$BASE/terms")" == "200" ]] && ok "/terms 200" || ko "/terms 200"
[[ "$(code "$BASE/privacy")" == "200" ]] && ok "/privacy 200" || ko "/privacy 200"
H="$(body "$BASE/health" || true)"; if [[ -n "$H" ]] && grep -qi '"api":\s*true' <<<"$H"; then ok "/health api:true"; else ok "/health opcional"; fi
CC="$(code -X OPTIONS "$BASE/api/notes")"; [[ "$CC" == "204" || "$CC" == "200" ]] && ok "preflight /api/notes" || ko "preflight /api/notes"
ANH="$(headers "$BASE/api/notes?limit=10")"; [[ "$(code "$BASE/api/notes?limit=10")" == "200" ]] && ok "/api/notes 200" || ko "/api/notes 200"
grep -qi 'content-type: application/json' <<<"$ANH" && ok "api/notes JSON" || ko "api/notes content-type"
grep -qE '^link:.*rel="next"' <<<"$ANH" && ok "Link: rel=next" || ko "Link: rel=next"
DSC="$(code "$BASE/api/deploy-stamp")"; if [[ "$DSC" == "200" ]]; then DSB="$(body "$BASE/api/deploy-stamp")"; grep -qi '"commit"' <<<"$DSB" && ok "deploy-stamp" || ko "deploy-stamp"; else ok "deploy-stamp opcional"; fi
LEN="$(printf "%s" "$IDX" | wc -c)"; (( LEN>=15360 && LEN<=122880 )) && ok "index peso razonable ($LEN)" || ko "index peso fuera de rango ($LEN)"
IH="$(headers "$BASE")"; grep -qi 'content-type: text/html' <<<"$IH" && ok "index content-type" || ko "index content-type"
grep -q 'p12FetchJson' <<<"$IDX" && ok "p12FetchJson expuesto" || ko "p12FetchJson ausente"
( grep -qi '^etag:' <<<"$IH" || grep -qi '^last-modified:' <<<"$IH" ) && ok "cache header" || ko "cache header"
echo "PASS=$PASS FAIL=$FAIL"; [[ "$FAIL" -eq 0 ]]
