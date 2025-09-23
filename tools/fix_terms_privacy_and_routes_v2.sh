#!/usr/bin/env bash
set -euo pipefail

CLIENT_ID="${1:-ca-pub-9479870293204581}"
HTML_DIR="frontend"
TERMS="${HTML_DIR}/terms.html"
PRIV="${HTML_DIR}/privacy.html"

[[ -d "$HTML_DIR" ]] || mkdir -p "$HTML_DIR"

ts() { date -u +%Y%m%d-%H%M%SZ; }

tmpl_page() {
  local TITLE="$1"
  cat <<PAGE
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${TITLE}</title>
<link rel="stylesheet" href="/css/styles.css">
<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${CLIENT_ID}" crossorigin="anonymous"></script>
<style>
  body{font:16px/1.55 system-ui,Segoe UI,Roboto,Arial;margin:2rem;max-width:56rem}
  main{display:block}
  footer{margin-top:2rem;opacity:.85}
  .stats{position:fixed;right:.75rem;bottom:.75rem;display:flex;gap:.5rem;background:#fff8;border:1px solid #0001;padding:.4rem .6rem;border-radius:.8rem;backdrop-filter:saturate(1.8) blur(6px)}
  .stats span b{font-weight:700}
</style>
</head>
<body>
<main>
  <h1>${TITLE}</h1>
  <p>Documento ${TITLE} de Paste12.</p>
  <p><a href="/">Volver</a></p>
</main>
<div id="p12-stats" class="stats">
  <span class="views" data-views="0">👁️ <b>0</b></span>
  <span class="likes" data-likes="0">❤️ <b>0</b></span>
  <span class="reports" data-reports="0">🚩 <b>0</b></span>
</div>
<footer>
  <a href="/terms">Términos y Condiciones</a> ·
  <a href="/privacy">Política de Privacidad</a>
</footer>
</body>
</html>
PAGE
}

# === 1) Crear/actualizar páginas ===
BK="frontend/index.$(ts).legal.bak"
[[ -f frontend/index.html ]] && cp -f frontend/index.html "$BK" && echo "[backup] $BK"

if [[ ! -f "$TERMS" ]]; then tmpl_page "Términos y Condiciones" > "$TERMS" && echo "[create] $TERMS"; fi
if [[ ! -f "$PRIV"  ]]; then tmpl_page "Política de Privacidad" > "$PRIV"  && echo "[create] $PRIV";  fi

# === 2) Asegurar rutas en backend/routes.py y que wsgi.py las importe ===
python - <<'PY'
import io, os, re, sys
routes_p = "backend/routes.py"
os.makedirs(os.path.dirname(routes_p), exist_ok=True)
src = ""
if os.path.exists(routes_p):
    src = io.open(routes_p, "r", encoding="utf-8").read()

need_terms = re.search(r"@.*route\(['\"]/terms", src or "", re.I) is None
need_priv  = re.search(r"@.*route\(['\"]/privacy", src or "", re.I) is None
need_bp    = re.search(r"Blueprint\\(", src or "", re.I) is None

if not src:
    src = ""

head = "from flask import Blueprint, send_from_directory\n\nweb = Blueprint('web', __name__)\n"
terms = "@web.route('/terms')\ndef _terms():\n    return send_from_directory('frontend', 'terms.html')\n\n"
priv  = "@web.route('/privacy')\ndef _privacy():\n    return send_from_directory('frontend', 'privacy.html')\n\n"
registrar = """
# Intento de registro automático del blueprint en la app si está disponible
try:
    from backend import app as _app  # type: ignore
except Exception:
    _app = None
try:
    from wsgi import application as _wapp  # type: ignore
except Exception:
    _wapp = None
try:
    tgt = _app or _wapp
    if tgt and hasattr(tgt, 'register_blueprint'):
        if 'web' not in {bp.name for bp in getattr(tgt, 'blueprints', {}).values()}:
            tgt.register_blueprint(web)  # type: ignore
except Exception:
    pass
"""

changed = False
out = src

if need_bp:
    out = head + out
    changed = True
if need_terms:
    out = out + ("\n" if not out.endswith("\n") else "") + terms
    changed = True
if need_priv:
    out = out + ("\n" if not out.endswith("\n") else "") + priv
    changed = True

# Añadir registrador si no existe algo equivalente
if re.search(r"register_blueprint\\(web\\)", out) is None:
    out = out + ("\n" if not out.endswith("\n") else "") + registrar
    changed = True

if changed:
    io.open(routes_p, "w", encoding="utf-8").write(out)
    print(f"[routes] actualizado {routes_p}")
else:
    print("[routes] OK (ya tenía blueprint y rutas)")

# Forzar import en wsgi.py
wsgi_p = "wsgi.py"
if os.path.exists(wsgi_p):
    s = io.open(wsgi_p, "r", encoding="utf-8").read()
else:
    s = ""
if re.search(r"import\\s+backend\\.routes", s) is None:
    if s:
        s = s.replace("\n", "\n", 1) + "\nimport backend.routes  # ensure web routes\n"
    else:
        s = "import backend.routes  # ensure web routes\n"
    io.open(wsgi_p, "w", encoding="utf-8").write(s)
    print("[wsgi] import backend.routes añadido")
else:
    print("[wsgi] import backend.routes ya estaba")
PY

python - <<'PY'
import py_compile
for f in ("backend/routes.py","wsgi.py"):
    try:
        py_compile.compile(f, doraise=True)
        print(f"[py_compile] OK {f}")
    except Exception as e:
        print(f"[py_compile] FAIL {f}: {e}")
        raise
PY

echo "Listo. Ahora puedes probar y luego hacer push."
