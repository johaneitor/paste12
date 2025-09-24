#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backup"
cp -f "$INIT" "$INIT.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path, re, sys
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# 1) Eliminar registros globales peligrosos (a nivel módulo)
#    - app.register_blueprint(webui)
#    - bloques anteriores "attach webui" en global
s = re.sub(r'^\s*app\.register_blueprint\s*\(\s*webui\s*\)\s*#?.*\n', '', s, flags=re.M)
s = re.sub(r'\n#\s*===\s*attach webui.*?^except\s+Exception:\s*\n\s*pass\s*', '\n', s, flags=re.S|re.M)

# 2) Inyectar ensure_webui(app) DENTRO de create_app, justo antes de 'return app'
m = re.search(r'(def\s+create_app\s*\([^)]*\)\s*:\s*[\s\S]*?)\n(\s*)return\s+app\b', s)
if m:
    indent = m.group(2)
    inject = (
        f"\n{indent}# -- adjuntar frontend de forma segura --\n"
        f"{indent}try:\n"
        f"{indent}    from .webui import ensure_webui  # type: ignore\n"
        f"{indent}    ensure_webui(app)\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
    )
    s = s[:m.start(2)] + inject + s[m.start(2):]
else:
    print("(!) No encontré create_app(...). No inyecto hook; revisa tu factory.", file=sys.stderr)

# 3) Validar sintaxis
try:
    compile(s, str(p), 'exec')
except SyntaxError as e:
    print("(!) Error de sintaxis aún en backend/__init__.py:", e)
    sys.exit(2)

p.write_text(s, encoding="utf-8")
print("✓ backend/__init__.py parchado.")
PY

echo "➤ Restart local (si aplica)"
pkill -9 -f "python .*run\\.py" 2>/dev/null || true
pkill -9 -f gunicorn 2>/dev/null || true
pkill -9 -f waitress 2>/dev/null || true
pkill -9 -f flask 2>/dev/null || true
sleep 1
nohup python -u run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smoke /api/health"
curl -sS -o /dev/null -w 'health=%{http_code}\n' http://127.0.0.1:8000/api/health || true

echo "➤ Commit & push"
git add backend/__init__.py || true
git commit -m "fix(init): quitar registro global de webui y adjuntar frontend dentro de create_app()" || true
git push origin main || true

echo "✓ Listo."
