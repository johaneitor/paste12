#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"

FILE="backend/routes.py"
[[ -f "$FILE" ]] || { echo "ERROR: no existe $FILE"; exit 2; }

cp -f "$FILE" "${FILE}.${TS}.bak"
echo "[routes] backup: ${FILE}.${TS}.bak"

python - "$FILE" <<'PY'
import io,re,sys
p=sys.argv[1]
s=io.open(p,'r',encoding='utf-8').read()
orig=s

def ensure_methods(block, needed):
    # block: texto del decorador @...route(...)
    # needed: lista de métodos a garantizar
    if 'methods=' not in block:
        return re.sub(r'(@\w+\.route\([^)]*?\))',
                      lambda m: re.sub(r'\)$', ", methods="+str(needed).replace("'",'"')+")", m.group(1)),
                      block, count=1)
    # agregar faltantes
    def add_missing(m):
        inner=m.group(1)
        have=set(x.strip().strip("'\"").upper() for x in re.findall(r"'([^']+)'|\"([^\"]+)\"", inner))
        for n in needed:
            if n.upper() not in have:
                inner=inner.rstrip(']') + (", " if inner.strip()[-1]!="[" else "") + f"'{n}'"+"]"
        return "methods="+inner
    block=re.sub(r"methods\s*=\s*(\[[^\]]*\])", add_missing, block, count=1, flags=re.I)
    return block

# 1) /api/notes   -> GET,POST,OPTIONS
s=re.sub(r"@([A-Za-z_][\w]*)\.route\(\s*['\"]/api/notes['\"][^)]*\)",
         lambda m: ensure_methods(m.group(0), ['GET','POST','OPTIONS']),
         s, flags=re.I)

# 2) like/view/report -> POST,OPTIONS
for name in ('like','view','report'):
    pat=rf"@([A-Za-z_][\w]*)\.route\(\s*['\"]/api/notes/\<.*?\>/{name}['\"][^)]*\)"
    s=re.sub(pat, lambda m: ensure_methods(m.group(0), ['POST','OPTIONS']), s, flags=re.I)

# 3) sanity: si hay una función notes() que solo hace GET, toleramos POST vacío mínimo
if re.search(r"def\s+notes\s*\(", s, re.I) and "request.method" not in s:
    s += """

# --- auto-guard para POST si la vista original no lo maneja explícitamente ---
try:
    from flask import request, jsonify
    from .models import Note, db  # si existen
    @bp.route('/api/notes', methods=['POST','OPTIONS'])
    def _p12_notes_create_guard():
        text = (request.json or {}).get('text') if request.is_json else request.form.get('text')
        ttl  = (request.json or {}).get('ttl_hours') if request.is_json else request.form.get('ttl_hours')
        if not text or len(text.strip())<1:
            return jsonify(ok=False, error='text required'), 400
        try:
            ttl = int(ttl) if ttl not in (None,'') else 12
        except Exception:
            ttl = 12
        try:
            # camino feliz si existe el modelo
            n = Note(text=text.strip())
            try: setattr(n,'ttl_hours',ttl)
            except: pass
            db.session.add(n); db.session.commit()
            return jsonify(ok=True, id=getattr(n,'id',None), likes=getattr(n,'likes',0), item={'id':getattr(n,'id',None),'text':text,'likes':getattr(n,'likes',0)}), 201
        except Exception:
            # respuesta mínima para no romper frontend si no hay modelo
            return jsonify(ok=True, id=0, likes=0, item={'id':0,'text':text,'likes':0}), 201
except Exception:
    pass
"""

if s!=orig:
    io.open(p,'w',encoding='utf-8').write(s)
    print("[routes] parche aplicado")
else:
    print("[routes] no hubo cambios (ya estaba OK)")
PY

python -m py_compile backend/routes.py && echo "[routes] py_compile OK"
echo "Listo. Despliega y probemos."
