#!/usr/bin/env bash
set -euo pipefail

CID="${1:-}"
[[ -n "$CID" ]] || { echo "Uso: $0 ca-pub-XXXXXXXXXXXXXXX"; exit 2; }

HTML="frontend/index.html"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="frontend/index.$TS.adsense.bak"
cp -f "$HTML" "$BAK"
echo "[adsense] Backup: $BAK"

python - <<'PY'
import io,re,sys,os
p="frontend/index.html"
cid=os.environ.get("P12_CID","")
s=io.open(p,"r",encoding="utf-8").read()
orig=s

tag=f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={cid}" crossorigin="anonymous"></script>'

# quitar duplicados previos del script de pagead2
s=re.sub(r'<script[^>]+pagead2\.googlesyndication\.com[^>]*></script>','',s,flags=re.I)

# insertar en <head> si no está
if cid and cid not in s:
    s=re.sub(r'</head>', tag+'\n</head>', s, count=1, flags=re.I)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[adsense] index.html actualizado")
else:
    print("[adsense] ya estaba OK")
PY
