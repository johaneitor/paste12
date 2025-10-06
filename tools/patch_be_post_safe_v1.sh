#!/usr/bin/env bash
set -euo pipefail
PY="wsgiapp/__init__.py"
[[ -f "$PY" ]] || { echo "ERROR: falta $PY"; exit 1; }

python - <<'PYCODE'
import io,os,py_compile
p="wsgiapp/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()

marker="# --- p12 POST /api/notes safe layer ---"
if marker not in s:
    s += "\n\n"+marker+"\n"
    s += r'''
try:
    from flask import request, jsonify
    _app = application  # usa la app ya existente

    def _p12_notes_post():
        # CORS básico
        if request.method == "OPTIONS":
            return ("", 204, {
                "Access-Control-Allow-Origin":"*",
                "Access-Control-Allow-Methods":"POST, OPTIONS",
                "Access-Control-Allow-Headers":"Content-Type, Accept"
            })
        data = {}
        if request.is_json:
            data = (request.get_json(silent=True) or {})
        else:
            try:
                data = request.form.to_dict(flat=True)
            except Exception:
                data = {}
        text = (data.get("text") or data.get("content") or "").strip()
        if not text:
            return jsonify(error="missing_text"), 400

        # Intentar persistir si existen db/Note
        try:
            db = globals().get("db")
            Note = globals().get("Note") or globals().get("Notes")
            if db and Note:
                n = Note(text=text) if "text" in getattr(Note, "__table__").columns else Note()
                if hasattr(n,"text"): setattr(n,"text",text)
                if hasattr(n,"score") and "score" in data:
                    try:
                        setattr(n,"score", int(data.get("score")))
                    except Exception:
                        pass
                db.session.add(n); db.session.commit()
                nid = getattr(n,"id", None)
                return jsonify(ok=True, id=nid), 201
        except Exception:
            # Silencioso: no rompemos
            pass

        # Fallback sin DB: eco 202
        return jsonify(ok=True, id=None, note={"text":text}), 202

    # Añadir POST/OPTIONS si no existen
    try:
        exists_post = any(getattr(r,"rule",None)=="/api/notes" and "POST" in getattr(r,"methods",{}) for r in _app.url_map.iter_rules())
    except Exception:
        exists_post = False
    if not exists_post:
        _app.add_url_rule("/api/notes", "p12_notes_post", _p12_notes_post, methods=["POST","OPTIONS"])
except Exception:
    pass
'''
    io.open(p,"w",encoding="utf-8").write(s)

py_compile.compile(p, doraise=True)
print("PATCH_OK", p)
PYCODE

python -m py_compile "$PY" && echo "OK: $PY compilado"
