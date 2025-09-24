#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

# TMP doméstico + limpieza segura
mkd() { local base="${TMPDIR:-$HOME}"; mkdir -p "$base/.tmp_p12" 2>/dev/null || true; mktemp -d "$base/.tmp_p12/p12.XXXXXX"; }
TMPD="$(mkd)"; trap 'rm -rf "$TMPD"' EXIT

pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"

FE_OUT="$DEST/frontend-audit-$TS.txt"
BE_OUT="$DEST/backend-audit-$TS.txt"
FB_OUT="$DEST/fe-be-audit-$TS.txt"

# ===== FRONTEND =====
{
  echo "== FE: index (sin SW) ==";
  IDX="$TMPD/index.html"
  curl -fsS "$BASE/?nosw=1&_=$TS" -o "$IDX" || true
  echo "bytes=$(wc -c < "$IDX" | tr -d ' ')"
  echo "scripts=$(grep -oi '<script' "$IDX" | wc -l | tr -d ' ' || echo 0)"
  echo "safe_shim=$([ -s "$IDX" ] && grep -Fqi 'name=\"p12-safe-shim\"' "$IDX" && echo yes || echo no)"
  echo "single_meta=$([ -s "$IDX" ] && grep -Fqi 'name=\"p12-single\"' "$IDX" && echo yes || echo no)"
  echo
  echo "== Primeros bytes (hex) ==";
  if command -v xxd >/dev/null; then xxd -l 64 -g 1 "$IDX" || true; else head -c 64 "$IDX" | od -An -t x1 || true; fi
} > "$FE_OUT" || true

# ===== BACKEND =====
{
  echo "== /api/health =="; curl -sS "$BASE/api/health" && echo
  echo; echo "== OPTIONS /api/notes =="; curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,20p'
  echo; echo "== GET /api/notes?limit=3 =="; curl -sS -i "$BASE/api/notes?limit=3" | sed -n '1,30p'
  echo; echo "== POST (FORM) create + like/view ==";
  ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "text=audit $TS — 1234567890 abcdefghij" "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p'); echo "id=$ID"
  curl -sS -X POST "$BASE/api/notes/$ID/like" && echo
  curl -sS -X POST "$BASE/api/notes/$ID/view" && echo
} > "$BE_OUT" || true

# ===== FE <-> BE (single-by-id y banderas) =====
{
  echo "== single-by-id flags ==";
  H="$(curl -fsS "$BASE/?id=$ID&nosw=1&_=$TS")"
  printf "meta=%s\n" $([ -n "$H" ] && echo "$H" | tr -d '\n' | grep -Fqi '<meta name="p12-single"' && echo 1 || echo 0)
  printf "body=%s\n" $([ -n "$H" ] && echo "$H" | tr -d '\n' | grep -Fqi 'data-single="1"'        && echo 1 || echo 0)
  echo; echo "== resumen ==";
  echo "FE -> $FE_OUT"
  echo "BE -> $BE_OUT"
} > "$FB_OUT" || true

echo "OK: $FE_OUT"
echo "OK: $BE_OUT"
echo "OK: $FB_OUT"
