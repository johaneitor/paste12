#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

echo "🔧 Stabilize feed: backend per_page + frontend sentinel/guard"

# Backups
cp -p backend/routes.py "backend/routes.py.bak.$ts" 2>/dev/null || true
cp -p frontend/index.html "frontend/index.html.bak.$ts" 2>/dev/null || true

# --- Backend: asegurar per_page en /api/notes ---
python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
code = p.read_text(encoding="utf-8")

# Asegurar import request
if "from flask import" in code and "request" not in code:
    code = code.replace("from flask import jsonify", "from flask import jsonify, request")
    code = code.replace("from flask import Blueprint, jsonify", "from flask import Blueprint, jsonify, request")

# Localizar handler GET /notes
pat = re.compile(r'@bp\.get\("/notes"\)\s*def\s+(\w+)\s*\([^)]*\):\s*([\s\S]*?)(?=\n\s*@|\Z)', re.M)
m = pat.search(code)
if not m:
    print("⚠️  No encontré @bp.get(\"/notes\"). No modifico backend.")
else:
    name, body = m.group(1), m.group(2)
    # Si ya hay per_page, no tocamos
    if "per_page" not in body or "limit(" not in body or "offset(" not in body:
        body_lines = body.splitlines()
        # Insertar lógica de paginación (respetuosa)
        inject = [
            "    page = request.args.get('page', type=int) or 1",
            "    per_page = request.args.get('per_page', type=int) or 12",
            "    per_page = max(5, min(per_page, 20))",
            "    off = (page - 1) * per_page",
        ]
        # Si ya existe 'q = Note.query...' lo reutilizamos y forzamos limit/offset
        if "q =" in body:
            # Quitar .limit/.offset previos
            body2 = re.sub(r"\.limit\([^)]+\)\.offset\([^)]+\)", "", body)
            # Asegurar fetch de items
            if "items =" not in body2:
                body2 = re.sub(r"(q\s*=\s*[^\n]+)", r"\1", body2, count=1)
                body2 += "\n    items = q.limit(per_page).offset(off).all()"
            else:
                body2 = re.sub(r"items\s*=\s*[^\n]+", "    items = q.limit(per_page).offset(off).all()", body2)
        else:
            # Construcción mínima
            body2 = (
                "    now = datetime.now(timezone.utc)\n"
                "    q = Note.query.filter(Note.expires_at > now).order_by(Note.timestamp.desc())\n"
                "    items = q.limit(per_page).offset(off).all()\n"
            )

        # Calcular has_more “barato”
        if "has_more" not in body2:
            body2 += "\n    has_more = len(items) == per_page\n"

        # Serialización: respetar helper existente si lo hay
        if "return jsonify(" not in body2 or "notes" not in body2:
            # Buscar serializador existente (buscamos dict con campos 'text'/'likes', etc.)
            if "def" in code and ("def to_note" in code or "def note_json" in code or "def serialize" in code):
                ser_name = "to_note" if "def to_note" in code else ("note_json" if "def note_json" in code else "serialize")
                notes_line = f"    payload = [ {ser_name}(n) for n in items ]\n"
            else:
                notes_line = (
                    "    payload = [{\n"
                    "        'id': n.id,\n"
                    "        'text': n.text,\n"
                    "        'timestamp': n.timestamp.isoformat() if n.timestamp else None,\n"
                    "        'expires_at': n.expires_at.isoformat() if n.expires_at else None,\n"
                    "        'likes': int(getattr(n, 'likes', 0) or 0),\n"
                    "        'views': int(getattr(n, 'views', 0) or 0),\n"
                    "        'reports': int(getattr(n, 'reports', 0) or 0)\n"
                    "    } for n in items]\n"
                )
            body2 += "\n" + notes_line + "    return jsonify({'notes': payload, 'page': page, 'per_page': per_page, 'has_more': has_more, 'next_page': (page+1) if has_more else None})\n"

        # Inyectar page/per_page arriba del body y sustituir
        body2 = "\n" + "\n".join(inject) + "\n" + body2.lstrip("\n")
        code = code[:m.start()] + f'@bp.get("/notes")\ndef {name}():\n' + body2 + code[m.end():]
        p.write_text(code, encoding="utf-8")
        print("✓ Backend /api/notes con per_page/has_more")
    else:
        print("• Backend ya tenía per_page/limit/offset (ok)")
PY

# --- Frontend: feed_guard (sentinel + gating de fetch) ---
mkdir -p frontend/js
cat > frontend/js/feed_guard.js <<'JS'
/* Gateador de /api/notes: pagina real, libera 1 página por scroll, recorta DOM >300 items */
(function(){
  if (window.__p12_feed_guard) return; window.__p12_feed_guard = true;

  const PER_PAGE = 12;
  const N_MAX = 300;
  const nativeFetch = window.fetch.bind(window);
  let allowNext = true; // permitimos page=1

  function looksNotes(u){
    if(typeof u !== 'string') u = (u && u.url) || '';
    return u.includes('/api/notes');
  }
  function norm(u){
    const url = new URL(u, location.origin);
    const p = parseInt(url.searchParams.get('page')||'1',10)||1;
    url.searchParams.set('per_page', PER_PAGE);
    return {page:p, href: url.pathname + url.search + url.hash};
  }

  window.fetch = async function(input, init){
    if(!looksNotes(input)) return nativeFetch(input, init);
    const {page, href} = norm(typeof input==='string'? input: input.url);
    input = href;

    if(page>1 && !allowNext){
      // Retornar “vacío pero válido” hasta que el sentinel libere el siguiente
      const fake = new Response(JSON.stringify({notes:[], page, per_page:PER_PAGE, has_more:true, next_page:page}), {status:200, headers:{'Content-Type':'application/json'}});
      return Promise.resolve(fake);
    }
    allowNext = false;
    return nativeFetch(input, init);
  };

  // Sentinel: permite la siguiente página cuando el usuario llega al final
  const sentinel = document.createElement('div');
  sentinel.id = 'p12-feed-sentinel';
  sentinel.style.cssText = 'height:1px;';
  const attach = ()=> (document.querySelector('#notes-list') || document.body).appendChild(sentinel);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', attach, {once:true});
  else attach();

  const io = new IntersectionObserver((ents)=>{
    for(const e of ents){ if(e.isIntersecting){ allowNext = true; } }
  }, {root:null, threshold:0});
  io.observe(sentinel);

  // Ventana deslizante: mantener como mucho N_MAX tarjetas
  function trim(){
    const host = document.querySelector('#notes-list') || document.querySelector('.notes') || document.body;
    const items = host.querySelectorAll('[data-note-id], .note-card, li.note');
    const extra = items.length - N_MAX;
    for(let i=0;i<extra;i++){ items[i].remove(); }
  }
  setInterval(trim, 3000);
})();
JS

# Incluir feed_guard.js en index.html si no está
if ! grep -q 'feed_guard.js' frontend/index.html 2>/dev/null; then
  perl -0777 -pe "s#</body>#  <script defer src=\"/js/feed_guard.js?v=$ts\"></script>\n</body>#i" -i frontend/index.html
  echo "✓ index.html actualizado (feed_guard.js)"
else
  echo "• index.html ya incluye feed_guard.js (ok)"
fi

# Validaciones
python -m py_compile backend/routes.py || { echo "❌ Error en backend/routes.py"; exit 1; }

# Commit + push → Render
git add backend/routes.py frontend/js/feed_guard.js frontend/index.html
git commit -m "perf(feed): sentinel + gating de /api/notes (per_page, has_more) y ventana DOM" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "🚀 Enviado. Tras el redeploy, abre: https://paste12-rmsk.onrender.com/?v=$ts"
echo "   Revisa en DevTools→Network que /api/notes empiece con page=1 y sólo cargue la siguiente cuando llegues al final."
