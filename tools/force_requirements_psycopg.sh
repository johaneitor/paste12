#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"; cd "$ROOT"

REQ=requirements.txt
touch "$REQ"

# Asegura dependencias mínimas para Flask + SQLAlchemy + Gunicorn + Limiter + Postgres
ensure() {
  local pkg_re="$1"
  local line="$2"
  if ! grep -Eiq "^${pkg_re}([[:space:]]|$)" "$REQ"; then
    echo "$line" >> "$REQ"
    echo "  [+] add $line"
  else
    echo "  [=] keep $pkg_re"
  fi
}

echo "[+] Ensuring requirements in $REQ"
ensure 'Flask'               'Flask>=2.3'
ensure 'Werkzeug'            'Werkzeug>=2.3'
ensure 'gunicorn'            'gunicorn>=21.2'
ensure 'SQLAlchemy'          'SQLAlchemy>=2.0'
ensure 'Flask-SQLAlchemy'    'Flask-SQLAlchemy>=3.1'
ensure 'Flask-Limiter'       'Flask-Limiter>=3.5'
ensure 'psycopg2-binary'     'psycopg2-binary>=2.9'

# Normalizador de DATABASE_URL en render_entry.py (idempotente)
if [ -f render_entry.py ]; then
  python - <<'PY'
import os, sys
p="render_entry.py"
s=open(p,"r",encoding="utf-8").read()
if "def _normalize_database_url(" not in s:
    s += """

# --- bootstrap DB URL normalize (idempotente) ---
def _normalize_database_url(url: str|None):
    if not url: return url
    if url.startswith("postgres://"):
        return "postgresql://" + url[len("postgres://"):]
    return url

try:
    import os
    if "SQLALCHEMY_DATABASE_URI" in app.config:
        app.config["SQLALCHEMY_DATABASE_URI"] = _normalize_database_url(app.config.get("SQLALCHEMY_DATABASE_URI"))
    else:
        _env = _normalize_database_url(os.environ.get("DATABASE_URL"))
        if _env:
            app.config["SQLALCHEMY_DATABASE_URI"] = _env
    try:
        from backend import db
        with app.app_context():
            db.create_all()
    except Exception:
        pass
except Exception:
    pass
"""
    open(p,"w",encoding="utf-8").write(s)
    print("[+] render_entry.py: DB URL normalize + create_all() best-effort.")
else:
    print("[i] render_entry.py no existe (ok si usas wsgiapp bridge).")
PY
fi

# Commit & push
git add -A
git commit -m "build: force psycopg2-binary + normalize DATABASE_URL" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

cat <<'NOTE'

[✓] Cambios enviados.

Siguientes pasos en Render:
1) Asegúrate de tener la variable DATABASE_URL configurada.
   - Si empieza con 'postgres://', el código ya la corrige a 'postgresql://'.
2) Redeploy (si puedes, "Clear build cache" para que reinstale deps).
3) Mantén el Start Command actual (wsgiapp:app o render_entry:app según tu config).

Luego, prueba:
    bash tools/remote_probe_wsgiapp.sh

Esperado:
- /api/diag/import -> "import_path":"render_entry:app", "fallback": false
- /api/diag/urlmap  -> /api/notes GET/POST + endpoints de interactions
- /api/ix/...       -> 200 JSON (no 500)

Si todavía falla por el driver, usa el plan B temporal (abajo).
NOTE
