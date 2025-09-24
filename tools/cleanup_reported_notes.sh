#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
LIMIT="${LIMIT:-200}"
THRESHOLD="${THRESHOLD:-3}"
DRY_RUN="${DRY_RUN:-1}"

if [ -z "$BASE" ]; then
  echo "Uso: [DRY_RUN=0] [THRESHOLD=3] [LIMIT=200] $0 https://tu-app.onrender.com" >&2
  exit 1
fi

scan() {
  curl -fsS "$BASE/api/notes?limit=$LIMIT"
}

delete_note() {
  local id="$1"
  # Intento 1: DELETE REST clásico
  if curl -s -o /dev/null -w '%{http_code}\n' -X DELETE "$BASE/api/notes/$id" | grep -q '^20'; then
    return 0
  fi
  # Intento 2: POST a /api/notes/<id>/delete (algunos backends lo usan)
  if curl -s -o /dev/null -w '%{http_code}\n' -X POST "$BASE/api/notes/$id/delete" | grep -q '^20'; then
    return 0
  fi
  # Sin endpoint admin: devolvemos 1
  return 1
}

echo "➡️  Escaneando $BASE/api/notes?limit=$LIMIT (DRY_RUN=$DRY_RUN)"
json="$(scan)"
python - <<PY
import sys, json, os
data = json.loads(sys.stdin.read())
th = int(os.environ.get("THRESHOLD","3"))
notes = [x for x in data if isinstance(x, dict)]
candidates = [x for x in notes if int(x.get("reports",0))>=th]
print("──────── resumen")
print("Escaneados:", len(notes))
print("Elegibles (reports >= %d): %d" % (th, len(candidates)))
for x in candidates[:5]:
    print(" - id=%s reports=%s" % (x.get("id"), x.get("reports")))
PY <<<"$json"

if [ "${DRY_RUN}" = "1" ]; then
  echo "(DRY-RUN) No se eliminarán notas."
  exit 0
fi

deleted=0; kept=0; errors=0
for id in $(printf "%s" "$json" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | uniq); do
  reps="$(printf "%s" "$json" | sed -n "s/.*\"id\":${id}[^}]*\"reports\":\([0-9][0-9]*\).*/\1/p" | head -n1)"
  reps="${reps:-0}"
  if [ "$reps" -ge "$THRESHOLD" ]; then
    if delete_note "$id"; then
      echo "✔ eliminado id=$id (reports=$reps)"
      deleted=$((deleted+1))
    else
      echo "… no hay endpoint de borrado para id=$id (reports=$reps)"
      kept=$((kept+1))
    fi
  fi
done

echo "──────── resumen"
echo "Eliminados: $deleted"
echo "Quedaron (sin endpoint o error): $kept"
echo "Errores: $errors"
