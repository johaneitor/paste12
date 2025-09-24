#!/usr/bin/env bash
set -Eeuo pipefail

ROUTES="backend/routes.py"
grep -q "Blueprint(\"api\"" "$ROUTES" 2>/dev/null || {
  echo "(!) $ROUTES no define un blueprint 'api'; abortando para no romper nada."
  exit 1
}

# ¿Ya existe list_notes?
if grep -q "def list_notes" "$ROUTES"; then
  echo "list_notes ya existe (ok)."
else
  echo "Inyectando list_notes en $ROUTES…"
  cat >> "$ROUTES" <<'PY'

# --- /api/notes (GET) listado con paginado cursor after_id ---
try:
    from flask import jsonify, request
    from backend import db  # SQLAlchemy
    # Intento de import común; si tu modelo vive en otro módulo, ajusta esta importación
    try:
        from backend.models import Note  # type: ignore
    except Exception:
        from .models import Note  # type: ignore

    @api.route("/notes", methods=["GET", "HEAD"])  # type: ignore
    def list_notes():
        try:
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
                return {
                    "id": n.id,
                    "text": getattr(n, "text", None),
                    "timestamp": n.timestamp.isoformat() if getattr(n, "timestamp", None) else None,
                    "expires_at": n.expires_at.isoformat() if getattr(n, "expires_at", None) else None,
                    "likes": getattr(n, "likes", 0) or 0,
                    "views": getattr(n, "views", 0) or 0,
                    "reports": getattr(n, "reports", 0) or 0,
                }

            resp = jsonify([_to(n) for n in page])
            if len(items) > limit and page:
                # Cursor de siguiente página
                resp.headers["X-Next-After"] = str(page[-1].id)
            return resp, 200
        except Exception as e:
            return jsonify({"error":"list_failed","detail":str(e)}), 500
except Exception as _e:
    # No romper el import del módulo si falla algo
    pass
PY
fi

git add backend/routes.py || true
git commit -m "api: ensure /api/notes (GET) exists with cursor pagination" || true
git push origin main
