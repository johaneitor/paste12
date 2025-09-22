#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"
echo "== test_db_hardening_smoke_v2 =="
echo "BASE=$BASE"

tmp_body="$(mktemp)"
code=$(curl -sS -o "$tmp_body" -w "%{http_code}" "$BASE/api/notes?limit=1")
ct=$(curl -sSI "$BASE/api/notes?limit=1" | awk -F': ' 'BEGIN{IGNORECASE=1}/^Content-Type:/{print $2; exit}' | tr -d '\r')

if [[ "$code" != "200" ]]; then
  echo "ERROR: /api/notes?limit=1 -> HTTP $code"
  sed -n '1,200p' "$tmp_body" || true
  exit 2
fi

if ! grep -qi 'application/json' <<<"$ct"; then
  echo "ERROR: Content-Type no JSON: $ct"
  head -c 200 "$tmp_body" || true; echo
  exit 2
fi

ID="$(python - <<'PY'
import sys,json
data=json.load(open(sys.argv[1]))
if isinstance(data,list) and data:
    print(data[0].get('id') or '')
elif isinstance(data,dict) and data.get('items'):
    print(data['items'][0].get('id') or '')
PY
"$tmp_body"
)"

rm -f "$tmp_body"

if [[ -z "$ID" ]]; then
  echo "ERROR: no pude extraer id de nota"
  exit 2
fi
echo "→ id=$ID"

ok=0 handled=0 other=0
for i in $(seq 1 20); do
  c=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/api/notes/$ID/like")
  case "$c" in
    200|201) ok=$((ok+1));;
    503)     handled=$((handled+1));;
    *)       other=$((other+1));;
  esac
  sleep 0.15
done
echo "likes -> ok=$ok handled_503=$handled other=$other"

l_ok=0 l_err=0
for i in $(seq 1 10); do
  c=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/api/notes?limit=10")
  if [[ "$c" == "200" ]]; then l_ok=$((l_ok+1)); else l_err=$((l_err+1)); fi
  sleep 0.1
done
echo "list  -> ok=$l_ok err=$l_err"

if (( other==0 )); then
  echo "✔ Smoke OK"
  exit 0
else
  echo "❌ Hay códigos inesperados en like: $other"
  exit 1
fi
