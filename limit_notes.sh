#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# Backups
cp -p backend/__init__.py "backend/__init__.py.bak.$ts" 2>/dev/null || true
cp -p backend/routes.py   "backend/routes.py.bak.$ts"   2>/dev/null || true

############################################
# 1) __init__.py → asegurar Limiter global
############################################
python - <<'PY'
from pathlib import Path
import re
p = Path("backend/__init__.py")
code = p.read_text()

# Asegura imports
need = [
    "from flask_limiter import Limiter",
    "from flask_limiter.util import get_remote_address",
]
for imp in need:
    if imp not in code:
        code = imp + "\n" + code

# Crear objeto limiter global si no existe
if re.search(r'\blimiter\s*=\s*Limiter\(', code) is None:
    code = code.replace(
        "db = SQLAlchemy()",
        "db = SQLAlchemy()\n\n# Limiter global (memoria por defecto; en producción usa Redis con RATELIMIT_STORAGE_URL)\n"
        "limiter = Limiter(\n"
        "    key_func=get_remote_address,\n"
        "    storage_uri=os.getenv('RATELIMIT_STORAGE_URL', 'memory://'),\n"
        "    default_limits=[],  # sin límites globales, se fijan por endpoint\n"
        ")"
    )

# Asegura init_app(limiter)
if "limiter.init_app(app)" not in code:
    code = code.replace("db.init_app(app)", "db.init_app(app)\n    limiter.init_app(app)")

p.write_text(code)
print("✓ __init__.py: limiter global listo")
PY

############################################################
# 2) routes.py → key_func robusto + límites en /api/notes
############################################################
python - <<'PY'
from pathlib import Path
import re
rp = Path("backend/routes.py")
code = rp.read_text()

# Imports necesarios
if "from hashlib import sha256" not in code:
    code = "from hashlib import sha256\n" + code
if "from . import limiter" not in code:
    code = code.replace("from . import db", "from . import db, limiter")

# Función key de rate limit
rate_key_fn = (
    "def _rate_key():\n"
    "    tok = (request.headers.get('X-User-Token') or request.cookies.get('p12') or '').strip()\n"
    "    if tok:\n"
    "        return tok[:128]\n"
    "    xff = request.headers.get('X-Forwarded-For','')\n"
    "    ip = xff.split(',')[0].strip() if xff else (request.remote_addr or '')\n"
    "    ua = request.headers.get('User-Agent','')\n"
    "    return sha256(f\"{ip}|{ua}\".encode()).hexdigest()\n"
)

if "_rate_key(" not in code:
    # Inserta antes del primer endpoint
    pos = code.find("@bp.")
    if pos == -1: pos = 0
    code = code[:pos] + "\n" + rate_key_fn + "\n" + code[pos:]

# Añadir decoradores de límite a create_note
# Busca el decorator del POST
post_pat = re.compile(r'(@bp\.post\(\s*["\']\/notes["\']\s*\)\s*\n)(def\s+create_note\s*\(\)\s*:)', re.M)
if not post_pat.search(code):
    # Variante con route(methods=["POST"])
    post_pat = re.compile(r'(@bp\.route\(\s*["\']\/notes["\']\s*,\s*methods=\[["\']POST["\']\]\s*\)\s*\n)(def\s+create_note\s*\(\)\s*:)', re.M)

def add_limits(m):
    head = m.group(1)
    funcdef = m.group(2)
    limits = (
        f"{head}"
        "@limiter.limit('1 per 10 seconds', key_func=_rate_key)\n"
        "@limiter.limit('500 per day', key_func=_rate_key)\n"
        f"{funcdef}"
    )
    return limits

code2, n = post_pat.subn(add_limits, code, count=1)
if n == 0 and "@limiter.limit('1 per 10 seconds'" not in code:
    # fallback: inserta manualmente sobre la primera def create_note
    code2 = re.sub(r'(\n)def\s+create_note\s*\(\)\s*:', r"\n@limiter.limit('1 per 10 seconds', key_func=_rate_key)\n@limiter.limit('500 per day', key_func=_rate_key)\ndef create_note():", code, count=1)

rp.write_text(code2)
print("✓ routes.py: límites 1/10s y 500/día añadidos")
PY

# 3) Validación rápida de sintaxis
python -m py_compile backend/__init__.py backend/routes.py

# 4) Commit + push → Render redeploy
git add backend/__init__.py backend/routes.py
git commit -m "feat(rate): limitar creación de notas a 1/10s y 500/día por usuario (cookie p12 o IP+UA)" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "🚀 Subido. Cuando Render termine, entra con /?v=$ts para limpiar caché."
