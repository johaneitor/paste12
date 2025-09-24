#!/usr/bin/env bash
set -euo pipefail

# 1) Entry que arma la WSGI app desde backend.create_app() (sin tocar wsgiapp)
cat > render_backend_entry.py <<'PY'
from importlib import import_module
import inspect

def _is_wsgi(obj):
    # función o objeto callable(environ, start_response) o Flask con wsgi_app
    if callable(obj) and not inspect.isclass(obj):
        try:
            sig = inspect.signature(obj)
            params = [p.name.lower() for p in sig.parameters.values()
                      if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
            if len(params) >= 2 and params[0] in ("environ", "env") and params[1] == "start_response":
                return True
        except Exception:
            pass
    call = getattr(obj, "__call__", None)
    if call and callable(call):
        try:
            sig = inspect.signature(call)
            params = [p.name.lower() for p in sig.parameters.values()
                      if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
            return len(params) >= 2 and params[0] in ("environ","env") and params[1] == "start_response"
        except Exception:
            pass
    if hasattr(obj, "wsgi_app") and callable(obj):
        return True
    return False

def _build():
    # 1) Camino sano: factory de backend
    try:
        be = import_module("backend")
        create_app = getattr(be, "create_app", None)
        if callable(create_app):
            app = create_app()
            if _is_wsgi(app):
                return app
    except Exception:
        pass

    # 2) Candidates clásicos (por si existe un app= en backend.*)
    candidates = [
        ("backend.app", "app"),
        ("backend.main", "app"),
        ("backend.wsgi", "app"),
        ("app", "app"),
        ("run", "app"),
    ]
    for modname, attr in candidates:
        try:
            mod = import_module(modname)
            obj = getattr(mod, attr, None)
            if obj and _is_wsgi(obj):
                return obj
        except Exception:
            pass

    tried = ", ".join([f"{m}:{a}" for m,a in candidates])
    raise RuntimeError(f"render_backend_entry: no encontré WSGI app (probé backend.create_app() y {tried})")

_APP = _build()

def app(environ, start_response):
    return _APP(environ, start_response)
PY

python - <<'PY'
import py_compile; py_compile.compile('render_backend_entry.py', doraise=True); print("✓ py_compile render_backend_entry.py OK")
PY

# 2) Start estable apuntando al entry nuevo (evita wsgiapp)
cat > start_render.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exec gunicorn render_backend_entry:app \
  --chdir /opt/render/project/src \
  -w "${WEB_CONCURRENCY:-2}" -k gthread --threads "${THREADS:-4}" \
  --timeout "${TIMEOUT:-120}" -b "0.0.0.0:${PORT}"
SH
chmod +x start_render.sh

git add render_backend_entry.py start_render.sh
git commit -m "ops: start estable desde backend.create_app() (evita wsgiapp en arranque)"
