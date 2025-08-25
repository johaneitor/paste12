from __future__ import annotations
from flask import Blueprint, request, jsonify, send_from_directory
import datetime as _dt
import sqlalchemy as sa
from hashlib import sha256
import os
from datetime import datetime, timedelta, date
from pathlib import Path

from backend import db, limiter
from backend.models import Note, ReportLog, LikeLog, ViewLog

api = Blueprint("api", __name__, url_prefix="/api")

def _fingerprint_from_request(req):
    uid = req.cookies.get('uid')
    if uid and len(uid) >= 8:
        base = f"uid:{uid}"
    else:
        ip = (req.headers.get("X-Forwarded-For") or getattr(req, "remote_addr", "") or "").split(",")[0].strip()
        ua = req.headers.get("User-Agent", "")
        base = f"{ip}|{ua}"
    return sha256(base.encode("utf-8")).hexdigest()

def _to_dict(n: Note):
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": n.timestamp.isoformat() if getattr(n, "timestamp", None) else None,
        "expires_at": n.expires_at.isoformat() if getattr(n, "expires_at", None) else None,
        "likes": getattr(n, "likes", 0) or 0,
        "views": getattr(n, "views", 0) or 0,
        "reports": getattr(n, "reports", 0) or 0,
    }

@api.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True}), 200


@api.route("/notes", methods=["POST"])
def create_note():
    raw_json = request.get_json(silent=True) or {}
    data = raw_json if isinstance(raw_json, dict) else {}

def pick(*vals):
    for v in vals:
        if v is None:
            continue
        s = str(v).strip()
        if s != "":
            return s
    return ""

        return 0