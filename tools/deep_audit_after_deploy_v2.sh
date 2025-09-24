#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 BASE_URL [OUT_DIR]}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
CID="${ADSENSE_CLIENT_ID:-ca-pub-9479870293204581}"

mkdir -p "$OUT"

f() { printf '%s\n' "$OUT/$1-$TS.$2"; }

HEALTH="$(f health json)"
OPT="$(f options txt)"
NHDR="$(f api-notes-headers txt)"
NBOD="$(f api-notes json)"
LINKCHK="$(f linkhdr txt)"
IDXH="$(f index-headers txt)"
IDX="$(f index html)"
TRMH="$(f terms-headers txt)"
TRM="$(f terms html)"
PRVH="$(f privacy-headers txt)"
PRV="$(f privacy html)"
POSTJ_H="$(f post-json-h txt)"
POSTJ_B="$(f post-json-b txt)"
POSTF_H="$(f post-form-h txt)"
POSTF_B="$(f post-form-b txt)"
NEG_H="$(f negatives-h txt)"
NEG_B="$(f negatives-b txt)"
SUM="$(f unified-audit txt)"

# Helpers
status_of() { awk 'BEGIN{code="-"} NR==1{for(i=1;i<=NF;i++)if($i~/^HTTP\/[0-9.]/) code=$NF} END{print code}' "$1" 2>/dev/null || echo "-"; }
has_hdr() { grep -iE "^$1:" "$2" >/dev/null 2>&1 && echo "Y" || echo "N"; }
has_ads() { grep -i 'pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js' "$1" >/dev/null 2>&1 && grep -i "$CID" "$1" >/dev/null 2>&1 && echo "Y" || echo "N"; }
has_views() { grep -i 'class="views"' "$1" >/dev/null 2>&1 && echo "Y" || echo "N"; }

# 1) Health
curl -fsS "$BASE/api/health" -o "$HEALTH" || true

# 2) OPTIONS /api/notes (CORS)
curl -sS -D - -o /dev/null -X OPTIONS "$BASE/api/notes" > "$OPT" || true

# 3) GET /api/notes (headers + body)
curl -sS -D - -o "$NBOD" "$BASE/api/notes?limit=10" > "$NHDR" || true

# 4) Link: rel=next
{ echo "-- headers --"; head -n 40 "$NHDR" 2>/dev/null; echo; echo "-- grep Link --"; grep -i '^Link:' "$NHDR" 2>/dev/null || true; } > "$LINKCHK"

# 5) POST JSON
curl -sS -D "$POSTJ_H" -o "$POSTJ_B" -H 'Content-Type: application/json' \
     -d "{\"text\":\"audit-json $TS 123456\"}" "$BASE/api/notes" || true

# 6) POST FORM
curl -sS -D "$POSTF_H" -o "$POSTF_B" -H 'Content-Type: application/x-www-form-urlencoded' \
     --data-urlencode "text=audit-form $TS 123456" "$BASE/api/notes" || true

# 7) Negativos (404 esperados)
{
  curl -sS -D - -o /dev/null -X POST "$BASE/api/notes/999999/like" || true
  curl -sS -D - -o /dev/null -X POST "$BASE/api/notes/999999/report" || true
  curl -sS -D - -o /dev/null -X POST "$BASE/api/notes/999999/view" || true
} > "$NEG_H" 2>&1
echo "(ver encabezados arriba)" > "$NEG_B"

# 8) HTML público (sin SW / sin caché)
curl -sS -D "$IDXH" -o "$IDX" "$BASE/?debug=1&nosw=1&v=$TS" || true
curl -sS -D "$TRMH" -o "$TRM" "$BASE/terms?v=$TS" || true
curl -sS -D "$PRVH" -o "$PRV" "$BASE/privacy?v=$TS" || true

# 9) Checks
CORS_A=$(has_hdr 'Access-Control-Allow-Origin' "$OPT")
CORS_M=$(has_hdr 'Access-Control-Allow-Methods' "$OPT")
CORS_H=$(has_hdr 'Access-Control-Allow-Headers' "$OPT")
CORS_X=$(has_hdr 'Access-Control-Max-Age' "$OPT")
OPT_CODE=$(status_of "$OPT")
GET_CODE=$(status_of "$NHDR")
POSTJ_CODE=$(status_of "$POSTJ_H")
POSTF_CODE=$(status_of "$POSTF_H")
IDX_CODE=$(status_of "$IDXH")
TRM_CODE=$(status_of "$TRMH")
PRV_CODE=$(status_of "$PRVH")

ADS_IDX=$(has_ads "$IDX")
ADS_TRM=$(has_ads "$TRM")
ADS_PRV=$(has_ads "$PRV")
VIEWS_IDX=$(has_views "$IDX")

LINK_LINE="$(grep -i '^Link:' "$NHDR" 2>/dev/null | head -n1 || true)"

# 10) Comparación con repo (opcional)
REPO_HTML="frontend/index.html"
REPO_SUM="(no existe)"
LIVE_SUM="(sin archivo)"
if [[ -f "$REPO_HTML" ]]; then
  REPO_SUM="$(sha256sum "$REPO_HTML" | awk '{print $1}')"
fi
if [[ -s "$IDX" ]]; then
  LIVE_SUM="$(sha256sum "$IDX" | awk '{print $1}')"
fi

# 11) Informe unificado
{
  echo "== Unified audit $TS =="
  echo "BASE: $BASE"
  echo
  echo "-- health --"
  head -c 400 "$HEALTH" 2>/dev/null || echo "(sin archivo)"
  echo; echo
  echo "-- OPTIONS /api/notes --"
  echo "status: $OPT_CODE"
  echo "ACAO: $CORS_A  ACAM: $CORS_M  ACAH: $CORS_H  Max-Age: $CORS_X"
  echo; head -n 15 "$OPT" 2>/dev/null || true
  echo
  echo "-- GET /api/notes --"
  echo "status: $GET_CODE"
  echo "Link: ${LINK_LINE:-"(no)"}"
  echo; head -n 15 "$NHDR" 2>/dev/null || true
  echo; echo "body prefix:"; head -c 256 "$NBOD" 2>/dev/null || echo "(sin body)"
  echo; echo
  echo "-- POST /api/notes (JSON) --"
  echo "status: $POSTJ_CODE"; head -n 10 "$POSTJ_H" 2>/dev/null || true
  echo; head -c 160 "$POSTJ_B" 2>/dev/null || true
  echo; echo
  echo "-- POST /api/notes (FORM) --"
  echo "status: $POSTF_CODE"; head -n 10 "$POSTF_H" 2>/dev/null || true
  echo; head -c 160 "$POSTF_B" 2>/dev/null || true
  echo; echo
  echo "-- Negativos (404 esperados) --"
  head -n 60 "$NEG_H" 2>/dev/null || true
  echo
  echo "-- HTML público --"
  echo "/ status: $IDX_CODE  AdSense: $ADS_IDX  .views: $VIEWS_IDX"
  echo "/terms status: $TRM_CODE  AdSense: $ADS_TRM"
  echo "/privacy status: $PRV_CODE AdSense: $ADS_PRV"
  echo
  echo "-- Live vs Repo --"
  echo "sha live : $LIVE_SUM"
  echo "sha repo : $REPO_SUM"
  echo
  echo "Archivos generados:"
  printf '  %s\n' "$HEALTH" "$OPT" "$NHDR" "$NBOD" "$LINKCHK" \
                 "$POSTJ_H" "$POSTJ_B" "$POSTF_H" "$POSTF_B" \
                 "$NEG_H" "$NEG_B" "$IDXH" "$IDX" "$TRMH" "$TRM" "$PRVH" "$PRV"
  echo "== END =="
} > "$SUM"

echo "Guardado informe: $SUM"
