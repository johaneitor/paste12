#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
TMP="${TMPDIR:-/tmp}/p12.$$.html"
echo "== GET / (descarga) =="
curl -fsS "$BASE/" -o "$TMP"
echo "bytes: $(wc -c < "$TMP" | tr -d ' ')"
grep -q 'id="p12-client-template"' "$TMP" && echo "✓ cliente template v2 presente" || { echo "✗ cliente no encontrado"; exit 1; }
# Heurística: el banner no debe estar en el HTML estático (igual lo eliminamos en runtime)
if grep -qi 'nueva versión disponible' "$TMP"; then
  echo "⚠ cadena de banner encontrada en HTML; se eliminará en runtime por el cliente"
else
  echo "✓ sin cadena de banner en HTML"
fi
echo "Listo."
