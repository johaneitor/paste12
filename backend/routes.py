from flask import Blueprint, request, jsonify
from . import limiter
from .notes import view_note

api_bp = Blueprint("api", __name__)

@api_bp.route("/view", methods=["GET", "POST"])
@limiter.limit("60 per hour")
def view_alias():
    """
    Delegar a view_note para deduplicación por fingerprint
    """
    return view_note()
