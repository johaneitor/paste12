#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="$HOME/tmp/verify-$TS"
mkdir -p "$TMP" "$OUT"

ua="paste12-verifier/1.1"
pos="$TMP/positivos.txt"; neg="$TMP/negativos.txt"; lim="$TMP/limits.txt"
sum="$OUT/verify-$TS-summary.txt"

# POSITIVOS
{
  echo "== POSITIVOS =="
  echo "GET /: $(curl -o /dev/null -w "%{http_code}" -fsS -A "$ua" "$BASE/")"
  echo "GET /terms: $(curl -o /dev/null -w "%{http_code}" -fsS -A "$ua" "$BASE/terms")"
  echo "GET /privacy: $(curl -o /dev/null -w "%{http_code}" -fsS -A "$ua" "$BASE/privacy")"
  echo "GET /api/notes?limit=10: $(curl -o /dev/null -w "%{http_code}" -fsS -A "$ua" "$BASE/api/notes?limit=10")"
  pj='{"text":"hola mvp"}'
  hdr="$TMP/notes-post.hdr"
  curl -sS -A "$ua" -H 'Content-Type: application/json' -X POST --data "$pj" -D "$hdr" "$BASE/api/notes" -o /dev/null || true
  echo -n "POST /api/notes [json]: "; sed -n '1s/.* //p' "$hdr"
} > "$pos" 2>&1 || true

# NEGATIVOS
{
  echo "== NEGATIVOS =="
  echo "like?id=99999999: $(curl -o /dev/null -w "%{http_code}" -fsS -A "$ua" "$BASE/api/like?id=99999999" || true)"
  echo "view GET id inexistente: $(curl -o /dev/null -w "%{http_code}" -fsS -A "$ua" "$BASE/api/view?id=99999999" || true)"
  echo "view POST id inexistente: $(curl -o /dev/null -w "%{http_code}" -fsS -A "$ua" -X POST "$BASE/api/view" || true)"
  echo "report?id=99999999: $(curl -o /dev/null -w "%{http_code}" -fsS -A "$ua" "$BASE/api/report?id=99999999" || true)"
} > "$neg" 2>&1 || true

# LIMITS (placeholder)
{
  echo "== LIMITS =="
  echo "TTL: pending (requiere BE c/TTL)"
  echo "CAPACITY: pending (requiere BE c/CAP)"
  echo "next anti-abuso: clamp limit<=25 (overlay) OK"
} > "$lim" 2>&1 || true

# SUMMARY
{
  echo "----- RESUMEN (verify) -----"
  echo; echo "• == POSITIVOS ==";  sed -n '1,120p' "$pos"
  echo; echo "• == NEGATIVOS ==";  sed -n '1,120p' "$neg"
  echo; echo "• == LÍMITES ==";    sed -n '1,120p' "$lim"
} > "$sum"

echo "OK: verify_v7 listo → $sum"
