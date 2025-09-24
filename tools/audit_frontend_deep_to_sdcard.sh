#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"

pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
IDX="$DEST/index-$TS.html"
OUT="$DEST/frontend-audit-$TS.txt"

TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
: > "$OUT"

line(){ printf '%s\n' "$*" >> "$OUT"; }
title(){ printf '\n== %s ==\n' "$*" >> "$OUT"; }
kv(){ printf '%-28s %s\n' "• $1:" "$2" >> "$OUT"; }

line "# Frontend Deep Audit — $TS"
kv "Base" "$BASE"
kv "Destino HTML" "$IDX"
kv "Destino Reporte" "$OUT"

# Descarga index sin SW
curl -fsS "$BASE/?nosw=1&_=$TS" -o "$IDX" || : 

BYTES="$(wc -c < "$IDX" 2>/dev/null | tr -d ' ' || echo 0)"
SCOUNT="$(grep -oiF '<script' "$IDX" | wc -l | tr -d ' ' || echo 0)"
HAS_SHIM=$([ -s "$IDX" ] && grep -Fqi 'name="p12-safe-shim"' "$IDX" && echo yes || echo no)
HAS_SINGLE_META=$([ -s "$IDX" ] && grep -Fqi 'name="p12-single"' "$IDX" && echo yes || echo no)
HAS_SINGLE_BODY=$([ -s "$IDX" ] && grep -Fqi 'data-single="1"' "$IDX" && echo yes || echo no)

title "Resumen"
kv "bytes" "$BYTES"
kv "<script> tags" "$SCOUNT"
kv "meta p12-safe-shim" "$HAS_SHIM"
kv "meta p12-single" "$HAS_SINGLE_META"
kv "body data-single" "$HAS_SINGLE_BODY"

title "Headers index (GET, primeras 25 líneas)"
curl -sS -i "$BASE/?nosw=1&_=$TS" | sed -n '1,25p' >> "$OUT" || line "<error>"

title "Primeros bytes (hex) del HTML"
if command -v xxd >/dev/null 2>&1; then
  xxd -l 96 -g 1 "$IDX" >> "$OUT" 2>/dev/null || line "<sin xxd o sin archivo>"
else
  head -c 96 "$IDX" | od -An -t x1 >> "$OUT" 2>/dev/null || line "<sin od o sin archivo>"
fi

title "Métricas adicionales"
EXT="$(grep -oiF '<script ' "$IDX" | wc -l | tr -d ' ' || echo 0)"
INL="$(grep -oiF '<script>' "$IDX" | wc -l | tr -d ' ' || echo 0)"
kv "scripts (heurística)" "total=$SCOUNT, ext=$EXT, inline=$INL"

echo "OK: $IDX"
echo "OK: $OUT"
