#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
OUT="audit-$(date -u +%Y%m%d-%H%M%SZ).txt"

dump(){
  local title="$1"; shift
  echo "== $title ==" >> "$OUT"
  tmp="$(mktemp)"
  curl -sS -i "$@" > "$tmp" || true
  sed -n '1,240p' "$tmp" >> "$OUT"
  echo >> "$OUT"
  rm -f "$tmp"
}

{
  echo "# AUDIT @ $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo

  echo "## HEALTH & DEPLOY"
  curl -sI "$BASE/api/health" | sed -n '1,8p'
  curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null || echo "(deploy-stamp no expuesto)"
  echo

  echo "## ROOT HEADERS"
  curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(wsgi-bridge|index-source):|X-Max-TTL-Hours:)/{print}'
  echo

} > "$OUT"

dump "NOTES create (JSON)" -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" <<EOF
{"text":"audit note $(date -u +%Y-%m-%dT%H:%M:%SZ) – json largo >= 80 chars 1234567890 abcdefghij"}
EOF

dump "NOTES create (form-urlencoded)" -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=audit note $(date -u +%Y-%m-%dT%H:%M:%SZ) – form largo >= 80 chars" \
  "$BASE/api/notes"

{
  echo "## PAGINATION headers"
  curl -sI "$BASE/api/notes?limit=5" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|link:|x-next-cursor:)/{print}'
  echo
} >> "$OUT"

# Likes rápido (best-effort)
nid="$(jq -n --arg t "audit likes $(date -u +%H:%M:%SZ) — texto largo para validar" '{text:$t}' \
  | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" \
  | jq -r '.item.id' 2>/dev/null || echo "")"
if [ -n "$nid" ]; then
  a="$(curl -fsS -X POST "$BASE/api/notes/$nid/like" | jq -r '.likes,.deduped' | paste -sd' ' 2>/dev/null || true)"
  b="$(curl -fsS -X POST "$BASE/api/notes/$nid/like" | jq -r '.likes,.deduped' | paste -sd' ' 2>/dev/null || true)"
  {
    echo "## LIKES quick"
    echo "note: $nid"
    echo "same-FP => $a -> $b"
  } >> "$OUT"
  echo >> "$OUT"
fi

# Auth (si está)
code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/register")
if [ "$code" != "404" ]; then
  {
    echo "## AUTH smoke (resumen)"
    tools/smoke_auth_min_v2.sh "$BASE" || true
  } >> "$OUT" 2>&1
  echo >> "$OUT"
else
  {
    echo "## AUTH no montado (register → 404)"
    echo
  } >> "$OUT"
fi

echo "Escrito: $OUT"
echo "Para copiar a Descargas (Termux):  cp \"$OUT\" ~/storage/downloads/"
