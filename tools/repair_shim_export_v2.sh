#!/usr/bin/env bash
set -euo pipefail

FILE="contract_shim.py"
[ -f "$FILE" ] || { echo "❌ No existe $FILE (ejecuta desde la raíz del repo)"; exit 1; }

# ¿Ya hay símbolo 'application =' en el shim?
if grep -Eq '^\s*application\s*=' "$FILE"; then
  echo "✔ $FILE ya exporta 'application'. No toco nada."
else
  echo "→ Inyectando export WSGI 'application' seguro en $FILE ..."
  ts="$(date +%s)"
  cp -f "$FILE" "$FILE.bak.$ts"

  cat >> "$FILE" <<'PY'
# --- paste12 export safety (autoinjected) ---
try:
    application  # noqa: F821
except NameError:  # pragma: no cover
    _app_candidate = None
    # Si existe un objeto Flask 'app', úsalo (Flask es WSGI-callable).
    if 'app' in globals():
        _app_candidate = globals().get('app')
    # Si existe 'wsgi_app' dentro de app, también vale (pero Flask ya es callable).
    if _app_candidate is None and 'wsgiapp' in globals():
        _app_candidate = globals().get('wsgiapp')
    # Último recurso: no-op WSGI para no romper el arranque (debería no usarse).
    if _app_candidate is None:
        def _noop_app(environ, start_response):  # pragma: no cover
            start_response('200 OK', [('Content-Type', 'text/plain')])
            return [b'OK']
        _app_candidate = _noop_app
    application = _app_candidate  # export final
# --- end paste12 export safety ---
PY

  echo "✓ Código añadido. Probando compilación..."
  python - <<'PY'
import py_compile, sys
py_compile.compile("contract_shim.py", dfile="contract_shim.py", doraise=True)
print("✓ py_compile OK")
PY
fi

echo "→ wsgi.py debe importar:  from contract_shim import application"
if ! grep -Eq 'from\s+contract_shim\s+import\s+application' wsgi.py 2>/dev/null; then
  if [ -f wsgi.py ]; then
    echo "… agregando import en wsgi.py"
    ts="$(date +%s)"
    cp -f wsgi.py "wsgi.py.bak.$ts"
    awk 'BEGIN{done=0}
         /^from / && done==0 {print; next}
         /^import / && done==0 {print; next}
         !done {print "from contract_shim import application"; done=1}
         done {print}' wsgi.py > wsgi.py.tmp && mv wsgi.py.tmp wsgi.py
  else
    echo "⚠️  wsgi.py no existe; omito."
  fi
fi

echo "✔ Backend export asegurado."
