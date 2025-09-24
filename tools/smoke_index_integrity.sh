#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="${TMPDIR:-/tmp}/idx.$$"
mkdir -p "$TMP"

echo "== FETCH index =="
curl -fsS "$BASE/?_=$TS&nosw=1" -o "$TMP/index.html"
BYTES=$(wc -c < "$TMP/index.html" | tr -d ' ')
echo "bytes: $BYTES"

# 1) No debe haber cosas DESPUÉS de </html>
COUNT_HTML=$(grep -in "</html>" "$TMP/index.html" | wc -l | tr -d ' ')
TAIL_LAST=$(tail -n +$(( $(grep -in "</html>" "$TMP/index.html" | tail -n1 | cut -d: -f1) )) "$TMP/index.html" | wc -l)
if [ "$COUNT_HTML" -ge 1 ] && [ "$TAIL_LAST" -le 1 ]; then
  echo "✓ cierre </html> al final"
else
  echo "✗ contenido después de </html>"
  exit 1
fi

# 2) No debe aparecer el IIFE suelto (texto visible)
if grep -q "^\s*(()=>" "$TMP/index.html"; then
  echo "✗ IIFE visible en HTML (JS impreso)"
  exit 1
else
  echo "✓ sin IIFE visible"
fi

# 3) IDs duplicados que indican doble inyección
for id in p12-hotfix-v4 tagline-rot; do
  N=$(grep -o "id=\"$id\"" "$TMP/index.html" | wc -l | tr -d ' ')
  if [ "$N" -le 1 ]; then
    echo "✓ $id único ($N)"
  else
    echo "✗ $id duplicado ($N)"; exit 1
  fi
done

# 4) Haya botón “Cargar más” (controlado por hotfix)
grep -q "Cargar más" "$TMP/index.html" && echo "✓ 'Cargar más' presente" || echo "⚠ 'Cargar más' no detectado (la UI puede crearlo en runtime)"

echo "OK."
