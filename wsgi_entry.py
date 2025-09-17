"""
Entrypoint robusto para Gunicorn (v7):
- Solo acepta WSGI reales: funciones (environ,start_response) u objetos cuya __call__
  tenga esa firma, o con atributo 'wsgi_app'.
- Excluye clases, símbolos de 'typing', helpers privados, etc.
- Busca primero en módulos comunes y luego escanea el repo (sin venv/.git).
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
            names.append(p.name.lower())
    return names

def _looks_wsgi_function(obj):
    if not callable(obj) or inspect.isclass(obj):
        return False
    names = _positional_names(obj)
    return len(names) >= 2 and names[0] in ("environ","env") and names[1] == "start_response"

def _looks_wsgi_object(obj):
    # Objetos tipo Flask (instancias), u otros con __call__(environ,start_response)
    if inspect.isclass(obj):
        return False
    if getattr(obj, "__module__", "").startswith("typing"):
        return False
    if hasattr(obj, "wsgi_app") and callable(obj):
        # Flask expone wsgi_app y es invocable
        return True
    call = getattr(obj, "__call__", None)
    if call and callable(call):
        names = _positional_names(call)
        if len(names) >= 2 and names[0] in ("environ","env") and names[1] == "start_response":
            return True
    return False

def _is_private_name(name: str) -> bool:
    name = name.lower()
    return name.startswith("_") or "bump_counter" in name or "typing" in name

def _import_module(modname):
    try:
        return importlib.import_module(modname)
    except Exception:
        return None

def _pick_from_module(mod):
    # 1) nombres típicos (sin privados)
    for name in ("app","application","wsgi_app","inner_app"):
        if hasattr(mod, name):
            obj = getattr(mod, name)
            if _looks_wsgi_function(obj) or _looks_wsgi_object(obj):
                return obj
    # 2) factorías sin args que devuelvan WSGI
    for fac in ("create_app","make_app","build_app","get_app"):
        if hasattr(mod, fac):
            fn = getattr(mod, fac)
            if callable(fn) and not inspect.isclass(fn):
                try:
                    out = fn()
                    if _looks_wsgi_function(out) or _looks_wsgi_object(out):
                        return out
                except Exception:
                    pass
    # 3) escaneo de atributos públicos (evitar privados/sospechosos)
    for name in dir(mod):
        if _is_private_name(name):
            continue
        try:
            obj = getattr(mod, name)
        except Exception:
            continue
        if _looks_wsgi_function(obj) or _looks_wsgi_object(obj):
            return obj
    return None

def _module_candidates_from_fs():
    root = os.getcwd()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            if not f.endswith(".py"):
                continue
            if f in ("wsgi_entry.py",):
                continue
            rel = os.path.relpath(os.path.join(dirpath, f), root)
            parts = rel.split(os.sep)
            if parts[-1] == "__init__.py":
                parts = parts[:-1]
            else:
                parts[-1] = parts[-1].rsplit(".", 1)[0]
            if not parts:
                continue
            mod = ".".join(parts)
            if mod.startswith("tools.") or ".tests." in mod or mod.endswith(".tests"):
                continue
            yield mod

def _resolve_app():
    # 0) módulos priorizados
    tried = []
    for modname in PRIORITY_MODULES:
        mod = _import_module(modname)
        tried.append(f"{modname} {'OK' if mod else 'fail'}")
        if not mod:
            continue
        app = _pick_from_module(mod)
        if app:
            return app
    # 1) escaneo del repo
    for modname in _module_candidates_from_fs():
        mod = _import_module(modname)
        if not mod:
            continue
        app = _pick_from_module(mod)
        if app:
            return app
    raise RuntimeError("No pude localizar una app WSGI. Probados: " + ", ".join(tried))

app = _resolve_app()
