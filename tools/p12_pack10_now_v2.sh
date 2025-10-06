#!/usr/bin/env bash
# Uso: tools/p12_pack10_now_v2.sh BASE_URL [OUTDIR]
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
WORK="${HOME}/tmp/p12-pack10-${TS}"
mkdir -p "$WORK" "$OUTDIR"
trap 'rm -rf "$WORK"' EXIT

out(){
  local idx="$1"; local name="$2"; local src="$3"
  local dest="$OUTDIR/$(printf '%02d' "$idx")-$name.txt"
  if [ -f "$src" ]; then cp "$src" "$dest"; else printf '(sin datos)\n' > "$dest"; fi
  echo "$dest"
}

# 1) Status
STATUS="$WORK/status.txt"
tools/p12_status_now_v3.sh "$BASE" > "$STATUS" 2>&1 || true

# 2) Live vs local (suite o fallback)
LVL="$WORK/live-vs-local.txt"
if [ -x tools/live_vs_local_v1.sh ]; then
  tools/live_vs_local_v1.sh "$BASE" "$WORK" > "$LVL" 2>&1 || true
else
  {
    echo "== LIVE VS LOCAL (fallback) =="
    echo "-- HEAD local --"; git rev-parse HEAD 2>/dev/null || true
    CODE="$(curl -sS -o "$WORK/idx.html" -w '%{http_code}' "$BASE" || echo 000)"
    echo "GET / code: $CODE"
    if [ -f "$WORK/idx.html" ]; then
      echo "remote_index_bytes=$(wc -c < "$WORK/idx.html")"
      echo "p12-commit=$(sed -n 's/.*name=\"p12-commit\" content=\"\([0-9a-f]\{7,40\}\)\".*/\1/ip' "$WORK/idx.html" | head -n1)"
      echo "safe-shim=$(grep -qi 'p12-safe-shim' "$WORK/idx.html" && echo yes || echo no)"
      echo "single=$(grep -qiE '<body[^>]*data-single=\"1\"' "$WORK/idx.html" && echo yes || echo no)"
    fi
  } > "$LVL"
fi

# 3) Deep remoto (suite o fallback)
RDEEP="$WORK/remote-deep.txt"
if [ -x tools/audit_remote_deep_v4.sh ]; then
  tools/audit_remote_deep_v4.sh "$BASE" "$WORK" > "$RDEEP" 2>&1 || true
else
  {
    echo "== REMOTE DEEP (fallback) =="
    echo "-- /api/deploy-stamp --"
    curl -sS "$BASE/api/deploy-stamp" 2>/dev/null || echo "(404/NA)"
    if [ -f "$WORK/idx.html" ]; then
      echo "-- p12-commit(meta) --"
      sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/ip' "$WORK/idx.html" | head -n1
    fi
  } > "$RDEEP"
fi

# 4) Health (suite o fallback)
HEALTH="$WORK/health.txt"
if [ -x tools/audit_health_fullstack_v2.sh ]; then
  tools/audit_health_fullstack_v2.sh "$BASE" "$WORK" > "$HEALTH" 2>&1 || true
else
  {
    echo "== HEALTH (fallback) =="
    echo "-- /api/health --"; curl -sS -o /dev/null -w 'code:%{http_code}\n' "$BASE/api/health" || true
    echo "-- /terms --";     curl -sS -o /dev/null -w 'code:%{http_code}\n' "$BASE/terms" || true
    echo "-- /privacy --";   curl -sS -o /dev/null -w 'code:%{http_code}\n' "$BASE/privacy" || true
  } > "$HEALTH"
fi

# 5) Integración (suite o fallback)
INTEG="$WORK/integration.txt"
if [ -x tools/audit_integration_sync_v1.sh ]; then
  tools/audit_integration_sync_v1.sh "$BASE" "$WORK" > "$INTEG" 2>&1 || true
else
  {
    echo "== INTEGRACION (fallback) =="
    echo "Allow(api/notes):"
    curl -sS -X OPTIONS -D - -o /dev/null "$BASE/api/notes" | sed -n 's/^allow:/Allow:/Ip'
    echo "GET /api/notes?limit=3:"
    curl -sS -o /dev/null -w 'code:%{http_code}\n' "$BASE/api/notes?limit=3"
  } > "$INTEG"
fi

# 6) Repo cleanliness (suite o fallback)
RCLEAN="$WORK/repo-clean.txt"
if [ -x tools/audit_repo_cleanliness_v4.sh ]; then
  tools/audit_repo_cleanliness_v4.sh "$WORK" > "$RCLEAN" 2>&1 || true
else
  {
    echo "== REPO CLEAN (fallback) =="
    git status --porcelain || true
    git grep -nP '\t|\r$' || true
  } > "$RCLEAN"
fi

# 7) Clones (suite o fallback)
CLONES="$WORK/code-clones.txt"
if [ -x tools/audit_code_clones_v1.sh ]; then
  tools/audit_code_clones_v1.sh "$WORK" > "$CLONES" 2>&1 || true
else
  {
    echo "== CODE CLONES (fallback) =="
    git ls-files | xargs -I{} sh -c 'wc -l "{}" | sed "s/^/lines: /"' | sort -nr | head -n 50
  } > "$CLONES"
fi

# 8) Verify (nuevo)
VERIFY="$WORK/verify.txt"
tools/verify_all_behaviors_v6.sh "$BASE" "$WORK" > "$VERIFY" 2>&1 || true

# 9) Runtime básico
RUNTIME="$WORK/runtime.txt"
{
  echo "== RUNTIME headers base =="
  curl -sS -D- -o /dev/null "$BASE" || true
  curl -sS -D- -o /dev/null "$BASE/terms" || true
  curl -sS -D- -o /dev/null "$BASE/privacy" || true
} > "$RUNTIME"

# 10) SUMMARY
SUMMARY="$WORK/SUMMARY.txt"
{
  echo "== p12 PACK10 SUMMARY @ ${TS} =="
  echo "base: $BASE"
  echo
  echo "[status]";      sed -n '1,30p' "$STATUS"
  echo
  echo "[verify]";      sed -n '1,80p' "$VERIFY"
  echo
  echo "[live/local]";  sed -n '1,60p' "$LVL"
  echo
  echo "[health]";      sed -n '1,60p' "$HEALTH"
  echo
  echo "[integration]"; sed -n '1,60p' "$INTEG"
} > "$SUMMARY"

out 01 status            "$STATUS"  >/dev/null
out 02 live-vs-local     "$LVL"     >/dev/null
out 03 remote-deep       "$RDEEP"    >/dev/null
out 04 health            "$HEALTH"   >/dev/null
out 05 fe-be-integration "$INTEG"    >/dev/null
out 06 repo-clean        "$RCLEAN"   >/dev/null
out 07 code-clones       "$CLONES"   >/dev/null
out 08 verify            "$VERIFY"   >/dev/null
out 09 runtime           "$RUNTIME"  >/dev/null
out 10 SUMMARY           "$SUMMARY"  >/dev/null

echo "OK: pack10 listo en $OUTDIR (01-...-10-*.txt)"
