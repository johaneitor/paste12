#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://127.0.0.1:8000}"
HTML="$(curl -fsS "$BASE/")"
cnt="$(printf "%s" "$HTML" | grep -oi 'id="tagline"' | wc -l | awk '{print $1}')"
echo "taglines encontrados: $cnt"
if [ "$cnt" = "1" ]; then echo "✓ único"; else echo "✗ duplicados"; fi
echo "$HTML" | grep -q 'id="tagline-rotator-js"' && echo "✓ rotador JS" || echo "✗ sin rotador JS"
echo "$HTML" | grep -q 'id="tagline-style"' && echo "✓ estilo inyectado" || echo "✗ sin estilo"
# muestra frases detectadas
printf "frases: "
echo "$HTML" | sed -n '1,1000p' | grep -o 'data-phrases="[^"]*"' | head -n1 | sed 's/data-phrases="//;s/"$//'
