"""
Entrypoint robusto para Gunicorn en Render (v5).
- Respeta P12_WSGI_MODULE (default 'wsgiapp') y P12_WSGI_CALLABLE.
- Solo acepta callables WSGI reales (environ, start_response).
- Factorías: intenta sin args y valida que retornen WSGI.
- Incluye '_resolve_app' como factoría candidata.
"""
import os, importlib, inspect

SUBMODULES = ("wsgi", "app", "application", "main", "server")
CANDIDATE_NAMES = (
    # públicos
    "app","application","create_app","make_app","build_app","get_app",
    "inner_app","wsgi_app","api","serve","main",
    # privados comunes y factoría real de este proyecto
    "_app","_application","_create_app","_make_app","_inner_app","_wsgi_app","_resolve_app",
)

def _positional_names(fn):
    try:
        sig = inspect.signature(fn)
    except (ValueError, TypeError):
        return []
    return [p.name for p in sig.parameters.values()
            if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)]

def _is_wsgi_callable(obj):
    if not callable(obj):
        return False
    names = [n.lower() for n in _positional_names(obj)]
    return len(names) >= 2 and names[0] in ("environ","env") and "start_response" in names[1]

def _maybe_call_factory(obj):
    if not callable(obj):
        return None
    try:
        sig = inspect.signature(obj)
        req = [p for p in sig.parameters.values()
               if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)
               and p.default is inspect._empty]
        if len(req) == 0:
            out = obj()
            return out if _is_wsgi_callable(out) else None
    except (ValueError, TypeError):
        try:
            out = obj()
            return out if _is_wsgi_callable(out) else None
        except Exception:
            return None
    return None

def _pick_from_module(mod):
    hint = os.environ.get("P12_WSGI_CALLABLE")
    if hint and hasattr(mod, hint):
        obj = getattr(mod, hint)
        if _is_wsgi_callable(obj):
            return obj
        maybe = _maybe_call_factory(obj)
        if maybe:
            return maybe
        raise RuntimeError(f"P12_WSGI_CALLABLE='{hint}' no es WSGI válido en {mod.__name__}")

    for name in CANDIDATE_NAMES:
        if hasattr(mod, name):
            obj = getattr(mod, name)
            if _is_wsgi_callable(obj):
                return obj
            maybe = _maybe_call_factory(obj)
            if maybe:
                return maybe

    # Escaneo público (evita helpers con '_')
    for name in dir(mod):
        if name.startswith("_"):
            continue
        obj = getattr(mod, name)
        if _is_wsgi_callable(obj):
            return obj

    public = [n for n in dir(mod) if not n.startswith("__")]
    raise RuntimeError(
        f"No encontré un WSGI app en '{mod.__name__}'. Probé: {', '.join(CANDIDATE_NAMES)}. "
        f"Atributos públicos: {', '.join(sorted(public)[:60])}"
    )

def _resolve_app():
    base = os.environ.get("P12_WSGI_MODULE", "wsgiapp")
    mod = importlib.import_module(base)
    app = _pick_from_module(mod)
    if app:
        return app
    for sub in SUBMODULES:
        try:
            smod = importlib.import_module(f"{base}.{sub}")
        except Exception:
            continue
        app = _pick_from_module(smod)
        if app:
            return app
    raise RuntimeError(f"No encontré WSGI app en módulo '{base}' ni submódulos {SUBMODULES}")

app = _resolve_app()
