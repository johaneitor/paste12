#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-}"
if [[ -z "$OUTDIR" ]]; then
  OUTDIR="$(tools/_resolve_outdir.sh || echo "$HOME/Download/paste12-audits")"
fi
exec bash tools/audit_remote_deep_v4.sh "$BASE" "$OUTDIR"
