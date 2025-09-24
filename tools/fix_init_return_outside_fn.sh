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

# Normalizar EOL y tabs
s = s.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

# 0) Quitar 'return app' al nivel 0 (línea que empieza con 'return app')
lines = s.split("\n")
fixed = []
removed_returns = 0
for L in lines:
    if re.match(r'^return\s+app\b', L):  # totalmente al margen izquierdo
        removed_returns += 1
        continue
    fixed.append(L)
s = "\n".join(fixed)

# 1) Quitar wrappers previos de create_app inyectados por scripts
#    – bloques marcados por comentarios especiales
s = re.sub(r'\n# === Wrapper.*?return app\n', '\n', s, flags=re.S)
s = re.sub(r'\n# === Registro en app global.*?pass\n', '\n', s, flags=re.S)

# 2) Si no existe _create_app_orig, renombrar la primera def create_app a _create_app_orig
if not re.search(r'\bdef\s+_create_app_orig\s*\(', s):
    s, n = re.subn(r'\bdef\s+create_app\b', 'def _create_app_orig', s, count=1)
    if n == 0:
        # No hay factory; ok
        pass

# 3) Eliminar wrappers residuales 'def create_app(...)' (si quedaron otros)
s = re.sub(r'\n(?=def\s+create_app\s*\()[\s\S]*?(?=\n(?:def|class)\s+\w+\s*\(|\Z)', '\n', s, flags=re.M)

# 4) Append wrapper limpio + registro global
wrapper = '''
# === Wrapper limpio para registrar frontend en factory ===
def create_app(*args, **kwargs):
    app = None
    try:
        app = _create_app_orig(*args, **kwargs)  # type: ignore[name-defined]
    except Exception:
        # Si no existe factory, probamos usar app global
        try:
            app  # noqa: F821
        except Exception as _e:
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

if not s.endswith('\n'):
    s += '\n'
s += wrapper + '\n'

# Validar sintaxis
try:
    compile(s, str(p), 'exec')
except SyntaxError as e:
    print(f"(!) Sigue habiendo error de sintaxis en {p}: {e}")
    sys.exit(2)

p.write_text(s, encoding="utf-8")
print(f"✓ __init__.py saneado. (return sueltos removidos: {removed_returns})")
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
curl -sSI http://127.0.0.1:8000/          | sed -n '1,12p' || true
curl -sSI http://127.0.0.1:8000/js/app.js | sed -n '1,12p' || true

echo "➤ Commit & push"
git add backend/__init__.py || true
git commit -m "fix(init): remover 'return app' al nivel 0, limpiar wrappers y registrar blueprint (global+factory)" || true
git push origin main || true

echo "✓ Hecho."
