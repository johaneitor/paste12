#!/usr/bin/env bash
set -euo pipefail

# 1) entry_main.py SIN fallback a wsgiapp (evita recursión)
cat > entry_main.py <<'PY'
from importlib import import_module
import inspect

CANDIDATES = [
    ("backend.app", "app"),
    ("backend.main", "app"),
    ("backend.wsgi", "app"),
    ("app", "app"),
    ("run", "app"),
]

def _positional_names(fn):
    try:
        sig = inspect.signature(fn)
    except (ValueError, TypeError):
        return []
    return [p.name.lower() for p in sig.parameters.values()
            if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]

def _is_wsgi_function(obj):
    if not callable(obj) or inspect.isclass(obj):
        return False
    names = _positional_names(obj)
    return len(names) >= 2 and names[0] in ("environ","env") and names[1] == "start_response"

def _is_wsgi_object(obj):
    if inspect.isclass(obj):
        return False
    if hasattr(obj, "wsgi_app") and callable(obj):
        return True
    call = getattr(obj, "__call__", None)
    if call and callable(call):
        names = _positional_names(call)
        return len(names) >= 2 and names[0] in ("environ","env") and names[1] == "start_response"
    return False

def _build():
    for modname, attr in CANDIDATES:
        try:
            mod = import_module(modname)
            obj = getattr(mod, attr, None)
            if obj and (_is_wsgi_function(obj) or _is_wsgi_object(obj)):
                return obj
        except Exception:
            pass
    tried = ", ".join([f"{m}:{a}" for m,a in CANDIDATES])
    raise RuntimeError(f"entry_main: no encontré una app WSGI válida (intenté {tried})")

_APP = _build()

def app(environ, start_response):
    return _APP(environ, start_response)
PY

python - <<'PY'
import py_compile; py_compile.compile('entry_main.py', doraise=True); print("✓ py_compile entry_main.py OK")
PY

# 2) Alias directo en wsgiapp/__init__.py → entry_main:app
cp -a wsgiapp/__init__.py wsgiapp/__init__.py.bak_alias_$(date -u +%Y%m%d-%H%M%SZ)
cat >> wsgiapp/__init__.py <<'PY'

# --- P12 alias: exportar app desde entry_main para tolerar 'wsgiapp:app' ---
try:
    from entry_main import app as app
except Exception as e:
    raise RuntimeError(f"wsgiapp alias → entry_main:app falló: {e}")
# --- fin alias P12 ---
PY

python - <<'PY'
import py_compile; py_compile.compile('wsgiapp/__init__.py', doraise=True); print("✓ py_compile wsgiapp/__init__.py OK")
PY

git add entry_main.py wsgiapp/__init__.py
git commit -m "ops: alias wsgiapp:app → entry_main:app y entry_main sin fallback (anti-blueprint)"
