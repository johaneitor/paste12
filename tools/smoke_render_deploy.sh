#!/usr/bin/env bash
set -euo pipefail

APP="${APP:-https://paste12-rmsk.onrender.com}"

# Archivos temporales seguros
TMP1="$(mktemp)"; TMP2="$(mktemp)"
trap 'rm -f "$TMP1" "$TMP2"' EXIT

echo "=== [1] Smoke local de sintaxis (evita deploys rotos) ==="
fail=0

if [ -f render_entry.py ]; then
  echo -n " - py_compile render_entry.py … "
  if python -m py_compile render_entry.py 2>"$TMP1"; then
    echo "OK"
  else
    echo "✗"
    cat "$TMP1"
    fail=1
  fi
else
  echo " - (skip) render_entry.py no existe"
fi

if [ -f backend/modules/interactions.py ]; then
  echo -n " - py_compile backend/modules/interactions.py … "
  if python -m py_compile backend/modules/interactions.py 2>"$TMP2"; then
    echo "OK"
  else
    echo "✗"
    cat "$TMP2"
    fail=1
  fi
else
  echo " - (skip) backend/modules/interactions.py no existe"
fi

if [ $fail -ne 0 ]; then
  echo
  echo "✗ Hay errores de indentación/sintaxis. Corrige antes de redeploy."
  echo "  Pista: revisa líneas duplicadas o 'try:' sin bloque indentado."
  exit 2
fi

echo
echo "=== [2] Probes remotos (Render) ==="
echo "[import] /api/diag/import"
IMP_JSON="$(curl -sS "$APP/api/diag/import" || true)"
echo "$IMP_JSON" | jq . || echo "$IMP_JSON"

import_path="$(echo "$IMP_JSON" | jq -r '.import_path // empty' 2>/dev/null || true)"
import_error="$(echo "$IMP_JSON" | jq -r '.import_error // empty' 2>/dev/null || true)"
fallback="$(echo "$IMP_JSON" | jq -r '.fallback // false' 2>/dev/null || echo false)"

echo
echo "[map] /api/debug-urlmap (filtrado /api/(notes|ix)/)"
curl -sS "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))'

echo
echo "[diag] /api/notes/diag"
curl -sS "$APP/api/notes/diag" | jq . || true

echo
echo "=== [3] Diagnóstico rápido ==="
ok=1

if [ -n "$import_error" ] && [ "$import_error" != "null" ]; then
  echo "✗ import_error detectado en servidor:"
  echo "  $import_error"
  ok=0
fi

if [ "$fallback" = "true" ]; then
  echo "✗ Estás en fallback. Ajusta el Start Command de Render:"
  echo "   gunicorn render_entry:app -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --bind 0.0.0.0:\$PORT"
  ok=0
fi

if [ "$import_path" != "render_entry:app" ]; then
  echo "✗ import_path = '$import_path' (ideal: 'render_entry:app')"
  ok=0
fi

echo
echo "=== [4] Probar interacciones si el mapa tiene /api/ix/* ==="
has_ix="$(curl -sS "$APP/api/debug-urlmap" | jq '[.rules[] | select(.rule|test("^/api/ix/"))] | length' 2>/dev/null || echo 0)"
echo " - Reglas /api/ix/*: $has_ix"

if [ "$has_ix" != "0" ]; then
  ID="$(curl -sS "$APP/api/notes?page=1" | jq -r '.[0].id // empty' || true)"
  if [ -z "${ID:-}" ]; then
    ID="$(curl -sS -X POST -H 'Content-Type: application/json' -d '{"text":"probe","hours":24}' "$APP/api/notes" | jq -r '.id' || true)"
  fi
  echo " - Probando con ID=${ID:-<none>}"

  if [ -n "${ID:-}" ]; then
    echo "[like]";  curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'
    echo "[view]";  curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'
    echo "[stats]"; curl -si      "$APP/api/ix/notes/$ID/stats"   | sed -n '1,160p'
  else
    echo " (no hay ID válido para test)"
  fi
else
  echo " (No hay /api/ix/* — alias/blueprint sin registrar)"
  ok=0
fi

echo
if [ $ok -eq 1 ]; then
  echo "✔ Smoke OK."
else
  echo "✗ Smoke con hallazgos. Acciones típicas:"
  echo "  1) Corrige indentación en render_entry.py (usa tools/show_lines.sh para ver tramos)."
  echo "  2) En Render: Start Command = 'gunicorn render_entry:app -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --bind 0.0.0.0:\$PORT'"
  echo "  3) Asegura que interactions se registre y que exista 'interaction_event' (/api/notes/repair-interactions)."
  exit 3
fi
