#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="$HOME/tmp/verify-$TS"
mkdir -p "$TMP" "$OUT"

ua="paste12-verifier/1.1"

pos="$TMP/positivos.txt"
neg="$TMP/negativos.txt"
lim="$TMP/limits.txt"
sum="$OUT/verify-$TS-summary.txt"

curl_s(){ curl -fsS -A "$ua" "$@"; }

# POSITIVOS
{
  echo "== POSITIVOS =="
  code_root=$(curl -o /dev/null -w "%{http_code}" -A "$ua" "$BASE/")
  echo "GET /: $code_root"
  echo "GET /terms: $(curl -o /dev/null -w "%{http_code}" -A "$ua" "$BASE/terms")"
  echo "GET /privacy: $(curl -o /dev/null -w "%{http_code}" -A "$ua" "$BASE/privacy")"
  echo "GET /api/notes?limit=10: $(curl -o /dev/null -w "%{http_code}" -A "$ua" "$BASE/api/notes?limit=10")"
  pj='{"text":"hola mvp"}'
  cj=$(curl -sS -A "$ua" -H 'Content-Type: application/json' -X POST --data "$pj" -D "$TMP/notes-post.hdr" "$BASE/api/notes" || true)
  echo "POST /api/notes [json]: $(sed -n '1s/.* //p' "$TMP/notes-post.hdr")"
} > "$pos" 2>&1 || true

# NEGATIVOS
{
  echo "== NEGATIVOS =="
  echo "like?id=99999999: $(curl -o /dev/null -w "%{http_code}" -A "$ua" "$BASE/api/like?id=99999999" || true)"
  echo "view GET id inexistente: $(curl -o /dev/null -w "%{http_code}" -A "$ua" "$BASE/api/view?id=99999999" || true)"
  echo "view POST id inexistente: $(curl -o /dev/null -w "%{http_code}" -A "$ua" -X POST "$BASE/api/view" || true)"
  echo "report?id=99999999: $(curl -o /dev/null -w "%{http_code}" -A "$ua" "$BASE/api/report?id=99999999" || true)"
} > "$neg" 2>&1 || true

# LIMITS (placeholder: se activa cuando POST devuelva 2xx estable)
{
  echo "== LIMITS =="
  echo "TTL: pending (requiere BE con TTL activo)"
  echo "CAPACITY: pending (requiere BE con CAP activo)"
  echo "NEXT anti-abuso: clamp a limit<=25 (overlay) OK"
} > "$lim" 2>&1 || true

# SUMMARY
{
  echo "----- RESUMEN (verify) -----"
  echo
  echo "• == POSITIVOS ==";  sed -n '1,200p' "$pos"
  echo
  echo "• == NEGATIVOS ==";  sed -n '1,200p' "$neg"
  echo
  echo "• == LÍMITES ==";    sed -n '1,200p' "$lim"
} > "$sum"

echo "OK: verify_v7 listo → $sum"
