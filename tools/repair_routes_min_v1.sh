#!/usr/bin/env bash
set -euo pipefail

ROUTES="backend/routes.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$ROUTES" ]] && cp -f "$ROUTES" "${ROUTES}.${TS}.bak" || true
echo "[routes] backup: ${ROUTES}.${TS}.bak"

cat > "$ROUTES" <<'PY'
from __future__ import annotations

from flask import Blueprint, jsonify, request, Response, current_app
from typing import Any, Dict, List

# Intentar importar modelos/DB si existen, pero no romper si fallan
HAVE_MODELS = True
try:
    from .models import Note  # type: ignore
    from . import db          # type: ignore
except Exception as _e:
    HAVE_MODELS = False

api_bp = Blueprint("api_bp", __name__)

def _cors_headers() -> Dict[str, str]:
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, HEAD, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Max-Age": "86400",
    }

@api_bp.get("/api/health")
def api_health() -> Response:
    # Señal clara de que el blueprint está cargado
    return jsonify(ok=True, api=True, ver="routes-v1")

@api_bp.route("/api/notes", methods=["OPTIONS"])
def notes_options() -> Response:
    return Response(status=204, headers=_cors_headers())

@api_bp.get("/api/notes")
def list_notes() -> Response:
    """Lista notas con paginación best-effort.
    Siempre responde 200 con una lista (vacía si hay error de DB)."""
    limit = 10
    try:
        limit = max(1, min(50, int(request.args.get("limit", 10))))
    except Exception:
        limit = 10

    before_id = request.args.get("before_id", None)
    items: List[Dict[str, Any]] = []

    if HAVE_MODELS:
        try:
            q = Note.query
            if before_id:
                q = q.filter(Note.id < int(before_id))
            q = q.order_by(Note.id.desc()).limit(limit)
            for n in q.all():
                items.append({
                    "id": n.id,
                    "text": getattr(n, "text", ""),
                    "timestamp": getattr(n, "timestamp", None),
                    "expires_at": getattr(n, "expires_at", None),
                    "likes": int(getattr(n, "likes", 0) or 0),
                    "views": int(getattr(n, "views", 0) or 0),
                    "reports": int(getattr(n, "reports", 0) or 0),
                    "author_fp": getattr(n, "author_fp", None),
                })
        except Exception as e:
            current_app.logger.exception("DB read failed, serving empty list: %r", e)

    resp = jsonify(items)
    # Link header para siguiente página
    if items:
        next_before = min(x["id"] for x in items if isinstance(x.get("id"), int))
        base = request.url_root.rstrip("/")
        resp.headers["Link"] = f'<{base}/api/notes?limit={limit}&before_id={next_before}>; rel="next"'
    # CORS
    for k, v in _cors_headers().items():
        resp.headers[k] = v
    return resp
PY

python -m py_compile "$ROUTES" && echo "[routes] py_compile OK"
echo "[routes] listo"
