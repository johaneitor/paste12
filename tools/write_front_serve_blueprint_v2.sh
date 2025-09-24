#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="backend/front_serve.py"
[[ -f "$OUT" ]] && cp -f "$OUT" "${OUT}.${TS}.bak" && echo "[front-serve] Backup: ${OUT}.${TS}.bak"

cat > "$OUT" <<'PY'
from flask import Blueprint, Response
from pathlib import Path

front_bp = Blueprint("front", __name__)
ROOT = Path(__file__).resolve().parents[1] / "frontend"

def _read_html(name: str) -> Response:
    p = ROOT / name
    if not p.exists():
        return Response(f"{name} not found", 404, {"Content-Type": "text/plain; charset=utf-8"})
    body = p.read_text("utf-8")
    return Response(body, 200, {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
    })

@front_bp.get("/")
def index():
    return _read_html("index.html")

@front_bp.get("/terms")
def terms():
    return _read_html("terms.html")

@front_bp.get("/privacy")
def privacy():
    return _read_html("privacy.html")
PY

echo "[front-serve] backend/front_serve.py escrito"
