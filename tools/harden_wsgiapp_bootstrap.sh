#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

PKG="wsgiapp"
INIT="$PKG/__init__.py"
mkdir -p "$PKG"

echo "[+] Backup (si existe)"
[ -f "$INIT" ] && cp -f "$INIT" "$INIT.bak.$(date +%s)" || true

echo "[+] Escribiendo $INIT (bootstrap a prueba de fallos)…"
cat > "$INIT" <<'PY'
from __future__ import annotations

# --- Bootstrap robusto de app ---
import os, time, hashlib
from typing import Any
from flask import Flask, Blueprint, jsonify

# Variables de diagnóstico
WSGIAPP_IMPORT_PATH: str | None = None
WSGIAPP_IMPORT_ERROR: str | None = None

def _try_import_real_app() -> Flask | None:
    global WSGIAPP_IMPORT_PATH, WSGIAPP_IMPORT_ERROR
    # 1) render_entry:app
    try:
        from render_entry import app as real_app  # type: ignore
        WSGIAPP_IMPORT_PATH = "render_entry:app"
        return real_app
    except Exception as e1:
        WSGIAPP_IMPORT_ERROR = f"render_entry failed: {e1!r}"
    # 2) wsgi:app
    try:
        from wsgi import app as real_app  # type: ignore
        WSGIAPP_IMPORT_PATH = "wsgi:app"
        return real_app
    except Exception as e2:
        WSGIAPP_IMPORT_ERROR = (WSGIAPP_IMPORT_ERROR or "") + f" | wsgi failed: {e2!r}"
    return None

# Intenta cargar la app real; si no, crea fallback
app = _try_import_real_app()
if app is None:
    app = Flask(__name__)
    # Health básico para saber que estamos en fallback
    @app.get("/api/health")
    def _health():
        return jsonify(ok=True, note="wsgiapp-fallback"), 200

# --- Diags siempre disponibles ---
diag_bp = Blueprint("wsgiapp_diag", __name__)

@diag_bp.get("/diag/import", endpoint="wsgiapp_diag_import")
def _wsgiapp_diag_import():
    info: dict[str, Any] = {
        "ok": True,
        "import_path": WSGIAPP_IMPORT_PATH,
        "fallback": (WSGIAPP_IMPORT_PATH is None),
    }
    if WSGIAPP_IMPORT_ERROR:
        info["import_error"] = WSGIAPP_IMPORT_ERROR
    return jsonify(info), 200

@diag_bp.get("/diag/urlmap", endpoint="wsgiapp_diag_urlmap")
def _wsgiapp_diag_urlmap():
    rules = []
    for r in app.url_map.iter_rules():
        methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
        rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
    return jsonify(ok=True, rules=rules), 200

# Sello de versión (útil para verificar redeploy)
STAMP = os.getenv("DEPLOY_STAMP", str(int(time.time())))
@diag_bp.get("/health-stamp", endpoint="wsgiapp_health_stamp")
def _health_stamp():
    return jsonify(ok=True, note="wsgiapp", stamp=STAMP), 200

# Registra el blueprint diag bajo /api (no falla si ya está)
try:
    app.register_blueprint(diag_bp, url_prefix="/api")
except Exception:
    pass

# --- Auto-registro opcional de interacciones (like/view/stats) ---
def _has_rule(path: str, method: str) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == path and method.upper() in r.methods:
                return True
    except Exception:
        return False
    return False

try:
    need_like  = not _has_rule("/api/notes/<int:note_id>/like",  "POST")
    need_view  = not _has_rule("/api/notes/<int:note_id>/view",  "POST")
    need_stats = not _has_rule("/api/notes/<int:note_id>/stats", "GET")
    if any([need_like, need_view, need_stats]):
        try:
            # Preferir módulo del proyecto si existe
            from backend.modules.interactions import register_into as _reg, register_alias_into as _reg_alias  # type: ignore
            _reg(app)
            _reg_alias(app)
        except Exception:
            # Silencioso: no rompemos arranque si falta backend/DB
            pass
except Exception:
    pass
PY

echo "[+] Commit & push"
git add -A
git commit -m "fix(wsgiapp): robust bootstrap (diag + fallback + optional interactions autoreg)" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

echo
echo "[i] Ahora en Render verifica Start Command EXACTO:"
echo "    gunicorn -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} -b 0.0.0.0:\$PORT wsgiapp:app"
echo "    (si puedes, Clear build cache y Redeploy)"
echo
echo "[i] Tras redeploy, valida:"
cat <<'CMD'
curl -s https://paste12-rmsk.onrender.com/api/diag/import | jq .
curl -s https://paste12-rmsk.onrender.com/api/diag/urlmap  | jq .
curl -s https://paste12-rmsk.onrender.com/api/health-stamp | jq .
CMD
