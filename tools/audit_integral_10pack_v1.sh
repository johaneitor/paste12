#!/usr/bin/env bash
# paste12 — Auditoría integral: genera hasta 10 textos en OUTDIR
# Uso: tools/audit_integral_10pack_v1.sh BASE_URL [/sdcard/Download]
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
ROOT="$HOME/tmp/p12-integral-$TS"
mkdir -p "$ROOT" "$OUTDIR"
trap 'rm -rf "$ROOT"' EXIT

# Helpers
hcurl(){ # hcurl URL HEADERS OUTBODY -> echoes HTTP code
  local url="$1" ; local h="$2" ; local b="$3"
  curl -sS -D "$h" -o "$b" -w '%{http_code}' "$url"
}
status_line(){ sed -n '1{s/\r$//;p}' "$1" 2>/dev/null || true; }
hdr(){ awk -v k="$2" 'BEGIN{IGNORECASE=1} $0~"^"k":"{sub(/\r$/,"");print}' "$1" | sed 's/\r$//' || true; }
grep_q(){ grep -q "$@" 2>/dev/null; }

write_section(){
  printf "%s\n" "$@" >> "$4"
}

# --------------- [1] Runtime (positivos básicos) ---------------
RUNTIME_POS="$OUTDIR/01-runtime-positive.txt"
{
  echo "== RUNTIME POSITIVOS @ $TS =="
  # /
  code="$(hcurl "$BASE/" "$ROOT/h1.txt" "$ROOT/b1.bin")"
  echo "GET / -> $code ($(status_line "$ROOT/h1.txt"))"
  # index flags
  iok_commit="NO"; iok_shim="NO"; iok_single="NO"
  if grep_q -Ei 'name="p12-commit"' "$ROOT/b1.bin"; then iok_commit="YES"; fi
  if grep_q -Ei 'p12-safe-shim' "$ROOT/b1.bin"; then iok_shim="YES"; fi
  if grep_q -Ei '<body[^>]*data-single="1"' "$ROOT/b1.bin"; then iok_single="YES"; fi
  echo "FLAGS: p12-commit=$iok_commit p12-safe-shim=$iok_shim data-single=$iok_single"
  # /terms
  code="$(hcurl "$BASE/terms" "$ROOT/h2.txt" "$ROOT/b2.bin")"
  echo "GET /terms -> $code ($(status_line "$ROOT/h2.txt"))"
  # /privacy
  code="$(hcurl "$BASE/privacy" "$ROOT/h3.txt" "$ROOT/b3.bin")"
  echo "GET /privacy -> $code ($(status_line "$ROOT/h3.txt"))"
  # preflight /api/notes
  code="$(curl -sS -X OPTIONS -D "$ROOT/h4.txt" -o /dev/null -w '%{http_code}' "$BASE/api/notes")"
  echo "OPTIONS /api/notes -> $code ($(status_line "$ROOT/h4.txt"))"
  # GET /api/notes
  code="$(hcurl "$BASE/api/notes?limit=10" "$ROOT/h5.txt" "$ROOT/b5.json")"
  echo "GET /api/notes?limit=10 -> $code ($(status_line "$ROOT/h5.txt"))"
  # deploy-stamp
  code="$(hcurl "$BASE/api/deploy-stamp" "$ROOT/h6.txt" "$ROOT/b6.json")"
  if [ "$code" = "200" ]; then
    commit="$(sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p' "$ROOT/b6.json" | head -n1)"
    echo "deploy-stamp: 200 commit=$commit"
  else
    # Fallback meta
    commit="$(sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p' "$ROOT/b1.bin" | head -n1)"
    echo "deploy-stamp: $code (fallback meta) commit=$commit"
  fi
} > "$RUNTIME_POS"

# --------------- [2] Runtime (negativos) ---------------
RUNTIME_NEG="$OUTDIR/02-runtime-negative.txt"
{
  echo "== RUNTIME NEGATIVOS @ $TS =="
  id=99999999
  # like (GET)
  code="$(hcurl "$BASE/api/like?id=$id" "$ROOT/hn1.txt" "$ROOT/bn1.txt")"
  echo "GET /api/like?id=$id -> $code"
  # view (GET)
  code="$(hcurl "$BASE/api/view?id=$id" "$ROOT/hn2.txt" "$ROOT/bn2.txt")"
  echo "GET /api/view?id=$id -> $code"
  # view (POST)
  code="$(curl -sS -X POST -d "id=$id" -D "$ROOT/hn3.txt" -o "$ROOT/bn3.txt" -w '%{http_code}' "$BASE/api/view")"
  echo "POST /api/view (id=$id) -> $code"
  # report (GET)
  code="$(hcurl "$BASE/api/report?id=$id" "$ROOT/hn4.txt" "$ROOT/bn4.txt")"
  echo "GET /api/report?id=$id -> $code"
} > "$RUNTIME_NEG"

# --------------- [3] Live vs Local (índice) ---------------
LVL="$OUTDIR/03-live-vs-local.txt"
{
  echo "== LIVE vs LOCAL @ $TS =="
  # remoto
  rc="$(hcurl "$BASE/" "$ROOT/hidx.txt" "$ROOT/bidx.html")"
  rlen="$(wc -c < "$ROOT/bidx.html" | tr -d ' ')"
  rsha="$(sha256sum "$ROOT/bidx.html" | awk '{print $1}')"
  echo "REMOTE index: code=$rc bytes=$rlen sha256=$rsha"
  # local
  LCL=""
  for c in backend/static/index.html public/index.html static/index.html index.html; do
    if [ -f "$c" ]; then LCL="$c"; break; fi
  done
  if [ -n "$LCL" ]; then
    llen="$(wc -c < "$LCL" | tr -d ' ')"
    lsha="$(sha256sum "$LCL" | awk '{print $1}')"
    echo "LOCAL index: path=$LCL bytes=$llen sha256=$lsha"
    if [ "$rsha" = "$lsha" ]; then echo "index_equal: YES"; else echo "index_equal: NO"; fi
  else
    echo "LOCAL index: NOT FOUND"
    echo "index_equal: NO"
  fi
  # flags
  echo "FLAGS remote: p12-commit=$(grep -qi 'name=\"p12-commit\"' "$ROOT/bidx.html" && echo YES || echo NO)  p12-safe-shim=$(grep -qi 'p12-safe-shim' "$ROOT/bidx.html" && echo YES || echo NO)  data-single=$(grep -qi '<body[^>]*data-single="1"' "$ROOT/bidx.html" && echo YES || echo NO)"
} > "$LVL"

# --------------- [4] Remote deep (cabeceras y cache) ---------------
RDEEP="$OUTDIR/04-remote-deep.txt"
{
  echo "== REMOTE DEEP @ $TS =="
  echo "-- HEADERS / --"
  status_line "$ROOT/hidx.txt"
  hdr "$ROOT/hidx.txt" 'content-type'
  hdr "$ROOT/hidx.txt" 'cache-control'
  hdr "$ROOT/hidx.txt" 'etag'
  echo
  echo "-- HEADERS /api/notes --"
  status_line "$ROOT/h5.txt"
  hdr "$ROOT/h5.txt" 'content-type'
  hdr "$ROOT/h5.txt" 'cache-control'
  hdr "$ROOT/h5.txt" 'link'
} > "$RDEEP"

# --------------- [5] Health snapshot ---------------
HEALTH="$OUTDIR/05-health.txt"
{
  echo "== HEALTH @ $TS =="
  code="$(hcurl "$BASE/api/health" "$ROOT/hh.txt" "$ROOT/bh.json")"
  echo "GET /api/health -> $code ($(status_line "$ROOT/hh.txt"))"
  [ -s "$ROOT/bh.json" ] && head -c 400 "$ROOT/bh.json" | tr -d '\r' | sed 's/$/ .../;q' || true
} > "$HEALTH"

# --------------- [6] Integración FE↔BE ---------------
INTEG="$OUTDIR/06-integration.txt"
{
  echo "== INTEGRATION FE↔BE @ $TS =="
  echo "index flags: commit=$(grep -oEi 'name=\"p12-commit\" content=\"[0-9a-f]{7,40}\"' "$ROOT/bidx.html" | head -n1 | sed 's/.*content=\"//;s/\".*//') shim=$(grep -qi 'p12-safe-shim' "$ROOT/bidx.html" && echo YES || echo NO) single=$(grep -qi 'data-single="1"' "$ROOT/bidx.html" && echo YES || echo NO)"
  echo "preflight Allow: $(hdr "$ROOT/h4.txt" 'allow' | tr -d '\r')"
  echo "notes GET Link: $(hdr "$ROOT/h5.txt" 'link' | tr -d '\r')"
} > "$INTEG"

# --------------- [7] Repo cleanliness ---------------
REPOC="$OUTDIR/07-repo-cleanliness.txt"
{
  echo "== REPO CLEANLINESS @ $TS =="
  echo "-- git status -s --"
  git status -s || true
  echo
  echo "-- Untracked (top) --"
  git ls-files --others --exclude-standard | sed -n '1,200p'
  echo
  echo "-- Python compile --"
  python - <<'PY' || true
import py_compile, sys, pathlib
ok=True
for p in pathlib.Path(".").rglob("*.py"):
    try: py_compile.compile(str(p), doraise=True)
    except Exception as e:
        ok=False; print("PY_COMPILE_FAIL:", p, "->", e)
print("PY_COMPILE_OK" if ok else "PY_COMPILE_ERRORS")
PY
  echo
  echo "-- Helpers sanity (_p12_* not single-line) --"
  awk '
    /def _p12_/ {fn=$0; len=length($0); if (len>200) {print "WARN long def:", FILENAME ":" NR, "len=" len}}
  ' wsgiapp/__init__.py 2>/dev/null || true
} > "$REPOC"

# --------------- [8] Code clones (heurística liviana) ---------------
CLONES="$OUTDIR/08-code-clones.txt"
{
  echo "== CODE CLONES (heurístico) @ $TS =="
  find . -type f \( -name "*.py" -o -name "*.sh" -o -name "*.html" -o -name "*.js" \) \
    -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./venv/*" \
    -print0 | xargs -0 awk '
      {g=$0; gsub(/[ \t]+/,"",g); gsub(/^[ \t]*#/,"",g); if(length(g)>0) print FILENAME":"NR":"g}
    ' | awk -F: '{h=$3; if(length(h)>80) h=substr(h,1,80); cnt[h]++; map[h]=map[h] $1 ":" $2 "\n"} END{for(h in cnt) if(cnt[h]>4){print "----\nSIG:", h "\nCOUNT:", cnt[h] "\nLOCS:\n" map[h]}}'
} > "$CLONES"

# --------------- [9] Límites (TTL/CAP) — best-effort ---------------
LIMITS="$OUTDIR/09-limits.txt"
{
  echo "== LIMITS (TTL/CAP) @ $TS =="
  echo "(Best-effort; si POST /api/notes no está habilitado, se marca SKIP)"
  # JSON
  j='{"title":"audit","content":"hello from audit","ttl":"probe"}'
  c1="$(curl -sS -X POST -H 'Content-Type: application/json' -d "$j" -D "$ROOT/hp1.txt" -o "$ROOT/bp1.json" -w '%{http_code}' "$BASE/api/notes" || true)"
  echo "POST /api/notes [json] -> $c1 ($(status_line "$ROOT/hp1.txt"))"
  # FORM
  c2="$(curl -sS -X POST -d "title=audit&content=probe" -D "$ROOT/hp2.txt" -o "$ROOT/bp2.json" -w '%{http_code}' "$BASE/api/notes" || true)"
  echo "POST /api/notes [form] -> $c2 ($(status_line "$ROOT/hp2.txt"))"
  if [ "$c1" != "200" ] && [ "$c1" != "201" ] && [ "$c2" != "200" ] && [ "$c2" != "201" ]; then
    echo "TTL/CAPACITY: SKIP (no se pudo crear nota)"
  else
    echo "TTL/CAPACITY: TODO (endpoint responde; ejercitar borrado por antigüedad/capacidad si la API lo expone)"
  fi
} > "$LIMITS"

# --------------- [10] SUMMARY ---------------
SUMMARY="$OUTDIR/10-SUMMARY.txt"
{
  echo "== SUMMARY @ $TS =="
  echo "-- Positivos --"
  awk 'NR<=10' "$RUNTIME_POS"
  echo
  echo "-- Negativos --"
  cat "$RUNTIME_NEG"
  echo
  echo "-- FE flags --"
  awk '/FLAGS:/ || /REMOTE index/ || /LOCAL index/ || /index_equal:/' "$LVL"
  echo
  echo "-- Health --"
  awk 'NR<=8' "$HEALTH"
  echo
  echo "-- Repo --"
  awk 'NR<=40' "$REPOC"
  echo
  echo "(Archivos generados en $OUTDIR)"
  ls -1 "$OUTDIR" | sed -n '1,999p'
} > "$SUMMARY"

# Fin
echo "OK: auditoría integral (10 archivos) en: $OUTDIR"
printf "%s\n" \
  "$RUNTIME_POS" "$RUNTIME_NEG" "$LVL" "$RDEEP" "$HEALTH" \
  "$INTEG" "$REPOC" "$CLONES" "$LIMITS" "$SUMMARY" \
  | sed 's/^/  -> /'
