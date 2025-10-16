#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'MSG'
Usage: tools/audit_remote_vs_local_e2e_v1.sh BASE_URL [OUTDIR] [--allow-post] [--stress-posts]

Deep end-to-end audit comparing REMOTE (BASE_URL) vs LOCAL repo contents.
- Remote deep audit: headers, flags, deploy-stamp, health, API JSON, negatives, optional POSTs, rate-limit hints.
- Local vs Remote: HTML and assets comparison, negatives, normalized index diff (ignoring p12-commit meta).
- Extra: headers/CORS/OPTIONS and DB health prints.

Examples:
  tools/audit_remote_vs_local_e2e_v1.sh "https://paste12-rmsk.onrender.com" ./p12-e2e-out
  tools/audit_remote_vs_local_e2e_v1.sh "$BASE" ./p12-e2e-out --allow-post --stress-posts

Outputs under OUTDIR/p12-e2e-<timestamp>/
Main summary: E2E_SUMMARY.txt
MSG
}

[[ $# -lt 1 ]] && { usage; exit 1; }

BASE="${1%/}"
OUTROOT="${2:-./p12-e2e-out}"
shift || true
# If a second arg was provided, shift it
if [[ "${1-}x" != "x" && "${1-}" != --* ]]; then shift || true; fi

ALLOW_POST=false
STRESS_POSTS=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-post)   ALLOW_POST=true ;; 
    --stress-posts) STRESS_POSTS=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" ; usage; exit 1 ;;
  esac
  shift
done

TS="$(date -u +%Y%m%d-%H%M%SZ)"
PACK="${OUTROOT%/}/p12-e2e-${TS}"
mkdir -p "$PACK"

log(){ printf "[%s] %s\n" "$(date -u +%H:%M:%S)" "$*" | tee -a "$PACK/e2e-run.log" ; }

log "p12 E2E REMOTE VS LOCAL"
log "BASE: $BASE"
log "OUT:  $PACK"

# 1) Remote deep audit (non-destructive by default)
remote_args=("$BASE" "$PACK")
$ALLOW_POST && remote_args+=("--allow-post")
$ALLOW_POST && $STRESS_POSTS && remote_args+=("--stress-posts")

log "Running remote deep audit…"
if tools/audit_remote_deep_full_v1.sh "${remote_args[@]}" | tee -a "$PACK/remote-deep-run.log" ; then
  :
else
  log "WARN: remote deep audit returned non-zero; continuing"
fi
remote_deep_dir="$(ls -1dt "$PACK"/p12-deep-* 2>/dev/null | head -1 || true)"

# 2) Live vs Local (HTML/assets compare + negatives + normalized compare)
log "Running live-vs-local comparator…"
if tools/live_vs_local_v2.sh "$BASE" "$PACK" | tee -a "$PACK/live-vs-local-run.log" ; then
  :
else
  log "WARN: live-vs-local comparator returned non-zero; continuing"
fi
lvl_summary="$(ls -1t "$PACK"/live-vs-local-*-summary.txt 2>/dev/null | head -1 || true)"
if [[ -n "$lvl_summary" ]]; then
  lvl_base="${lvl_summary%-summary.txt}"
  lvl_remote_html="${lvl_base}-index-remote.html"
  lvl_local_html="${lvl_base}-index-local.html"
  lvl_assets_tsv="${lvl_base}-assets-compare.tsv"
  lvl_neg_file="${lvl_base}-negative.txt"
else
  lvl_base=""
  lvl_remote_html=""
  lvl_local_html=""
  lvl_assets_tsv=""
  lvl_neg_file=""
fi

# 3) Headers/CORS/OPTIONS/DB health capture
log "Capturing headers/CORS/OPTIONS and DB health…"
{ tools/check_headers_cors_rate_health_v1.sh "$BASE" ; } \
  > "$PACK/headers-cors-health.txt" 2>&1 || log "WARN: headers/CORS capture failed"

# 4) Create/View/Report checks (optional, guarded by --allow-post)
if $ALLOW_POST ; then
  if command -v jq >/dev/null 2>&1; then
    log "Running create/view/report checks (POST) …"
    { tools/check_create_view_report_v1.sh "$BASE" ; } \
      > "$PACK/create-view-report.txt" 2>&1 || log "WARN: create/view/report checks failed"
  else
    echo "jq not installed; skipping create/view/report checks." > "$PACK/create-view-report.txt"
  fi
else
  echo "SKIPPED: pass --allow-post to run create/view/report checks" > "$PACK/create-view-report.txt"
fi

# 5) Drift and equality indicators
remote_commit="$(curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p' | head -1 || true)"
if [[ -z "$remote_commit" && -f "$lvl_remote_html" ]]; then
  remote_commit="$(sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p' "$lvl_remote_html" | head -1 || true)"
fi
local_head="$(git rev-parse HEAD 2>/dev/null || echo)"
drift="unknown"
if [[ -n "$remote_commit" && -n "$local_head" ]]; then
  if [[ "$remote_commit" == "$local_head" ]]; then drift="aligned"; else drift="DRIFT"; fi
fi

index_equal_norm="unknown"
if [[ -f "$lvl_remote_html" && -f "$lvl_local_html" ]]; then
  if tools/html_compare_ignore_commit_v1.py "$lvl_remote_html" "$lvl_local_html" \
        | tee -a "$lvl_summary" | grep -q "index_equal_ignoring_commit: yes" ; then
    index_equal_norm="yes"
  else
    index_equal_norm="no"
  fi
fi

assets_status="unknown"; assets_total="unknown"
if [[ -f "$lvl_summary" ]]; then
  assets_status="$(grep -E '^assets_status:' "$lvl_summary" | awk '{print $2}' || true)"
  assets_total="$(grep -E '^assets_total:' "$lvl_summary" | awk '{print $2}' || true)"
fi

negatives_status="unknown"
if [[ -f "$lvl_neg_file" ]]; then
  grep -q "NEGATIVOS_OK" "$lvl_neg_file" && negatives_status="OK" || negatives_status="CHECK"
fi

# 6) Compose E2E summary
E2E_SUMMARY="$PACK/E2E_SUMMARY.txt"
{
  echo "p12 E2E REMOTE VS LOCAL - $TS"
  echo "BASE: $BASE"
  echo
  short(){ printf "%s" "${1:0:7}"; }
  echo "drift: $drift (remote: $(short "$remote_commit") vs local: $(short "$local_head"))"
  echo "index_equal_ignoring_commit: $index_equal_norm"
  echo "assets_status: $assets_status (total: $assets_total)"
  echo "negatives: $negatives_status"
  echo
  echo "-- Artifacts --"
  [[ -n "$remote_deep_dir" ]] && echo "remote_deep_dir: $remote_deep_dir" || true
  [[ -n "$lvl_summary"   ]] && echo "live_vs_local_summary: $lvl_summary" || true
  [[ -n "$lvl_assets_tsv" ]] && echo "assets_compare: $lvl_assets_tsv" || true
  [[ -n "$lvl_remote_html" ]] && echo "index_remote: $lvl_remote_html" || true
  [[ -n "$lvl_local_html"  ]] && echo "index_local : $lvl_local_html" || true
  echo "headers_cors: $PACK/headers-cors-health.txt"
  echo "create_view_report: $PACK/create-view-report.txt"
  if [[ -n "$remote_deep_dir" && -f "$remote_deep_dir/summary.txt" ]]; then
    echo "remote_deep_summary: $remote_deep_dir/summary.txt"
  fi
} | tee "$E2E_SUMMARY" >/dev/null

log "DONE. Main summary -> $(basename "$E2E_SUMMARY")"
log "Artifacts under: $PACK"
