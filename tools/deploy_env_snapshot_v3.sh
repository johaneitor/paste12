#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do
  [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }

DEST="$(pick)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"
TXT="$DEST/deploy-env-$TS.txt"
JSON="$DEST/deploy-env-$TS.json"
EMPTY="$DEST/deploy-env-$TS.json.empty"

# 1) headers básicos
{
  echo "timestamp: $TS"
  echo "base: $BASE"
  echo
  echo "== HEADERS / (index) =="
  curl -sS -i "$BASE/" | sed -n '1,20p'
  echo
  echo "== HEADERS /index.html =="
  curl -sS -i "$BASE/index.html" | sed -n '1,20p'
  echo
  echo "== HEADERS /?nosw=1 =="
  curl -sS -i "$BASE/?nosw=1" | sed -n '1,20p'
  echo
  echo "== HEALTH /api/health =="
  curl -sS "$BASE/api/health"
  echo
} > "$TXT"

# 2) intento fuerte de JSON (varias variantes)
get_json(){
  local url="$1" out="$2" ok=0
  curl -fsS "$url" -o "$out" && ok=1 || ok=0
  [ $ok -eq 1 ] && [ -s "$out" ] && return 0
  curl -fsS -H 'Accept: application/json' "$url" -o "$out" && ok=1 || ok=0
  [ $ok -eq 1 ] && [ -s "$out" ] && return 0
  curl -fsS "$url?json=1" -o "$out" && ok=1 || ok=0
  [ $ok -eq 1 ] && [ -s "$out" ] && return 0
  return 1
}

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
echo "== ENV SNAPSHOT ($BASE/diag/import) -> $(basename "$JSON") ==" >> "$TXT"
if get_json "$BASE/diag/import" "$TMP"; then
  mv "$TMP" "$JSON"
  echo >> "$TXT"
  echo "== RUNTIME SUMMARY ==" >> "$TXT"
  echo "http_code: 200 (asumido)" >> "$TXT"
  ct="$(file -b --mime-type "$JSON" 2>/dev/null || echo n/a)"
  echo "content_type: $ct" >> "$TXT"
  echo "body_size: $(wc -c < "$JSON" | tr -d ' ')" >> "$TXT"
else
  : > "$EMPTY"
  echo >> "$TXT"
  echo "== RUNTIME SUMMARY ==" >> "$TXT"
  echo "http_code: 200 (o sin error visible)" >> "$TXT"
  echo "content_type: n/a" >> "$TXT"
  echo "body_size: 0" >> "$TXT"
  echo >> "$TXT"
  echo "== ENV (whitelist) ==" >> "$TXT"
  echo "- warning: cuerpo vacío o endpoint no habilitado (no se moverá JSON a Download)" >> "$TXT"
fi

echo "OK: $TXT"
[ -s "$JSON" ] && echo "OK: $JSON" || echo "OK: $EMPTY"
