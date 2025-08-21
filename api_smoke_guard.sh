#!/usr/bin/env bash
set -Eeuo pipefail
base="${1:-https://paste12-rmsk.onrender.com}"

echo "== /api/health =="
curl -sS -H 'Accept: application/json' "$base/api/health"; echo; echo

echo "== page=1 =="
curl -sS -H 'Accept: application/json' "$base/api/notes?page=1" \
| python - <<'PY'
import sys,json
d=json.load(sys.stdin); ns=d.get("notes",[])
print("count:", len(ns))
print("ids:", [n["id"] for n in ns][:20])
PY
echo

# Extraer primer ID sin escribir a disco
ID="$(curl -sS -H 'Accept: application/json' "$base/api/notes?page=1" \
  | python - <<'PY'
import sys,json
d=json.load(sys.stdin); ns=d.get("notes",[])
print(ns[0]["id"] if ns else "")
PY
)"
echo "ID elegido = ${ID:-<vacío>}"
[ -z "$ID" ] && { echo "No hay notas para probar."; exit 0; }
echo

echo "== POST view/like/report válidos =="
echo "-- view   ->";  curl -sS -H 'Accept: application/json' -X POST "$base/api/notes/$ID/view";   echo
echo "-- like   ->";  curl -sS -H 'Accept: application/json' -X POST "$base/api/notes/$ID/like";   echo
echo "-- report ->";  curl -sS -H 'Accept: application/json' -X POST "$base/api/notes/$ID/report"; echo
echo

echo "== Fallbacks SIN id (deben ser 400 JSON; usamos -L para seguir 308) =="
curl -iL -sS -H 'Accept: application/json' -X POST "$base/api/notes//view"   | sed -n '1,12p'
curl -iL -sS -H 'Accept: application/json' -X POST "$base/api/notes//like"   | sed -n '1,12p'
curl -iL -sS -H 'Accept: application/json' -X POST "$base/api/notes//report" | sed -n '1,12p'
