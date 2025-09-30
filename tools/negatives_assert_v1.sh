#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
fail=0
check(){ local want="$1" path="$2" ; code=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE$2" || true); echo "$path -> $code"; [[ "$code" == "$want" ]] || fail=1; }
nid="99999999"
check 404 "/api/like?id=${nid}"
check 404 "/api/view?id=${nid}"
check 404 "/api/report?id=${nid}"
# también testear POST en /api/view por si existe
code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -d "id=${nid}" "$BASE/api/view" || true); echo "POST /api/view -> $code"
[[ "$code" == "404" || "$code" == "405" ]] || fail=1
if [[ $fail -eq 0 ]]; then echo "NEGATIVOS_OK"; else echo "NEGATIVOS_FAIL"; exit 1; fi
