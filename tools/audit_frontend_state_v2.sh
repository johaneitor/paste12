#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
TMP="${TMPDIR:-/tmp}/fe.$$"; mkdir -p "$TMP"
OUT="$HOME/downloads/audit-frontend-state-$(date -u +%Y%m%d-%H%M%SZ).txt"

say(){ echo -e "$*"; }
w(){ echo -e "$*" | tee -a "$OUT" >/dev/null; }

w "== FETCH index.html =="
curl -fsS "$BASE/?_=$(date +%s)" -o "$TMP/index.html"
BYTES="$(wc -c < "$TMP/index.html" | tr -d ' ')"
w "bytes: $BYTES"
w "---------------------------------------------"

w "== Scripts detectados =="
SC="$(grep -oi '<script[^>]*>' "$TMP/index.html" | wc -l | tr -d ' ')"
w "scripts: $SC"
w "markers mini-cliente v1/v2/v3: $(grep -c 'MINI-CLIENT v' "$TMP/index.html" || true)"
w "debug bootstrap: $(grep -c 'DEBUG-BOOTSTRAP' "$TMP/index.html" || true)"
w "PE shim: $(grep -c 'PE SHIM' "$TMP/index.html" || true)"
w "serviceWorker.register(): $(grep -c 'serviceWorker.register' "$TMP/index.html" || true)"
w "---------------------------------------------"

w "== Heurísticas UI =="
PUB_BTN="$(grep -oE '>\\s*Publicar\\s*<' "$TMP/index.html" | wc -l | tr -d ' ')"
TXT_COUNT="$(grep -o '<textarea' "$TMP/index.html" | wc -l | tr -d ' ')"
FEED_HINT="$(grep -oE 'data-(notes|feed)|id="(notes|feed)"' "$TMP/index.html" | wc -l | tr -d ' ')"
w "• botones 'Publicar': $PUB_BTN"
w "• textareas: $TXT_COUNT"
w "• hints de feed (data-notes/data-feed/#notes/#feed): $FEED_HINT"
w "• acciones mini (mini-actions|mini-actions-unified): $(grep -c 'mini-actions' "$TMP/index.html" || true)"
w "---------------------------------------------"

w "== /api/health y preflight =="
curl -fsS "$BASE/api/health" | tee -a "$OUT" >/dev/null; w ""
curl -fsSI -X OPTIONS "$BASE/api/notes" -H 'Origin: https://example.com' -H 'Access-Control-Request-Method: POST' | sed -n '1,20p' | tee -a "$OUT" >/dev/null
w "---------------------------------------------"

w "INFORME: $OUT"
echo "Listo: $OUT"
