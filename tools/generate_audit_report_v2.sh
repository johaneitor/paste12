#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
OUT="audit-$(date -u +%Y%m%d-%H%M%SZ).txt"

needs(){ command -v "$1" >/dev/null 2>&1 || { echo "falta $1" >&2; exit 2; }; }
needs curl
needs jq
needs awk
needs sed

# helper para volcar headers+cuerpo sin cortar
dump_req(){
  local label="$1"; shift
  echo "== $label ==" >> "$OUT"
  tmp="$(mktemp)"
  # guardamos todo en archivo temporal para evitar cortar stdout de curl
  curl -sS -i "$@" > "$tmp" || true
  # mostramos primeras 200 líneas de forma segura
  sed -n '1,200p' "$tmp" >> "$OUT"
  echo >> "$OUT"
  rm -f "$tmp"
}

{
  echo "== HEALTH & DEPLOY =="
  curl -sI "$BASE/api/health" | sed -n '1p'
  curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null || echo "(deploy-stamp no expuesto)"
  echo

  echo "== TTL CAP (headers de /) =="
  curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|X-Max-TTL-Hours:|cache-control:)/{print}'
  echo

  # NOTES create (JSON y form)
  dump_req "NOTES create (JSON)" -H 'Content-Type: application/json' \
    --data-binary @- "$BASE/api/notes" <<EOF
{"text":"audit note $(date -u +%Y-%m-%dT%H:%M:%SZ) – json cuerpo largo para validar (>= 80 chars) 1234567890 abcdefghij"}
EOF

  dump_req "NOTES create (form-urlencoded)" -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "text=audit note $(date -u +%Y-%m-%dT%H:%M:%SZ) – form cuerpo largo para validar (>= 80 chars)" \
    "$BASE/api/notes"

  # PAGINACIÓN (sólo headers)
  echo "== PAGINATION headers =="
  curl -sI "$BASE/api/notes?limit=5" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|link:|x-next-cursor:)/{print}'
  echo

  # AUTH (si está montado)
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/register")
  if [ "$code" != "404" ]; then
    echo "== AUTH smoke (resumen) =="
    tools/smoke_auth_min_v2.sh "$BASE" || true
    echo
  else
    echo "== AUTH no montado (register → 404) =="
    echo
  fi
} > "$OUT"

echo "Escrito: $OUT"
echo "Para copiar a Descargas (Termux):"
echo "  cp \"$OUT\" ~/storage/downloads/"
