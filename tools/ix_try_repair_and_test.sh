#!/usr/bin/env bash
set -euo pipefail
APP="${APP:-https://paste12-rmsk.onrender.com}"

say(){ printf "\n[+] %s\n" "$*"; }

say "1) Import path y URL map filtrado"
curl -s "$APP/api/diag/import" | jq .
curl -s "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(ix|notes)/")))'

say "2) Reparar tabla interaction_event (drop&create si FK incorrecta)"
curl -si -X POST "$APP/api/notes/repair-interactions" | sed -n '1,120p'

say "3) Re-chequear URL map (deben aparecer /api/ix/notes/<id>/(like|view|stats))"
curl -s "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(ix|notes)/")))'

say "4) Diag de notas (no debe dar 500)"
curl -s "$APP/api/notes/diag" | jq .

say "5) Buscar ID válido"
ID="$(curl -s "$APP/api/notes?page=1" | jq -r '.[0].id // empty')"
if [ -z "$ID" ]; then
  echo "    - No hay notas; creando una seed…"
  ID="$(curl -s -X POST -H 'Content-Type: application/json' \
        -d '{"text":"seed-interactions","hours":24}' "$APP/api/notes" | jq -r '.id')"
fi
echo "    - Usando ID=$ID"

say "6) LIKE (idempotente)"
curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'

say "7) VIEW (ventana 15m por fingerprint)"
curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'

say "8) STATS"
curl -si      "$APP/api/ix/notes/$ID/stats"   | sed -n '1,160p'

echo
echo "[i] Si aún ves 404 en /api/ix/*, el alias no está cargado en este proceso:"
echo "    - Revisa el URL map: falta cualquier regla que empiece con /api/ix/…"
echo "    - Asegúrate que render_entry registra el alias: register_alias_into(app)"
echo "    - Y que el Start Command apunta a render_entry:app o wsgiapp:app que lo importe."
