"""
Entrypoint robusto para Gunicorn (v8)
- Acepta SOLO WSGI reales:
  * Función con firma (environ, start_response)
  * Objeto invocable cuya __call__(environ, start_response) o que tenga .wsgi_app
- Excluye: clases, símbolos de 'typing'/'collections.abc', helpers privados (_...),
  y cualquier cosa sospechosa.
- Orden de resolución:
  1) Hints: APP_MODULE ('mod:attr' o 'mod:factory()'), P12_WSGI_MODULE/CALLABLE
  2) Lista wsgiapp.CANDIDATES (si existe)
  3) Módulos comunes (wsgiapp, backend.app/main/wsgi, app, run, server, wsgi, application)
  4) Scan del repo (sin .git/.venv/venv/__pycache__/node_modules/tools/tests)
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

def _from_typing_or_abc(obj):
    mod = getattr(obj, "__module__", "") or ""
    return mod.startswith("typing") or mod.startswith("collections.abc")

def _looks_wsgi_function(obj):
    if not callable(obj): return False
    if inspect.isclass(obj): return False
    if _from_typing_or_abc(obj): return False
    names = _positional_names(obj)
    return len(names) >= 2 and names[0] in ("environ","env") and names[1] == "start_response"

def _looks_wsgi_object(obj):
    if inspect.isclass(obj): return False
    if _from_typing_or_abc(obj): return False
    if hasattr(obj, "wsgi_app") and callable(obj):
        return True
    call = getattr(obj, "__call__", None)
    if call and callable(call) and not _from_typing_or_abc(call):
        names = _positional_names(call)
        if len(names) >= 2 and names[0] in ("environ","env") and names[1] == "start_response":
            return True
    return False

def _is_public_candidate_name(name: str) -> bool:
    n = name.lower()
    if n.startswith("_"): return False
    if "bump_counter" in n: return False
    if n in {"callable","tuple"}: return False
    return True

def _import_module(modname):
    try:
        return importlib.import_module(modname)
    except Exception:
        return None

def _load_modattr(spec: str):
    # spec: "mod:attr" o "mod:factory()"
    if ":" not in spec: return None
    modname, attr = spec.split(":", 1)
    call = attr.endswith("()")
    if call: attr = attr[:-2]
    mod = _import_module(modname.strip())
    if not mod or not hasattr(mod, attr): return None
    obj = getattr(mod, attr)
    if call:
        try:
            obj = obj()
        except Exception:
            return None
    if _looks_wsgi_function(obj) or _looks_wsgi_object(obj):
        return obj
    return None

def _pick_from_module(mod):
    # 1) nombres típicos
    for name in ("app","application","wsgi_app","inner_app"):
        if hasattr(mod, name):
            obj = getattr(mod, name)
            if _looks_wsgi_function(obj) or _looks_wsgi_object(obj):
                return obj
    # 2) factorías sin args
    for fac in ("create_app","make_app","build_app","get_app"):
        if hasattr(mod, fac):
            fn = getattr(mod, fac)
            if callable(fn) and not inspect.isclass(fn) and not _from_typing_or_abc(fn):
                try:
                    out = fn()
                    if _looks_wsgi_function(out) or _looks_wsgi_object(out):
                        return out
                except Exception:
                    pass
    # 3) atributos públicos
    for name in dir(mod):
        if not _is_public_candidate_name(name): continue
        try: obj = getattr(mod, name)
        except Exception: continue
        if _looks_wsgi_function(obj) or _looks_wsgi_object(obj):
            return obj
    return None

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
                parts[-1] = parts[-1].rsplit(".", 1)[0]
            if not parts: continue
            mod = ".".join(parts)
            # saltar tools y tests
            if mod.startswith("tools.") or ".tests." in mod or mod.endswith(".tests"):
                continue
            yield mod

def _try_hints():
    # APP_MODULE hint (del propio wsgiapp)
    appmod = os.environ.get("APP_MODULE")
    if appmod:
        obj = _load_modattr(appmod.strip())
        if obj: return obj
    # P12 hints
    pmod = os.environ.get("P12_WSGI_MODULE")
    pcall = os.environ.get("P12_WSGI_CALLABLE")
    if pmod and pcall:
        spec = f"{pmod.strip()}:{pcall.strip()}"
        obj = _load_modattr(spec)
        if obj: return obj
    if pmod:
        # probar nombres típicos sobre pmod
        mod = _import_module(pmod.strip())
        if mod:
            obj = _pick_from_module(mod)
            if obj: return obj
    if pcall:
        # buscar pcall en módulos prioritarios
        for mn in PRIORITY_MODULES:
            mod = _import_module(mn)
            if mod and hasattr(mod, pcall):
                obj = getattr(mod, pcall)
                if _looks_wsgi_function(obj) or _looks_wsgi_object(obj):
                    return obj
    return None

def _try_wsgiapp_candidates():
    wa = _import_module("wsgiapp")
    if not wa: return None
    cands = getattr(wa, "CANDIDATES", None)
    if isinstance(cands, (list, tuple)):
        for spec in cands:
            if isinstance(spec, str):
                obj = _load_modattr(spec)
                if obj: return obj
    # como fallback, intentar su factoría si existe y NO requiere APP_MODULE
    if hasattr(wa, "_resolve_app"):
        try:
            obj = wa._resolve_app()
            # Si _resolve_app() devolvió algo legítimo, lo aceptamos
            if _looks_wsgi_function(obj) or _looks_wsgi_object(obj):
                return obj
        except Exception:
            pass
    return None

def _resolve_app():
    # 1) Hints
    obj = _try_hints()
    if obj: return obj

    # 2) CANDIDATES de wsgiapp (si los hay)
    obj = _try_wsgiapp_candidates()
    if obj: return obj

    # 3) Módulos priorizados
    for mn in PRIORITY_MODULES:
        mod = _import_module(mn)
        if not mod: continue
        obj = _pick_from_module(mod)
        if obj: return obj

    # 4) Scan del repo
    for mn in _module_candidates_from_fs():
        mod = _import_module(mn)
        if not mod: continue
        obj = _pick_from_module(mod)
        if obj: return obj

    raise RuntimeError("wsgi_entry(v8): No pude localizar una app WSGI válida en el proyecto.")

app = _resolve_app()
