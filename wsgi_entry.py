"""
Entrypoint robusto para Gunicorn en Render.
- Si la env P12_WSGI_CALLABLE está seteada, usa ese atributo (o factory sin args).
- Si no, intenta nombres comunes, y por último escanea wsgiapp en busca de:
  * Un callable con firma WSGI (environ, start_response), o
  * Una factoría sin argumentos que devuelva ese callable.
"""
import os, sys, inspect

CANDIDATE_NAMES = [
    # comunes
    "app", "application",
    # factorías frecuentes
    "create_app", "make_app", "build_app", "get_app",
    # otros nombres vistos en proyectos WSGI
    "inner_app", "wsgi_app", "api", "serve", "main",
]

def _is_wsgi_callable(obj):
    """Heurística liviana: callable que acepte al menos 2 args posicionales."""
    if not callable(obj):
        return False
    try:
        sig = inspect.signature(obj)
        # contar posicionales requeridos (sin default)
        req_pos = [p for p in sig.parameters.values()
                   if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)
                   and p.default is inspect._empty]
        # si tiene al menos 2, parece WSGI
        if len(req_pos) >= 2:
            return True
        # objetos con __call__ sin introspección fiable: aceptamos
        return False
    except (ValueError, TypeError):
        # tipos C o callables sin firma; aceptamos y que falle en runtime si no sirve
        return True

def _maybe_call_factory(obj):
    """Si el callable no requiere argumentos, intentalo como factoría."""
    try:
        sig = inspect.signature(obj)
        req_pos = [p for p in sig.parameters.values()
                   if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD)
                   and p.default is inspect._empty]
        if len(req_pos) == 0:
            return obj()
    except (ValueError, TypeError):
        # sin firma: probamos llamarlo sin args
        try:
            return obj()
        except Exception:
            return None
    return None

def _resolve_app():
    import importlib
    wsgiapp = importlib.import_module("wsgiapp")

    # 1) Hint explícito por env (ej: P12_WSGI_CALLABLE=inner_app o create_app)
    hint = os.environ.get("P12_WSGI_CALLABLE")
    if hint:
        if hasattr(wsgiapp, hint):
            obj = getattr(wsgiapp, hint)
            if _is_wsgi_callable(obj):
                return obj
            maybe = _maybe_call_factory(obj)
            if maybe and _is_wsgi_callable(maybe):
                return maybe
        raise RuntimeError(f"P12_WSGI_CALLABLE='{hint}' no es un callable WSGI válido en wsgiapp")

    # 2) Intento por nombres conocidos (var o factory)
    for name in CANDIDATE_NAMES:
        if hasattr(wsgiapp, name):
            obj = getattr(wsgiapp, name)
            if _is_wsgi_callable(obj):
                return obj
            maybe = _maybe_call_factory(obj)
            if maybe and _is_wsgi_callable(maybe):
                return maybe

    # 3) Escaneo: primero variables/callables que parezcan WSGI,
    # luego factorías sin argumentos que devuelvan algo WSGI.
    for name in dir(wsgiapp):
        if name.startswith("_"):
            continue
        obj = getattr(wsgiapp, name)
        if _is_wsgi_callable(obj):
            return obj

    for name in dir(wsgiapp):
        if name.startswith("_"):
            continue
        obj = getattr(wsgiapp, name)
        if callable(obj):
            maybe = _maybe_call_factory(obj)
            if maybe and _is_wsgi_callable(maybe):
                return maybe

    # 4) Mensaje de error claro con pistas
    public = [n for n in dir(wsgiapp) if not n.startswith("_")]
    raise RuntimeError(
        "No encontré un WSGI app en 'wsgiapp'. Probé: "
        + ", ".join(CANDIDATE_NAMES)
        + ". Atributos públicos vistos: "
        + ", ".join(sorted(public)[:40]) + ("..." if len(public) > 40 else "")
    )

app = _resolve_app()
