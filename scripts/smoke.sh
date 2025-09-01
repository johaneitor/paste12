set -euo pipefail
: "${APP_URL:?Define APP_URL, ej: http://127.0.0.1:8000}"
for path in / /api/health /api/notes; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$APP_URL$path" || echo "000")
  printf "%-20s %s\n" "$path" "$code"
done
