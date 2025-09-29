#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE OUTDIR}"
OUTDIR="${2:-}"
if [[ -z "$OUTDIR" ]]; then
  # fallback inteligente si no pasás OUTDIR
  for d in "$HOME/storage/downloads" "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download"; do
    [[ -d "$d" && -w "$d" ]] && OUTDIR="$d" && break
  done
fi
mkdir -p "$OUTDIR"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

# helpers inline
code(){ curl -fsS -o /dev/null -w "%{http_code}" "$@"; }
body(){ curl -fsS "$@"; }
headers(){ curl -fsSI "$@"; }

# deploy-probe (auto /api/deploy-stamp o meta p12-commit)
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(curl -fsSL "$BASE/api/deploy-stamp" 2>/dev/null | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p' || true)"
[[ -z "${REMOTE:-}" ]] && REMOTE="$(curl -fsSL "$BASE" 2>/dev/null | sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
{
  echo "# deploy_probe_v3"
  echo "remote: ${REMOTE:-unknown}"
  echo "local : $LOCAL"
} | tee "$OUTDIR/runtime-deploy-$TS.txt" >/dev/null

PASS=0; FAIL=0; ok(){ echo "OK  - $1"; PASS=$((PASS+1)); }; ko(){ echo "FAIL- $1"; FAIL=$((FAIL+1)); }

[[ "$(code "$BASE")" == "200" ]] && ok "/ 200" || ko "/ 200"
IDX="$(body "$BASE")"
grep -qi 'name="p12-commit"' <<<"$IDX" && ok "index p12-commit" || ko "index p12-commit"
grep -qi 'p12-safe-shim' <<<"$IDX" && ok "p12-safe-shim" || ko "p12-safe-shim"
( grep -qi 'data-single="' <<<"$IDX" || grep -qi 'name="p12-single"' <<<"$IDX" ) && ok "single-detector" || ko "single-detector"
[[ "$(code "$BASE/terms")" == "200" ]] && ok "/terms 200" || ko "/terms 200"
[[ "$(code "$BASE/privacy")" == "200" ]] && ok "/privacy 200" || ko "/privacy 200"
H="$(body "$BASE/health" || true)"; if [[ -n "$H" ]] && grep -qi '"api":\s*true' <<<"$H"; then ok "/health api:true"; else ok "/health opcional"; fi
CC="$(code -X OPTIONS "$BASE/api/notes")"; [[ "$CC" == "204" || "$CC" == "200" ]] && ok "preflight /api/notes" || ko "preflight /api/notes"
ANH="$(headers "$BASE/api/notes?limit=10")"; [[ "$(code "$BASE/api/notes?limit=10")" == "200" ]] && ok "/api/notes 200" || ko "/api/notes 200"
grep -qi 'content-type: application/json' <<<"$ANH" && ok "api/notes JSON" || ko "api/notes content-type"
grep -qE '^link:.*rel="next"' <<<"$ANH" && ok "Link rel=next" || ko "Link rel=next"
DSC="$(code "$BASE/api/deploy-stamp")"; if [[ "$DSC" == "200" ]]; then DSB="$(body "$BASE/api/deploy-stamp")"; grep -qi '"commit"' <<<"$DSB" && ok "deploy-stamp" || ko "deploy-stamp"; else ok "deploy-stamp opcional"; fi
LEN="$(printf "%s" "$IDX" | wc -c)"; (( LEN>=15360 && LEN<=122880 )) && ok "index peso ok ($LEN)" || ko "index peso ($LEN)"
IH="$(headers "$BASE")"; grep -qi 'content-type: text/html' <<<"$IH" && ok "index content-type" || ko "index content-type"
grep -q 'p12FetchJson' <<<"$IDX" && ok "p12FetchJson" || ko "p12FetchJson"
( grep -qi '^etag:' <<<"$IH" || grep -qi '^last-modified:' <<<"$IH" ) && ok "cache header" || ko "cache header"

{
  echo "# test_suite_all (16 checks esperados)"
  echo "PASS=$PASS FAIL=$FAIL"
} | tee "$OUTDIR/runtime-positive-$TS.txt" >/dev/null

ID="999999999"
like="$(curl -fsS -X POST  -o /dev/null -w "%{http_code}" "$BASE/api/notes/$ID/like")"
view_get="$(curl -fsS -X GET   -o /dev/null -w "%{http_code}" "$BASE/api/notes/$ID/view")"
view_post="$(curl -fsS -X POST  -o /dev/null -w "%{http_code}" "$BASE/api/notes/$ID/view")"
report="$(curl -fsS -X POST  -o /dev/null -w "%{http_code}" "$BASE/api/notes/$ID/report")"
echo "negativos: like=$like view(GET/POST)=$view_get/$view_post report=$report" \
  | tee "$OUTDIR/runtime-negative-$TS.txt" >/dev/null

echo "Artefactos en: $OUTDIR"
ls -1 "$OUTDIR"/runtime-*"$TS"*.txt 2>/dev/null | sed 's/^/  /' || true
