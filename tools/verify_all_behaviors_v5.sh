#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="$HOME/tmp/verify-$TS"; mkdir -p "$TMP"

green(){ printf "\033[32m%s\033[0m\n" "$*"; }
red(){ printf "\033[31m%s\033[0m\n" "$*"; }

ok(){ echo "PASS"; }
ko(){ echo "FAIL($1)"; }

pos(){
  echo "• == POSITIVOS ==" >"$TMP/positivos.txt"
  # /
  code=$(curl -fsS -o "$TMP/idx.html" -w "%{http_code}" "$BASE" || true)
  [[ "$code" == "200" ]] && echo "• GET /: PASS" || echo "• GET /: FAIL($code)" >>"$TMP/positivos.txt"
  # flags
  if grep -qi 'name="p12-commit"' "$TMP/idx.html" && grep -qi 'p12-safe-shim' "$TMP/idx.html" && grep -qi 'data-single="1"' "$TMP/idx.html"; then
    :
  else
    echo "• FLAGS index: WARN (falta commit/shim/single)" >>"$TMP/positivos.txt"
  fi
  for p in terms privacy; do
    code=$(curl -fsS -o /dev/null -w "%{http_code}" "$BASE/$p" || true)
    [[ "$code" == "200" ]] && echo "• GET /$p: PASS" || echo "• GET /$p: FAIL($code)" >>"$TMP/positivos.txt"
  done
  # list
  code=$(curl -fsS -H 'Accept: application/json' -o "$TMP/list.json" -w "%{http_code}" "$BASE/api/notes?limit=10" || true)
  [[ "$code" == "200" ]] && echo "• GET /api/notes?limit=10: PASS" || echo "• GET /api/notes?limit=10: FAIL($code)" >>"$TMP/positivos.txt"
  # POST (json)
  code=$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"hello p12"}' -o /dev/null -w "%{http_code}" "$BASE/api/notes" || true)
  case "$code" in 201|202) echo "• POST /api/notes [json]: PASS($code)";;  *) echo "• POST /api/notes [json]: FAIL($code)";; esac >>"$TMP/positivos.txt"
  # POST (form)
  code=$(curl -fsS -H 'Accept: application/json' -d 'text=hello+form' -o /dev/null -w "%{http_code}" "$BASE/api/notes" || true)
  case "$code" in 201|202) echo "• POST /api/notes [form]: PASS($code)";;  *) echo "• POST /api/notes [form]: FAIL($code)";; esac >>"$TMP/positivos.txt"
}

neg(){
  echo "• == NEGATIVOS ==" >"$TMP/negativos.txt"
  declare -A paths=(
    ["like"]="/api/like?id=99999999"
    ["view_get"]="/api/view?id=99999999"
    ["view_post"]="/api/view"
    ["report"]="/api/report?id=99999999"
  )
  code=$(curl -fsS -o /dev/null -w "%{http_code}" "$BASE${paths[like]}" || true)
  [[ "$code" == "404" ]] && echo "• like?id inexistente: PASS" || echo "• like inexistente: FAIL($code)" >>"$TMP/negativos.txt"
  code=$(curl -fsS -o /dev/null -w "%{http_code}" "$BASE${paths[view_get]}" || true)
  [[ "$code" == "404" ]] && echo "• view GET id inexistente: PASS" || echo "• view GET inexistente: FAIL($code)" >>"$TMP/negativos.txt"
  code=$(curl -fsS -X POST -o /dev/null -w "%{http_code}" "$BASE${paths[view_post]}" || true)
  [[ "$code" == "404" ]] && echo "• view POST id inexistente: PASS" || echo "• view POST inexistente: FAIL($code)" >>"$TMP/negativos.txt"
  code=$(curl -fsS -o /dev/null -w "%{http_code}" "$BASE${paths[report]}" || true)
  [[ "$code" == "404" ]] && echo "• report?id inexistente: PASS" || echo "• report inexistente: FAIL($code)" >>"$TMP/negativos.txt"
}

limits_basic(){
  echo "• == LIMITES (básico) ==" >"$TMP/limites.txt"
  # Solo smoke: crea 5 notas rápidas para gatillar código (si el BE soporta persistencia real).
  okc=0; for i in 1 2 3 4 5; do
    c=$(curl -fsS -H 'Content-Type: application/json' -d "{\"text\":\"p12-$TS-$i\"}" -o /dev/null -w "%{http_code}" "$BASE/api/notes" || true)
    [[ "$c" == "201" || "$c" == "202" ]] && okc=$((okc+1))
  done
  if [ "$okc" -ge 3 ]; then
    echo "• POST burst 5 → PASS($okc OK)" >>"$TMP/limites.txt"
  else
    echo "• POST burst 5 → FAIL($okc OK)" >>"$TMP/limites.txt"
  fi
  echo "Nota: test profundo de TTL/CAP requiere modelo concreto; este smoke valida que POST no 405/500." >>"$TMP/limites.txt"
}

pos
neg
limits_basic

mkdir -p "$OUT"
SUM="$OUT/verify-$TS-summary.txt"
{
  sed -n '1,200p' "$TMP/positivos.txt"
  sed -n '1,200p' "$TMP/negativos.txt"
  sed -n '1,200p' "$TMP/limites.txt"
} | tee "$SUM"

echo "OK: resumen en $SUM"
