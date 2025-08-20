#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# Backups
cp -p backend/__init__.py "backend/__init__.py.bak.$ts" 2>/dev/null || true
cp -p backend/routes.py   "backend/routes.py.bak.$ts"   2>/dev/null || true

############ 1) PARCHES EN BACKEND (__init__.py): cookie p12 + migración mínima ############
python - <<'PY'
from pathlib import Path
p = Path("backend/__init__.py")
code = p.read_text()

# a) asegura imports necesarios
imports = [
    "import os",
    "from datetime import datetime, timezone, timedelta",
    "from flask import Flask, request, make_response, send_from_directory",
    "from flask_sqlalchemy import SQLAlchemy",
    "from flask_limiter import Limiter",
    "from flask_limiter.util import get_remote_address",
    "from flask_cors import CORS",
    "from apscheduler.schedulers.background import BackgroundScheduler",
    "from zoneinfo import ZoneInfo",
    "import secrets",
]
for imp in imports:
    if imp not in code:
        code = imp + "\n" + code

# b) inyecta hook before_request que garantiza cookie 'p12' si falta
if "def ensure_client_cookie()" not in code:
    code = code.replace(
        "def create_app(",
        "def ensure_client_cookie(app):\n"
        "    @app.before_request\n"
        "    def _p12_cookie():\n"
        "        # si ya hay cookie, no hacemos nada\n"
        "        if request.cookies.get('p12'): return\n"
        "        # colocamos cookie en la primera respuesta\n"
        "        @app.after_request\n"
        "        def _set_cookie(resp):\n"
        "            try:\n"
        "                if not request.cookies.get('p12'):\n"
        "                    tok = secrets.token_hex(16)\n"
        "                    resp.set_cookie('p12', tok, max_age=60*60*24*365, httponly=False, samesite='Lax')\n"
        "            except Exception:\n"
        "                pass\n"
        "            return resp\n"
        "        return None\n\n"
        "def create_app("
    )

# c) llama ensure_client_cookie(app) dentro de create_app
if "ensure_client_cookie(app)" not in code:
    code = code.replace(
        "app = Flask(",
        "app = Flask("
    )
    code = code.replace(
        "db.init_app(app)",
        "db.init_app(app)\n    ensure_client_cookie(app)"
    )

# d) migración mínima en arranque: crear tablas y constraints únicas si faltan
migrate_block = (
    "\n    with app.app_context():\n"
    "        db.create_all()\n"
    "        try:\n"
    "            from sqlalchemy import text\n"
    "            eng = db.engine\n"
    "            # Crea LikeLog / ReportLog si no existen (por seguridad)\n"
    "            eng.execute(text('''\n"
    "            CREATE TABLE IF NOT EXISTS like_log (\n"
    "              id SERIAL PRIMARY KEY,\n"
    "              note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,\n"
    "              fingerprint VARCHAR(128) NOT NULL,\n"
    "              created_at TIMESTAMPTZ DEFAULT NOW()\n"
    "            );\n"
    "            '''))\n"
    "            eng.execute(text('''\n"
    "            CREATE TABLE IF NOT EXISTS report_log (\n"
    "              id SERIAL PRIMARY KEY,\n"
    "              note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,\n"
    "              fingerprint VARCHAR(128) NOT NULL,\n"
    "              created_at TIMESTAMPTZ DEFAULT NOW()\n"
    "            );\n"
    "            '''))\n"
    "            # UNIQUE constraints si faltan\n"
    "            eng.execute(text('''\n"
    "            DO $$\n"
    "            BEGIN\n"
    "              IF NOT EXISTS (\n"
    "                SELECT 1 FROM pg_constraint c\n"
    "                JOIN pg_class t ON c.conrelid=t.oid\n"
    "                WHERE t.relname='like_log' AND c.conname='uq_like_note_fp'\n"
    "              ) THEN\n"
    "                ALTER TABLE like_log ADD CONSTRAINT uq_like_note_fp UNIQUE (note_id, fingerprint);\n"
    "              END IF;\n"
    "            END$$;\n"
    "            '''))\n"
    "            eng.execute(text('''\n"
    "            DO $$\n"
    "            BEGIN\n"
    "              IF NOT EXISTS (\n"
    "                SELECT 1 FROM pg_constraint c\n"
    "                JOIN pg_class t ON c.conrelid=t.oid\n"
    "                WHERE t.relname='report_log' AND c.conname='uq_report_note_fp'\n"
    "              ) THEN\n"
    "                ALTER TABLE report_log ADD CONSTRAINT uq_report_note_fp UNIQUE (note_id, fingerprint);\n"
    "              END IF;\n"
    "            END$$;\n"
    "            '''))\n"
    "        except Exception as e:\n"
    "            app.logger.warning(f\"migrate_min: {e}\")\n"
)
if "migrate_min" not in code:
    code = code.replace("return app", migrate_block + "    return app")

p.write_text(code)
print("✓ __init__.py parchado (cookie p12 + migrate_min)")
PY

############ 2) PARCHES EN RUTAS: huella robusta (header→cookie→XFF) ############
python - <<'PY'
from pathlib import Path
rp = Path("backend/routes.py")
code = rp.read_text()

# Asegurar import sha256 y request
if "from hashlib import sha256" not in code:
    code = code.replace("from hashlib import sha256", "from hashlib import sha256")
if "from flask import Blueprint, request, jsonify" not in code:
    code = code.replace("from flask import Blueprint, request, jsonify", "from flask import Blueprint, request, jsonify")

# Reemplazar función _fingerprint por una con cookie y XFF
import re
pat = re.compile(r"def _fingerprint\([\s\S]*?\n\)")
new_fp = (
"def _fingerprint():\n"
"    # 1) token explícito\n"
"    tok = (request.headers.get('X-User-Token') or request.cookies.get('p12') or '').strip()\n"
"    if tok:\n"
"        return tok[:128]\n"
"    # 2) X-Forwarded-For (primer IP)\n"
"    xff = request.headers.get('X-Forwarded-For', '')\n"
"    if xff:\n"
"        ip = xff.split(',')[0].strip()\n"
"    else:\n"
"        ip = request.remote_addr or ''\n"
"    ua = request.headers.get('User-Agent', '')\n"
"    return sha256(f\"{ip}|{ua}\".encode('utf-8')).hexdigest()\n"
)
if pat.search(code):
    code = pat.sub(new_fp, code)
elif "def _fingerprint()" in code:
    code = code.replace("def _fingerprint():", new_fp)
else:
    # si faltaba, lo insertamos cerca de las utils
    insert_at = code.find("@bp.get(\"/notes\")")
    if insert_at == -1:
        insert_at = len(code)
    code = code[:insert_at] + "\n" + new_fp + "\n" + code[insert_at:]

rp.write_text(code)
print("✓ routes.py parchado (_fingerprint robusto)")
PY

############ 3) VERIFICACIÓN LOCAL, COMMIT + PUSH ############
python -m compileall -q backend

git add backend/__init__.py backend/routes.py
git commit -m "fix(authz): token por cookie p12 y constraints únicas para like/report; fingerprint con XFF" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "🚀 Subido. Tras el redeploy en Render, recarga con /?v=$ts (limpia caché) y prueba likes/reportes."
