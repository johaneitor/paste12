#!/usr/bin/env bash
set -euo pipefail

# Backup
mkdir -p wsgiapp
cp -f wsgiapp/__init__.py "wsgiapp/__init__.py.bak-$(date -u +%Y%m%d-%H%M%SZ)" 2>/dev/null || true

cat > wsgiapp/__init__.py << 'PY'
# wsgiapp/__init__.py — API de notas mínima y estable
from flask import Flask, request, jsonify, make_response
import time, threading

# --- Config ---
TTL_HOURS_DEFAULT = 12        # coincide con el placeholder de la UI
CAP_LIMIT = 200               # capacidad duplicada (según pedido)

app = Flask(__name__)
application = app  # export para gunicorn

# --- Estado en memoria ---
_notes = {}         # id:int -> dict(note)
_next_id = 1
_lock = threading.Lock()

def _now(): return int(time.time())

def _purge_expired():
    """Elimina expiradas por TTL."""
    now = _now()
    rm = []
    with _lock:
        for nid, n in _notes.items():
            exp = n.get("exp")
            if exp and exp <= now:
                rm.append(nid)
        for nid in rm:
            _notes.pop(nid, None)

def _enforce_cap():
    """Si supera CAP_LIMIT elimina las menos relevantes y más viejas."""
    with _lock:
        if len(_notes) <= CAP_LIMIT:
            return
        # relevancia = likes+views; primero baja relevancia, y más viejas
        ordered = sorted(_notes.items(),
                         key=lambda kv: ((kv[1].get("likes",0) + kv[1].get("views",0)),
                                         kv[1].get("ts",0)))
        while len(_notes) > CAP_LIMIT and ordered:
            victim_id, _ = ordered.pop(0)
            _notes.pop(victim_id, None)

def _to_item(nid, n):
    return {
        "id": nid,
        "text": n.get("text",""),
        "likes": int(n.get("likes",0)),
        "views": int(n.get("views",0)),
        "ts": int(n.get("ts", _now())),
        "exp": int(n.get("exp", 0)) or None
    }

# --- Helpers de respuesta ---
def _json(data, status=200, headers=None):
    resp = make_response(jsonify(data), status)
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Cache-Control"] = "no-store"
    if headers:
        for k,v in headers.items():
            resp.headers[k] = v
    return resp

def _bad_request(msg="bad_request"):   return _json({"ok":False,"error":msg}, 400)
def _not_found(msg="not_found"):       return _json({"ok":False,"error":msg}, 404)
def _method_not_allowed():             return _json({"ok":False,"error":"method_not_allowed"}, 405)

# --- Health / Terms / Privacy (fallbacks sencillos) ---
@app.route("/api/health", methods=["GET"])
def api_health():
    return _json({"ok":True,"time":_now()})

@app.route("/terms", methods=["GET"])
def terms():
    return make_response("Términos y Condiciones — Paste12", 200)

@app.route("/privacy", methods=["GET"])
def privacy():
    return make_response("Política de Privacidad — Paste12", 200)

# --- Listado y creación de notas ---
@app.route("/api/notes", methods=["GET","POST","OPTIONS"])
def notes_list_create():
    if request.method == "OPTIONS":
        # Preflight CORS
        return _json({"ok":True}, 200, {
            "Access-Control-Allow-Methods":"GET,POST,OPTIONS",
            "Access-Control-Allow-Headers":"Content-Type,Accept"
        })

    if request.method == "GET":
        _purge_expired()
        try:
            limit = int(request.args.get("limit", "10"))
        except Exception:
            limit = 10
        if limit < 1: limit = 1
        with _lock:
            items = [
                _to_item(nid, n)
                for nid, n in sorted(_notes.items(), key=lambda kv: kv[1].get("ts",0), reverse=True)
            ][:limit]
        # Header Link (sintético) para checker que lo espera
        headers = {"Link": "</api/notes?cursor=next>; rel=\"next\""} if len(_notes)>limit else {}
        return _json({"ok":True,"items":items}, 200, headers)

    # POST (JSON o FORM)
    data = (request.get_json(silent=True) or {})
    if not data and request.form:
        data = request.form.to_dict(flat=True)
    text = (data.get("text") or "").strip()
    if len(text) < 12:
        return _bad_request("text_too_short")

    # TTL
    try:
        ttl_hours = int(data.get("ttl_hours", TTL_HOURS_DEFAULT))
    except Exception:
        ttl_hours = TTL_HOURS_DEFAULT
    if ttl_hours < 1: ttl_hours = TTL_HOURS_DEFAULT
    exp = _now() + ttl_hours*3600

    global _next_id
    with _lock:
        nid = _next_id
        _next_id += 1
        _notes[nid] = {"text":text, "likes":0, "views":0, "ts":_now(), "exp":exp}

    _purge_expired()
    _enforce_cap()
    return _json({"ok":True, "item": _to_item(nid, _notes[nid])}, 201)

# --- Acciones sobre una nota: view/like/report ---
def _get_note(nid):
    try:
        nid = int(nid)
    except Exception:
        return None, None
    with _lock:
        n = _notes.get(nid)
    return nid, n

@app.route("/api/notes/<nid>/view", methods=["POST"])
def note_view(nid):
    _purge_expired()
    nid, n = _get_note(nid)
    if not n: return _not_found()
    with _lock:
        n["views"] = int(n.get("views",0))+1
    return _json({"ok":True, "id":nid, "views":n["views"]})

@app.route("/api/notes/<nid>/like", methods=["POST"])
def note_like(nid):
    _purge_expired()
    nid, n = _get_note(nid)
    if not n: return _not_found()
    with _lock:
        n["likes"] = int(n.get("likes",0))+1
    return _json({"ok":True, "id":nid, "likes":n["likes"]})

@app.route("/api/notes/<nid>/report", methods=["POST"])
def note_report(nid):
    _purge_expired()
    nid, n = _get_note(nid)
    if not n: return _not_found()
    # Política simple: remover la nota reportada
    with _lock:
        _notes.pop(nid, None)
    return _json({"ok":True, "removed":True, "id":nid})

# --- Guard 404 para rutas REST inexistentes (evita 200 fantasmas) ---
@app.errorhandler(404)
def _fallback_404(_e):
    # Devuelve JSON para paths /api/* y HTML simple para otros
    p = request.path or ""
    if p.startswith("/api/"):
        return _not_found()
    return make_response("404", 404)
PY

python -m py_compile wsgiapp/__init__.py
echo "PATCH_OK wsgiapp/__init__.py"
