#!/usr/bin/env bash
set -euo pipefail
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"
OUT="${HOME}/.cache/p12/services.json"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$(dirname "$OUT")"
HOST="api.render.com"; PORT="443"

doh_ips(){ for u in \
 "https://1.1.1.1/dns-query?name=${HOST}&type=A" \
 "https://1.0.0.1/dns-query?name=${HOST}&type=A"
do curl -sS -H 'accept: application/dns-json' "$u" \
 | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' \
 | cut -d':' -f2 | tr -d '"'; done | sort -u; }

fetch_page(){ # $1=url $2=outpath
  local url="$1" ip ok=1
  while read -r ip; do
    if curl -fsS --resolve "${HOST}:${PORT}:${ip}" \
         -H "Authorization: Bearer ${RENDER_API_KEY}" \
         -H "Accept: application/json" "$url" -o "$2"; then ok=0; break; fi
  done < <(doh_ips)
  return $ok
}

echo "[" > "$OUT.tmp"
first=1
cursor=""
while :; do
  url="https://${HOST}/v1/services?limit=100"
  [[ -n "$cursor" ]] && url="${url}&cursor=${cursor}"
  fetch_page "$url" "$TMP/resp.json" || { echo "]" >> "$OUT.tmp"; mv "$OUT.tmp" "$OUT"; echo "OK: $OUT (incompleto)"; exit 0; }

  python - "$TMP/resp.json" "$TMP/items.json" "$TMP/next.txt" <<'PY'
import json,sys
raw=open(sys.argv[1],'r',encoding='utf-8').read()
try: data=json.loads(raw)
except Exception: data=[]
arr = data.get('data', data) if isinstance(data, dict) else data
items=[]; nxt=""
if isinstance(arr, list):
  for obj in arr:
    if isinstance(obj, dict):
      svc = obj.get('service', obj)
      if isinstance(svc, dict): items.append(svc)
      if isinstance(obj, dict) and 'cursor' in obj: nxt = obj['cursor']
open(sys.argv[2],'w',encoding='utf-8').write(json.dumps(items,ensure_ascii=False))
open(sys.argv[3],'w',encoding='utf-8').write(nxt or "")
PY

  # append chunk
  if [[ -s "$TMP/items.json" && "$(wc -c < "$TMP/items.json")" -gt 2 ]]; then
    [[ $first -eq 1 ]] && first=0 || echo "," >> "$OUT.tmp"
    sed '1s/^\[//; $s/\]$//' "$TMP/items.json" >> "$OUT.tmp"
  fi

  cursor="$(cat "$TMP/next.txt" || true)"
  [[ -z "$cursor" ]] && break
done
echo "]" >> "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
echo "OK: ${OUT}"
