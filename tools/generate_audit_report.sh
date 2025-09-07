#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
OUT="audit-$(date -u +%Y%m%d-%H%M%SZ).txt"

{
  echo "== HEALTH & DEPLOY =="
  curl -sI "$BASE/api/health" | sed -n '1p'
  curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null || echo "(deploy-stamp no expuesto)"
  echo

  echo "== TTL CAP (header) =="
  curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(X-Max-TTL-Hours:|cache-control:)/{print}'
  echo

  echo "== NOTES create (JSON y form) =="
  jq -n --arg t "audit note $(date -u +%H:%M:%SZ) – json" '{text:$t}' \
  | curl -sS -i -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" | sed -n '1,8p'
  echo
  curl -sS -i -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "text=audit note $(date -u +%H:%M:%SZ) – form" "$BASE/api/notes" | sed -n '1,8p'
  echo

  echo "== PAGINATION (primera página, headers) =="
  curl -sI "$BASE/api/notes?limit=5" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|link:|x-next-cursor:)/{print}'
  echo

  if [ -x tools/smoke_likes_race_v2.sh ]; then
    echo "== LIKES smoke (resumen) =="
    tools/smoke_likes_race_v2.sh "$BASE" || true
    echo
  fi

  if [ -x tools/smoke_auth_min.sh ]; then
    echo "== AUTH smoke (resumen) =="
    tools/smoke_auth_min.sh "$BASE" || true
    echo
  fi
} > "$OUT"

echo "Escrito: $OUT"
echo "Sugerencia (Termux): termux-share -a send -c text/plain $OUT  # o cp a ~/downloads/"
