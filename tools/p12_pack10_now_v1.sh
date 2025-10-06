#!/usr/bin/env bash
# Uso: tools/p12_pack10_now_v1.sh BASE_URL [OUTDIR]
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
WORK="${HOME}/tmp/p12-pack10-${TS}"
mkdir -p "$WORK" "$OUTDIR"
trap 'rm -rf "$WORK"' EXIT

out(){
  local idx="$1"; shift
  local name="$1"; shift
  local src="$1"; shift
  local dest="$OUTDIR/$(printf '%02d' "$idx")-$name.txt"
  [ -f "$src" ] && cp "$src" "$dest" || printf '%s\n' "$(<"$src")" > "$dest" 2>/dev/null || true
  [ -f "$dest" ] || { echo "(sin datos)" > "$dest"; }
  echo "$dest"
}

# 1) Status rápido
STATUS="$WORK/status.txt"
tools/p12_status_now_v2.sh "$BASE" > "$STATUS" 2>&1 || true

# 2) Live vs local (si existe la suite), con fallback
LVL="$WORK/live-vs-local.txt"
if command -v tools/live_vs_local_v1.sh >/dev/null 2>&1; then
  tools/live_vs_local_v1.sh "$BASE" "$WORK" > "$LVL" 2>&1 || true
else
  {
    echo "== LIVE VS LOCAL (fallback) =="
    echo "-- HEAD local --"
    git rev-parse HEAD 2>/dev/null || true
    echo "-- index remoto --"
    curl -fsS -D "$WORK/idx.h" "$BASE" -o "$WORK/idx.html" || true
    echo "remote_index_bytes=$(wc -c < "$WORK/idx.html" 2>/dev/null || echo 0)"
    echo "p12-commit=$(sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/ip' "$WORK/idx.html" | head -n1)"
    echo "safe-shim=$(grep -qi 'p12-safe-shim' "$WORK/idx.html" && echo yes || echo no)"
    echo "single=$(grep -qi '<body[^>]*data-single="1"' "$WORK/idx.html" -i -E && echo yes || echo no)"
  } > "$LVL"
fi

# 3) Deep remoto (si existe), con fallback
RDEEP="$WORK/remote-deep.txt"
if command -v tools/audit_remote_deep_v4.sh >/dev/null 2>&1; then
  tools/audit_remote_deep_v4.sh "$BASE" "$WORK" > "$RDEEP" 2>&1 || true
else
  {
    echo "== REMOTE DEEP (fallback) =="
    echo "-- HEAD remoto via /api/deploy-stamp --"
    curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null || echo "(404/NA)"
    echo "-- HEAD remoto via meta --"
    sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/ip' "$WORK/idx.html" | head -n1
    echo "-- assets --"
    echo "(no indexados; FE estático inline)"
  } > "$RDEEP"
fi

# 4) Salud FE/BE (si existe), con fallback
HEALTH="$WORK/health.txt"
if command -v tools/audit_health_fullstack_v2.sh >/dev/null 2>&1; then
  tools/audit_health_fullstack_v2.sh "$BASE" "$WORK" > "$HEALTH" 2>&1 || true
else
  {
    echo "== HEALTH (fallback) =="
    echo "-- /api/health --"
    curl -sS -w '\nHTTP %{http_code}\n' "$BASE/api/health" -o /dev/null || true
    echo "-- /terms /privacy --"
    curl -sS -o /dev/null -w "terms:%{http_code}\n" "$BASE/terms"
    curl -sS -o /dev/null -w "privacy:%{http_code}\n" "$BASE/privacy"
  } > "$HEALTH"
fi

# 5) Integración FE↔BE (si existe), con fallback
INTEG="$WORK/integration.txt"
if command -v tools/audit_integration_sync_v1.sh >/dev/null 2>&1; then
  tools/audit_integration_sync_v1.sh "$BASE" "$WORK" > "$INTEG" 2>&1 || true
else
  {
    echo "== INTEGRACION FE↔BE (fallback) =="
    echo "p12-commit(meta)=$(sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/ip' "$WORK/idx.html" | head -n1)"
    echo "Allow(api/notes OPTIONS):"
    curl -fsS -X OPTIONS -D - -o /dev/null "$BASE/api/notes" 2>/dev/null | sed -n 's/^allow:/Allow:/Ip'
  } > "$INTEG"
fi

# 6) Repo cleanliness (si existe), con fallback
RCLEAN="$WORK/repo-clean.txt"
if command -v tools/audit_repo_cleanliness_v4.sh >/dev/null 2>&1; then
  tools/audit_repo_cleanliness_v4.sh "$WORK" > "$RCLEAN" 2>&1 || true
else
  {
    echo "== REPO CLEAN (fallback) =="
    echo "-- git status --"
    git status --porcelain || true
    echo "-- archivos sospechosos (tabs, CRLF) --"
    git grep -nP '\t|\r$' || true
  } > "$RCLEAN"
fi

# 7) Code clones (si existe), con fallback
CLONES="$WORK/code-clones.txt"
if command -v tools/audit_code_clones_v1.sh >/dev/null 2>&1; then
  tools/audit_code_clones_v1.sh "$WORK" > "$CLONES" 2>&1 || true
else
  {
    echo "== CODE CLONES (fallback ligero) =="
    git ls-files | xargs -I{} sh -c 'wc -l "{}" | sed "s/^/lines: /"' | sort -nr | head -n 50
  } > "$CLONES"
fi

# 8) Verify (positivos/negativos/límites)
VERIFY="$WORK/verify.txt"
tools/verify_all_behaviors_v5.sh "$BASE" "$WORK" > "$VERIFY" 2>&1 || true

# 9) Runtime (smoke GET + headers base)
RUNTIME="$WORK/runtime.txt"
{
  echo "== RUNTIME GET SMOKE =="
  curl -fsS -D- -o /dev/null "$BASE" || true
  curl -fsS -D- -o /dev/null "$BASE/terms" || true
  curl -fsS -D- -o /dev/null "$BASE/privacy" || true
  echo "== PRE-API =="
  curl -sS -o /dev/null -w "notes:%{http_code}\n" "$BASE/api/notes?limit=3"
} > "$RUNTIME" || true

# 10) SUMMARY
SUMMARY="$WORK/SUMMARY.txt"
{
  echo "== p12 PACK10 SUMMARY @ ${TS} =="
  echo "base: $BASE"
  echo
  echo "[status]";      tail -n +1 "$STATUS"      | sed -n '1,25p'
  echo
  echo "[verify]";      tail -n +1 "$VERIFY"      | sed -n '1,60p'
  echo
  echo "[live/local]";  tail -n +1 "$LVL"         | sed -n '1,40p'
  echo
  echo "[health]";      tail -n +1 "$HEALTH"      | sed -n '1,40p'
  echo
  echo "[integration]"; tail -n +1 "$INTEG"       | sed -n '1,40p'
} > "$SUMMARY"

# Copiar a OUTDIR (hasta 10 archivos)
out 01 status               "$STATUS"      >/dev/null
out 02 live-vs-local        "$LVL"         >/dev/null
out 03 remote-deep          "$RDEEP"       >/dev/null
out 04 health               "$HEALTH"      >/dev/null
out 05 fe-be-integration    "$INTEG"       >/dev/null
out 06 repo-clean           "$RCLEAN"      >/dev/null
out 07 code-clones          "$CLONES"      >/dev/null
out 08 verify               "$VERIFY"      >/dev/null
out 09 runtime              "$RUNTIME"     >/dev/null
out 10 SUMMARY              "$SUMMARY"     >/dev/null

echo "OK: pack10 listo en $OUTDIR (01-...-10-*.txt)"
