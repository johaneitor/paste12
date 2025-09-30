#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://<servicio>.onrender.com}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"
HOST="api.render.com"; PORT="443"
TMP="${HOME}/.cache/p12"; mkdir -p "$TMP"
OUT_JSON="$TMP/services-all.json"; OUT_LOG="$TMP/services-find.log"

tools/p12_doh_ips_v1.sh "${HOST}" >/dev/null 2>&1 || {
  echo "ERROR: falta tools/p12_doh_ips_v1.sh"; exit 0;
}

fetch_page(){ # $1=url $2=outfile → 0/1
  local url="$1" ip
  while IFS= read -r ip; do
    if curl -fsS --resolve "${HOST}:${PORT}:${ip}" \
      -H "Authorization: Bearer ${RENDER_API_KEY}" -H "Accept: application/json" \
      "$url" -o "$2"; then return 0; fi
  done < <(tools/p12_doh_ips_v1.sh "$HOST")
  return 1
}

echo "[" > "$OUT_JSON.tmp"; first=1; cursor=""
while :; do
  url="https://${HOST}/v1/services?limit=100"
  [[ -n "$cursor" ]] && url="${url}&cursor=${cursor}"
  fetch_page "$url" "$TMP/resp.json" || break
  python - "$TMP/resp.json" "$TMP/chunk.json" "$TMP/next.txt" <<'PY'
import json,sys
raw=open(sys.argv[1],'r',encoding='utf-8').read()
try: data=json.loads(raw)
except: data=[]
arr = data.get('data', data) if isinstance(data, dict) else data
items=[]; nxt=""
if isinstance(arr,list):
  for obj in arr:
    svc = obj.get('service', obj) if isinstance(obj,dict) else None
    if isinstance(svc,dict): items.append(svc)
    c = obj.get('cursor') if isinstance(obj,dict) else None
    if c: nxt=c
open(sys.argv[2],'w',encoding='utf-8').write(json.dumps(items,ensure_ascii=False))
open(sys.argv[3],'w',encoding='utf-8').write(nxt or "")
PY
  if [[ -s "$TMP/chunk.json" && "$(wc -c < "$TMP/chunk.json")" -gt 2 ]]; then
    [[ $first -eq 1 ]] && first=0 || echo "," >> "$OUT_JSON.tmp"
    sed '1s/^\[//; $s/\]$//' "$TMP/chunk.json" >> "$OUT_JSON.tmp"
  fi
  cursor="$(cat "$TMP/next.txt" 2>/dev/null || true)"
  [[ -z "$cursor" ]] && break
done
echo "]" >> "$OUT_JSON.tmp"; mv "$OUT_JSON.tmp" "$OUT_JSON"

python - "$BASE" "$OUT_JSON" "$OUT_LOG" <<'PY'
import json,sys,urllib.parse
base=sys.argv[1].rstrip('/')
services=json.load(open(sys.argv[2],'r',encoding='utf-8'))
log=open(sys.argv[3],'w',encoding='utf-8')

def host(u):
  try: return urllib.parse.urlparse(u).netloc.lower()
  except: return ''

base_host=host(base)

def svc_url(s):
  sd=s.get('serviceDetails') or {}
  return (s.get('url') or sd.get('url') or '').rstrip('/')

def svc_domains(s):
  sd=s.get('serviceDetails') or {}
  return sd.get('customDomains') or []

# 1) Match exacto por URL o por host (incluye dominios custom)
for s in services:
  if s.get('type')!='web_service': continue
  url=svc_url(s)
  urls=[url] + [("https://"+d).rstrip('/') for d in svc_domains(s)]
  hosts=set([host(u) for u in urls if u])
  if base in urls or (base_host and base_host in hosts):
    sid=s.get('id'); name=s.get('name')
    print(f'export RENDER_SERVICE_ID="{sid}"')
    print(f'export RENDER_DEPLOY_HOOK="https://api.render.com/deploy/{sid}?key=<<TU_KEY>>"')
    print(f'echo "OK: match por URL/host → {sid} ({name}) url={url} domains={','.join(svc_domains(s)) or "[]"}"')
    log.write(f"MATCH {sid} {name} {url}\n"); log.close()
    sys.exit(0)

# 2) Lista de candidatos útiles (no corta la shell)
def norm(t): return (t or '').lower()
subs=[norm(base), 'paste12', 'rmsk']
cands=[]
for s in services:
  if s.get('type')!='web_service': continue
  url=svc_url(s); dom=svc_domains(s)
  row=(s.get('id'), s.get('name') or '', url, ','.join(dom) or '[]', s.get('repo') or '', s.get('branch') or '')
  if any(x in norm(row[1]) or x in norm(row[2]) for x in subs) or (row[4].endswith('johaneitor/paste12') and row[5]=='main'):
    cands.append(row)

print("# NO_MATCH_URL. Revisá ~/.cache/p12/services-find.log y la lista debajo.")
log.write("NO_MATCH_URL\n"); 
for r in cands:
  line=f"{r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]}\n"
  print("#", line.strip()); log.write(line)
log.close()
PY
