"""
Entrypoint robusto para Gunicorn en Render.

Orden de resolución:
  1) Módulo por env P12_WSGI_MODULE (default: 'wsgiapp').
  2) Atributo/factoría indicado por env P12_WSGI_CALLABLE (si existe).
  3) Submódulos comunes: wsgi, app, application, main, server.
  4) Nombres típicos (incluyendo privados con '_').
  5) Escaneo de callables WSGI o factorías sin args que retornen uno.

Si no encuentra, lanza un error con pistas de atributos públicos.
"""
import os, importlib, inspect

SUBMODULES = ("wsgi", "app", "application", "main", "server")
CANDIDATE_NAMES = [
    # públicos
    "app","application","create_app","make_app","build_app","get_app",
    "inner_app","wsgi_app","api","serve","main",
    # privados comunes
    "_app","_application","_create_app","_make_app","_inner_app","_wsgi_app",
]

def _is_wsgi_callable(obj):
    if not callable(obj):
        return False
    try:
        sig = inspect.signature(obj)
        req = [p for p in sig.parameters.values()
               if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)
               and p.default is inspect._empty]
        return len(req) >= 2  # environ, start_response
    except (ValueError, TypeError):
        # Callables C / objetos con __call__ sin firma util; aceptamos
        return True

def _maybe_call_factory(obj):
    try:
        sig = inspect.signature(obj)
        req = [p for p in sig.parameters.values()
               if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)
               and p.default is inspect._empty]
        if len(req) == 0:
            maybe = obj()
            if _is_wsgi_callable(maybe):
                return maybe
    except (ValueError, TypeError):
        try:
            maybe = obj()
            if _is_wsgi_callable(maybe):
                return maybe
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

    # 2) Candidatos por nombre
    for name in CANDIDATE_NAMES:
        if hasattr(mod, name):
            obj = getattr(mod, name)
            if _is_wsgi_callable(obj):
                return obj
            maybe = _maybe_call_factory(obj)
            if maybe:
                return maybe

    # 3) Escaneo de callables directos
    for name in dir(mod):
        obj = getattr(mod, name)
        if _is_wsgi_callable(obj):
            return obj
    # 4) Escaneo de factorías sin args
    for name in dir(mod):
        obj = getattr(mod, name)
        if callable(obj):
            maybe = _maybe_call_factory(obj)
            if maybe:
                return maybe
    return None

def _resolve_app():
    base = os.environ.get("P12_WSGI_MODULE", "wsgiapp")
    # 0) Módulo base
    mod = importlib.import_module(base)
    app = _pick_from_module(mod)
    if app:
        return app

    # 1) Submódulos típicos
    for sub in SUBMODULES:
        try:
            smod = importlib.import_module(f"{base}.{sub}")
        except Exception:
            continue
        app = _pick_from_module(smod)
        if app:
            return app

    # 2) Error con pistas
    public = [n for n in dir(mod) if not n.startswith("__")]
    raise RuntimeError(
        f"No encontré un WSGI app en '{base}'. "
        f"Probé submódulos: {', '.join(SUBMODULES)} y nombres: {', '.join(CANDIDATE_NAMES)}. "
        f"Atributos públicos en {base}: {', '.join(sorted(public)[:60])}"
    )

app = _resolve_app()
