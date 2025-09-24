#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
WEBUI="backend/webui.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backup"
cp -f "$INIT" "$INIT.bak.$(date +%s)" 2>/dev/null || true

# 1) Asegurar blueprint robusto del frontend
python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")
if not p.exists():
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text('''\
from flask import Blueprint, send_from_directory
from pathlib import Path

PKG_DIR = Path(__file__).resolve().parent
CANDIDATES = [
    PKG_DIR / "frontend",
    PKG_DIR.parent / "frontend",
    Path.cwd() / "frontend",
]
for _cand in CANDIDATES:
    if _cand.exists():
        FRONT_DIR = _cand
        break
else:
    FRONT_DIR = CANDIDATES[0]

webui = Blueprint("webui", __name__)

@webui.route("/", methods=["GET"])
def index():
    return send_from_directory(FRONT_DIR, "index.html")

@webui.route("/js/<path:fname>", methods=["GET"])
def js(fname):
    return send_from_directory(FRONT_DIR / "js", fname)

@webui.route("/css/<path:fname>", methods=["GET"])
def css(fname):
    return send_from_directory(FRONT_DIR / "css", fname)

@webui.route("/favicon.ico", methods=["GET"])
def favicon():
    p = FRONT_DIR / "favicon.ico"
    if p.exists():
        return send_from_directory(FRONT_DIR, "favicon.ico")
    return ("", 204)

@webui.route("/robots.txt", methods=["GET"])
def robots():
    p = FRONT_DIR / "robots.txt"
    if p.exists():
        return send_from_directory(FRONT_DIR, "robots.txt")
    return ("User-agent: *\nAllow: /\n", 200, {"Content-Type": "text/plain"})
''', encoding="utf-8")
    print("webui.py: creado.")
else:
    print("webui.py: ok")
PY

# 2) Sanear __init__.py: comentar return app fuera de función y garantizar return dentro de create_app
python - <<'PY'
from pathlib import Path, re, sys
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")
lines = s.splitlines(True)

def indent_width(line:str)->int:
    w=0
    for ch in line:
        if ch==' ': w+=1
        elif ch=='\t': w+=4
        else: break
    return w

# a) Comentar "return app" a nivel tope (heurística: línea que hace match y la línea significativa anterior NO termina con ':')
new = []
prev_sig_idx = None
for i, ln in enumerate(lines):
    stripped = ln.strip()
    if re.match(r'^\s*return\s+app\b', ln):
        prev_line = lines[prev_sig_idx] if prev_sig_idx is not None else ""
        prev_sig_ends_colon = prev_line.rstrip().endswith(':')
        if not prev_sig_ends_colon:
            # top-level o fuera de bloque: comentar
            ln = re.sub(r'^(\s*)return\s+app\b', r'\1# return app  # commented by repair', ln)
    if stripped and not stripped.startswith('#'):
        prev_sig_idx = i
    new.append(ln)
lines = new

# b) Asegurar que create_app tenga un return app al final del bloque
in_create = False
def_indent = None
has_return_inside = False
create_last_idx = None

for i, ln in enumerate(lines):
    if re.match(r'^\s*def\s+create_app\s*\(.*\)\s*:', ln):
        in_create = True
        def_indent = indent_width(ln)
        has_return_inside = False
        create_last_idx = i
        continue
    if in_create:
        if ln.strip():
            iw = indent_width(ln)
            # dedent => terminó el def
            if iw <= def_indent and not ln.lstrip().startswith(('#','@')):
                # si no tenía return, lo insertamos antes de esta línea
                if not has_return_inside:
                    ins = ' '*(def_indent+4) + 'return app\n'
                    lines.insert(i, ins)
                    i += 1
                in_create = False
                def_indent = None
                # seguimos
        # marcar return
        if re.match(r'^\s*return\s+app\b', ln):
            has_return_inside = True
        create_last_idx = i

# Si el archivo terminaba dentro de create_app sin dedent, añadimos return
if in_create and create_last_idx is not None and not has_return_inside:
    lines.insert(create_last_idx+1, ' '*(def_indent+4) + 'return app\n')

s2 = ''.join(lines)

# c) Adjuntar blueprint (global + factory) idempotente
attach = r'''
# === Adjuntar blueprint del frontend (global y factory) ===
try:
    from .webui import webui
    # Caso app global (gunicorn backend:app)
    if 'app' in globals():
        try:
            app.register_blueprint(webui)  # type: ignore[name-defined]
        except Exception:
            pass
    # Caso factory (gunicorn backend:create_app())
    if 'create_app' in globals() and callable(create_app):
        def _wrap_create_app(_orig):
            def _inner(*args, **kwargs):
                app = _orig(*args, **kwargs)
                try:
                    app.register_blueprint(webui)
                except Exception:
                    pass
                return app
            return _inner
        if getattr(create_app, '__name__', '') != '_inner':
            create_app = _wrap_create_app(create_app)  # type: ignore
except Exception:
    pass
'''.strip('\n')

if attach not in s2:
    if not s2.endswith('\n'): s2 += '\n'
    s2 += attach + '\n'

# Validar sintaxis
try:
    compile(s2, str(p), 'exec')
except SyntaxError as e:
    print(f"(!) sigue error de sintaxis: {e}")
    sys.exit(2)

p.write_text(s2, encoding="utf-8")
print("✓ __init__.py reparado y parcheado.")
PY

echo "➤ Restart local"
pkill -9 -f "python .*run\\.py" 2>/dev/null || true
pkill -9 -f gunicorn 2>/dev/null || true
pkill -9 -f waitress 2>/dev/null || true
pkill -9 -f flask 2>/dev/null || true
sleep 1
nohup python -u run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smokes locales"
curl -sS -o /dev/null -w 'health=%{http_code}\n' http://127.0.0.1:8000/api/health || true
for p in / "/js/app.js" "/css/styles.css" "/robots.txt"; do
  echo "--- $p"
  curl -sSI "http://127.0.0.1:8000$p" | sed -n '1,12p' || true
done

echo "➤ Commit & push"
git add backend/__init__.py backend/webui.py || true
git commit -m "fix(init): comentar 'return app' top-level y asegurar 'return app' dentro de create_app; adjuntar blueprint frontend (global+factory)" || true
git push origin main || true

echo "✓ Hecho."
