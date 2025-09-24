#!/usr/bin/env bash
set -euo pipefail

echo "→ Restaurando wsgiapp/__init__.py desde origin/main…"
git fetch origin --quiet
git checkout origin/main -- wsgiapp/__init__.py

echo "→ Prepend de exportación WSGI segura (application/app) sin raise…"
awk 'BEGIN{
  print "# --- P12 SAFE EXPORT (prepend) ---"
  print "def _p12_try_entry_app():"
  print "    try:"
  print "        from entry_main import app as _a"
  print "        return _a if callable(_a) else None"
  print "    except Exception:"
  print "        return None"
  print ""
  print "def _p12_try_legacy_resolver():"
  print "    try:"
  print "        ra = globals().get(\"_resolve_app\")"
  print "        if callable(ra):"
  print "            a = ra()"
  print "            return a if a else None"
  print "    except Exception:"
  print "        return None"
  print "    return None"
  print ""
  print "def application(environ, start_response):"
  print "    a = _p12_try_entry_app() or _p12_try_legacy_resolver()"
  print "    if a is None:"
  print "        start_response(\"500 Internal Server Error\", [(\"Content-Type\",\"text/plain; charset=utf-8\")])"
  print "        return [b\"wsgiapp: no pude resolver la WSGI app (entry_main o _resolve_app)\"]"
  print "    return a(environ, start_response)"
  print ""
  print "app = application"
  print "# --- END P12 SAFE EXPORT ---"
}
{ print }' wsgiapp/__init__.py > wsgiapp/__init__.py.new && mv wsgiapp/__init__.py.new wsgiapp/__init__.py

echo "→ Validando sintaxis…"
python - <<'PY'
import py_compile; py_compile.compile('wsgiapp/__init__.py', doraise=True); print("✓ py_compile wsgiapp/__init__.py OK")
PY

git add wsgiapp/__init__.py
git commit -m "ops: reset a origin/main y prepend de export WSGI seguro en wsgiapp (application/app sin raise)"
echo "✓ Patch listo"
