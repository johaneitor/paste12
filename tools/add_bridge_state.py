import re, pathlib, json
P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

# Inyectar handler dentro de _middleware(..) justo después de path/method/qs
pat = r"(def\s+_middleware\s*\([^\)]*\):\s*\n\s*def\s+_app\s*\(\s*environ,\s*start_response\s*\):\s*\n\s*path\s*=\s*environ\.get\([^\n]*\)\s*\n\s*method\s*=\s*environ\.get\([^\n]*\)\.upper\(\)\s*\n\s*qs\s*=\s*environ\.get\([^\n]*\)\s*\n)"
inject = r"""\1        # --- bridge: diagnóstico raíz ---
        if path == "/api/bridge-state":
            try:
                force = (os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on"))
            except Exception:
                force = False
            override = os.environ.get("WSGI_BRIDGE_INDEX") or ""
            cands = [
                os.path.join(_REPO_DIR, "backend", "static", "index.html"),
                os.path.join(_REPO_DIR, "public", "index.html"),
                os.path.join(_REPO_DIR, "frontend", "index.html"),
                os.path.join(_REPO_DIR, "index.html"),
            ]
            resolved = None
            for _p in ([override] if override else cands):
                if _p and os.path.isfile(_p):
                    resolved = _p
                    break
            data = {
                "ok": True,
                "force_env": os.getenv("FORCE_BRIDGE_INDEX",""),
                "force_bool": force,
                "is_fallback": bool(is_fallback),
                "WSGI_BRIDGE_INDEX": override,
                "resolved_index": resolved,
                "exists_backend_static": os.path.isfile(os.path.join(_REPO_DIR,"backend","static","index.html")),
            }
            status, headers, body = _json(200, data)
            return _finish(start_response, status, headers, body, method)
"""
ns, n = re.subn(pat, inject, s, flags=re.S)
if n:
    P.write_text(ns, encoding="utf-8")
    print("patched: /api/bridge-state")
else:
    print("no patch (anchor no encontrado)")
