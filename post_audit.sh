#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
API="http://127.0.0.1:8000"

echo "🔎 Endpoints sensibles"
for p in like report; do
  echo " - POST /api/notes/1/$p"
  curl -s -o /dev/null -w "   HTTP %{http_code}\n" -X POST "$API/api/notes/1/$p" || true
done

echo
echo "🔎 Cabeceras de seguridad"
curl -sI "$API/" | awk 'BEGIN{IGNORECASE=1}/^(x-content-type-options|x-frame-options|referrer-policy|permissions-policy|strict-transport-security):/{print}'

echo
echo "🔎 Preflight CORS"
curl -s -o /dev/null -w "   HTTP %{http_code}\n" -X OPTIONS \
  -H "Origin: https://tu-dominio.com" \
  -H "Access-Control-Request-Method: POST" \
  "$API/api/notes/1/report"
