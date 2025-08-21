#!/usr/bin/env bash
set -Eeuo pipefail
echo "🔧 Reset limpio de create_app() en backend/__init__.py"

python - <<'PY'
from pathlib import Path
import re, os

p = Path("backend/__init__.py")
code = p.read_text()

# Asegurar imports base (no duplicados feos)
need_imports = [
    ("from flask import Flask, send_from_directory", r"\bFlask\b"),
    ("from flask_sqlalchemy import SQLAlchemy", r"\bSQLAlchemy\b"),
    ("from flask_limiter import Limiter", r"\bLimiter\b"),
    ("from flask_limiter.util import get_remote_address", r"\bget_remote_address\b"),
]
for line, sym in need_imports:
    if re.search(sym, code) and line not in code:
        # si ya hay un import alterno, lo dejamos; si no, insertamos arriba
        pass
    elif line not in code:
        code = line + "\n" + code

# Garantizar singletons db/limiter (si ya existen, no duplicar)
if not re.search(r"^\s*db\s*=\s*SQLAlchemy\(\)", code, re.M):
    code = re.sub(r"(from flask_sqlalchemy import SQLAlchemy[^\n]*\n)", r"\1\ndb = SQLAlchemy()\n", code, count=1)
if not re.search(r"^\s*limiter\s*=\s*Limiter\(", code, re.M):
    # crear un limiter default sin límites globales
    ins_at = code.find("\n", code.find("from flask_limiter.util"))
    if ins_at == -1: ins_at = 0
    code = code[:ins_at] + "\nlimiter = Limiter(key_func=get_remote_address, default_limits=[])\n" + code[ins_at:]

# Construir la nueva create_app limpia
new_create = r'''
def create_app():
    import os
    from sqlalchemy import text

    app = Flask(__name__, static_folder=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend")), static_url_path="")

    # --- Config básica ---
    uri = os.getenv("DATABASE_URL") or os.getenv("SQLALCHEMY_DATABASE_URI")
    if not uri:
        # fallback a SQLite local
        base = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "instance"))
        os.makedirs(base, exist_ok=True)
        uri = f"sqlite:///{os.path.join(base, "production.db")}"
    app.config["SQLALCHEMY_DATABASE_URI"] = uri
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # --- Inicializar extensiones (una vez) ---
    try:
        db.init_app(app)
    except Exception:
        # ya estaba inicializado; ignorar
        pass
    try:
        limiter.init_app(app)
    except Exception:
        pass

    # --- Registrar blueprint /api (idempotente) ---
    try:
        from . import routes as _routes
        if "api" not in app.blueprints:
            app.register_blueprint(_routes.bp, url_prefix="/api")
    except Exception as e:
        app.logger.error(f"No se pudo registrar blueprint API: {e}")

    # --- Rutas estáticas/SPA (idempotentes) ---
    try:
        rules = {r.rule for r in app.url_map.iter_rules()}
        if "/favicon.ico" not in rules:
            app.add_url_rule(
                "/favicon.ico",
                endpoint="static_favicon",
                view_func=lambda: send_from_directory(app.static_folder, "favicon.svg", mimetype="image/svg+xml"),
            )
        if "/ads.txt" not in rules:
            app.add_url_rule(
                "/ads.txt",
                endpoint="static_ads",
                view_func=lambda: send_from_directory(app.static_folder, "ads.txt", mimetype="text/plain"),
            )
        if "/" not in rules:
            app.add_url_rule(
                "/",
                endpoint="static_root",
                view_func=lambda: send_from_directory(app.static_folder, "index.html"),
            )
        if "static_any" not in app.view_functions:
            from flask import abort
            def static_any(path):
                if path.startswith("api/"):
                    return abort(404)
                full = os.path.join(app.static_folder, path)
                if os.path.isfile(full):
                    return send_from_directory(app.static_folder, path)
                return send_from_directory(app.static_folder, "index.html")
            app.add_url_rule("/<path:path>", endpoint="static_any", view_func=static_any)
    except Exception as e:
        app.logger.warning(f"Rutas estáticas: {e}")

    # --- Índices útiles (no falla si ya existen) ---
    try:
        with app.app_context():
            with db.engine.begin() as conn:
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_expires_at ON note (expires_at)"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_exp_ts ON note (expires_at, timestamp)"))
    except Exception as e:
        app.logger.warning(f"Índices: {e}")

    # --- Cap de notas al arrancar (si está implementado) ---
    try:
        from .tasks import enforce_cap_on_boot
        enforce_cap_on_boot(app)
    except Exception as e:
        app.logger.warning(f"enforce_cap_on_boot: {e}")

    return app
'''.lstrip()

# Reemplazar el bloque create_app entero por la versión limpia.
# Buscamos desde 'def create_app(' hasta el primer 'return app' y cerramos.
m = re.search(r"def\s+create_app\s*\([^)]*\):", code)
if not m:
    raise SystemExit("❌ No se encontró create_app() para reemplazar.")
start = m.start()

# Intento 1: hasta el 'return app' y el salto de línea siguiente
m_ret = re.search(r"\n\s*return\s+app\b.*", code[m.end():], re.S)
end = None
if m_ret:
    end = m.end() + m_ret.end()
else:
    # si falla, hasta el próximo 'def ' o EOF
    m_next = re.search(r"\ndef\s+\w+\s*\(", code[m.end():])
    end = m.end() + (m_next.start() if m_next else len(code[m.end():]))

code = code[:start] + new_create + code[end:]

p.write_text(code)
print("✓ create_app() reescrita con una versión estable y con sangría correcta.")
PY

# Validar sintaxis
python -m py_compile backend/__init__.py && echo "✅ Sintaxis OK"

echo
echo "Ahora sube y redeploy:"
echo "  git add backend/__init__.py && git commit -m 'fix(init): reset limpio de create_app estable' || true"
echo "  git push -u origin main"
echo "Tras el deploy, valida:"
echo "  curl -sSf https://paste12-rmsk.onrender.com/api/health || true"
echo "  curl -sSf 'https://paste12-rmsk.onrender.com/api/notes?page=1' | head -c 400; echo"
