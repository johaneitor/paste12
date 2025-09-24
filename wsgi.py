# WSGI mínima y robusta.
# Intenta (en orden): backend.create_app(), backend.app, backend.wsgi.app, contract_shim.application
from importlib import import_module

def _first_ok(cands):
    for mod_name, expr in cands:
        try:
            mod = import_module(mod_name)
            obj = mod
            for part in expr.split('.'):
                obj = getattr(obj, part)
            return obj
        except Exception:
            continue
    raise RuntimeError("no pude resolver una app WSGI válida")

cands = [
    ("backend", "create_app"),
    ("backend", "app"),
    ("backend.wsgi", "app"),
    ("contract_shim", "application"),
]

app_or_factory = _first_ok(cands)
application = app_or_factory() if callable(app_or_factory) else app_or_factory
