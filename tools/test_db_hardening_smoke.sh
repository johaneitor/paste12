#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"
echo "== test_db_hardening_smoke =="
echo "BASE=$BASE"

# 1) Saca un id válido
ID="$(curl -fsS "$BASE/api/notes?limit=1" | python - <<'PY'
import sys,json
j=json.load(sys.stdin)
if isinstance(j,list) and j:
    print(j[0].get('id') or '')
elif isinstance(j,dict) and j.get('items'):
    print(j['items'][0].get('id') or '')
PY
)"

if [[ -z "$ID" ]]; then
  echo "ERROR: no pude obtener un id de nota"
  exit 2
fi
echo "→ id=$ID"

# 2) 20 likes seguidos
ok=0 fail=0 err=0
for i in $(seq 1 20); do
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/api/notes/$ID/like")
  if [[ "$code" == "200" || "$code" == "201" ]]; then ok=$((ok+1))
  elif [[ "$code" == "503" ]]; then fail=$((fail+1))  # handler actuó
  else err=$((err+1)); fi
  sleep 0.15
done

echo "likes -> ok=$ok, handled_503=$fail, otros=$err"

# 3) 10 listados
l_ok=0 l_err=0
for i in $(seq 1 10); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/api/notes?limit=10")
  if [[ "$code" == "200" ]]; then l_ok=$((l_ok+1)); else l_err=$((l_err+1)); fi
  sleep 0.1
done
echo "list   -> ok=$l_ok, err=$l_err"

# Resultado
if (( err==0 )); then
  echo "✔ Smoke passed (sin 500 sin manejar)."
  exit 0
else
  echo "❌ Hay respuestas no 200/503 en like: $err"
  exit 1
fi
