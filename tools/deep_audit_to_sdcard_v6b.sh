#!/usr/bin/env bash
set -Eeuo pipefail

# Deep audit FE/BE para Paste12
# Uso:
#   tools/deep_audit_to_sdcard_v6b.sh "https://tu-base" [/sdcard/Download]
# Ejemplo:
#   tools/deep_audit_to_sdcard_v6b.sh "https://paste12-rmsk.onrender.com" /sdcard/Download

BASE="${1:-}"
OUTDIR="${2:-/sdcard/Download}"
[[ -n "$BASE" ]] || { echo "ERROR: falta BASE"; exit 2; }

# Asegurar permisos de almacenamiento en Termux
mkdir -p "$OUTDIR" 2>/dev/null || {
  echo "ERROR: no puedo crear $OUTDIR. Si usas Termux, corre: termux-setup-storage"; exit 3;
}

ts(){ date -u +%Y%m%d-%H%M%SZ; }
TS="$(ts)"

# Rutas de salida (estilo conocido)
FRONT_AUD="$OUTDIR/frontend-audit-$TS.txt"
BACK_AUD="$OUTDIR/backend-audit-$TS.txt"
COMBO_AUD="$OUTDIR/fe-be-audit-$TS.txt"
LIVE_HTML="$OUTDIR/index-$TS.html"
LOCAL_HTML="$OUTDIR/index-local-$TS.html"
HDR_TXT="$OUTDIR/notes-headers-$TS.txt"
HEALTH_JSON="$OUTDIR/health-$TS.json"
DEPLOY_JSON="$OUTDIR/deploy-stamp-$TS.json"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

# --- 1) FRONTEND: descargar HTML vivo y copiar local (si existe) ---
log "Descargando HTML público con cache-busting…"
curl -fsSL -A "p12-audit/1.0" -H "Cache-Control: no-cache" \
  "$BASE/?nosw=1&v=$TS" -o "$LIVE_HTML" || { echo "ERROR: no pude descargar $BASE"; exit 4; }

if [[ -f frontend/index.html ]]; then
  cp -f frontend/index.html "$LOCAL_HTML"
else
  echo "<!-- frontend/index.html no encontrado en repo local -->" > "$LOCAL_HTML"
fi

# Calcular hashes
hash_pair(){ # $1 file
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v md5sum >/dev/null 2>&1; then md5sum "$1" | awk '{print $1}'
  else echo "n/a"; fi
}
SHA_LIVE="$(hash_pair "$LIVE_HTML")"
SHA_LOCAL="$(hash_pair "$LOCAL_HTML")"

# Diff (para que puedas abrirlo aparte si querés)
DIFF_FILE="$OUTDIR/diff-index-$TS.txt"
if diff -u "$LOCAL_HTML" "$LIVE_HTML" > "$DIFF_FILE"; then
  DIFF_STATUS="identical"
else
  DIFF_STATUS="different"
fi

# Checks HTML (vivo)
contains_re(){ grep -Eq "$1" "$LIVE_HTML"; }
tag_count(){ grep -oi "<$1[ >]" "$LIVE_HTML" | wc -l | tr -d '[:space:]'; }

METRICS="no"; grep -E 'class="[^"]*(views|likes|reports)[^"]*"' "$LIVE_HTML" >/dev/null 2>&1 && METRICS="yes"
ADSENSE="no"; grep -E 'adsbygoogle|pagead2\.googlesyndication' "$LIVE_HTML" >/dev/null 2>&1 && ADSENSE="yes"
SAFE_SHIM="no"; grep -qi 'name="p12-safe-shim"' "$LIVE_HTML" && SAFE_SHIM="yes"
SUMM_ENH="no";  grep -qi 'id="summary-enhancer"' "$LIVE_HTML" && SUMM_ENH="yes"
TITLE_N="$(tag_count title)"
FOOTER_N="$(tag_count footer)"
HAS_SW="no";   grep -E 'serviceWorker|navigator\.serviceWorker' "$LIVE_HTML" >/dev/null 2>&1 && HAS_SW="yes"

# Armar FRONTEND audit
{
  echo "== FRONTEND AUDIT =="
  echo "url: $BASE"
  echo "ts : $TS"
  echo "file_live : $LIVE_HTML"
  echo "file_local: $LOCAL_HTML"
  echo "sha_live  : $SHA_LIVE"
  echo "sha_local : $SHA_LOCAL"
  echo "diff_file : $DIFF_FILE ($DIFF_STATUS)"
  echo
  echo "-- checks (live) --"
  echo "metrics (.views/.likes/.reports): $METRICS"
  echo "AdSense                       : $ADSENSE"
  echo "safe-shim meta                : $SAFE_SHIM"
  echo "summary-enhancer              : $SUMM_ENH"
  echo "<title> count                 : $TITLE_N"
  echo "<footer> count                : $FOOTER_N"
  echo "service worker refs           : $HAS_SW"
} > "$FRONT_AUD"

# --- 2) BACKEND: headers/health/deploy-stamp ---
log "Sondeando /api/health …"
curl -fsSL "$BASE/api/health" -o "$HEALTH_JSON" || true

HEALTH_JSON_OK="no"
if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
  PYBIN="$(command -v python3 || command -v python)"
  if "$PYBIN" - "$HEALTH_JSON" >/dev/null 2>&1 <<'PY'
import sys, json
try:
    json.load(open(sys.argv[1],'rb'))
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
  then HEALTH_JSON_OK="yes"; fi
fi

log "Sondeando /api/deploy-stamp …"
curl -fsSL "$BASE/api/deploy-stamp" -o "$DEPLOY_JSON" || true
REMOTE_SHA="$(grep -oE '"commit"\s*:\s*"[^"]+"' "$DEPLOY_JSON" | sed -E 's/.*"commit"\s*:\s*"([^"]+)".*/\1/' | head -n1)"

log "Sondeando headers GET /api/notes?limit=10 …"
curl -fsS -D "$HDR_TXT" -o /dev/null "$BASE/api/notes?limit=10" || true

STATUS_LINE="$(head -n1 "$HDR_TXT" 2>/dev/null || true)"
ACAO="$(grep -i '^access-control-allow-origin:' "$HDR_TXT" | sed 's/\r$//' || true)"
ACAM="$(grep -i '^access-control-allow-methods:' "$HDR_TXT" | sed 's/\r$//' || true)"
ACAH="$(grep -i '^access-control-allow-headers:' "$HDR_TXT" | sed 's/\r$//' || true)"
MAXAGE="$(grep -i '^access-control-max-age:' "$HDR_TXT" | sed 's/\r$//' || true)"
LINK_NEXT_LINE="$(grep -i '^link:' "$HDR_TXT" | grep -i 'rel="next"' || true)"

LOCAL_SHA=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  LOCAL_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
fi

{
  echo "== BACKEND AUDIT =="
  echo "url: $BASE"
  echo "ts : $TS"
  echo "health_json: $HEALTH_JSON (json_ok=$HEALTH_JSON_OK)"
  echo "deploy_json: $DEPLOY_JSON"
  echo "headers    : $HDR_TXT"
  echo
  echo "-- status/headers --"
  echo "status    : ${STATUS_LINE:-n/a}"
  echo "${ACAO:-access-control-allow-origin: n/a}"
  echo "${ACAM:-access-control-allow-methods: n/a}"
  echo "${ACAH:-access-control-allow-headers: n/a}"
  echo "${MAXAGE:-access-control-max-age: n/a}"
  if [[ -n "$LINK_NEXT_LINE" ]]; then
    echo "Link rel=next: present"
    echo "Link line    : $LINK_NEXT_LINE"
  else
    echo "Link rel=next: missing"
  fi
  echo
  echo "-- SHAs --"
  echo "local HEAD        : ${LOCAL_SHA:-n/a}"
  echo "remote deploy SHA : ${REMOTE_SHA:-n/a}"
  if [[ -n "$LOCAL_SHA" && -n "$REMOTE_SHA" ]]; then
    [[ "$LOCAL_SHA" == "$REMOTE_SHA" ]] && echo "equal? yes" || echo "equal? no"
  else
    echo "equal? n/a"
  fi
} > "$BACK_AUD"

# --- 3) COMBINADO (resumen legible) ---
{
  echo "== FE/BE AUDIT (combo) =="
  echo "BASE: $BASE"
  echo "TS  : $TS"
  echo
  echo "[Frontend]"
  echo " live_html : $LIVE_HTML"
  echo " local_html: $LOCAL_HTML"
  echo " diff_file : $DIFF_FILE ($DIFF_STATUS)"
  echo " metrics   : $METRICS"
  echo " AdSense   : $ADSENSE"
  echo " safe_shim : $SAFE_SHIM"
  echo " summ_enh  : $SUMM_ENH"
  echo " title_cnt : $TITLE_N"
  echo " footer_cnt: $FOOTER_N"
  echo " sw_refs   : $HAS_SW"
  echo
  echo "[Backend]"
  echo " health_json_ok: $HEALTH_JSON_OK"
  echo " status_line   : ${STATUS_LINE:-n/a}"
  echo " ACAO          : ${ACAO#*: }"
  echo " ACAM          : ${ACAM#*: }"
  echo " ACAH          : ${ACAH#*: }"
  echo " Max-Age       : ${MAXAGE#*: }"
  [[ -n "$LINK_NEXT_LINE" ]] && echo " Link rel=next : present" || echo " Link rel=next : missing"
  echo
  echo "[SHAs]"
  echo " local_head    : ${LOCAL_SHA:-n/a}"
  echo " remote_deploy : ${REMOTE_SHA:-n/a}"
} > "$COMBO_AUD"

# --- 4) Salidas estilo conocidas ---
[[ -s "$BACK_AUD"  ]] && echo "OK: $BACK_AUD"   || echo "WARN: backend audit vacío"
[[ -s "$LIVE_HTML" ]] && echo "OK: $LIVE_HTML"  || echo "WARN: no se guardó index (live)"
[[ -s "$FRONT_AUD" ]] && echo "OK: $FRONT_AUD" || echo "WARN: frontend audit vacío"
[[ -s "$COMBO_AUD" ]] && echo "OK: $COMBO_AUD" || true
