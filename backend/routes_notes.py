from flask import request, jsonify
# Reusamos el mismo blueprint y helpers ya definidos en backend.routes
from backend.routes import bp, _now, _note_json, _fp
from backend.services import notes_service as svc
from backend.errors import BadInput, DomainError

@bp.errorhandler(BadInput)
def _bad_input(e):
    return jsonify({"error": "bad_input", "detail": str(e)}), 400

@bp.route("/api/notes", methods=["GET"])
def list_notes():
    try:
        page = int(request.args.get("page", 1) or 1)
    except Exception:
        page = 1
    page = max(1, page)
    items = svc.list_(page, 20, _now())
    return jsonify([_note_json(n, _now()) for n in items]), 200

@bp.route("/api/notes", methods=["POST"])
def create_note():
    data = request.get_json(silent=True) or {}
    n = svc.create(data, _now(), _fp())
    return jsonify(_note_json(n, _now())), 201
