#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"

OUT_TXT="$DEST/deploy-env-$TS.txt"
OUT_JSN="$DEST/deploy-env-$TS.json"

# 1) Cabeceras y rutas clave
{
  echo "timestamp: $TS"
  echo "base: $BASE"
  echo; echo "== HEADERS / (index) =="; curl -sSI "$BASE/" | sed -n '1,30p'
  echo; echo "== HEADERS /index.html =="; curl -sSI "$BASE/index.html" | sed -n '1,30p' || true
  echo; echo "== HEADERS /?nosw=1 =="; curl -sSI "$BASE/?nosw=1" | sed -n '1,30p' || true
  echo; echo "== HEALTH /api/health =="; curl -sS "$BASE/api/health" || true; echo
} > "$OUT_TXT"

# 2) Intentar snapshot de entorno (endpoints diagnósticos si existen)
ok=0
for P in /diag/import /diag/env /api/diag/import ; do
  if curl -fsS "$BASE$P" -o "$OUT_JSN" 2>/dev/null; then
    echo >> "$OUT_TXT"
    echo "== ENV SNAPSHOT ($P) -> $(basename "$OUT_JSN") ==" >> "$OUT_TXT"
    ok=1
    break
  fi
done
[ "$ok" = "0" ] && echo "{}" > "$OUT_JSN"

# 3) Resumen legible (sin jq): Python embebido
python - "$OUT_JSN" >> "$OUT_TXT" <<'PY'
import json, os, sys
p=sys.argv[1]
try:
  data=json.load(open(p,'r',encoding='utf-8'))
except Exception:
  data={}
print("\n== RUNTIME SUMMARY ==")
py=data.get('python',{}) or data.get('runtime',{})
print(f"python_version: {py.get('version') or py.get('python_version') or 'n/a'}")
print(f"platform: {py.get('platform') or data.get('platform') or 'n/a'}")
print(f"timezone: {data.get('tz') or data.get('timezone') or 'n/a'}")
env=data.get('env') or data.get('environ') or {}
# Lista blanca de env que queremos mirar
keys = [
  "FORCE_BRIDGE_INDEX","WEB_CONCURRENCY","GUNICORN_WORKERS","GUNICORN_CMD_ARGS",
  "RENDER","RENDER_EXTERNAL_HOSTNAME","PORT","PYTHONHASHSEED","TMPDIR","HOME",
  "DATABASE_URL","TZ","PYTHONUNBUFFERED"
]
print("\n== ENV (whitelist) ==")
for k in keys:
  v = env.get(k, os.environ.get(k, ""))
  if not v: print(f"- {k}: (unset)")
  elif k=="DATABASE_URL":
    # proteger credenciales: mostrar solo esquema y host
    show=v
    try:
      import re
      m=re.match(r'^([a-z0-9+]+)://([^@]+@)?([^/:?]+)', v, re.I)
      if m: show=f"{m.group(1)}://***@{m.group(3)}"
    except Exception: pass
    print(f"- {k}: {show}")
  else:
    print(f"- {k}: {v}")

# Pequeñas heurísticas útiles
print("\n== NOTES ==")
idx_headers=open(sys.argv[0], 'r', encoding='utf-8', errors='ignore')
PY

echo "OK: $OUT_TXT"
echo "OK: $OUT_JSN"
