#!/usr/bin/env bash
set -Eeuo pipefail

# Frontend/Backend Deep Audit para PASTE12
# Uso:
#   tools/frontend_fe_be_deep_audit_v1.sh "https://tu-dominio" [/sdcard/Download]
# Ejemplo:
#   tools/frontend_fe_be_deep_audit_v1.sh "https://paste12-rmsk.onrender.com"

BASE="${1:-}"
OUTDIR="${2:-/sdcard/Download}"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }
die(){ echo "ERROR: $*" >&2; exit 2; }

[[ -n "$BASE" ]] || die "falta BASE. Ej: tools/frontend_fe_be_deep_audit_v1.sh \"https://paste12-rmsk.onrender.com\""
mkdir -p "$OUTDIR" || die "no puedo crear $OUTDIR (revisa permisos de almacenamiento en Termux: termux-setup-storage)"

TS="$(date -u +%Y%m%d-%H%M%SZ)"
LIVE_HTML="$OUTDIR/index-live-$TS.html"
LOCAL_SRC="frontend/index.html"
LOCAL_HTML="$OUTDIR/index-local-$TS.html"
DIFF_FILE="$OUTDIR/diff-index-$TS.txt"
REPORT="$OUTDIR/frontend-version-audit-$TS.txt"
NOTES_HDR="$OUTDIR/api-notes-headers-$TS.txt"
HEALTH_JSON="$OUTDIR/health-$TS.json"
DEPLOY_JSON="$OUTDIR/deploy-stamp-$TS.json"

# 1) Descargar el HTML en vivo con cache-busting
log "Descargando index.html (live) desde $BASE ..."
curl -fsSL -A "p12-audit/1.0" -H "Cache-Control: no-cache" \
     "$BASE/?nosw=1&v=$TS" -o "$LIVE_HTML" || die "fallo al descargar $BASE"

# 2) Guardar copia del HTML local (si existe)
if [[ -f "$LOCAL_SRC" ]]; then
  cp -f "$LOCAL_SRC" "$LOCAL_HTML"
else
  echo "<!-- local frontend/index.html ausente -->" > "$LOCAL_HTML"
fi

# 3) Hashes
sha_cmd=""
if command -v sha256sum >/dev/null 2>&1; then sha_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then sha_cmd="shasum -a 256"
fi
if [[ -n "$sha_cmd" ]]; then
  SHA_LIVE="$($sha_cmd "$LIVE_HTML" | awk '{print $1}')"
  SHA_LOCAL="$($sha_cmd "$LOCAL_HTML" | awk '{print $1}')"
else
  # fallback a md5 si no hay sha
  if command -v md5sum >/dev/null 2>&1; then
    SHA_LIVE="$(md5sum "$LIVE_HTML" | awk '{print $1}')"
    SHA_LOCAL="$(md5sum "$LOCAL_HTML" | awk '{print $1}')"
  else
    SHA_LIVE="n/a"; SHA_LOCAL="n/a"
  fi
fi

# 4) Diff
if diff -u "$LOCAL_HTML" "$LIVE_HTML" > "$DIFF_FILE"; then
  DIFF_STATUS="identical"
else
  DIFF_STATUS="different"
fi

# 5) Probes backend
log "Probe /api/health ..."
curl -fsSL "$BASE/api/health" -o "$HEALTH_JSON" || true

log "Probe /api/deploy-stamp ..."
curl -fsSL "$BASE/api/deploy-stamp" -o "$DEPLOY_JSON" || true

log "Probe headers /api/notes?limit=10 ..."
curl -fsS -D "$NOTES_HDR" -o /dev/null "$BASE/api/notes?limit=10" || true

# 6) Chequeos en HTML live
contains(){ grep -qE "$1" "$LIVE_HTML"; }
count_tag(){ grep -oi "<$1[ >]" "$LIVE_HTML" | wc -l | tr -d '[:space:]'; }

METRICS_PRESENT="no"
grep -E 'class="[^"]*(views|likes|reports)[^"]*"' "$LIVE_HTML" >/dev/null 2>&1 && METRICS_PRESENT="yes"

ADSENSE_PRESENT="no"
grep -E 'adsbygoogle|pagead2\.googlesyndication' "$LIVE_HTML" >/dev/null 2>&1 && ADSENSE_PRESENT="yes"

SAFE_SHIM_PRESENT="no"
grep -i 'name="p12-safe-shim"' "$LIVE_HTML" >/dev/null 2>&1 && SAFE_SHIM_PRESENT="yes"

SUMMARY_ENHANCER_PRESENT="no"
grep -i 'id="summary-enhancer"' "$LIVE_HTML" >/dev/null 2>&1 && SUMMARY_ENHANCER_PRESENT="yes"

TITLE_COUNT="$(count_tag "title")"
FOOTER_COUNT="$(count_tag "footer")"

HAS_SW_REFS="no"
grep -E 'serviceWorker|navigator\.serviceWorker' "$LIVE_HTML" >/dev/null 2>&1 && HAS_SW_REFS="yes"

# 7) Parse headers backend
CORS_ORIGIN="$(grep -i '^access-control-allow-origin:' "$NOTES_HDR" | awk '{print $2}' | tr -d '\r')"
LINK_NEXT_LINE="$(grep -i '^link:' "$NOTES_HDR" | grep -i 'rel="next"' || true)"
ALLOW_METHODS="$(grep -i '^access-control-allow-methods:' "$NOTES_HDR" | tr -d '\r')"
ALLOW_HEADERS="$(grep -i '^access-control-allow-headers:' "$NOTES_HDR" | tr -d '\r')"
MAX_AGE="$(grep -i '^access-control-max-age:' "$NOTES_HDR" | awk '{print $2}' | tr -d '\r')"

# 8) SHAs git y deploy
LOCAL_GIT_SHA=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  LOCAL_GIT_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
fi
REMOTE_DEPLOY_SHA="$(grep -oE '"commit"\s*:\s*"[^"]+"' "$DEPLOY_JSON" | head -n1 | sed -E 's/.*"commit"\s*:\s*"([^"]+)".*/\1/')"

# 9) Validar health JSON con Python (sin depender de jq)
HEALTH_JSON_OK="no"
if command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  PYBIN="$(command -v python3 || command -v python)"
  if "$PYBIN" - "$HEALTH_JSON" >/dev/null 2>&1 <<'PY'
import sys, json
try:
    with open(sys.argv[1], 'rb') as f:
        json.load(f)
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
  then HEALTH_JSON_OK="yes"; fi
fi

# 10) Reporte
{
  echo "PASTE12 Frontend/Backend Deep Audit - $TS"
  echo "BASE: $BASE"
  echo
  echo "Files:"
  echo "  Live HTML : $LIVE_HTML"
  echo "  Local HTML: $LOCAL_HTML"
  echo "  Diff      : $DIFF_FILE ($DIFF_STATUS)"
  echo "  Health    : $HEALTH_JSON (json_ok=$HEALTH_JSON_OK)"
  echo "  Notes hdr : $NOTES_HDR"
  echo "  Deploy    : $DEPLOY_JSON"
  echo
  echo "Hashes:"
  echo "  live  : $SHA_LIVE"
  echo "  local : $SHA_LOCAL"
  echo
  echo "Git:"
  echo "  local HEAD         : ${LOCAL_GIT_SHA:-n/a}"
  echo "  remote deploy SHA  : ${REMOTE_DEPLOY_SHA:-n/a}"
  if [[ -n "$LOCAL_GIT_SHA" && -n "$REMOTE_DEPLOY_SHA" ]]; then
    if [[ "$LOCAL_GIT_SHA" == "$REMOTE_DEPLOY_SHA" ]]; then
      echo "  equal?             : yes"
    else
      echo "  equal?             : no"
    fi
  else
    echo "  equal?             : n/a"
  fi
  echo
  echo "Live HTML checks:"
  echo "  metrics (.views/.likes/.reports): $METRICS_PRESENT"
  echo "  AdSense detected                : $ADSENSE_PRESENT"
  echo "  safe_shim meta                  : $SAFE_SHIM_PRESENT"
  echo "  summary-enhancer script         : $SUMMARY_ENHANCER_PRESENT"
  echo "  <title> count                   : $TITLE_COUNT"
  echo "  <footer> count                  : $FOOTER_COUNT"
  echo "  service worker refs             : $HAS_SW_REFS"
  echo
  echo "Backend headers (/api/notes?limit=10):"
  echo "  Access-Control-Allow-Origin : ${CORS_ORIGIN:-n/a}"
  echo "  Access-Control-Allow-Methods: ${ALLOW_METHODS:-n/a}"
  echo "  Access-Control-Allow-Headers: ${ALLOW_HEADERS:-n/a}"
  echo "  Access-Control-Max-Age      : ${MAX_AGE:-n/a}"
  if [[ -n "$LINK_NEXT_LINE" ]]; then
    echo "  Link rel=next               : present"
    echo "  Link line                   : $LINK_NEXT_LINE"
  else
    echo "  Link rel=next               : missing"
  fi
  echo
  echo "Observations:"
  if [[ "$DIFF_STATUS" == "different" ]]; then
    echo "  - Live y local index.html difieren. Revisa el diff."
  else
    echo "  - Live y local index.html son idénticos."
  fi
  [[ "$METRICS_PRESENT" == "no" ]] && echo "  - Faltan bloques de métricas en el HTML en vivo."
  [[ "$ADSENSE_PRESENT" == "no" ]] && echo "  - AdSense no detectado en el HTML en vivo."
  [[ "$TITLE_COUNT" != "1" ]] && echo "  - Número inesperado de <title>: $TITLE_COUNT"
  [[ "$FOOTER_COUNT" != "1" ]] && echo "  - Número inesperado de <footer>: $FOOTER_COUNT"
  [[ "$HAS_SW_REFS" == "yes" ]] && echo "  - Hay referencias a Service Worker; posible desincronización por caché."
  if [[ -n "$LOCAL_GIT_SHA" && -n "$REMOTE_DEPLOY_SHA" && "$LOCAL_GIT_SHA" != "$REMOTE_DEPLOY_SHA" ]]; then
    echo "  - HEAD local y commit desplegado no coinciden."
  fi
} | tee "$REPORT" >/dev/null

log "Listo. Reporte: $REPORT"
echo "$REPORT"
