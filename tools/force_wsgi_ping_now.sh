#!/usr/bin/env bash
set -euo pipefail

python - <<'PY'
from pathlib import Path, re
p = Path("wsgiapp.py")
s = p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

block = r'''
# --- WSGI FORCE NOW: endpoints directos y versión ---
try:
    from flask import jsonify as _j
    with app.app_context():
        # /__version
        try:
            import subprocess, os
            _git_rev = subprocess.check_output(["git","rev-parse","--short","HEAD"], text=True).strip()
        except Exception:
            _git_rev = None
        @app.get("/__version")
        def __version():
            return _j({"rev": _git_rev}), 200

        # /api/ping directo
        try:
            if not any(str(r).rstrip("/") == "/api/ping" for r in app.url_map.iter_rules()):
                app.add_url_rule("/api/ping",
                                 endpoint="api_ping_force_now",
                                 view_func=(lambda: _j({"ok": True, "pong": True, "src": "wsgi-force-now"})),
                                 methods=["GET"])
        except Exception:
            pass

        # /api/_routes directo
        try:
            if not any(str(r).rstrip("/") == "/api/_routes" for r in app.url_map.iter_rules()):
                def _dump_routes_force():
                    info=[]
                    for r in app.url_map.iter_rules():
                        info.append({
                            "rule": str(r),
                            "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
                            "endpoint": r.endpoint
                        })
                    info.sort(key=lambda x: x["rule"])
                    return _j({"routes": info}), 200
                app.add_url_rule("/api/_routes",
                                 endpoint="api_routes_dump_force_now",
                                 view_func=_dump_routes_force,
                                 methods=["GET"])
        except Exception:
            pass
except Exception:
    # no rompemos wsgi aunque falle algo
    pass
'''
# Evitar duplicados: sólo añadimos si no está nuestra marca
if "WSGI FORCE NOW: endpoints directos y versión" not in s:
    if not s.endswith("\n"): s += "\n"
    s = s + "\n" + block + "\n"
    p.write_text(s, encoding="utf-8")
    print("patched wsgiapp.py")
else:
    print("already present")
PY

git add wsgiapp.py >/dev/null 2>&1 || true
git commit -m "hotfix(wsgiapp): force-now /api/ping, /api/_routes y /__version (app_context)" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hechos."
