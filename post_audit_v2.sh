#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
API="http://127.0.0.1:8000"

echo "🔎 Endpoints sensibles"
echo " - POST /api/notes/1/like"
curl -s -o /dev/null -w "   HTTP %{http_code}\n" -X POST "$API/api/notes/1/like" || true

echo " - POST /api/reports (content_id=1)"
curl -s -o /dev/null -w "   HTTP %{http_code}\n" -X POST "$API/api/reports" \
  -H "Content-Type: application/json" \
  -d '{"content_id":"1"}' || true

echo
echo "🔎 Cabeceras de seguridad"
curl -sI "$API/" | awk 'BEGIN{IGNORECASE=1}/^(x-content-type-options|x-frame-options|referrer-policy|permissions-policy|strict-transport-security):/{print}'

echo
echo "🔎 Preflight CORS (OPTIONS /api/reports)"
curl -s -o /dev/null -w "   HTTP %{http_code}\n" -X OPTIONS \
  -H "Origin: https://tu-dominio.com" \
  -H "Access-Control-Request-Method: POST" \
  "$API/api/reports" || true
