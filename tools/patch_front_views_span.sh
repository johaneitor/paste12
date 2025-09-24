#!/usr/bin/env bash
set -euo pipefail

HTML="${1:-frontend/index.html}"
[[ -f "$HTML" ]] || HTML="index.html"
[[ -f "$HTML" ]] || { echo "No encuentro $HTML"; exit 1; }

cp -a "$HTML" "$HTML.bak.$(date +%s)"

# Reemplazo conservador: detecta el bloque meta con ❤ y 👁 y agrega el span en 👁
# Usamos una sustitución que tolere espacios.
tmp="$(mktemp)"
python - <<'PY' "$HTML" "$tmp"
import re, sys
src = open(sys.argv[1], 'r', encoding='utf-8').read()

def repl(m):
    block = m.group(0)
    # si ya tiene span.views, no tocamos
    if 'class="views"' in block:
        return block
    # intentar envolver el primer "👁" seguido de número
    block2 = re.sub(r'(👁\s*)(\d+)',
                    r'<span class="views">\1\2</span>',
                    block, count=1)
    return block2

pat = re.compile(r'<div class="meta">.*?</div>', re.S)
out = pat.sub(repl, src)
open(sys.argv[2], 'w', encoding='utf-8').write(out)
PY
mv "$tmp" "$HTML"

echo "✓ views span aplicado en $HTML"
