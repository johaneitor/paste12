#!/usr/bin/env bash
set -Eeuo pipefail
echo "🔧 Patch: backend (405→JSON + fallbacks) y frontend (guard ID) …"

# ---- Backend: handler JSON preservando status + fallbacks sin id ----
python - <<'PY'
from pathlib import Path
p=Path('backend/routes.py'); s=p.read_text(encoding='utf-8')

# Asegurar imports
if 'from werkzeug.exceptions' not in s:
    s = s.replace('from sqlalchemy.exc import IntegrityError',
                  'from sqlalchemy.exc import IntegrityError\nfrom werkzeug.exceptions import HTTPException, MethodNotAllowed, NotFound, BadRequest')

# Error handler que conserva e.code si es HTTPException
if '__api_error_handler' not in s:
    s += '''

# --- Generic JSON error handler that preserves HTTP status ---
@bp.errorhandler(Exception)
def __api_error_handler(e):
    from flask import current_app, jsonify
    try:
        if isinstance(e, HTTPException):
            return jsonify({"ok": False, "error": e.description}), e.code
        current_app.logger.exception("API error: %s", e)
        return jsonify({"ok": False, "error": str(e)}), 500
    except Exception:  # fallback
        return ("", 500)
'''

# Endpoints "cortafuego" cuando llega /notes/(like|report|view) sin id
if '__report_missing' not in s:
    s += '''

@bp.post("/notes/report")
def __report_missing():
    from flask import jsonify
    return jsonify({"ok": False, "error": "note_id required"}), 400

@bp.post("/notes/like")
def __like_missing():
    from flask import jsonify
    return jsonify({"ok": False, "error": "note_id required"}), 400

@bp.post("/notes/view")
def __view_missing():
    from flask import jsonify
    return jsonify({"ok": False, "error": "note_id required"}), 400
'''
p.write_text(s, encoding='utf-8')
print("✓ routes.py patched")
PY

python -m py_compile backend/routes.py || { echo "❌ Syntax error en routes.py"; exit 1; }

# ---- Frontend: guardar llamadas sin id (evita /notes//accion) ----
if ! grep -q "/* guard invalid note actions */" frontend/js/app.js 2>/dev/null; then
cat >> frontend/js/app.js <<'JS'

// /* guard invalid note actions */
(function(){
  try{
    const origFetch = window.fetch;
    window.fetch = function(input, init){
      try{
        const url = typeof input==='string' ? input : (input && input.url) || '';
        const m = url && url.match(/\/api\/notes\/(\d+)\/(like|report|view)/);
        if (m){
          const id = parseInt(m[1],10);
          if (!Number.isInteger(id) || id<=0){
            console.warn("[guard] blocked invalid note action:", url);
            return Promise.resolve(new Response(
              JSON.stringify({ok:false,error:"invalid note id"}),
              {status:400, headers:{"Content-Type":"application/json"}}
            ));
          }
        }
      }catch(_e){}
      return origFetch(input, init);
    };
  }catch(_e){}
})();
JS
  echo "✓ app.js guard añadido"
else
  echo "✓ app.js guard ya estaba presente"
fi

echo "✅ Patch aplicado."
