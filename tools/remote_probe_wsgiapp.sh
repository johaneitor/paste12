#!/usr/bin/env bash
set -euo pipefail
APP="${RENDER_URL:-https://paste12-rmsk.onrender.com}"

line(){ printf "\n%s\n" "$*"; }

line "[1] /api/diag/import"
curl -sS "$APP/api/diag/import" | jq . || { echo "(no JSON o 404)"; curl -si "$APP/api/diag/import" | sed -n '1,80p'; }

line "[2] /api/diag/urlmap"
curl -sS "$APP/api/diag/urlmap"  | jq . || { echo "(no JSON o 404)"; curl -si "$APP/api/diag/urlmap" | sed -n '1,120p'; }

line "[3] /api/health-stamp"
curl -sS "$APP/api/health-stamp" | jq .

line "[4] Probar /api/notes (GET, si existe)"
curl -si "$APP/api/notes?page=1" | sed -n '1,80p'

line "[5] Probar /api/ix alias (seguro, si existen rutas de interactions)"
echo "- POST like  /api/ix/notes/1/like"
curl -si -X POST "$APP/api/ix/notes/1/like" | sed -n '1,80p'
echo "- POST view  /api/ix/notes/1/view"
curl -si -X POST "$APP/api/ix/notes/1/view" | sed -n '1,80p'
echo "- GET  stats /api/ix/notes/1/stats"
curl -si      "$APP/api/ix/notes/1/stats" | sed -n '1,120p'
