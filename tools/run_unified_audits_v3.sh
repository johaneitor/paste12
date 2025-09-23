#!/usr/bin/env bash
# Audita FE/BE + AdSense + Legales + comparación live vs repo.
# Uso: tools/run_unified_audits_v3.sh "https://paste12-rmsk.onrender.com" "/sdcard/Download"
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

say(){ printf "[%s] %s\n" "$TS" "$*"; }

# Helpers para “best-effort” si faltan testers especializados
have(){ command -v "$1" >/dev/null 2>&1; }
run_or_fallback(){
  local label="$1"; shift
  if "$@"; then
    say "OK  - $label"
  else
    say "WARN- $label (fallback simple)"
    # Fallback genérico
    curl -fsSIL "$BASE" >/dev/null || true
  fi
}

# ===== 1) Health & headers mínimos (BE) =====
say "== BE: /api/health y headers =="
curl -fsS "$BASE/api/health" -o "$OUT/health-$TS.json" && say "guardado: health-$TS.json"
# OPTIONS /api/notes
curl -fsS -X OPTIONS -D "$OUT/options-$TS.txt" "$BASE/api/notes" -o /dev/null && say "guardado: options-$TS.txt"
# GET /api/notes (cuerpo + headers)
curl -fsS -D "$OUT/api-notes-headers-$TS.txt" "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json"
say "guardado: api-notes(-headers)-$TS.*"

# ===== 2) Auditoría FE/BE profunda (si existe tu script v9) =====
if [[ -x tools/deep_fe_be_audit_v9.sh ]]; then
  say "== deep_fe_be_audit_v9 =="
  tools/deep_fe_be_audit_v9.sh "$BASE" "$OUT" || true
else
  say "INFO: deep_fe_be_audit_v9.sh no está, salto."
fi

# ===== 3) AdSense en /, /terms, /privacy =====
if [[ -x tools/test_adsense_everywhere_v2.sh ]]; then
  say "== AdSense everywhere =="
  tools/test_adsense_everywhere_v2.sh "$BASE" "$OUT" || true
else
  say "INFO: test_adsense_everywhere_v2.sh no está, uso fallback."
  for path in "" "terms" "privacy"; do
    P="${BASE%/}/$path"
    curl -fsS "$P" -o "$OUT/index_${path:-_}-$TS.html" || true
    grep -qi 'googlesyndication.com/pagead/js/adsbygoogle.js' "$OUT/index_${path:-_}-$TS.html" \
      && say "OK  - AdSense en /$path" || say "FAIL- AdSense en /$path"
  done
fi

# ===== 4) Legales (/terms y /privacy) =====
if [[ -x tools/test_legal_pages_v2.sh ]]; then
  say "== legales (v2) =="
  tools/test_legal_pages_v2.sh "$BASE" "ca-pub-9479870293204581" "$OUT" || true
else
  say "INFO: test_legal_pages_v2.sh no está, uso fallback."
  for pg in terms privacy; do
    code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/$pg")"
    echo "/$pg code:$code" >> "$OUT/legal-audit-$TS.txt"
    curl -fsS "$BASE/$pg" -o "$OUT/index_${pg}-$TS.html" || true
  done
  say "guardado: legal-audit-$TS.txt"
fi

# ===== 5) Comparación live vs repo + cache-bust =====
if [[ -x tools/verify_live_vs_repo_v1.sh ]]; then
  say "== verify_live_vs_repo_v1 =="
  tools/verify_live_vs_repo_v1.sh "$BASE" "$OUT" || true
else
  say "INFO: verify_live_vs_repo_v1.sh no está, hago snapshot live."
  curl -fsS "$BASE" -o "$OUT/index-live-$TS.html" || true
fi

if [[ -x tools/cache_bust_and_verify.sh ]]; then
  say "== cache_bust_and_verify =="
  tools/cache_bust_and_verify.sh "$BASE" "$OUT" || true
fi

# ===== 6) Resumen legible =====
SUMMARY="$OUT/audits-summary-$TS.txt"
{
  echo "base: $BASE"
  echo "ts  : $TS"
  echo
  echo "-- BE --"
  jq -r '.|tojson?' "$OUT/health-$TS.json" 2>/dev/null || cat "$OUT/health-$TS.json" 2>/dev/null || echo "(no health)"
  echo
  echo "-- /api/notes headers --"
  sed -n '1,50p' "$OUT/api-notes-headers-$TS.txt" 2>/dev/null || echo "(sin headers)"
  echo
  echo "-- AdSense checks --"
  for f in "$OUT"/index_*-"$TS".html; do
    [[ -f "$f" ]] || continue
    basef="$(basename "$f")"
    if grep -qi 'googlesyndication.com/pagead/js/adsbygoogle.js' "$f"; then
      echo "OK  - $basef (AdSense)"
    else
      echo "FAIL- $basef (sin AdSense)"
    fi
  done
  echo
  echo "-- Legales --"
  for p in terms privacy; do
    code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/$p")"
    echo "/$p -> $code"
  done
} > "$SUMMARY"
say "Resumen: $SUMMARY"

say "== FIN =="
