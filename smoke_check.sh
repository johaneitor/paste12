#!/usr/bin/env bash
set -Eeuo pipefail

echo "== /api/health =="
curl -sS https://paste12-rmsk.onrender.com/api/health || true
echo -e "\n"

echo "== /api/notes?page=1 (primeras claves) =="
curl -sS 'https://paste12-rmsk.onrender.com/api/notes?page=1' \
| python - <<'PY'
import sys, json
d=json.load(sys.stdin)
notes=d.get("notes",[])
print("page:", d.get("page"), "page_size:", d.get("page_size"), "has_more:", d.get("has_more"))
print("count(notes):", len(notes))
if notes:
    print("first id/timestamp:", notes[0].get("id"), notes[0].get("timestamp"))
    print("last  id/timestamp:", notes[-1].get("id"), notes[-1].get("timestamp"))
PY
echo

echo "== /api/notes?page=2 (sanidad de paginación) =="
curl -sS 'https://paste12-rmsk.onrender.com/api/notes?page=2' \
| python - <<'PY'
import sys, json
try:
  d=json.load(sys.stdin)
  notes=d.get("notes",[])
  print("page:", d.get("page"), "count(notes):", len(notes), "has_more:", d.get("has_more"))
  if notes:
      print("first id:", notes[0].get("id"), "last id:", notes[-1].get("id"))
except Exception as e:
  print("no-json:", e)
PY
echo

echo "== Prueba vistas idempotentes (si hay al menos 1 nota en page=1) =="
ID=$(curl -sS 'https://paste12-rmsk.onrender.com/api/notes?page=1' | python - <<'PY'
import sys, json
d=json.load(sys.stdin); ns=d.get("notes",[])
print(ns[0]["id"] if ns else "")
PY
)
if [ -n "$ID" ]; then
  echo "Usando note_id=$ID"
  echo "POST view #1:"; curl -sS -X POST "https://paste12-rmsk.onrender.com/api/notes/$ID/view"
  echo; sleep 1
  echo "POST view #2 (debería NO contar):"; curl -sS -X POST "https://paste12-rmsk.onrender.com/api/notes/$ID/view"
  echo
else
  echo "No hay notas para probar vistas."
fi
