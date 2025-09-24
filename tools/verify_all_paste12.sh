#!/usr/bin/env bash
set -euo pipefail

# Config
APP="${RENDER_URL:-${1:-https://paste12-rmsk.onrender.com}}"
SLEEP_SECS="${SLEEP_SECS:-0}"

h()  { printf "\n\033[1m[+] %s\033[0m\n" "$*"; }
ok() { printf "    \033[32m✓ %s\033[0m\n" "$*"; }
ko() { printf "    \033[31m✗ %s\033[0m\n" "$*"; }
inf(){ printf "    • %s\n" "$*"; }

if [ "$SLEEP_SECS" -gt 0 ]; then
  h "Esperando ${SLEEP_SECS}s para permitir el redeploy"
  sleep "$SLEEP_SECS"
fi

fail=0

# 1) Import path
h "1) Import path (/api/diag/import)"
IMP_RAW="$(curl -sS "$APP/api/diag/import" || true)"
if jq -e . >/dev/null 2>&1 <<<"$IMP_RAW"; then
  echo "$IMP_RAW" | jq .
  IMP_PATH="$(jq -r '.import_path // empty' <<<"$IMP_RAW")"
  IMP_FALLBACK="$(jq -r '.fallback // false' <<<"$IMP_RAW")"
  if [[ "$IMP_PATH" == "render_entry:app" && "$IMP_FALLBACK" == "false" ]]; then
    ok "Entrypoint correcto (render_entry:app)"
  else
    ko "Entrypoint no ideal (import_path='$IMP_PATH', fallback=$IMP_FALLBACK)"
    inf "Si ves errores de indentación/modulo en 'import_error', debes corregir render_entry.py."
    fail=1
  fi
else
  ko "No JSON/404 en /api/diag/import"
  fail=1
fi

# 2) URL map: deben aparecer /api/notes/<id>/(like|view|stats) o alias /api/ix/...
h "2) URL map filtrado (/api/debug-urlmap)"
MAP_RAW="$(curl -sS "$APP/api/debug-urlmap" || true)"
if jq -e . >/dev/null 2>&1 <<<"$MAP_RAW"; then
  RULES="$(jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))' <<<"$MAP_RAW")"
  echo "$RULES" | jq .
  HAVE_LIKE="$(jq -r 'map(.rule)|join("\n")|test("/api/(notes|ix)/<int:note_id>/like")' <<<"$RULES" || echo false)"
  HAVE_VIEW="$(jq -r 'map(.rule)|join("\n")|test("/api/(notes|ix)/<int:note_id>/view")' <<<"$RULES" || echo false)"
  HAVE_STATS="$(jq -r 'map(.rule)|join("\n")|test("/api/(notes|ix)/<int:note_id>/stats")' <<<"$RULES" || echo false)"
  if [[ "$HAVE_LIKE" == "true" || "$HAVE_VIEW" == "true" || "$HAVE_STATS" == "true" ]]; then
    ok "Rutas de interacciones visibles en el urlmap"
  else
    ko "No aparecen rutas /api/notes|ix … (like/view/stats)."
    inf "Asegúrate de registrar los blueprints del módulo interactions en render_entry/wsgiapp."
    fail=1
  fi
else
  ko "No JSON/404 en /api/debug-urlmap"
  fail=1
fi

# 3) Diagnóstico del esquema de interacciones
h "3) Diagnóstico de interacciones (/api/notes/diag)"
DIAG_RAW="$(curl -sS "$APP/api/notes/diag" || true)"
if jq -e . >/dev/null 2>&1 <<<"$DIAG_RAW"; then
  echo "$DIAG_RAW" | jq .
  DIAG_OK="$(jq -r '.ok // false' <<<"$DIAG_RAW")"
  if [[ "$DIAG_OK" == "true" ]]; then
    HAS_EVT="$(jq -r '.has_interaction_event // false' <<<"$DIAG_RAW")"
    if [[ "$HAS_EVT" == "true" ]]; then
      ok "Tabla 'interaction_event' existe"
    else
      ko "No existe la tabla 'interaction_event'"
      NEED_REPAIR=1
    fi
  else
    ko "Diag devolvió error (ok=false)"
    NEED_REPAIR=1
  fi
else
  ko "No JSON/404 en /api/notes/diag"
  NEED_REPAIR=1
fi

# 4) Reparación idempotente
if [[ "${NEED_REPAIR:-0}" -eq 1 ]]; then
  h "4) Reparación de esquema (/api/notes/repair-interactions)"
  curl -si -X POST "$APP/api/notes/repair-interactions" | sed -n '1,120p'
  # Re-chequear
  DIAG_RAW="$(curl -sS "$APP/api/notes/diag" || true)"
  if jq -e . >/dev/null 2>&1 <<<"$DIAG_RAW"; then
    HAS_EVT="$(jq -r '.has_interaction_event // false' <<<"$DIAG_RAW")"
    if [[ "$HAS_EVT" == "true" ]]; then
      ok "Reparación OK: 'interaction_event' creada"
    else
      ko "Reparación no logró crear 'interaction_event'"
      inf "Revisa DATABASE_URL/driver (psycopg2-binary) y permisos."
      fail=1
    fi
  else
    ko "Diag tras reparación no responde JSON"
    fail=1
  fi
fi

# 5) Elegir/crear nota para pruebas
h "5) Buscar o crear una nota para test"
ID="$(curl -sS "$APP/api/notes?page=1" | jq -r '.[0].id // empty' || true)"
if [[ -z "${ID:-}" ]]; then
  inf "No hay notas; creando una de prueba…"
  CR="$(curl -sS -X POST -H 'Content-Type: application/json' \
        -d "{\"text\":\"probe-$(date +%s)\",\"hours\":24}" \
        "$APP/api/notes" || true)"
  if jq -e . >/dev/null 2>&1 <<<"$CR"; then
    ID="$(jq -r '.id // empty' <<<"$CR")"
  fi
fi
if [[ -n "${ID:-}" ]]; then
  ok "Usando note_id=$ID"
else
  ko "No pude obtener/crear una nota de prueba"
  fail=1
fi

# 6) Pruebas de endpoints /api/ix
if [[ -n "${ID:-}" ]]; then
  h "6) LIKE (idempotente) /api/ix/notes/$ID/like"
  curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'

  h "7) VIEW (ventana 15m) /api/ix/notes/$ID/view"
  curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'

  h "8) STATS /api/ix/notes/$ID/stats"
  curl -si      "$APP/api/ix/notes/$ID/stats"    | sed -n '1,160p'
fi

# 9) Resumen
h "9) Resumen"
if [[ "$fail" -eq 0 ]]; then
  ok "Todo OK. Interacciones deberían funcionar."
else
  ko "Quedaron pendientes (${fail})."
  inf "Pistas:"
  inf "- Si /api/diag/import no muestra render_entry:app → corrige render_entry.py (indentación/errores)."
  inf "- Si /api/notes/diag falla por Postgres → valida DATABASE_URL (postgresql://…) y psycopg2-binary."
  inf "- Si /api/ix/* 404 → alias no registrado; reasegura que el bootstrap de interactions se ejecute al inicio."
fi
