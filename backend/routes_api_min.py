from __future__ import annotations
from flask import Blueprint, jsonify, make_response, request

api_bp = Blueprint("api_bp", __name__)

@api_bp.route("/api/health", methods=["GET"])
def api_health():
    return jsonify(ok=True, api=True, ver="api-bp-min"), 200

@api_bp.route("/api/notes", methods=["OPTIONS"])
def api_notes_options():
    # 204 vacío con CORS canónico
    resp = make_response("", 204)
    h = resp.headers
    h["Access-Control-Allow-Origin"] = "*"
    h["Access-Control-Allow-Methods"] = "GET, POST, HEAD, OPTIONS"
    h["Access-Control-Allow-Headers"] = "Content-Type"
    h["Access-Control-Max-Age"] = "86400"
    return resp

@api_bp.route("/api/notes", methods=["GET"])
def api_notes_get():
    # Respuesta mínima saludable (si tu ORM aún no está listo)
    # Estructura amigable para el FE actual
    return jsonify(items=[], next=None), 200
