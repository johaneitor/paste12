#!/usr/bin/env bash
set -Eeuo pipefail

WSGI="wsgi.py"
cp -a "$WSGI" "$WSGI.bak.$(date +%s)" 2>/dev/null || true

python - "$WSGI" <<'PY'
import io, sys, re
p = sys.argv[1]
s = io.open(p, 'r', encoding='utf-8').read()

marker = "# --- Fallback API (auto-attached if backend.routes fails) ---"
if marker in s:
    print("already present")
    sys.exit(0)

block = f"""
{marker}
try:
    # 1) Intentar adjuntar el blueprint real del API
    from backend.routes import api as _api_bp  # type: ignore
    try:
        if hasattr(app, "register_blueprint"):
            if "api" not in getattr(app, "blueprints", {{}}):
                app.register_blueprint(_api_bp)  # type: ignore[attr-defined]
    except Exception as _e:
        print("[wsgi] attach api blueprint failed:", _e)
except Exception as _e_import:
    print("[wsgi] import backend.routes failed:", _e_import)
    # 2) Fallback: registrar endpoints mínimos directamente sobre 'app'
    try:
        from flask import jsonify, request
        # /api/_routes — diagnóstico en runtime
        def _fb_routes():
            rules = sorted(
                [{{"rule": r.rule, "methods": sorted(getattr(r, "methods", []))}} for r in app.url_map.iter_rules()],  # type: ignore
                key=lambda x: x["rule"]
            )
            return jsonify({{"routes": rules}}), 200
        if not any(getattr(r, "rule", None) == "/api/_routes" for r in app.url_map.iter_rules()):  # type: ignore
            app.add_url_rule("/api/_routes", "fb_api_routes", _fb_routes, methods=["GET"])  # type: ignore

        # /api/notes (GET) — paginación con after_id y X-Next-After
        def _fb_notes_get():
            try:
                from backend import db  # type: ignore
                try:
                    from backend.models import Note  # type: ignore
                except Exception:
                    from .models import Note  # type: ignore
                import datetime as _dt

                after_id = request.args.get("after_id")
                try:
                    limit = int((request.args.get("limit") or "20").strip() or "20")
                except Exception:
                    limit = 20
                limit = max(1, min(limit, 50))

                q = db.session.query(Note).order_by(Note.id.desc())
                if after_id:
                    try:
                        aid = int(after_id)
                        q = q.filter(Note.id < aid)
                    except Exception:
                        pass
                items = q.limit(limit + 1).all()
                page = items[:limit]

                def _to(n):
                    ts = getattr(n, "timestamp", None)
                    ex = getattr(n, "expires_at", None)
                    return {{
                        "id": n.id,
                        "text": getattr(n, "text", None),
                        "timestamp": ts.isoformat() if ts else None,
                        "expires_at": ex.isoformat() if ex else None,
                        "likes": getattr(n, "likes", 0) or 0,
                        "views": getattr(n, "views", 0) or 0,
                        "reports": getattr(n, "reports", 0) or 0,
                    }}

                from flask import Response
                import json as _json
                body = _json.dumps([_to(n) for n in page])
                resp = Response(body, status=200, mimetype="application/json")
                if len(items) > limit and page:
                    resp.headers["X-Next-After"] = str(page[-1].id)
                return resp
            except Exception as e:
                return jsonify({{"error":"fb_list_failed","detail":str(e)}}), 500

        if not any(getattr(r, "rule", None) == "/api/notes" and "GET" in getattr(r,"methods",[]) for r in app.url_map.iter_rules()):  # type: ignore
            app.add_url_rule("/api/notes", "fb_api_notes_get", _fb_notes_get, methods=["GET"])  # type: ignore

        # /api/notes (POST) — informar 501 hasta que el módulo real esté vivo
        def _fb_notes_post():
            return jsonify({{"error":"not_implemented","detail":"El módulo de API real no se cargó; POST /api/notes estará disponible cuando backend.routes importe sin errores."}}), 501

        if not any(getattr(r, "rule", None) == "/api/notes" and "POST" in getattr(r,"methods",[]) for r in app.url_map.iter_rules()):  # type: ignore
            app.add_url_rule("/api/notes", "fb_api_notes_post", _fb_notes_post, methods=["POST"])  # type: ignore

    except Exception as _e_fb:
        print("[wsgi] fallback api failed:", _e_fb)
"""

# lo añadimos al final de wsgi.py
s = s.rstrip() + "\n\n" + block + "\n"
io.open(p, 'w', encoding='utf-8').write(s)
print("patched")
PY

git add wsgi.py || true
git commit -m "wsgi: add fallback API (/api/_routes, GET /api/notes, POST /api/notes=501) if backend.routes fails" || true
git push origin main || true
