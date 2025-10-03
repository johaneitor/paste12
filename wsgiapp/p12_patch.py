# -*- coding: utf-8 -*-
from flask import request, jsonify, make_response

def _cors(resp):
    try:
        resp.headers["Access-Control-Allow-Origin"]  = "*"
        resp.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
        resp.headers["Cache-Control"] = "no-store"
    except Exception:
        pass
    return resp

def _parse_text():
    ctype = (request.headers.get("Content-Type") or "").lower()
    text = None
    # JSON
    if "application/json" in ctype:
        j = request.get_json(silent=True) or {}
        if isinstance(j, dict):
            for k in ("text","note","content","message"):
                v = j.get(k)
                if isinstance(v, str) and v.strip():
                    text = v.strip(); break
        elif isinstance(j, str) and j.strip():
            text = j.strip()
    # FORM
    if text is None and "application/x-www-form-urlencoded" in ctype:
        for k in ("text","note","content","message"):
            v = request.form.get(k)
            if isinstance(v, str) and v.strip():
                text = v.strip(); break
    # RAW
    if text is None:
        try:
            raw = request.get_data(cache=False, as_text=True)
            if isinstance(raw, str) and raw.strip():
                text = raw.strip()
        except Exception:
            pass
    return text

def apply(app):
    # Preflight CORS
    @app.route("/api/notes", methods=["OPTIONS"])
    def _p12_notes_preflight():
        return _cors(make_response("", 204))

    # POST /api/notes (201 si insert OK, 202 si degradado)
    @app.route("/api/notes", methods=["POST"])
    def _p12_notes_create():
        text = _parse_text()
        if not text:
            return _cors(make_response(jsonify(error="bad_request", hint="text required"), 400))
        created = False; new_id = None
        try:
            # Integra con tus modelos existentes
            from wsgiapp import db, Note
            obj = Note(text=text)
            db.session.add(obj)
            db.session.commit()
            new_id = getattr(obj, "id", None)
            created = new_id is not None
        except Exception:
            created = False
            new_id = None
        return _cors(make_response(jsonify(id=new_id, created=bool(created)), 201 if created else 202))

    # Guard 404 para REST /api/notes/<id>/(like|view|report) cuando la nota no existe
    def _exists(note_id):
        try:
            from wsgiapp import db, Note
            row = db.session.get(Note, int(note_id))
            return row is not None
        except Exception:
            return False

    @app.before_request
    def _p12_guard_not_found():
        p = (request.path or "")
        # Coincide /api/notes/<id>/(like|view|report)
        if p.startswith("/api/notes/") and any(p.endswith("/"+a) for a in ("like","view","report")):
            seg = p.split("/")
            # ['', 'api', 'notes', '<id>', '<action>']
            note_id = seg[3] if len(seg) >= 5 else None
            if not note_id or not _exists(note_id):
                return _cors(make_response(jsonify(error="not_found"), 404))
        return None
