#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-http://localhost:5000}"

echo "== FRONTEND TEST (AdSense + estructura) =="
# 1) index 200 y tamaño mínimo
H="$(mktemp)"; B="$(mktemp)"
curl -fsS -D "$H" -o "$B" "$BASE/" >/dev/null
SZ=$(wc -c < "$B" | tr -d ' ')
echo "HTTP HEADERS:"
sed -n '1,20p' "$H"
echo "bytes=$SZ"
if [ "$SZ" -lt 200 ]; then
  echo "FAIL - index muy chico (<200 bytes)"; exit 1
fi
echo "OK  - index bytes > 200"

# 2) presencia del shim seguro (tolerado si no)
if grep -q 'name="p12-safe-shim"' "$B"; then
  echo "OK  - p12-safe-shim"
else
  echo "INFO- p12-safe-shim no encontrado (tolerado)"
fi

# 3) AdSense presente
if grep -q 'googlesyndication.com/pagead/js/adsbygoogle.js' "$B"; then
  echo "OK  - AdSense script presente"
else
  echo "FAIL- AdSense no encontrado"; exit 1
fi

# 4) UI básica: botón publicar y lista
grep -q 'id="send"' "$B" && echo "OK  - botón publicar" || { echo "FAIL- botón publicar"; exit 1; }
grep -q 'id="list"' "$B" && echo "OK  - contenedor lista" || { echo "FAIL- contenedor lista"; exit 1; }

# 5) Paginación: fetch inicial al feed (tolerado si cambia)
if grep -q "fetchPage('/api/notes?limit=10')" "$B"; then
  echo "OK  - gancho paginación encontrado"
else
  echo "INFO- no vi el gancho de paginación (tolerado)"
fi

rm -f "$H" "$B"
echo "✔ FRONTEND OK"
