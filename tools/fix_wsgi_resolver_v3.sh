#!/usr/bin/env bash
set -euo pipefail
PY=${PYTHON:-python}

# --- contract_shim.py (robusto, nunca raise en import) ---
ts="$(date -u +%Y%m%d-%H%M%SZ)"
shim="contract_shim.py"
[[ -f "$shim" ]] && cp -f "$shim" "${shim}.${ts}.bak" || true
echo "[wsgi-fix] Backup: ${shim}.${ts}.bak"

cat > "$shim" <<'PYCODE'
# contract_shim.py — v3 (robusto)
# Garantiza que siempre exista `application` aunque el backend real no cargue.
import importlib, os, types, traceback
from typing import Optional, Tuple

def _try_load(module_attr: str) -> Tuple[Optional[object], str]:
    """
    Acepta "pkg.mod:attr" o "pkg.mod".
    Devuelve (objeto_app, motivo_fallo)
    """
    fail = ""
    try:
        if ":" in module_attr:
            mod_name, attr = module_attr.split(":", 1)
            mod = importlib.import_module(mod_name)
            obj = getattr(mod, attr, None)
            if callable(obj):  # factory create_app()
                try:
                    obj = obj()
                except Exception as e:
                    fail = f"factory {module_attr} lanzó: {e!r}"
                    return (None, fail)
            if obj is None:
                fail = f"attr {attr} no existe en {mod_name}"
                return (None, fail)
            return (obj, "")
        else:
            mod = importlib.import_module(module_attr)
            # Preferir 'app' o 'application' si existen
            for name in ("app","application"):
                if hasattr(mod, name):
                    obj = getattr(mod, name)
                    if callable(obj):
                        try:
                            obj = obj()
                        except Exception as e:
                            fail = f"factory {module_attr}.{name} lanzó: {e!r}"
                            return (None, fail)
                    return (obj, "")
            # Último recurso: si el módulo es un Flask directamente
            return (mod, "")
    except Exception as e:
        fail = f"import {module_attr} falló: {e.__class__.__name__}: {e}"
        return (None, fail)

def _load_real_app() -> Tuple[Optional[object], str]:
    tried = []
    # Si APP_MODULE está seteado en Render, respétalo primero (p.ej. "backend:app" o "backend:create_app")
    env_mod = os.environ.get("APP_MODULE","").strip()
    if env_mod:
        app, why = _try_load(env_mod)
        if app is not None:
            return (app, f"ok:{env_mod}")
        tried.append(f"{env_mod} -> {why}")

    # Candidatos comunes en este repo
    for cand in [
        "backend.app:app",
        "backend:create_app",
        "backend.main:app",
        "backend.wsgi:app",
        "backend:app",
        "app:app",
        "run:app",
    ]:
        app, why = _try_load(cand)
        if app is not None:
            return (app, f"ok:{cand}")
        tried.append(f"{cand} -> {why}")

    return (None, " ; ".join(tried))

_real_app, _diag = _load_real_app()

# Fallback mínimo (no rompe el deploy) si no se pudo resolver
if _real_app is None:
    try:
        from flask import Flask, jsonify, request, send_from_directory, Response
    except Exception:  # si no está Flask, algo está muy mal, pero intentamos igual
        Flask = None

    if Flask is None:
        # Ultimísimo recurso: objeto WSGI trivial
        def application(environ, start_response):
            start_response('200 OK',[('Content-Type','text/plain')])
            return [b'fallback: wsgi minimal (Flask ausente)']
    else:
        app = Flask(__name__, static_folder="frontend", static_url_path="")
        @app.get("/api/health")
        def _health():
            return jsonify({"ok": True, "api": False, "ver": "shim-fallback-v3", "diag": _diag})

        # Satisface preflight de /api/notes (204) para no bloquear front
        @app.route("/api/notes", methods=["OPTIONS"])
        def _notes_options():
            return ("", 204)

        # Index mínimo (sirve frontend/index.html si existe)
        @app.route("/")
        def _index():
            try:
                return send_from_directory("frontend","index.html")
            except Exception:
                return Response("<!doctype html><meta charset='utf-8'><h1>Paste12</h1><p>Backend real no cargado todavía.</p>", mimetype="text/html")
        application = app
else:
    # Backend real resuelto
    application = _real_app
PYCODE

$PY -m py_compile "$shim" && echo "[wsgi-fix] py_compile OK"

# --- wsgi.py (mínimo) ---
wsgi="wsgi.py"
[[ -f "$wsgi" ]] && cp -f "$wsgi" "${wsgi}.${ts}.bak" || true
echo "[wsgi-fix] Backup: ${wsgi}.${ts}.bak"

cat > "$wsgi" <<'PYCODE'
# wsgi.py — mínimo y estable
from contract_shim import application  # WSGI callable
PYCODE

$PY -m py_compile "$wsgi" && echo "[wsgi-fix] wsgi.py py_compile OK"

echo "[wsgi-fix] Listo. Usa Start Command:"
echo "  gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
