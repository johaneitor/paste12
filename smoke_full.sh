#!/usr/bin/env bash
set -Eeuo pipefail
base="https://paste12-rmsk.onrender.com"

echo "== /api/health =="
curl -sS "$base/api/health"; echo; echo

check_page() {
  p="$1"
  echo "→ $base/api/notes?page=$p"
  curl -sS "$base/api/notes?page=$p" \
  | python - <<PY
import sys,json
d=json.load(sys.stdin)
ns=d.get("notes",[])
print("  page:",d.get("page"),"page_size:",d.get("page_size"),"has_more:",d.get("has_more"))
print("  count(notes):",len(ns))
print("  ids:",[n["id"] for n in ns])
PY
  echo
}

check_page 1
check_page 2
check_page 3

# primer id de page=1
ID=$(curl -sS "$base/api/notes?page=1" | python - <<'PY'
import sys,json
d=json.load(sys.stdin); ns=d.get("notes",[])
print(ns[0]["id"] if ns else "")
PY
)
[ -z "$ID" ] && { echo "No hay notas para probar acciones."; exit 0; }

echo "Usando note_id=$ID"

echo "-- POST /view (1ª vez, debería contar) --"
curl -sS -X POST "$base/api/notes/$ID/view"; echo
sleep 1
echo "-- POST /view (2ª vez, NO debería contar) --"
curl -sS -X POST "$base/api/notes/$ID/view"; echo

echo "-- POST /like (1ª vez) --"
curl -sS -X POST "$base/api/notes/$ID/like"; echo
echo "-- POST /like (2ª vez, ya debería marcar 'already_liked') --"
curl -sS -X POST "$base/api/notes/$ID/like"; echo

echo "-- POST /report (1ª vez) --"
curl -sS -X POST "$base/api/notes/$ID/report"; echo
echo "-- POST /report (2ª vez, 'already_reported') --"
curl -sS -X POST "$base/api/notes/$ID/report"; echo
