#!/usr/bin/env bash
set -euo pipefail
HOOK="${RENDER_DEPLOY_HOOK:?Uso: export RENDER_DEPLOY_HOOK='https://api.render.com/deploy/srv-...?...'}"
HOST="api.render.com"; PORT="443"
TMPDIR="${HOME}/.cache/p12"; mkdir -p "$TMPDIR"
HDR="$(mktemp -p "$TMPDIR" hdr-XXXX.txt)"
BODY="$(mktemp -p "$TMPDIR" body-XXXX.json)"
trap 'rm -f "$HDR" "$BODY"' EXIT

while IFS= read -r ip; do
  if curl -sS -X POST --resolve "${HOST}:${PORT}:${ip}" "$HOOK" -D "$HDR" -o "$BODY"; then
    break
  fi
done < <(tools/p12_doh_ips_v1.sh "$HOST")

sed -n '1,20p' "$HDR" >&2

python - <<'PY' "$BODY"
import json,sys
try:
  j=json.load(open(sys.argv[1])); did=j.get("deploy",{}).get("id")
  if not did: raise SystemExit(1)
  print(did)
except Exception: raise SystemExit(2)
PY
