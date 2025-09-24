#!/usr/bin/env bash
set -euo pipefail

HTML="frontend/index.html"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="frontend/index.$TS.dedupe.bak"
cp -f "$HTML" "$BAK"
echo "[dedupe] Backup: $BAK"

python - <<'PY'
import io, re
p="frontend/index.html"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

# Mantener primer <title>, borrar extras
titles = list(re.finditer(r'<title[^>]*>.*?</title>', s, flags=re.I|re.S))
if len(titles)>1:
    keep = titles[0].group(0)
    s = re.sub(r'<title[^>]*>.*?</title>', '', s, flags=re.I|re.S)
    s = re.sub(r'</head>', keep+'\n</head>', s, count=1, flags=re.I)

# Un solo meta viewport
vps = list(re.finditer(r'<meta[^>]+name=["\']viewport["\'][^>]*>', s, flags=re.I))
if len(vps)>1:
    # dejar el primero y quitar el resto
    first = vps[0].group(0)
    s = re.sub(r'<meta[^>]+name=["\']viewport["\'][^>]*>', '', s, flags=re.I)
    # reinsertar el primero al inicio de <head>
    s = re.sub(r'(<head[^>]*>)', r'\1\n  '+first, s, count=1, flags=re.I)

# Evitar doble H1 Paste12 (si hay dos h1 con el mismo texto)
h1s = list(re.finditer(r'<h1[^>]*>(.*?)</h1>', s, flags=re.I|re.S))
if len(h1s)>1:
    texts=[re.sub(r'\\s+',' ',h.group(1)).strip().lower() for h in h1s]
    # si hay duplicados exactos, quitar los siguientes
    if len(set(texts))<len(texts):
        seen=set()
        parts=[]
        idx=0
        for m in h1s:
            parts.append(s[idx:m.start()])
            txt=re.sub(r'\\s+',' ',m.group(1)).strip().lower()
            if txt in seen:
                # drop duplicate
                pass
            else:
                parts.append(m.group(0))
                seen.add(txt)
            idx=m.end()
        parts.append(s[idx:])
        s=''.join(parts)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[dedupe] index.html normalizado")
else:
    print("[dedupe] nada que cambiar")
PY

echo "Listo."
