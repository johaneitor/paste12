#!/usr/bin/env bash
set -u -o pipefail

BASE="${1:-}"
[ -n "$BASE" ] || { echo "Uso: $0 https://host"; exit 2; }

TMPDIR="${TMPDIR:-$HOME/tmp}"; mkdir -p "$TMPDIR"
HDR="$TMPDIR/smoke_hdr.$$"
BODY="$TMPDIR/smoke_body.$$"

echo "== TARGET =="
echo "BASE: $BASE"
echo "DATE: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "---------------------------------------------"

echo "== CONNECT / HEADERS =="
curl -sS -I "$BASE/" | tee "$HDR" || true
META="$(curl -sS "$BASE/" -o /dev/null -w 'ip=%{remote_ip} http=%{http_version} code=%{http_code} dns=%{time_namelookup}s conn=%{time_connect}s tls=%{time_appconnect}s ttfb=%{time_starttransfer}s total=%{time_total}s\n')"
echo "$META"
echo "---------------------------------------------"

echo "== /api/health =="
CODE=0
curl -fsS "$BASE/api/health" -D "$TMPDIR/health.h" -o "$BODY" || CODE=$?
if [ "$CODE" -eq 0 ]; then
  echo "HTTP: $(sed -n '1p' "$TMPDIR/health.h")"
  if command -v jq >/dev/null 2>&1; then jq . < "$BODY" || (echo "(raw)"; sed -n '1,40p' "$BODY"); else sed -n '1,60p' "$BODY"; fi
else
  echo "✗ fallo curl ($CODE). Respuesta/preview:"; sed -n '1,60p' "$BODY" 2>/dev/null || true
fi
echo "---------------------------------------------"

echo "== CORS preflight /api/notes (OPTIONS) =="
curl -sS -i -X OPTIONS "$BASE/api/notes" \
  -H 'Origin: https://example.com' \
  -H 'Access-Control-Request-Method: POST' | sed -n '1,60p'
echo "---------------------------------------------"

echo "== CREATE note (JSON) y like (best-effort) =="
NOTE_ID="$(
  printf '{"text":"smoke %s 1234567890 abcdefghij"}' "$(date -u +%H:%M:%SZ)" |
  curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" |
  { if command -v jq >/dev/null 2>&1; then jq -r '.item.id // .id // empty'; else cat; fi; }
)"
if [ -n "$NOTE_ID" ]; then
  echo "✓ note id: $NOTE_ID"
  echo "like:"
  RESP="$(curl -sS -X POST "$BASE/api/notes/$NOTE_ID/like")"
  if command -v jq >/dev/null 2>&1; then echo "$RESP" | jq . || echo "$RESP"; else echo "$RESP"; fi
else
  echo "✗ no se pudo crear nota (posible fallo de backend o schema)"
fi
echo "---------------------------------------------"

echo "== /api/notes?limit=3 (paginación básica) =="
curl -sS -i "$BASE/api/notes?limit=3" | sed -n '1,80p' || true
echo "---------------------------------------------"

echo "HINTS:"
echo "- 502/503 ⇢ despliegue/runner caído o warmup fallido"
echo "- 500     ⇢ error app; mira logs del proveedor"
echo "- 404 en / o /api/health ⇢ ruta/bridge no montado"
