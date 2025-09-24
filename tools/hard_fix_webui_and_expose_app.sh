#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
WEBUI="backend/webui.py"

echo "➤ Backups"
cp -f "$INIT" "$INIT.bak.$(date +%s)" 2>/dev/null || true
cp -f "$WEBUI" "$WEBUI.bak.$(date +%s)" 2>/dev/null || true

echo "➤ Asegurar frontend mínimo en backend/frontend"
mkdir -p backend/frontend/js backend/frontend/css
[ -f backend/frontend/index.html ] || cat > backend/frontend/index.html <<'HTML'
<!doctype html><html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>paste12</title>
<link rel="stylesheet" href="/css/styles.css">
</head><body>
<main>
  <h1>paste12</h1>
  <ul id="notes"></ul>
  <button id="loadMore" style="display:none;margin:12px auto;">Cargar más</button>
</main>
<script src="/js/app.js"></script>
</body></html>
HTML

[ -f backend/frontend/js/app.js ] || cat > backend/frontend/js/app.js <<'JS'
function renderNote(n){
  const li=document.createElement('li');
  li.textContent = `#${n.id} — ${n.text}`;
  return li;
}
(async function boot(){
  const $list=document.getElementById('notes');
  const $btn=document.getElementById('loadMore');
  let after=null; const LIMIT=5;
  async function page(append=false){
    const qs=new URLSearchParams({limit:String(LIMIT)});
    if(after) qs.set('after_id', after);
    const res=await fetch('/api/notes?'+qs.toString());
    const data=await res.json();
    if(!append) $list.innerHTML='';
    data.forEach(n=>$list.appendChild(renderNote(n)));
    const next=res.headers.get('X-Next-After');
    after = next && next.trim() ? next.trim() : null;
    $btn.style.display = after ? 'block' : 'none';
  }
  $btn?.addEventListener('click', ()=>page(true));
  page(false);
})();
JS

[ -f backend/frontend/css/styles.css ] || cat > backend/frontend/css/styles.css <<'CSS'
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial,sans-serif;background:#0d1320;color:#eaf2ff;margin:0;padding:24px}
h1{margin:0 0 12px 0}
ul#notes{list-style:none;padding:0;margin:12px 0}
button{padding:8px 12px;border:1px solid #253044;border-radius:10px;background:#172030;color:#eaf2ff}
CSS

[ -f backend/frontend/robots.txt ] || printf "User-agent: *\nAllow: /\n" > backend/frontend/robots.txt
[ -f backend/frontend/privacy.html ] || printf '<!doctype html><title>Privacidad</title><a href="/">Volver</a>' > backend/frontend/privacy.html
[ -f backend/frontend/terms.html ] || printf '<!doctype html><title>Términos</title><a href="/">Volver</a>' > backend/frontend/terms.html
# favicon placeholder (evita errores de git add si falta)
[ -f backend/frontend/favicon.ico ] || : > backend/frontend/favicon.ico

echo "➤ Escribir/actualizar backend/webui.py (blueprint robusto)"
python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")
p.write_text("""\
from flask import Blueprint, send_from_directory
from pathlib import Path

# Detecta carpeta frontend en varios layouts (repo root o dentro de backend/)
PKG = Path(__file__).resolve().parent
CANDIDATES = [
    PKG / "frontend",
    PKG.parent / "frontend",
    Path.cwd() / "frontend",
]
for _c in CANDIDATES:
    if _c.exists():
        FRONT_DIR = _c
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

@webui.route("/robots.txt", methods=["GET"])
def robots():
    return send_from_directory(FRONT_DIR, "robots.txt")

@webui.route("/favicon.ico", methods=["GET"])
def favicon():
    p = FRONT_DIR / "favicon.ico"
    if p.exists():
        return send_from_directory(FRONT_DIR, "favicon.ico")
    return ("", 204)

@webui.route("/privacy.html", methods=["GET"])
def privacy():
    return send_from_directory(FRONT_DIR, "privacy.html")

@webui.route("/terms.html", methods=["GET"])
def terms():
    return send_from_directory(FRONT_DIR, "terms.html")
""", encoding="utf-8")
print("webui.py OK")
PY

echo "➤ Inyectar registro del blueprint dentro de create_app() y exponer app global"
python - <<'PY'
from pathlib import Path, re

initp = Path("backend/__init__.py")
s = initp.read_text(encoding="utf-8")

# 1) Insertar el registro del blueprint justo antes de 'return app' dentro de create_app(...)
m = re.search(r'(def\s+create_app\s*\([^)]*\)\s*:\s*[\s\S]*?)\n(\s*)return\s+app\b', s)
if m:
    indent = m.group(2)
    block = f"""{indent}# -- register webui blueprint --
{indent}try:
{indent}    from .webui import webui
{indent}    app.register_blueprint(webui)
{indent}except Exception:
{indent}    pass
"""
    s = s[:m.start(2)] + block + s[m.start(2):]
    changed = True
else:
    changed = False

# 2) Asegurar app = create_app() a nivel de módulo (para backend:app)
if not re.search(r'^\s*app\s*=\s*create_app\(', s, re.M):
    s = s.rstrip() + "\n\n# Export WSGI app for gunicorn (backend:app)\napp = create_app()\n"
    changed = True or changed

if changed:
    initp.write_text(s, encoding="utf-8")
    print("__init__.py actualizado")
else:
    print("__init__.py ya tenía registro + app global")
PY

echo "➤ Commit & push"
git add backend/__init__.py backend/webui.py backend/frontend/index.html backend/frontend/js/app.js backend/frontend/css/styles.css backend/frontend/robots.txt backend/frontend/privacy.html backend/frontend/terms.html backend/frontend/favicon.ico || true
git commit -m "fix(web): registrar webui dentro de create_app() y exponer app=Create_app(); servir /, /js/*, /css/* y robots.txt" || true
git push origin main

echo "✓ Listo. Verificá producción con:"
echo 'BASE="https://paste12-rmsk.onrender.com"; for p in / "/js/app.js" "/css/styles.css" "/robots.txt" "/api/health"; do echo "--- $p"; curl -sSI "$BASE$p" | head -n 12; done'
