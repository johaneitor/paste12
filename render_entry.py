from importlib import import_module
import inspect

def _is_wsgi(obj):
    if callable(obj) and not inspect.isclass(obj):
        try:
            sig = inspect.signature(obj)
            params = [p.name.lower() for p in sig.parameters.values()
                      if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
            return len(params) >= 2 and params[0] in ("environ","env") and params[1] == "start_response"
        except Exception:
            return False
    # objetos con __call__(environ, start_response) o Flask-like con wsgi_app
    call = getattr(obj, "__call__", None)
    if call and callable(call):
        try:
            sig = inspect.signature(call)
            params = [p.name.lower() for p in sig.parameters.values()
                      if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]
            return len(params) >= 2 and params[0] in ("environ","env") and params[1] == "start_response"
        except Exception:
            return False
    if hasattr(obj, "wsgi_app") and callable(obj):
        return True
    return False

def _resolve():
    wa = import_module("wsgiapp")
    # 1) export estándar
    for name in ("app", "application"):
        obj = getattr(wa, name, None)
        if obj and _is_wsgi(obj):
            return obj
    # 2) resolver interno si existe
    res = getattr(wa, "_resolve_app", None)
    if callable(res):
        obj = res()
        if obj and _is_wsgi(obj):
            return obj
    raise RuntimeError("render_entry: no pude resolver la WSGI app desde wsgiapp")

_APP = _resolve()

def app(environ, start_response):
    return _APP(environ, start_response)
