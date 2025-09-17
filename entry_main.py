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
    # 1) Intentos directos típicos (Flask/WSGI)
    for modname, attr in CANDIDATES:
        try:
            mod = import_module(modname)
            obj = getattr(mod, attr, None)
            if obj and (_is_wsgi_function(obj) or _is_wsgi_object(obj)):
                return obj
        except Exception:
            pass
    # 2) Fallback legacy: resolver interno de wsgiapp
    try:
        wa = import_module("wsgiapp")
        if hasattr(wa, "_resolve_app"):
            obj = wa._resolve_app()
            if obj and (_is_wsgi_function(obj) or _is_wsgi_object(obj)):
                return obj
    except Exception:
        pass
    tried = ", ".join([f"{m}:{a}" for m,a in CANDIDATES]) + " + wsgiapp._resolve_app()"
    raise RuntimeError(f"entry_main: no encontré una app WSGI válida (intenté {tried})")

_APP = _build()

def app(environ, start_response):
    return _APP(environ, start_response)
