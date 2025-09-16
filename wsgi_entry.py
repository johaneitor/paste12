"""
Entrypoint robusto para Gunicorn en Render (v4).

- Usa P12_WSGI_MODULE (default 'wsgiapp') y P12_WSGI_CALLABLE como hints.
- Acepta SOLO callables con firma WSGI (environ, start_response).
- Factorías: intenta llamarlas SIN argumentos y valida que devuelvan WSGI.
- Evita confundir helpers (p.ej. _bump_counter) con la app.
"""
import os, importlib, inspect

SUBMODULES = ("wsgi", "app", "application", "main", "server")
CANDIDATE_NAMES = (
    "app","application","create_app","make_app","build_app","get_app",
    "inner_app","wsgi_app","api","serve","main",
    "_app","_application","_create_app","_make_app","_inner_app","_wsgi_app",
)

def _positional_names(fn):
    try:
        sig = inspect.signature(fn)
    except (ValueError, TypeError):
        return []
    names = []
    for p in sig.parameters.values():
        if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD):
            names.append(p.name)
    return names

def _is_wsgi_callable(obj):
    if not callable(obj):
        return False
    names = [n.lower() for n in _positional_names(obj)]
    # Debe aceptar EXACTAMENTE los dos primeros como environ/start_response
    if len(names) >= 2 and names[0] in ("environ","env") and "start_response" in names[1]:
        return True
    return False

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
        # No podemos inspeccionar: probá con llamada vacía y validá
        try:
            out = obj()
            return out if _is_wsgi_callable(out) else None
        except Exception:
            return None
    return None

def _pick_from_module(mod):
    # 1) Hint explícito
    hint = os.environ.get("P12_WSGI_CALLABLE")
    if hint and hasattr(mod, hint):
        obj = getattr(mod, hint)
        if _is_wsgi_callable(obj):
            return obj
        maybe = _maybe_call_factory(obj)
        if maybe:
            return maybe
        raise RuntimeError(f"P12_WSGI_CALLABLE='{hint}' no es WSGI válido en {mod.__name__}")

    # 2) Candidatos frecuentes
    for name in CANDIDATE_NAMES:
        if hasattr(mod, name):
            obj = getattr(mod, name)
            if _is_wsgi_callable(obj):
                return obj
            maybe = _maybe_call_factory(obj)
            if maybe:
                return maybe

    # 3) Escaneo (solo verdaderos WSGI, NO helpers sueltos)
    for name in dir(mod):
        if name.startswith("_"):  # evitamos helpers privados tipo _bump_counter
            continue
        obj = getattr(mod, name)
        if _is_wsgi_callable(obj):
            return obj

    # 4) Error con pistas
    public = [n for n in dir(mod) if not n.startswith("__")]
    raise RuntimeError(
        f"No encontré un WSGI app en '{mod.__name__}'. "
        f"Probé nombres: {', '.join(CANDIDATE_NAMES)}. "
        f"Atributos públicos: {', '.join(sorted(public)[:60])}"
    )

def _resolve_app():
    base = os.environ.get("P12_WSGI_MODULE", "wsgiapp")
    mod = importlib.import_module(base)

    # Intento en módulo base
    app = _pick_from_module(mod)
    if app:
        return app

    # Submódulos típicos (wsgi, app, application, main, server)
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
