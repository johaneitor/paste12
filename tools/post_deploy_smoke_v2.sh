#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUTDIR"

echo "== post_deploy_smoke_v2 =="
echo "[base] $BASE"
echo "[ts]   $TS"

# 1) Health
curl -fsS "$BASE/api/health" -o "$OUTDIR/health-$TS.json" && echo "[health] ok -> $OUTDIR/health-$TS.json" || echo "[health] FAIL"

# 2) OPTIONS CORS
curl -s -D "$OUTDIR/options-$TS.txt" -o /dev/null -X OPTIONS "$BASE/api/notes" || true
echo "[options] -> $OUTDIR/options-$TS.txt"

# 3) GET headers/body + Link
curl -s -D "$OUTDIR/api-notes-headers-$TS.txt" -o "$OUTDIR/api-notes-$TS.json" "$BASE/api/notes?limit=10" || true
echo "[notes] -> headers/body en $OUTDIR"

# 4) publish JSON/FORM (tolerante)
curl -fsS -H 'Content-Type: application/json' -d '{"text":"post-deploy smoke json 123456"}' "$BASE/api/notes" -o /dev/null && echo "[publish-json] OK" || echo "[publish-json] WARN"
curl -fsS -d 'text=post-deploy+smoke+form+123456' "$BASE/api/notes" -o /dev/null && echo "[publish-form] OK" || echo "[publish-form] WARN"

# 5) Ads y legales (si tienes los testers ya en repo)
if [[ -x tools/test_adsense_everywhere_v2.sh ]]; then
  tools/test_adsense_everywhere_v2.sh "$BASE" "ca-pub-9479870293204581" "$OUTDIR" || true
fi
if [[ -x tools/test_legal_pages_v2.sh ]]; then
  tools/test_legal_pages_v2.sh "$BASE" "ca-pub-9479870293204581" "$OUTDIR" || true
fi

# 6) Frontend: cache-bust + diff live vs repo (si existen)
if [[ -x tools/cache_bust_and_verify.sh ]]; then
  tools/cache_bust_and_verify.sh "$BASE" || true
fi
if [[ -x tools/verify_live_vs_repo_v1.sh ]]; then
  tools/verify_live_vs_repo_v1.sh "$BASE" "$OUTDIR" || true
fi

# 7) Resumen mínimo
echo "[resumen] archivos en $OUTDIR:"
ls -1 "$OUTDIR" | sed -n "1,200p"
echo "== FIN =="
