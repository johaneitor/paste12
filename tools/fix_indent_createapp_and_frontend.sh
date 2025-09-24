#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backup"
cp -f "$INIT" "$INIT.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
import re, sys
from pathlib import Path

p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# Normalizar finales de línea e indentaciones (tabs -> 4 espacios)
s = s.replace('\r\n','\n').replace('\r','\n').replace('\t','    ')

# --- 1) Renombrar la PRIMERA create_app existente a _create_app_orig si no está ya ---
if re.search(r'\bdef\s+_create_app_orig\s*\(', s) is None:
    s, n = re.subn(r'\bdef\s+create_app\b', 'def _create_app_orig', s, count=1)
    if n == 0:
        print("Aviso: no encontré create_app original para renombrar (ok si tu app no usa factory).")

# --- 2) Eliminar cualquier wrapper residual def create_app(...) mal inyectado previamente ---
#    Captura desde "def create_app(" hasta la siguiente "def " en columna 0 o EOF
s = re.sub(
    r'\n(?=def\s+create_app\s*\()[\s\S]*?(?=\ndef\s+\w+\s*\(|\Z)',
    '\n',
    s,
    flags=re.M
)

# --- 3) Agregar wrapper limpio al final ---
wrapper = '''
# === Wrapper limpio para registrar frontend en la app de fábrica ===
def create_app(*args, **kwargs):
    # Si existe _create_app_orig úsala; si no, cae a la global (por compatibilidad)
    app = None
    try:
        app = _create_app_orig(*args, **kwargs)  # type: ignore[name-defined]
    except Exception:
        # Puede que no exista factory; intentamos usar 'app' global si está
        try:
            app  # noqa: F821
        except Exception:
            raise

    try:
        from .webui import webui
        try:
            app.register_blueprint(webui)  # type: ignore[attr-defined]
        except Exception:
            pass
    except Exception:
        pass
    return app
'''.strip('\n')

if not s.endswith('\n'):
    s += '\n'
s += wrapper + '\n'

# --- 4) Registro en app global (por si el entrypoint es backend:app) ---
global_reg = '''
# === Registro en app global (si existe) ===
try:
    from .webui import webui
    if 'app' in globals():
        try:
            app.register_blueprint(webui)  # type: ignore[attr-defined]
        except Exception:
            pass
except Exception:
    pass
'''.strip('\n')

s += global_reg + '\n'

# Validar sintaxis antes de escribir
try:
    compile(s, str(p), 'exec')
except SyntaxError as e:
    print("(!) Sigue habiendo error de sintaxis:", e)
    sys.exit(2)

p.write_text(s, encoding="utf-8")
print("✓ backend/__init__.py saneado.")
PY

echo "➤ Restart local"
pkill -9 -f "python .*run\\.py" 2>/dev/null || true
pkill -9 -f gunicorn 2>/dev/null || true
pkill -9 -f waitress 2>/dev/null || true
pkill -9 -f flask 2>/dev/null || true
sleep 1
nohup python -u run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smoke /api/health"
curl -sS -o /dev/null -w 'health=%{http_code}\n' http://127.0.0.1:8000/api/health || true

echo "➤ HEAD / y /js/app.js"
curl -sSI http://127.0.0.1:8000/        | sed -n '1,12p' || true
curl -sSI http://127.0.0.1:8000/js/app.js | sed -n '1,12p' || true

echo "➤ Commit & push"
git add backend/__init__.py || true
git commit -m "fix(init): sanear indentación y wrapper de create_app; registrar blueprint frontend (global y factory)" || true
git push origin main || true

echo "✓ Listo."
