#!/usr/bin/env bash
set -euo pipefail

HTML="frontend/index.html"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }
bak="frontend/index.$(date -u +%Y%m%d-%H%M%SZ).seo.bak"
cp -f "$HTML" "$bak"
echo "[seo] Backup: $bak"

python - <<'PY'
import io, re
p="frontend/index.html"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

def inject(meta_tag, test_re):
    global s
    if not re.search(test_re, s, re.I):
        s = s.replace("<head>", "<head>\n  "+meta_tag+"\n", 1)

inject('<meta name="description" content="Paste12: notas rápidas con enlaces para compartir, likes, vistas y caducidad automática. Ligero, privado y sin cuentas.">', r'<meta\s+name=["\']description["\']')
inject('<meta property="og:title" content="Paste12">', r'property=["\']og:title["\']')
inject('<meta property="og:description" content="Notas rápidas con likes, vistas y expiración automática.">', r'property=["\']og:description["\']')
inject('<meta property="og:type" content="website">', r'property=["\']og:type["\']')
inject('<link rel="canonical" href="https://paste12-rmsk.onrender.com/">', r'rel=["\']canonical["\']')

# Evitar títulos duplicados (mantener el primero)
parts = re.split(r'(<title>.*?</title>)', s, flags=re.I|re.S)
if parts.count(parts[1])>1:
    # guarda solo el primero
    first = True
    out=[]
    for i,ch in enumerate(parts):
        if i%2==1: # tag title
            if first:
                out.append(ch)
                first=False
            else:
                continue
        else:
            out.append(ch)
    s="".join(out)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[seo] aplicado OK")
else:
    print("[seo] ya estaba OK")
PY
