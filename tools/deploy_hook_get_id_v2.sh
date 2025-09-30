#!/usr/bin/env bash
set -euo pipefail
HOOK="${RENDER_DEPLOY_HOOK:?Uso: export RENDER_DEPLOY_HOOK='https://api.render.com/deploy/srv-...?...'}"
HOST="api.render.com"; PORT="443"
TMPDIR="${HOME}/.cache/p12"; mkdir -p "$TMPDIR"
HDR="$(mktemp -p "$TMPDIR" hdr-XXXX.txt)"
BODY="$(mktemp -p "$TMPDIR" body-XXXX.json)"
trap 'rm -f "$HDR" "$BODY"' EXIT

doh_ips(){ for u in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
  curl -sS -H 'accept: application/dns-json' "$u" | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' | cut -d':' -f2 | tr -d '"'
done | sort -u; }

ok=1
for ip in $(doh_ips); do
  if curl -sS -X POST --resolve "${HOST}:${PORT}:${ip}" "$HOOK" -D "$HDR" -o "$BODY"; then ok=0; break; fi
done
[ $ok -eq 0 ] || { echo "ERROR: no pude hittear el HOOK" >&2; exit 2; }

# Log de headers a stderr (informativo)
sed -n '1,20p' "$HDR" >&2

# Imprimir SOLO el deploy.id por stdout (para capturar con $(...))
python - <<'PY' "$BODY"
import json,sys; j=json.load(open(sys.argv[1])); d=j.get("deploy") or {}
did=d.get("id"); 
if not did: raise SystemExit(1)
print(did)
PY
