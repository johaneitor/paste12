#!/usr/bin/env bash
set -euo pipefail
idx="backend/static/index.html"
[[ -f "$idx" ]] || { echo "No existe $idx"; exit 1; }
cp -f "$idx" "$idx.bak.$(date -u +%Y%m%d-%H%M%SZ)"
head="$(git rev-parse HEAD)"

# Asegurar data-single="1" en <body …>
python3 - "$idx" <<'PY'
import sys,re
p=sys.argv[1]
s=open(p,encoding='utf-8').read()
s=re.sub(r'(<body\b[^>]*\bdata-single=")(0|false)(")', r'\g<1>1\3', s, flags=re.I)
if not re.search(r'<body\b[^>]*\bdata-single=', s, flags=re.I):
    s=re.sub(r'<body\b', r'<body data-single="1"', s, count=1, flags=re.I)
open(p,'w',encoding='utf-8').write(s)
PY

# Insertar meta p12-commit si falta
python3 - "$idx" "$head" <<'PY'
import sys,re
p,commit=sys.argv[1],sys.argv[2]
s=open(p,encoding='utf-8').read()
if re.search(r'<meta\s+name=["\']p12-commit["\']', s, flags=re.I) is None:
    # inserta después de la primera etiqueta <head>
    s=re.sub(r'(<head[^>]*>)', r'\1\n<meta name="p12-commit" content="'+commit+'">', s, count=1, flags=re.I)
open(p,'w',encoding='utf-8').write(s)
PY

# Validar y commitear
python -m py_compile wsgiapp/__init__.py || { echo "py_compile falló"; exit 2; }
git add backend/static/index.html
git commit -m "feat(frontend): data-single=1 y meta p12-commit=$(git rev-parse --short HEAD)" || true
