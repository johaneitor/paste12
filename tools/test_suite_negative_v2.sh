#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

pick(){ 
  for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do 
    [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; 
  done; 
  echo "$HOME"; 
}
DEST="$(pick)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"; OUT="$DEST/negative-audit-$TS.txt"

log(){ printf '%s\n' "$*" | tee -a "$OUT" >/dev/null; }

expect_404(){
  local path="$1"
  local code body
  body="$(curl -sS -X POST "$BASE$path" -H 'Content-Type: application/json' -d '{}' || true)"
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$BASE$path" -H 'Content-Type: application/json' -d '{}' || true)"
  if [ "$code" = "404" ]; then
    log "OK  - $path -> 404"
  else
    log "FAIL- $path -> $code"
    log "body: $body"
  fi
}

: > "$OUT"
log "timestamp: $TS"
log "base: $BASE"
log ""
log "== POST vacío (FORM) =="
curl -sS -i -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=" "$BASE/api/notes" | sed -n '1,20p' | tee -a "$OUT" >/dev/null

log "== POST vacío (JSON) =="
curl -sS -i -H 'Content-Type: application/json' \
  --data '{}' "$BASE/api/notes" | sed -n '1,20p' | tee -a "$OUT" >/dev/null

log "== Like/View/Report inexistente (espera 404) =="
expect_404 "/api/notes/999999/like"
expect_404 "/api/notes/999999/view"
expect_404 "/api/notes/999999/report"

log ""
log "OK: $OUT"
