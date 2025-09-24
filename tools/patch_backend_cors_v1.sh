#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

echo "[cors-fix] buscando módulos a parchear…"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
touched=0

patch_one() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp -f "$f" "${f}.${TS}.bak"
  python - "$f" <<'PY'
import io,sys,re,os
p=sys.argv[1]
s=io.open(p,"r",encoding="utf-8").read()
orig=s

def ensure_import(s):
    if re.search(r'\bfrom\s+flask_cors\s+import\s+CORS\b', s): 
        return s
    # inserta justo después de shebang/encoding si existieran, si no al inicio
    lines=s.splitlines(True)
    ins=0
    if lines and lines[0].startswith('#!'): ins=1
    if len(lines)>ins and 'coding:' in lines[ins]: ins+=1
    lines.insert(ins,'from flask_cors import CORS\n')
    return ''.join(lines)

def ensure_init_after_app(s):
    # si ya hay CORS(app) no tocamos
    if re.search(r'\bCORS\(\s*app\b', s): 
        return s
    # caso 1: app = Flask(...)
    s2, n = re.subn(r'(\bapp\s*=\s*Flask\([^\n]*\)\s*\n)',
                    r'\1CORS(app, resources={r"/api/*":{"origins":"*"}}, supports_credentials=False)\n',
                    s, count=1)
    if n: return s2
    # caso 2: dentro de create_app(...)
    def inject_in_factory(m):
        block=m.group(0)
        if 'CORS(app' in block: return block
        return re.sub(r'(\bapp\s*=\s*Flask\([^\n]*\)\s*\n)',
                      r'\1    CORS(app, resources={r"/api/*":{"origins":"*"}}, supports_credentials=False)\n',
                      block, count=1)
    s2, n = re.subn(r'(def\s+create_app\([^\)]*\):\s*\n(?:\s.*\n)+?)\Z', inject_in_factory, s, flags=re.M)
    return s2 if n else s

s=ensure_import(s)
s=ensure_init_after_app(s)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print(f"[patched] {p}")
else:
    print(f"[skip] {p} (ya OK)")
PY
  touched=1
}

for f in backend/__init__.py backend/app.py backend/main.py; do
  [[ -f "$f" ]] && patch_one "$f"
done

if [[ "$touched" -eq 0 ]]; then
  echo "[cors-fix] nada que parchar (no se hallaron archivos)."
fi

python -m py_compile backend/__init__.py 2>/dev/null || true
[[ -f backend/app.py  ]] && python -m py_compile backend/app.py  || true
[[ -f backend/main.py ]] && python -m py_compile backend/main.py || true
echo "[cors-fix] listo."
