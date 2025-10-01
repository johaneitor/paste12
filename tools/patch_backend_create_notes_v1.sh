#!/usr/bin/env bash
set -euo pipefail
PY="wsgiapp/__init__.py"
[[ -f "$PY" ]] || { echo "ERROR: falta $PY"; exit 1; }

python - <<'PYCODE'
import io, re, textwrap

p="wsgiapp/__init__.py"
s=io.open(p, "r", encoding="utf-8").read()

def ensure_imports(src):
    need = []
    if re.search(r'from\s+flask\s+import\b', src) is None:
        src = "from flask import request, jsonify\n" + src
    else:
        if re.search(r'\brequest\b', src) is None:
            src = re.sub(r'(from\s+flask\s+import[^\n]*?)\n', r"\1, request\n", src, count=1)
        if re.search(r'\bjsonify\b', src) is None:
            src = re.sub(r'(from\s+flask\s+import[^\n]*?)\n', r"\1, jsonify\n", src, count=1)
    return src

def add_post_route(src):
    block = textwrap.dedent(r'''
    # ---- paste12: create note endpoint (POST /api/notes) ----
    @app.route("/api/notes", methods=["POST","OPTIONS"])
    def _p12_notes_create():
        from flask import request, jsonify
        # lee entrada (JSON o form)
        if request.is_json:
            j = (request.get_json(silent=True) or {})
            text = (j.get("text") or "").strip()
            ttl = j.get("ttl_hours", 12)
        else:
            text = (request.form.get("text") or "").strip()
            ttl = request.form.get("ttl_hours", 12)
        try:
            ttl = float(ttl)
        except Exception:
            ttl = 12.0
        if not text:
            return jsonify(error="text_required"), 400

        # Inserción con SQLAlchemy Core + RETURNING id (PG) y fallbacks
        try:
            from sqlalchemy import text as sql_text
        except Exception:
            return jsonify(error="sqlalchemy_missing"), 500

        # localizar 'db' (SQLAlchemy) expuesto por la app
        _db = globals().get("db")
        if _db is None:
            try:
                from wsgiapp import db as _db  # común en este proyecto
            except Exception:
                _db = None
        if _db is None:
            return jsonify(error="server_db_unavailable"), 500

        row_id = None
        # intentos con RETURNING
        for sql in [
            "INSERT INTO notes (text, ttl_hours) VALUES (:text, :ttl) RETURNING id",
            "INSERT INTO notes (text) VALUES (:text) RETURNING id",
        ]:
            try:
                res = _db.session.execute(sql_text(sql), {"text": text[:8192], "ttl": ttl})
                try:
                    row = res.fetchone()
                    row_id = int(row[0]) if row and row[0] is not None else None
                except Exception:
                    row_id = None
                _db.session.commit()
                if row_id:
                    break
            except Exception:
                _db.session.rollback()
                continue

        # fallback sin RETURNING (SQLite antiguo, etc.)
        if not row_id:
            try:
                _db.session.execute(sql_text("INSERT INTO notes (text) VALUES (:text)"), {"text": text[:8192]})
                _db.session.commit()
                res = _db.session.execute(sql_text("SELECT id FROM notes ORDER BY id DESC LIMIT 1"))
                row = res.fetchone()
                row_id = int(row[0]) if row and row[0] is not None else None
            except Exception:
                _db.session.rollback()

        if not row_id:
            return jsonify(error="insert_failed"), 500

        return jsonify(id=row_id, ok=True), 201
    ''')
    return src + "\n" + block

# 1) Asegurar imports
s = ensure_imports(s)

# 2) Asegurar símbolo 'app' (si sólo existe 'application', creamos alias)
if re.search(r'^\s*app\s*=', s, re.M) is None and re.search(r'^\s*application\s*=', s, re.M):
    s += "\n# paste12: alias Flask app\napp = application\n"

# 3) ¿Ya hay ruta a /api/notes? Si sí, garantizamos POST; si no, añadimos la ruta POST nueva
if re.search(r'@(?:app|bp)\.route\(\s*[\'"]/api/notes[\'"]\s*,\s*methods\s*=\s*\[', s):
    # añade 'POST' si faltara en methods=[...]
    def add_post(m):
        inside = m.group(1)
        if re.search(r"'POST\"?|POST", inside, re.I):
            return m.group(0)  # ya lo tiene
        return m.group(0).replace(inside, inside.rstrip() + ", 'POST'")
    s = re.sub(r'(@(?:app|bp)\.route\(\s*[\'"]/api/notes[\'"]\s*,\s*methods\s*=\s*\[)([^\]]*)\]',
               lambda m: m.group(1) + (m.group(2) + (", 'POST'" if "'POST'" not in m.group(2) and "POST" not in m.group(2) else "") ) + "]",
               s, count=1)
    # NOTA: si el handler existente sólo maneja GET internamente, dependerá de su lógica;
    # por eso dejamos además un handler POST específico si no hay ninguno definido.
    if not re.search(r'def\s+_p12_notes_create\s*\(', s):
        s = add_post_route(s)
else:
    # no hay ruta declarada: agregamos la POST mínima y segura
    s = add_post_route(s)

io.open(p, "w", encoding="utf-8").write(s)
print("PATCH_OK", p)
PYCODE

python -m py_compile wsgiapp/__init__.py
echo "OK: wsgiapp/__init__.py compilado"
git add wsgiapp/__init__.py
git commit -m "API: habilitar POST /api/notes (INSERT … RETURNING id) [p12]" || true
