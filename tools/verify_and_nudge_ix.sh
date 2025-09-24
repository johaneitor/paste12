#!/usr/bin/env bash
set -euo pipefail
APP="${RENDER_URL:-https://paste12-rmsk.onrender.com}"
SLEEP_SECS="${SLEEP_SECS:-18}"

say(){ printf "\n[+] %s\n" "$*"; }
warn(){ printf "\n[!] %s\n" "$*"; }

say "Esperando ${SLEEP_SECS}s a que Render termine el redeploy…"
sleep "$SLEEP_SECS"

say "Health/entry"
curl -sS "$APP/api/health-stamp" || true
echo

say "Import path"
curl -sS "$APP/api/diag/import" || true
echo

say "URL map (solo /api/notes y /api/ix)"
curl -sS "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))'

say "Diag de eventos"
curl -sS "$APP/api/notes/diag" || true
echo

say "Elegir un note_id válido"
ID="$(curl -sS "$APP/api/notes?page=1" | jq -r '.[0].id // empty')"
if [ -z "${ID}" ] || [ "${ID}" = "null" ]; then
  warn "No hay notas → creando una semilla…"
  ID="$(curl -sS -X POST -H 'Content-Type: application/json' \
        -d '{"text":"seed-interactions","hours":24}' \
        "$APP/api/notes" | jq -r '.id')"
fi
echo "ID=${ID}"

say "POST /api/ix/notes/\$ID/like"
curl -si -X POST "$APP/api/ix/notes/${ID}/like" | sed -n '1,120p'

say "POST /api/ix/notes/\$ID/view"
curl -si -X POST "$APP/api/ix/notes/${ID}/view" | sed -n '1,120p'

say "GET  /api/ix/notes/\$ID/stats"
curl -si "$APP/api/ix/notes/${ID}/stats" | sed -n '1,160p'

echo
say "Sugerencias si falla:"
cat <<'HINTS'
- 404 en /api/ix/* → el blueprint de alias no está registrado:
  * Revisá /api/debug-urlmap: deben verse /api/ix/notes/<id>/(like|view|stats).
  * Si no aparecen, asegurate que el Start Command usa render_entry:app **o**
    que wsgiapp:app está importando render_entry correctamente (/api/diag/import).

- 500 en /api/ix/* → casi siempre es DB/esquema:
  * Revisá /api/notes/diag: should show "has_interaction_event = true".
  * Si es false, vuelve a aplicar el patch de schema del módulo
    (o asegura que `ensure_schema()` se ejecuta en el arranque de render_entry).

- GET /api/notes OK pero /api/ix 404/500:
  * El módulo interactions puede estar cargado pero sin alias.
    Reaplicá el script de “force_alias_only_in_render_entry” y redeploy.
HINTS
