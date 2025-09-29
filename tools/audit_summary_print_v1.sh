#!/usr/bin/env bash
set -euo pipefail
OUT="${HOME}/Download"
last_of(){ ls -1t "$OUT"/"$1" 2>/dev/null | head -n1 || true; }

p_dep="$(last_of 'runtime-deploy-*.txt')"
p_pos="$(last_of 'runtime-positive-*.txt')"
p_neg="$(last_of 'runtime-negative-*.txt')"
p_repo="$(last_of 'repo-audit-*.txt')"
p_cln="$(last_of 'clones-*.txt')"

echo "== Snapshot de salud paste12 =="
if [[ -n "$p_dep" ]]; then
  echo "-- Deploy (remote vs local) --"
  sed -n '1,5p' "$p_dep"
else
  echo "-- Deploy -- (sin archivo reciente)"
fi

if [[ -n "$p_pos" ]]; then
  echo "-- Suite positiva (16 checks) --"
  grep -E '^(OK|FAIL)- ' "$p_pos" | sed -n '1,50p' || true
  tail -n 1 "$p_pos" | grep -E 'PASS=|FAIL=' || true
else
  echo "-- Suite positiva -- (sin archivo reciente)"
fi

if [[ -n "$p_neg" ]]; then
  echo "-- Suite negativa (IDs inexistentes) --"
  grep -E 'negativos:' "$p_neg" || true
else
  echo "-- Suite negativa -- (sin archivo reciente)"
fi

if [[ -n "$p_repo" ]]; then
  echo "-- Limpieza del repo --"
  grep -E 'OK py_compile|ERROR py_compile' "$p_repo" || true
  echo -n "marcadores de conflicto: "
  grep -cE '^(<<<<<<<|=======|>>>>>>>)' "$p_repo" 2>/dev/null || echo 0
  echo "frontend flags relevantes:"
  awk '/== FRONTEND INDEX/{p=1;next}/== BACKEND HELPERS/{p=0}p' "$p_repo" | sed -n '1,10p' || true
  echo "helpers en una línea (prohibido):"
  awk '/== BACKEND HELPERS/{p=1;next}/== ENDPOINTS/{p=0}p' "$p_repo" | sed -n '1,10p' || echo "(sin defs en línea)"
else
  echo "-- Limpieza del repo -- (sin archivo reciente)"
fi

if [[ -n "$p_cln" ]]; then
  echo "-- Clones/duplicados FE↔BE --"
  if grep -q 'no se hallaron clones' "$p_cln"; then
    echo "sin clones cruzados"
  else
    n=$(grep -c '--- DUPLICADO ---' "$p_cln" || true)
    echo "bloques duplicados: $n (ver $p_cln)"
    # muestra la primera cabecera de duplicado
    awk '/--- DUPLICADO ---/{print; c=0; next} c<4 && /:[0-9]+$/{print; c++}' "$p_cln" | sed -n '1,8p'
  fi
else
  echo "-- Clones/duplicados -- (sin archivo reciente)"
fi
