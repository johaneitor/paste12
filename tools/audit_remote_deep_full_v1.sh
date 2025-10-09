#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<MSG
Usage: $0 BASE_URL OUTDIR [--allow-post] [--stress-posts]
Example:
  $0 "https://paste12-rmsk.onrender.com" "/sdcard/Download" --allow-post
Options:
  --allow-post    : send a single small POST to /api/notes (non-destructive payload)
  --stress-posts  : when used together with --allow-post, send 5 quick POSTs to test rate limits
Outputs (max 10 files) saved under OUTDIR/p12-deep-<ts>/
MSG
  exit 1
}

if [[ $# -lt 2 ]]; then usage; fi

BASE="${1%/}"
OUTROOT="${2}"
shift 2

ALLOW_POST=false
STRESS_POSTS=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-post) ALLOW_POST=true; shift ;;
    --stress-posts) STRESS_POSTS=true; shift ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUTDIR="${OUTROOT%/}/p12-deep-${TS}"
mkdir -p "$OUTDIR"

# Small helpers
curl_code() { curl -sS -L -w "%{http_code}" -o "$2" "$1" 2>/dev/null || echo "000"; }
curl_head() { curl -sS -I -L "$1" 2>/dev/null || true; }
jq_or_cat() {
  if command -v jq >/dev/null 2>&1; then jq . "$1" 2>/dev/null || cat "$1"; else cat "$1"; fi
}

echo "=== p12 DEEP REMOTE AUDIT ($TS) ==="
echo "BASE: $BASE"
echo "OUTDIR: $OUTDIR"
echo

# 1) Index + headers + detect flags + FE errors
INDEX_F="$OUTDIR/index-remote.html"
IDX_STATUS="$(curl_code "$BASE/" "$INDEX_F")"
echo "[1] GET / -> $IDX_STATUS (saved $INDEX_F)"
# headers separately
HEADERS_F="$OUTDIR/index-remote-headers.txt"
curl -sS -I -L "$BASE/" > "$HEADERS_F" || true
echo "[1.a] headers -> $HEADERS_F"

# extract p12 meta flags
echo "-- index flags check --" > "$OUTDIR/fe-flags.txt"
for key in 'name="p12-commit"' 'p12-safe-shim' 'data-single'; do
  if grep -qi "$key" "$INDEX_F"; then
    echo "OK: $key" >> "$OUTDIR/fe-flags.txt"
  else
    echo "MISSING: $key" >> "$OUTDIR/fe-flags.txt"
  fi
done
echo "[1.b] FE flags -> $OUTDIR/fe-flags.txt"

# search for visible errors/tracebacks in index
grep -Ein --color=never -m 20 "traceback|exception|error handling request|500 internal server error|patternerror|valueerror|stacktrace|syntaxerror" "$INDEX_F" > "$OUTDIR/fe-index-errors.txt" || true
echo "[1.c] FE index error hints -> $OUTDIR/fe-index-errors.txt"

# 2) Find main JS bundle (simple heuristics) and fetch it
echo "-- locating JS bundle --"
SCRIPT_SRC="$(sed -n '1,400p' "$INDEX_F" | tr '\n' ' ' | sed -E 's/</\n</g' | grep -iEo '<script[^>]+>' \
  | grep -iEo 'src=[\"'\''][^\"'\'']+[\"'\'']' | sed -E "s/src=['\"](.*)['\"]/\\1/" \
  | grep -Ei 'app(\.min)?\.js|/js/|main\.[a-z0-9]+\.js' | head -n1 || true)"
ASSETS_F="$OUTDIR/assets.txt"
: > "$ASSETS_F"
if [[ -n "$SCRIPT_SRC" ]]; then
  if [[ "$SCRIPT_SRC" =~ ^https?:// ]]; then JS_URL="$SCRIPT_SRC"; else
    if [[ "$SCRIPT_SRC" =~ ^/ ]]; then JS_URL="${BASE}${SCRIPT_SRC}"; else JS_URL="${BASE}/${SCRIPT_SRC}"; fi
  fi
  JS_F="$OUTDIR/remote-app-js.bundle"
  JS_STATUS="$(curl_code "$JS_URL" "$JS_F")" || JS_STATUS="000"
  echo "FOUND JS: $SCRIPT_SRC -> $JS_URL (HTTP $JS_STATUS)" >> "$ASSETS_F"
  echo "JS saved -> $JS_F" >> "$ASSETS_F"
  # quick grep for "console.error" or "throw" or obvious runtime errors
  grep -Ei "console\.error|throw |Uncaught |ReferenceError|TypeError" "$JS_F" | sed -n '1,40p' > "$OUTDIR/js-suspected-errors.txt" || true
  echo "JS error hints -> $OUTDIR/js-suspected-errors.txt" >> "$ASSETS_F"
else
  echo "NO obvious JS bundle found in index" >> "$ASSETS_F"
fi
echo "[2] assets report -> $ASSETS_F"

# 3) deploy-stamp endpoint + compare with index meta p12-commit
DEP_STAMP_F="$OUTDIR/deploy-stamp.json"
DEP_STATUS="$(curl -sS -w "%{http_code}" -o "$DEP_STAMP_F" "$BASE/api/deploy-stamp" 2>/dev/null || echo "000")"
echo "[3] GET /api/deploy-stamp -> $DEP_STATUS (saved $DEP_STAMP_F)"
# extract commit from index meta
IDX_COMMIT="$(grep -iEo 'name=["'\'']p12-commit["'\'']\s+content=["'\''][0-9a-f]{7,40}["'\'']' "$INDEX_F" 2>/dev/null || true \
  | sed -E 's/.*content=["'\'']([0-9a-f]{7,40})["'\''].*/\1/' | head -n1 || true)"
DEP_COMMIT="$(jq -r '.commit // empty' "$DEP_STAMP_F" 2>/dev/null || true)"
echo "index.commit: ${IDX_COMMIT:-<none>}" > "$OUTDIR/deploy-compare.txt"
echo "deploy-stamp.commit: ${DEP_COMMIT:-<none>}" >> "$OUTDIR/deploy-compare.txt"
if [[ -n "$IDX_COMMIT" && -n "$DEP_COMMIT" && "$IDX_COMMIT" == "$DEP_COMMIT" ]]; then
  echo "OK: index and /api/deploy-stamp agree" >> "$OUTDIR/deploy-compare.txt"
else
  echo "WARN: mismatch or missing commits" >> "$OUTDIR/deploy-compare.txt"
fi
echo "[3.a] deploy compare -> $OUTDIR/deploy-compare.txt"

# 4) Health checks
HEALTH_F="$OUTDIR/health.json"
HEALTH_STATUS="$(curl -sS -w "%{http_code}" -o "$HEALTH_F" "$BASE/api/health" 2>/dev/null || echo "000")"
echo "[4] GET /api/health -> $HEALTH_STATUS (saved $HEALTH_F)"

# 5) API notes GET + headers + CORS
API_GET_F="$OUTDIR/api-notes-get.json"
API_STATUS="$(curl -sS -w "%{http_code}" -o "$API_GET_F" -L "${BASE}/api/notes?limit=10" 2>/dev/null || echo "000")"
echo "[5] GET /api/notes?limit=10 -> $API_STATUS (saved $API_GET_F)"
curl_head "${BASE}/api/notes" > "$OUTDIR/api-notes-headers.txt" || true
echo "[5.a] /api/notes headers -> $OUTDIR/api-notes-headers.txt"

# Try to parse JSON briefly
if [[ "$API_STATUS" == "200" ]]; then
  if command -v jq >/dev/null 2>&1; then
    if jq empty "$API_GET_F" >/dev/null 2>&1; then
      echo "API /api/notes JSON OK" > "$OUTDIR/api-notes-parse.txt"
      jq 'if type=="array" then {count:length, sample:.[0:3]} else {keys:keys, sample:.} end' "$API_GET_F" > "$OUTDIR/api-notes-summary.json" 2>/dev/null || true
      echo "[5.b] api notes summary -> $OUTDIR/api-notes-summary.json"
    else
      echo "ERR: /api/notes response not valid JSON" > "$OUTDIR/api-notes-parse.txt"
    fi
  else
    echo "No jq installed; saved raw JSON at $API_GET_F" > "$OUTDIR/api-notes-parse.txt"
  fi
else
  echo "GET /api/notes returned $API_STATUS; saved body -> $API_GET_F" > "$OUTDIR/api-notes-parse.txt"
fi

# 6) Negative tests (like/view/report with non-existing ids) — safe GET/POST check
NEG_F="$OUTDIR/negatives.txt"
: > "$NEG_F"
for ep in "/api/like?id=99999999" "/api/view?id=99999999" "/api/report?id=99999999"; do
  SFILE="$OUTDIR/neg-$(basename ${ep})"
  CODE="$(curl -sS -w "%{http_code}" -o "$SFILE" "${BASE}${ep}" 2>/dev/null || echo "000")"
  echo "$ep -> $CODE" >> "$NEG_F"
done
# test POST view/report like with id that doesn't exist (non-destructive)
for ep in "/api/view" "/api/report" "/api/like"; do
  SFILE="$OUTDIR/neg-post-$(basename ${ep})"
  CODE="$(curl -sS -w "%{http_code}" -o "$SFILE" -X POST -H "Content-Type: application/json" -d '{"id":99999999}' "${BASE}${ep}" 2>/dev/null || echo "000")"
  echo "POST ${ep} -> $CODE" >> "$NEG_F"
done
echo "[6] negatives -> $NEG_F"

# 7) POST probe (optional and safe): create note
POST_F="$OUTDIR/api-notes-post.json"
POST_STATUS="SKIP"
if [[ "$ALLOW_POST" == "true" ]]; then
  echo "[7] Attempting safe POST /api/notes (small payload)"
  POST_STATUS="$(curl -sS -w "%{http_code}" -o "$POST_F" -X POST -H "Content-Type: application/json" \
    -d '{"text":"smoke create from auditor","hours":1}' "${BASE}/api/notes" 2>/dev/null || echo "000")"
  echo "POST /api/notes -> $POST_STATUS (saved $POST_F)"
  if [[ "$POST_STATUS" =~ ^2 ]]; then
    echo "OK: create seems to work; saved response $POST_F"
  else
    echo "WARN: POST returned $POST_STATUS; allow header:"
    curl -sI "${BASE}/api/notes" | sed -n '1,50p' > "$OUTDIR/api-notes-allow-header.txt" || true
  fi

  if [[ "$STRESS_POSTS" == "true" ]]; then
    echo "[7.b] stress posts (5 quick posts to see rate-limit/429)"
    : > "$OUTDIR/post-stress-summary.txt"
    for i in 1 2 3 4 5; do
      C="$(curl -sS -w "%{http_code}" -o "$OUTDIR/post-stress-$i.json" -X POST -H "Content-Type: application/json" \
           -d "{\"text\":\"stress $i\",\"hours\":1}" "${BASE}/api/notes" 2>/dev/null || echo "000")"
      echo "$i -> $C" >> "$OUTDIR/post-stress-summary.txt"
    done
  fi
else
  echo "[7] SKIPPED POST probes (no --allow-post). To enable, re-run with --allow-post"
fi

# 8) Rate limiting / basic abuse checks via simple header probes
RL_F="$OUTDIR/rate-limit-probe.txt"
echo "-- Rate-limit probe (OPTIONS + repeated HEAD) --" > "$RL_F"
curl -sS -X OPTIONS -i "${BASE}/api/notes" >> "$RL_F" || true
# quick repeated GETs to see if any 429 appears quickly
for i in 1 2 3 4 5; do
  curl -sS -o /dev/null -w "%{http_code}" "${BASE}/api/notes?limit=1" >> "$RL_F" 2>&1 || true
  echo " " >> "$RL_F"
done
echo "[8] rate-limit probe -> $RL_F"

# 9) Search for stacktraces or errors across saved artifacts (index, JS, API bodies)
ERRS_F="$OUTDIR/remote-errors-found.txt"
: > "$ERRS_F"
for f in "$INDEX_F" "$JS_F" "$API_GET_F" "$POST_F" "$HEALTH_F" "$DEP_STAMP_F"; do
  if [[ -f "$f" ]]; then
    grep -Ein "traceback|exception|error handling request|500 internal server error|patternerror|valueerror|syntaxerror|uncaught|ReferenceError|TypeError" "$f" \
      | sed -n '1,50p' >> "$ERRS_F" || true
  fi
done
echo "[9] aggregated quick error hints -> $ERRS_F"

# 10) Summary file (concise)
SUMMARY="$OUTDIR/summary.txt"
{
  echo "p12 DEEP REMOTE AUDIT - $TS"
  echo "BASE: $BASE"
  echo
  echo "INDEX HTTP: $IDX_STATUS"
  echo "INDEX flags file: $OUTDIR/fe-flags.txt"
  echo "INDEX errors hints: $OUTDIR/fe-index-errors.txt"
  echo
  echo "JS bundle: ${SCRIPT_SRC:-<none>} (fetched status: ${JS_STATUS:-<none>})"
  echo "JS error hints: $OUTDIR/js-suspected-errors.txt"
  echo
  echo "deploy-stamp status: $DEP_STATUS -> $DEP_STAMP_F"
  echo "deploy compare: $OUTDIR/deploy-compare.txt"
  echo
  echo "health: $HEALTH_STATUS -> $HEALTH_F"
  echo "GET /api/notes: $API_STATUS -> $API_GET_F"
  echo "api notes parse: $OUTDIR/api-notes-parse.txt"
  echo
  echo "negatives: $NEG_F"
  echo "POST probe status: $POST_STATUS (allowed only if --allow-post)"
  if [[ "$STRESS_POSTS" == "true" ]]; then echo "post stress: $OUTDIR/post-stress-summary.txt"; fi
  echo "rate-limit-probe: $RL_F"
  echo
  echo "collected artifacts (up to 10):"
  ls -1 "$OUTDIR" | sed -n '1,200p'
} > "$SUMMARY"
echo "[10] summary -> $SUMMARY"

echo
echo "=== FINISHED ==="
echo "Artifacts: $OUTDIR"
echo "Main summary: $SUMMARY"
echo "If you want I can also:"
echo " - compare index remote vs local (requires local index path)"
echo " - run a deeper JS static scan (grep for '//# sourceMappingURL' or sourcemaps)"
echo " - produce a single tarball ready to upload"
exit 0
