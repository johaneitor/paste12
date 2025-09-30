#!/usr/bin/env bash
set -euo pipefail
: "${RENDER_API_KEY:?export RENDER_API_KEY=...}"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/services?limit=200"

doh_ips(){ for u in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
  curl -sS -H 'accept: application/dns-json' "$u" \
  | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' | cut -d':' -f2 | tr -d '"'
done | sort -u; }

fetch_json(){ 
  while IFS= read -r ip; do
    curl -sS --resolve "${HOST}:${PORT}:${ip}" \
      -H "Authorization: Bearer ${RENDER_API_KEY}" -H "Accept: application/json" \
      "$URL" && return 0
  done < <(doh_ips)
  return 1
}

json="$(fetch_json)" || { echo "ERROR: no pude listar servicios (API)"; exit 2; }

P12_JSON="$json" python - <<'PY'
import os, json
arr = json.loads(os.environ['P12_JSON'])
print("id,name,type,url,repo,branch")
for s in arr:
    print("{id},{name},{type},{url},{repo},{branch}".format(
        id=s.get("id"), name=s.get("name"), type=s.get("type"),
        url=s.get("url"), repo=s.get("repo"), branch=s.get("branch")))
PY
