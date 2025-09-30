#!/usr/bin/env bash
set -euo pipefail
: "${RENDER_API_KEY:?export RENDER_API_KEY=...}"
: "${RENDER_SERVICE_ID:?export RENDER_SERVICE_ID=srv-...}"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/services/${RENDER_SERVICE_ID}"

TMPDIR="${HOME}/.cache/p12"; mkdir -p "$TMPDIR"
HEADERS="$(mktemp -p "$TMPDIR" p12-hdr-XXXX.txt)"
BODY="$(mktemp -p "$TMPDIR" p12-svc-XXXX.json)"
trap 'rm -f "$HEADERS" "$BODY"' EXIT

doh_ips(){ for u in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
  curl -sS -H 'accept: application/dns-json' "$u" \
  | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' | cut -d':' -f2 | tr -d '"'
done | sort -u; }

ok=1
while IFS= read -r ip; do
  if curl -sS --resolve "${HOST}:${PORT}:${ip}" -D "$HEADERS" -H "Authorization: Bearer ${RENDER_API_KEY}" \
      -H "Accept: application/json" "$URL" -o "$BODY"; then ok=0; break; fi
done < <(doh_ips)
[[ $ok -eq 0 ]] || { echo "ERROR: no pude consultar Service (API)"; exit 2; }

python - <<'PY'
import json,sys
with open(sys.argv[1]) as f: j=json.load(f)
print("== SERVICE ==")
print("id:", j.get("id"))
print("name:", j.get("name"))
print("type:", j.get("type"))
print("url:", j.get("url"))
print("repo:", j.get("repo"))
print("branch:", j.get("branch"))
PY
"$BODY"
