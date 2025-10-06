#!/usr/bin/env bash
set -Eeuo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"
ts="$(date -u +%Y%m%d-%H%M%SZ)"
root="$HOME/tmp/p12-pack10-$ts"; mkdir -p "$root"
out="$OUTDIR/p12-pack10-$ts"; mkdir -p "$out"

# 1) status
tools/p12_status_now_v4.sh "$BASE" > "$out/01-status.txt" || true

# 2) verify (genera 4 archivos)
tools/verify_all_behaviors_v7.sh "$BASE" "$out" || true

# 3) live vs local (si existe)
if [[ -x tools/live_vs_local_v1.sh ]]; then
  tools/live_vs_local_v1.sh "$BASE" "$out" >/dev/null 2>&1 || true
  # normalizamos nombres
  for f in "$out"/live-vs-local-*summary.txt "$out"/live-vs-local-*negative.txt; do
    [[ -f "$f" ]] && cp -f "$f" "$out/02-live-vs-local.txt" && break
  done
fi

# 4) remote deep (si existe)
if [[ -x tools/audit_remote_deep_v4.sh ]]; then
  tools/audit_remote_deep_v4.sh "$BASE" "$out" >/dev/null 2>&1 || true
  # pick el último resumen
  last="$(ls -1t "$out"/paste12-remote-deep-*.txt 2>/dev/null | head -1 || true)"
  [[ -n "$last" ]] && cp -f "$last" "$out/03-remote-deep.txt"
fi

# 5) cleanliness (si existe)
if [[ -x tools/audit_repo_cleanliness_v4.sh ]]; then
  tools/audit_repo_cleanliness_v4.sh "$BASE" >/dev/null 2>&1 || true
fi
# volcamos últimos clones/cleanliness si están
for cand in "$HOME"/Download/*repo-audit-*.txt "$HOME"/Download/*clones-*.txt; do
  [[ -f "$cand" ]] && cp -f "$cand" "$out/" || true
done

# 6) health snapshot simple
{
  echo "== HEALTH SNAPSHOT @ $ts =="
  echo "BASE: $BASE"
  curl -sD - -o /dev/null "$BASE/api/health" | sed 's/\r$//'
} > "$out/04-health.txt" || true

# 7) resumen global
{
  echo "== PACK10 SUMMARY @ $ts =="
  echo "BASE: $BASE"
  echo "Contenido de $out:"
  ls -1 "$out" | sed 's/^/ - /'
} > "$out/10-SUMMARY.txt"

echo "OK: pack en $out"
ls -1 "$out" | sed 's/^/  /'
