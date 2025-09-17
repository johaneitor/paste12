"""
Entrypoint robusto para Gunicorn (v6):
- Tolera apps WSGI como objetos (ej. Flask) o funciones.
- Prioriza módulos comunes: wsgiapp, backend.app/main/wsgi, app, run, server.
- Si no encuentra, escanea el árbol del proyecto (sin venv/.git/__pycache__).
- Evita helpers privados (_bump_counter, etc.).
- Sin depender de APP_MODULE.
"""
import os, sys, importlib, inspect, types

PRIORITY_MODULES = [
    "wsgiapp",
    "backend.app", "backend.main", "backend.wsgi",
    "app", "run", "server", "application", "wsgi",
]

SKIP_DIRS = {".git", ".venv", "venv", "__pycache__", "node_modules"}

def _positional_names(fn):
    try:
        sig = inspect.signature(fn)
    except (ValueError, TypeError):
        return []
    names = []
    for p in sig.parameters.values():
        if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD):
            names.append(p.name)
    return [n.lower() for n in names]

def _looks_wsgi_function(obj):
    if not callable(obj): return False
    names = _positional_names(obj)
    # Firma clásica WSGI
    return len(names) >= 2 and names[0] in ("environ","env") and "start_response" in names[1]

def _looks_wsgi_object(obj):
    # Objetos tipo Flask u otros que son WSGI-callables
    # Heurística: tienen atributo 'wsgi_app' o '__call__' y NO son helper privado
    if hasattr(obj, "wsgi_app"):  # Flask, Starlette, etc.
        return True
    if callable(obj) and not isinstance(obj, (types.FunctionType, types.BuiltinFunctionType)):
        # callable no-función (clase con __call__)
        return True
    return False

def _is_private_name(name: str) -> bool:
    return name.startswith("_") or "bump_counter" in name

def _module_candidates_from_fs():
    root = os.getcwd()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            if not f.endswith(".py"): continue
            if f in ("wsgi_entry.py",): continue
            rel = os.path.relpath(os.path.join(dirpath, f), root)
            parts = rel.split(os.sep)
            if parts[-1] == "__init__.py":
                parts = parts[:-1]
            else:
                parts[-1] = parts[-1].rsplit(".",1)[0]
            if not parts: continue
            mod = ".".join(parts)
            # Ignorar tests y scripts de tools (normalmente no exportan WSGI)
            if mod.startswith("tools.") or mod.endswith(".tests") or ".tests." in mod:
                continue
            yield mod

def _import_module(modname):
    try:
        return importlib.import_module(modname)
    except Exception:
        return None

def _pick_from_module(mod):
    # 1) nombres típicos
    for name in ("app","application","wsgi_app","inner_app"):
        if hasattr(mod, name):
            obj = getattr(mod, name)
            if _looks_wsgi_function(obj) or _looks_wsgi_object(obj):
                return obj
    # 2) factorías sin args que devuelvan WSGI
    for fac in ("create_app","make_app","build_app","get_app"):
        if hasattr(mod, fac):
            fn = getattr(mod, fac)
            if callable(fn):
                try:
                    out = fn()
                    if _looks_wsgi_function(out) or _looks_wsgi_object(out):
                        return out
                except Exception:
                    pass
    # 3) escaneo de atributos públicos
    for name in dir(mod):
        if _is_private_name(name):  # evita helpers privados
            continue
        try:
            obj = getattr(mod, name)
        except Exception:
            continue
        if _looks_wsgi_function(obj) or _looks_wsgi_object(obj):
            return obj
    return None

def _resolve_app():
    # 0) Intentos de alta prioridad
    tried = []
    for modname in PRIORITY_MODULES:
        mod = _import_module(modname)
        tried.append(modname + (" (ok)" if mod else " (fail)"))
        if not mod: continue
        app = _pick_from_module(mod)
        if app:
            return app
    # 1) Escaneo del árbol
    for modname in _module_candidates_from_fs():
        mod = _import_module(modname)
        if not mod: continue
        app = _pick_from_module(mod)
        if app:
            return app
    # 2) Error con pistas
    raise RuntimeError("No pude localizar una app WSGI en módulos probados: " + ", ".join(tried))

# Resolvemos UNA VEZ en import (evita condiciones de carrera)
app = _resolve_app()
