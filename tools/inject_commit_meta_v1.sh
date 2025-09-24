#!/usr/bin/env bash
set -euo pipefail

HTML="frontend/index.html"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="frontend/index.$TS.commitmeta.bak"
cp -f "$HTML" "$BAK"
echo "[commit-meta] Backup: $BAK"

COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
BUILT_AT="$TS"

python - <<'PY'
import io, re, sys, os
p="frontend/index.html"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

def upsert_meta(s,name,val):
    rg=r'<meta[^>]+name=["\']%s["\'][^>]*>'%re.escape(name)
    tag=f'<meta name="{name}" content="{val}">'
    if re.search(rg,s,re.I):
        return re.sub(rg, tag, s, count=1, flags=re.I)
    # insert before </head>
    return re.sub(r'</head>', f'  {tag}\n</head>', s, count=1, flags=re.I)

commit=os.popen("git rev-parse HEAD 2>/dev/null").read().strip() or "unknown"
built=os.popen("date -u +%Y%m%d-%H%M%SZ").read().strip()

s=upsert_meta(s,"p12-commit",commit)
s=upsert_meta(s,"p12-built-at",built)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[commit-meta] index.html actualizado")
else:
    print("[commit-meta] ya estaba OK")
PY

echo "Listo."
