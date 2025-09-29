#!/usr/bin/env bash
set -euo pipefail
# Si definís P12_OUTDIR, lo usamos tal cual.
if [[ -n "${P12_OUTDIR:-}" ]]; then
  echo "$P12_OUTDIR"
  exit 0
fi
candidates=( "$HOME/storage/downloads" "/sdcard/Download" "/storage/emulated/0/Download" )
for d in "${candidates[@]}"; do
  if [[ -d "$d" && -w "$d" ]]; then
    echo "$d/paste12-audits"
    exit 0
  fi
done
# Fallback a HOME (avisa al caller si quiere)
echo "$HOME/Download/paste12-audits"
exit 0
