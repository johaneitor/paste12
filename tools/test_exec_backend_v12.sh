#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
echo "== Smoke backend v12 =="
# health
H="$(curl -fsS "$BASE/api/health")"
[[ "$H" == '{"ok":true}' ]] && echo "OK  - health body JSON" || { echo "FAIL- health ($H)"; exit 1; }

# CORS OPTIONS
hdr="$(curl -i -s -X OPTIONS "$BASE/api/notes" | sed -n '1,40p')"
echo "$hdr" | grep -q '^HTTP/.* 204 ' && echo "OK  - OPTIONS 204" || { echo "FAIL- OPTIONS 204"; echo "$hdr"; exit 1; }
echo "$hdr" | grep -qi 'Access-Control-Allow-Origin: \*' && echo "OK  - ACAO" || { echo "FAIL- ACAO"; exit 1; }
echo "$hdr" | grep -qi 'Access-Control-Allow-Methods' && echo "OK  - ACAM" || { echo "FAIL- ACAM"; exit 1; }
echo "$hdr" | grep -qi 'Access-Control-Allow-Headers' && echo "OK  - ACAH" || { echo "FAIL- ACAH"; exit 1; }
echo "$hdr" | grep -qi 'Access-Control-Max-Age' && echo "OK  - Max-Age" || { echo "FAIL- Max-Age"; exit 1; }

# GET /api/notes (Link)
resp="$(curl -i -s "$BASE/api/notes?limit=3")"
echo "$resp" | grep -qi '^content-type: application/json' && echo "OK  - CT json" || { echo "FAIL- CT json"; exit 1; }
echo "$resp" | grep -qi '^Link: .*rel="next"' && echo "OK  - Link: next" || { echo "FAIL- Link: next"; echo "$resp" | sed -n '1,20p'; exit 1; }

# POST JSON
J="$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"test suite ascii 123456"}' "$BASE/api/notes")"
echo "$J" | grep -q '"id":' && echo "OK  - publish JSON" || { echo "FAIL- publish JSON ($J)"; exit 1; }

# POST FORM (FORM→JSON shim)
F="$(curl -fsS -d 'text=form shim create' "$BASE/api/notes")"
echo "$F" | grep -q '"id":' && echo "OK  - publish FORM" || { echo "FAIL- publish FORM ($F)"; exit 1; }

# Negativos (404)
for a in like view report; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/999999/$a")"
  [[ "$code" == "404" ]] && echo "OK  - $a 404" || { echo "FAIL- $a $code"; exit 1; }
done
echo "✔ Todo OK (backend v12)."
