#!/usr/bin/env bash
# Usa: tools/run_reconcile_and_audit_v2.sh "ca-pub-XXXX" "https://paste12-rmsk.onrender.com"
set -euo pipefail
ADS="${1:-}"
BASE="${2:-}"
[[ -n "$ADS" ]] || { echo "Uso: $0 ADSENSE_ID BASE_URL"; exit 2; }
[[ -n "$BASE" ]] || { echo "Uso: $0 ADSENSE_ID BASE_URL"; exit 2; }

tools/frontend_reconcile_v2.sh frontend/index.html "$ADS" "$BASE"

TS="$(date -u +%Y%m%d-%H%M%SZ)"
DLD="/sdcard/Download"

# Auditoría rápida FE/BE
curl -fsS "$BASE/api/health" -o "$DLD/health-$TS.json" || true
curl -fsSI -X OPTIONS "$BASE/api/notes" -o "$DLD/options-$TS.txt" || true
curl -fsSI "$BASE/api/notes?limit=10" -o "$DLD/api-notes-headers-$TS.txt" || true
curl -fsS  "$BASE/api/notes?limit=10" -o "$DLD/api-notes-$TS.json" || true
curl -fsS  "$BASE" -o "$DLD/index-$TS.html" || true

REPORT="$DLD/unified-audit-$TS.txt"
{
  echo "== unified audit (reconcile + fe/be) =="
  echo "base: $BASE"
  echo "ts  : $TS"
  echo "-- health --"
  [[ -f "$DLD/health-$TS.json" ]] && cat "$DLD/health-$TS.json" || echo "health: (no file)"
  echo
  echo "-- OPTIONS /api/notes --"
  [[ -f "$DLD/options-$TS.txt" ]] && sed -n '1,999p' "$DLD/options-$TS.txt" || echo "(no file)"
  echo
  echo "-- GET /api/notes headers --"
  [[ -f "$DLD/api-notes-headers-$TS.txt" ]] && sed -n '1,999p' "$DLD/api-notes-headers-$TS.txt" || echo "(no file)"
  echo
  echo "-- GET / (head checks) --"
  if [[ -f "$DLD/index-$TS.html" ]]; then
    META=$(grep -ic '<meta[^>]*name=["'"'"']google-adsense-account' "$DLD/index-$TS.html" || true)
    TAGS=$(grep -ic 'googlesyndication\.com/pagead/js/adsbygoogle\.js' "$DLD/index-$TS.html" || true)
    echo "HEAD meta-adsense: $META"
    echo "HEAD adsbygoogle : $TAGS"
  else
    echo "(no index html)"
  fi
  echo
  echo "== files =="
  ls -1 "$DLD"/{health-$TS.json,options-$TS.txt,api-notes-headers-$TS.txt,api-notes-$TS.json,index-$TS.html} 2>/dev/null || true
} > "$REPORT"
echo "Reporte: $REPORT"
