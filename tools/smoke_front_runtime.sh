#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

echo "== smoke_front_runtime @ $BASE =="
echo "-- HEAD assets --"
for p in /css/actions.css?v=3 /js/actions.js?v=3; do
  c="$(curl -sS -I "$BASE$p" -o /dev/null -w '%{http_code}')" || c=000
  echo "$p -> $c"
  [[ "$c" == "200" || "$c" == "304" ]] || { echo "FAIL $p ($c)"; exit 1; }
done

echo "-- grep actions.js (helpers) --"
js="$(curl -sS "$BASE/js/actions.js?v=3")"
echo "$js" | grep -q 'window.p12Enhance' || { echo "FAIL falta p12Enhance"; exit 1; }
echo "$js" | grep -q 'tagDomByOrder'     || { echo "FAIL falta tagDomByOrder"; exit 1; }
echo "ok helpers"

echo "-- API sanity --"
curl -sS "$BASE/api/health" | python -m json.tool

echo "-- crea y marca vista --"
body="$(curl -sS -H 'Content-Type: application/json' --data '{"text":"smoke ui v3","hours":24}' "$BASE/api/notes")"
id="$(python - <<PY
import json,sys; j=json.loads("""$body"""); print(j["id"])
PY
)"
[[ -n "$id" ]] || { echo "FAIL no ID"; exit 1; }
curl -sS -X POST "$BASE/api/notes/$id/view" | python -m json.tool
curl -sS "$BASE/api/notes/$id" | python -m json.tool
echo "OK id=$id"
