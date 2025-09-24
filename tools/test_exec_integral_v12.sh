#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
[ -n "$BASE" ] || { echo "Uso: $0 https://tu-app.onrender.com"; exit 1; }

echo "== Smoke backend =="
# Health JSON
hb="$(curl -fsS "$BASE/api/health" || true)"
echo "$hb" | grep -q '{"ok":true}' && echo "OK  - health body JSON" || { echo "FAIL- health"; exit 2; }

# OPTIONS CORS
hopt="$(curl -fsSI -X OPTIONS "$BASE/api/notes")"
echo "$hopt" | grep -qi '^HTTP/.* 204' && echo "OK  - OPTIONS 204" || echo "WARN- OPTIONS"
echo "$hopt" | grep -qi '^Access-Control-Allow-Origin:' && echo "OK  - ACAO" || echo "WARN- ACAO"
echo "$hopt" | grep -qi '^Access-Control-Allow-Methods:' && echo "OK  - ACAM" || echo "WARN- ACAM"
echo "$hopt" | grep -qi '^Access-Control-Allow-Headers:' && echo "OK  - ACAH" || echo "WARN- ACAH"

# GET /api/notes (Link)
hget="$(curl -fsSI "$BASE/api/notes?limit=5")"
echo "$hget" | grep -qi '^content-type: application/json' && echo "OK  - CT json" || echo "FAIL- CT"
echo "$hget" | grep -qi '^link:.*rel=next' && echo "OK  - Link: next" || echo "WARN- Link ausente"

# POST JSON + FORM (aceptar texto)
pj="$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"test v12 123456"}' "$BASE/api/notes")"
echo "$pj" | grep -q '"id":' && echo "OK  - publish JSON" || echo "FAIL- publish JSON"
pf="$(curl -fsS -d 'text=form v12 123' "$BASE/api/notes" || true)"
echo "$pf" | grep -q '"id":' && echo "OK  - publish FORM" || echo "WARN- publish FORM"

echo "== Frontend =="
idx="$(curl -fsS "$BASE/" || true)"
echo "$idx" | grep -q '<span class="views"' && echo "OK  - index incluye <span class=\"views\">" || echo "FAIL- falta span.views (frontend)"

echo "== Hecho =="
