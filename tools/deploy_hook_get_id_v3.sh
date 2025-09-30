#!/usr/bin/env bash
set -euo pipefail
HOOK="${RENDER_DEPLOY_HOOK:?Uso: export RENDER_DEPLOY_HOOK='https://api.render.com/deploy/srv-...?...'}"
HOST="api.render.com"; PORT="443"
TMPDIR="${HOME}/.cache/p12"; mkdir -p "$TMPDIR"
HDR="$(mktemp -p "$TMPDIR" hdr-XXXX.txt)"
BODY="$(mktemp -p "$TMPDIR" body-XXXX.json)"
trap 'rm -f "$HDR" "$BODY"' EXIT
doh_ips(){ for u in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
  curl -sS -H 'accept: application/dns-json' "$u" | sed -n 's/.*"data":"\([0-9.]\+\)".*/\1/p'
done | sort -u; }
ok=1; for ip in $(doh_ips); do
  if curl -sS -X POST --resolve "${HOST}:${PORT}:${ip}" "$HOOK" -D "$HDR" -o "$BODY"; then ok=0; break; fi
done
[ $ok -eq 0 ] || { echo "ERROR: no pude hittear el HOOK" >&2; exit 2; }
sed -n '1,20p' "$HDR" >&2
python - <<'PY' "$BODY"
import json,sys
try:
  j=json.load(open(sys.argv[1])); did=j.get("deploy",{}).get("id")
  if not did: raise SystemExit(1)
  print(did)
except Exception: raise SystemExit(2)
PY
