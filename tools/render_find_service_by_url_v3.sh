#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://<servicio>.onrender.com}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"
OUT="${HOME}/.cache/p12/services.json"
tools/render_fetch_services_v1.sh "$OUT"

python - "$BASE" "$OUT" <<'PY'
import json, sys
base=sys.argv[1].rstrip('/')
services=json.load(open(sys.argv[2]))

by_url=[s for s in services if (s.get("url") or "").rstrip('/')==base]
if by_url:
    s=by_url[0]
    print(f'export RENDER_SERVICE_ID="{s.get("id")}"')
    print(f'echo "OK: service {s.get("id")} ({s.get("name")}) por url={base}"')
    sys.exit(0)

# fallback repo/main (tu repo + branch main)
cands=[s for s in services
       if (s.get("repo") or "").endswith("johaneitor/paste12")
       and s.get("branch")=="main"
       and s.get("type")=="web_service"]
if not cands:
    print('echo "ERROR: no encontré service por url ni por repo/main" >&2; exit 2')
    sys.exit(0)

# si hay varios, elegimos el que tenga name parecido a 'paste12' y mostramos hint
cands_sorted=sorted(cands, key=lambda s: 0 if 'paste12' in (s.get('name') or '').lower() else 1)
s=cands_sorted[0]
print(f'export RENDER_SERVICE_ID="{s.get("id")}"')
print(f'echo "WARN: url no coincide; usando {s.get("id")} name={s.get("name")} repo={s.get("repo")} branch={s.get("branch")}"')
PY
