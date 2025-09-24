#!/usr/bin/env bash
set -euo pipefail
cp -a wsgiapp/__init__.py "wsgiapp/__init__.py.bak_safe_$(date -u +%Y%m%d-%H%M%SZ)"

# Prepend: exportación segura al tope del archivo (evita que explote el import)
awk 'BEGIN{print "# --- P12 SAFE EXPORT (prepend) ---";
            print "def _p12_try_entry_app():";
            print "    try:";
            print "        from entry_main import app as _a";
            print "        return _a if callable(_a) else None";
            print "    except Exception:";
            print "        return None";
            print "";
            print "def _p12_try_legacy_resolver():";
            print "    try:";
            print "        # Si _resolve_app existe más abajo, lo tomamos cuando el módulo termine de cargar";
            print "        ra = globals().get(\"_resolve_app\")";
            print "        if callable(ra):";
            print "            a = ra()";
            print "            return a if a else None";
            print "    except Exception:";
            print "        return None";
            print "";
            print "def app(environ, start_response):";
            print "    a = _p12_try_entry_app() or _p12_try_legacy_resolver()";
            print "    if a is None:";
            print "        start_response(\"500 Internal Server Error\", [(\"Content-Type\",\"text/plain; charset=utf-8\")])";
            print "        return [b\"wsgiapp: no pude resolver la WSGI app (entry_main o _resolve_app)\"]";
            print "    return a(environ, start_response)";
            print "";
            print "application = app";
            print "# --- END P12 SAFE EXPORT ---"} {print $0}' \
    wsgiapp/__init__.py > wsgiapp/__init__.py.new && mv wsgiapp/__init__.py.new wsgiapp/__init__.py

python - <<'PY'
import py_compile; py_compile.compile('wsgiapp/__init__.py', doraise=True); print("✓ py_compile wsgiapp/__init__.py OK")
PY

git add wsgiapp/__init__.py
git commit -m "ops: prepend export seguro en wsgiapp (application/app) con fallback controlado"
