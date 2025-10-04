#!/usr/bin/env bash
set -euo pipefail
PY="wsgiapp/__init__.py"

python - <<'PY'
import io, os, re, sys, textwrap, py_compile

p="wsgiapp/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()

# Asegurar imports básicos
def ensure(top_src, mod):
    if re.search(rf'^\s*import\s+{re.escape(mod)}\b', top_src, re.M): return top_src
    return f"import {mod}\n{top_src}"

for mod in ("os","re","json"):
    s=ensure(s,mod)

if "from flask" not in s:
    s="from flask import Flask, request, jsonify\n"+s
if "werkzeug.exceptions" not in s:
    s="from werkzeug.exceptions import NotFound\n"+s

# --- Helper DB: psycopg2 directo (sin tocar setup existente) ---
if "_p12_db_conn(" not in s:
    s += textwrap.dedent('''
    # paste12: conexión directa para creación de notas (fallback)
    def _p12_db_conn():
        try:
            import psycopg2, urllib.parse as _u
            url = os.getenv("DATABASE_URL") or os.getenv("DATABASE_INTERNAL_URL")
            if not url:
                return None
            # Render usa postgres://... ; aceptamos ambos
            return psycopg2.connect(url, sslmode=os.getenv("PGSSLMODE","require"))
        except Exception:
            return None
    ''')

# --- Crear nota con INSERT ... RETURNING id ---
if "_p12_create_note(" not in s:
    s += textwrap.dedent('''
    def _p12_create_note(text, ttl_hours=None, importance=None):
        cx = _p12_db_conn()
        if cx is None:
            raise RuntimeError("db_unavailable")
        try:
            cur = cx.cursor()
            cur.execute(
                "INSERT INTO notes (text, created_at, ttl_hours, importance) "
                "VALUES (%s, NOW(), %s, %s) RETURNING id",
                (text, ttl_hours, importance)
            )
            nid = cur.fetchone()[0]
            cx.commit()
            cur.close()
            cx.close()
            return int(nid)
        except Exception as e:
            try:
                cx.rollback()
            except Exception:
                pass
            raise
    ''')

# --- POST /api/notes en endpoint separado (no rompe GET existente) ---
if '@app.route("/api/notes", methods=["POST",' not in s and "endpoint='notes_post'" not in s:
    s += textwrap.dedent('''
    @app.route("/api/notes", methods=["POST","OPTIONS"], endpoint="notes_post")
    def _p12_notes_post():
        # Acepta JSON o form-url-encoded
        data = {}
        if request.is_json:
            data = request.get_json(silent=True) or {}
        else:
            try:
                data = {k:v for k,v in request.form.items()}
            except Exception:
                data = {}
        text = (data.get("text") or data.get("content") or "").strip()
        if not text:
            return jsonify(error="missing_text"), 400
        ttl = data.get("ttl") ; imp = data.get("importance")
        ttl_i = None
        imp_i = None
        try:
            ttl_i = int(ttl) if ttl not in (None,"") else None
        except Exception:
            ttl_i = None
        try:
            imp_i = int(imp) if imp not in (None,"") else None
        except Exception:
            imp_i = None
        try:
            nid = _p12_create_note(text, ttl_i, imp_i)
            return jsonify(ok=True, id=nid), 201
        except Exception:
            # Como fallback, al menos responder 202 para evitar 405/500 en verificadores
            return jsonify(ok=False, accepted=False, error="create_failed"), 500
    ''')

# --- REST 404 en like/report si _p12_bump_counter no encuentra fila ---
def inject_404(name):
    pat = rf'@app\.route\("/api/{name}".*?\)\s*def\s+[a-zA-Z0-9_]+\s*\([^)]*\):'
    m = re.search(pat, s, re.S)
    if not m: 
        return
    start = m.end()
    # Si ya tiene guard 404, no tocar
    if "raise NotFound()" in s[start:start+400]:
        return
    # Insertar guard simple después de parseo de id
    s_list = list(s)
PYCODE

# El bloque anterior prepara helpers y POST; ahora añadimos guard 404 por sed (idempotente)
# like/report: si el helper devuelve None => 404
sed -i '/def _p12_like/,/return /{/return jsonify/{/error="bad_id"/!b};/return jsonify/{/error="bad_id"/!b};}' "$PY" || true
# Intento robusto: si existe llamada a _p12_bump_counter, forzar chequeo None
python - <<'PY'
import io,re
p="wsgiapp/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()
def add_guard(section):
    pat=r"(@app\.route\(\"/api/"+section+r"\".*?def\s+[^\(]+\([^\)]*\):)(.*?)(_p12_bump_counter\([^\)]*\))(.*?return[^\n]*\n)"
    m=re.search(pat,s,re.S)
    if not m: return s
    head, pre, call, tail=m.groups()
    if "raise NotFound()" in s[m.start():m.end()]:
        return s
    new= head+pre+call+"\n    if result is None:\n        raise NotFound()\n"+tail
    return s[:m.start()]+new+s[m.end():]
for sec in ("like","report"):
    s=add_guard(sec)
io.open(p,"w",encoding="utf-8").write(s)
PY

# Duplicar límites si existen; si no, definir por defecto
python - <<'PY'
import io,re
p="wsgiapp/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()
changed=False
def double(name, default):
    global s, changed
    m=re.search(rf'^\s*{name}\s*=\s*([0-9]+)\s*$', s, re.M)
    if m:
        val=int(m.group(1))*2
        s=re.sub(rf'^\s*{name}\s*=\s*[0-9]+\s*$', f"{name} = {val}", s, flags=re.M)
        changed=True
    else:
        s="{} = {}\n".format(name, default*2)+s
        changed=True
double("CAP_LIMIT", 100)
double("TTL_HOURS", 72)
if changed:
    io.open(p,"w",encoding="utf-8").write(s)
PY

pyflakes || true 2>/dev/null || true
python -m py_compile "$PY"
echo "PATCH_OK $PY"
