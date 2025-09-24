#!/usr/bin/env bash
set -euo pipefail

RENDER_URL="${RENDER_URL:-https://paste12-rmsk.onrender.com}"

line(){ printf "\n%s\n" "$*"; }
hdr(){ printf "\n[+] %s\n" "$*"; }
ok(){  printf "    ✓ %s\n" "$*"; }
warn(){ printf "    [!] %s\n" "$*"; }

hdr "1) /api/health"
HEALTH_RAW="$(curl -sS "$RENDER_URL/api/health" || true)"
CT_HEALTH="$(curl -sSI "$RENDER_URL/api/health" | awk -F': ' 'BEGIN{IGNORECASE=1}/^Content-Type:/{print $2}' | tr -d '\r')"
echo "$HEALTH_RAW"
NOTE_VAL="$(printf '%s' "$HEALTH_RAW" | sed -n 's/.*"note"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)"

if echo "$CT_HEALTH" | grep -qi 'application/json' && echo "$HEALTH_RAW" | grep -q '"ok":'; then
  ok "health responde JSON (note='$NOTE_VAL')"
else
  warn "health no es JSON; Render podría estar sirviendo otra app."
fi

hdr "2) /api/bridge-ping y /api/debug-urlmap"
BRIDGE_RAW="$(curl -sS "$RENDER_URL/api/bridge-ping" || true)"
if command -v jq >/dev/null 2>&1 && jq -e . >/dev/null 2>&1 <<<"$BRIDGE_RAW"; then
  ok "bridge-ping OK"
  echo "$BRIDGE_RAW" | jq .
else
  warn "bridge-ping 404/HTML → el bridge de wsgiapp aún no está cargado (o no se re-deployó)."
fi

URLMAP_RAW="$(curl -sS "$RENDER_URL/api/debug-urlmap" || true)"
if command -v jq >/dev/null 2>&1 && jq -e . >/dev/null 2>&1 <<<"$URLMAP_RAW"; then
  ok "debug-urlmap OK (muestra reglas):"
  echo "$URLMAP_RAW" | jq '.rules'
else
  warn "debug-urlmap 404/HTML → sin bridge activo."
fi

hdr "3) Smoke /api/notes (GET)"
curl -i -sS "$RENDER_URL/api/notes?page=1" | sed -n '1,80p'

hdr "4) Smoke /api/notes (POST)"
curl -i -sS -X POST -H 'Content-Type: application/json' \
     -d '{"text":"remote-ok","hours":24}' \
     "$RENDER_URL/api/notes" | sed -n '1,120p'

hdr "5) Sugerencias automáticas"
if { [ -z "${BRIDGE_RAW:-}" ] || [[ "$BRIDGE_RAW" =~ \<!doctype ]]; } && { [ -z "${URLMAP_RAW:-}" ] || [[ "$URLMAP_RAW" =~ \<!doctype ]]; }; then
  warn "No veo endpoints del bridge. Revisa en Render > Service > Start Command:"
  echo "    gunicorn -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} -b 0.0.0.0:\$PORT wsgiapp:app"
  warn "Luego haz un redeploy *manual* (Clear build cache si es necesario)."
fi

if [ "${NOTE_VAL:-}" = "wsgiapp" ] && { [ -z "${BRIDGE_RAW:-}" ] || [[ "$BRIDGE_RAW" =~ \<!doctype ]]; }; then
  warn "La app parece llamarse 'wsgiapp' pero el bridge no se registró: verifica que exista 'wsgiapp/__init__.py' en la rama desplegada."
fi

echo
echo "[i] Puedes re-ejecutar con:"
echo "    RENDER_URL=$RENDER_URL bash tools/remote_diag_notes.sh"
