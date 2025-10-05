#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
DIR="$(mktemp -d "$HOME/tmp/p12-pack10-$TS.XXXX")"
mkdir -p "$DIR"
tools/live_vs_local_v1.sh     "$BASE" "$DIR"    >/dev/null || true
tools/audit_remote_deep_v4.sh "$BASE" "$DIR"    >/dev/null || true
tools/audit_full_stack_v3.sh  "$BASE" "$DIR"    >/dev/null || true
tools/audit_repo_cleanliness_v4.sh            "$DIR"       >/dev/null || true
tools/audit_integration_sync_v1.sh "$BASE" "$DIR"          >/dev/null || true
# Selección a 10 textos máximo
pack="$OUT/p12-pack10-$TS"
mkdir -p "$pack"
cp -f "$DIR"/live-vs-local-*summary.txt      "$pack/01-live-vs-local.txt" || true
cp -f "$DIR"/paste12-remote-deep-*Z.txt      "$pack/02-remote-deep.txt"   || true
cp -f "$DIR"/runtime-positive-*Z.txt         "$pack/03-runtime-positive.txt" || true
cp -f "$DIR"/runtime-negative-*Z.txt         "$pack/04-runtime-negative.txt" || true
cp -f "$DIR"/runtime-deploy-*Z.txt           "$pack/05-runtime-deploy.txt" || true
cp -f "$DIR"/repo-audit-*Z.txt               "$pack/06-repo-audit.txt" || true
cp -f "$DIR"/clones-*Z.txt                   "$pack/07-code-clones.txt" || true
# health e integración
cp -f "$DIR"/health-*Z.txt                   "$pack/08-health.txt" 2>/dev/null || true
cp -f "$DIR"/integration-*Z.txt              "$pack/09-integration-sync.txt" 2>/dev/null || true
# resumen maestro
{
  echo "== p12: resumen @ $TS =="
  sed -n '1,80p' "$pack/01-live-vs-local.txt" 2>/dev/null || true
  echo
  sed -n '1,120p' "$pack/03-runtime-positive.txt" 2>/dev/null || true
  echo
  sed -n '1,120p' "$pack/04-runtime-negative.txt" 2>/dev/null || true
} > "$pack/10-SUMMARY.txt"
echo "OK: pack en $pack"
