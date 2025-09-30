#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://<servicio>.onrender.com}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=...}"
HOST="api.render.com"; PORT="443"
LIST_URL="https://${HOST}/v1/services?limit=200"

doh_ips(){ for u in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
  curl -sS -H 'accept: application/dns-json' "$u" | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' | cut -d':' -f2 | tr -d '"'
done | sort -u; }

fetch_list(){ while IFS= read -r ip; do
  curl -sS --resolve "${HOST}:${PORT}:${ip}" -H "Authorization: Bearer ${RENDER_API_KEY}" -H "Accept: application/json" "$LIST_URL" && return 0
done < <(doh_ips); return 1; }

json="$(fetch_list)" || { echo "echo 'ERROR: no pude listar servicios' >&2; exit 2"; exit 0; }

# 1) Intento: match directo por campo "url" (si viniera)
code=$(P12_JSON="$json" P12_BASE="$BASE" python - <<'PY' || true)
import os, json
arr=json.loads(os.environ['P12_JSON']); base=os.environ['P12_BASE'].rstrip('/')
for s in arr:
  url=(s.get("url") or "").rstrip('/')
  if url and url==base:
    print(f'export RENDER_SERVICE_ID="{s.get("id")}"')
    print(f'echo "OK: service {s.get("id")} ({s.get("name")}) por url={url}"')
    raise SystemExit(0)
raise SystemExit(1)
PY
if [ $? -eq 0 ] && [ -n "$code" ]; then echo "$code"; exit 0; fi

# 2) Fallback: por repo/branch (usamos tu repo + main)
code=$(P12_JSON="$json" python - <<'PY' || true)
import os, json
arr=json.loads(os.environ['P12_JSON'])
cands=[s for s in arr if (s.get("repo") or "").endswith("johaneitor/paste12") and (s.get("branch")=="main")]
if not cands:
  print("echo 'ERROR: no encontré service por repo/branch' >&2; exit 2")
else:
  s=cands[0]
  print(f'export RENDER_SERVICE_ID="{s.get("id")}"')
  print(f'echo "OK: service {s.get("id")} ({s.get("name")}) por repo={s.get("repo")} branch={s.get("branch")}"')
PY
echo "$code"
