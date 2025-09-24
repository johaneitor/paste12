#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="${TMPDIR:-/tmp}/fe.$$.tmp"; mkdir -p "${TMP%/*}"
OUT="$HOME/downloads/audit-frontend-state-$TS.txt"
IDX="$HOME/downloads/index-$TS.html"
SUM="$HOME/downloads/frontend-summary-$TS.md"

fetch () { curl -fsS "$1" -o "$2"; }

echo "== FETCH index.html ==" | tee -a "$OUT"
fetch "$BASE/?_=$TS" "$TMP.index"
BYTES="$(wc -c < "$TMP.index" | tr -d ' ')"
echo "bytes: $BYTES" | tee -a "$OUT"
cp "$TMP.index" "$IDX"

echo "---------------------------------------------" | tee -a "$OUT"
echo "== Scripts detectados ==" | tee -a "$OUT"
grep -oi '<script[^>]*>' "$TMP.index" | sed -n '1,120p' | tee -a "$OUT" || true
echo "markers:" | tee -a "$OUT"
for k in 'MINI-CLIENT v' 'DEBUG-BOOTSTRAP' 'PE SHIM' 'serviceWorker.register' \
         'mini-actions' 'mini-actions-unified' 'Ver más' 'Publicar' 'textarea' 'data-id="' ; do
  printf "• %-24s %s\n" "$k" "$(grep -c "$k" "$TMP.index" || echo 0)" | tee -a "$OUT"
done

echo "---------------------------------------------" | tee -a "$OUT"
echo "== health/preflight ==" | tee -a "$OUT"
curl -fsS "$BASE/api/health" | tee -a "$OUT"; echo | tee -a "$OUT"
curl -fsSI -X OPTIONS "$BASE/api/notes" -H 'Origin: https://example.com' \
  -H 'Access-Control-Request-Method: POST' | sed -n '1,22p' | tee -a "$OUT"

# Resumen
cat > "$SUM" <<MD
# Frontend summary ($TS)

- index bytes: **$BYTES**
- Scripts tags: $(grep -oi '<script' "$TMP.index" | wc -l | tr -d ' ')
- Marcadores:
  - MINI-CLIENT v*: $(grep -c 'MINI-CLIENT v' "$TMP.index" || true)
  - DEBUG-BOOTSTRAP: $(grep -c 'DEBUG-BOOTSTRAP' "$TMP.index" || true)
  - PE SHIM: $(grep -c 'PE SHIM' "$TMP.index" || true)
  - mini-actions-unified: $(grep -c 'mini-actions-unified' "$TMP.index" || true)
- Presencia UI:
  - “Publicar”: $(grep -c '>[[:space:]]*Publicar[[:space:]]*<' "$TMP.index" || true)
  - “Ver más”: $(grep -c 'Ver más' "$TMP.index" || true)
  - Tarjetas (data-id): $(grep -c 'data-id="' "$TMP.index" || true)

Archivos:
- HTML: **$(basename "$IDX")**
- Log: **$(basename "$OUT")**
MD

echo
echo "INFORME: $OUT"
echo "INDEX  : $IDX"
echo "RESUMEN: $SUM"
