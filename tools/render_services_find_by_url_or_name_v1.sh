#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://<servicio>.onrender.com}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"

HOST="api.render.com"; PORT="443"
TMP="${HOME}/.cache/p12"; mkdir -p "$TMP"
OUT_JSON="$TMP/services-all.json"

# --- DoH robusto (una IP por línea) ---
tools/p12_doh_ips_v1.sh "${HOST}" >/dev/null 2>&1 || {
  cat > tools/p12_doh_ips_v1.sh <<'LIB'
#!/usr/bin/env bash
set -euo pipefail
HOST="${1:?Uso: $0 HOSTNAME}"
{
  curl -sS -H 'accept: application/dns-json' "https://1.1.1.1/dns-query?name=${HOST}&type=A" || true
  echo
  curl -sS -H 'accept: application/dns-json' "https://1.0.0.1/dns-query?name=${HOST}&type=A" || true
} | tr ',' '\n' \
  | sed -n 's/.*"data":"\([0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}\)".*/\1/p' \
  | awk '!seen[$0]++'
LIB
  chmod +x tools/p12_doh_ips_v1.sh
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

# --- Paginación por cursor y aplanado service{} ---
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

# --- Buscar match exacto por URL ---
python - "$BASE" "$OUT_JSON" <<'PY'
import json,sys,re
base=sys.argv[1].rstrip('/')
services=json.load(open(sys.argv[2],'r',encoding='utf-8'))
# 1) Match exacto por url
for s in services:
    url=(s.get('url') or '').rstrip('/')
    if url==base:
        sid=s.get('id'); name=s.get('name')
        print(f'export RENDER_SERVICE_ID="{sid}"')
        print(f'export RENDER_DEPLOY_HOOK="https://api.render.com/deploy/{sid}?key=<<TU_KEY>>"')
        print(f'echo "OK: match por URL → {sid} ({name}) url={url}"')
        sys.exit(0)
# 2) Candidatos por nombre/url parcial o repo/main
def norm(t): return (t or '').lower()
subs=[norm(base), 'paste12', 'rmsk']
cands=[]
for s in services:
    if s.get('type')!='web_service': continue
    row=(s.get('id'), s.get('name') or '', s.get('url') or '', s.get('repo') or '', s.get('branch') or '')
    if any(x in norm(row[1]) or x in norm(row[2]) for x in subs) or (row[3].endswith('johaneitor/paste12') and row[4]=='main'):
        cands.append(row)
print("# NO_MATCH_URL. Candidatos (id | name | url | repo | branch):")
for r in cands: print(f"# {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]}")
print('echo "ERROR: SERVICE_NOT_VISIBLE (la API key no ve un servicio con esa URL). Usá el HOOK real desde el Dashboard del servicio que sirve la URL dada." >&2; exit 2')
PY
