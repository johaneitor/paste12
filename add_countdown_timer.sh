#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# Backups
cp -p backend/routes.py backend/routes.py.bak.$ts 2>/dev/null || true
cp -p frontend/js/app.js frontend/js/app.js.bak.$ts 2>/dev/null || true
cp -p frontend/css/styles.css frontend/css/styles.css.bak.$ts 2>/dev/null || true
mkdir -p frontend/js frontend/css

python - <<'PY'
from pathlib import Path, re
# ------- Backend: enriquecer /api/notes con expires_in / expires_at -------
rp = Path("backend/routes.py")
code = rp.read_text(encoding="utf-8")

# Asegurar imports
if "timedelta" not in code:
    code = code.replace(
        "from datetime import datetime, timezone",
        "from datetime import datetime, timezone, timedelta"
    )

# En GET /api/notes, forzar que la serialización incluya expires_at y expires_in
# Detecta el bloque donde se construyen los dicts y lo sustituye con un helper robusto.
if "def _note_to_dict(" not in code:
    helper = """
def _note_to_dict(n):
    now = datetime.now(timezone.utc)
    try:
        exp = n.expires_at.astimezone(timezone.utc)
    except Exception:
        exp = n.expires_at
    ttl = max(0, int((exp - now).total_seconds()))
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": (n.timestamp.astimezone(timezone.utc).isoformat() if hasattr(n.timestamp,'isoformat') else str(n.timestamp)),
        "expires_at": (exp.isoformat() if hasattr(exp,'isoformat') else str(exp)),
        "expires_in": ttl,
        "likes": getattr(n, "likes", 0) or 0,
        "views": getattr(n, "views", 0) or 0,
        "reports": getattr(n, "reports", 0) or 0,
    }
"""
    # Inserta el helper tras la declaración del Blueprint
    ins = code.find("bp = Blueprint")
    ins = code.find("\n", ins) + 1
    code = code[:ins] + helper + code[ins:]

# Reemplaza cualquier construcción manual de dict por el helper
code = re.sub(
    r"\{[^{}]*?['\"]id['\"]\s*:\s*n\.id[^{}]*?\}",
    r"_note_to_dict(n)",
    code, flags=re.S
)
code = re.sub(
    r"\[(?:\s*n\s*for\s+n\s+in\s+items\s*)\]",
    r"[ _note_to_dict(n) for n in items ]",
    code
)

rp.write_text(code, encoding="utf-8")
print("✓ backend/routes.py: ahora devuelve expires_at + expires_in")

# ------- Frontend: dibujar y actualizar countdown -------
ap = Path("frontend/js/app.js")
js = ap.read_text(encoding="utf-8") if ap.exists() else ""

inject_js = r"""
// ===== Countdown por nota (días/horas/min/seg) =====
function fmtTTL(s){
  s = Math.max(0, Math.floor(s));
  const d = Math.floor(s/86400);
  s -= d*86400;
  const h = Math.floor(s/3600);
  s -= h*3600;
  const m = Math.floor(s/60);
  const x = s - m*60;
  if (d>0) return `${d}d ${h}h`;
  if (h>0) return `${h}h ${m}m`;
  if (m>0) return `${m}m ${x}s`;
  return `${x}s`;
}
function startCountdownLoop(){
  function tick(){
    const now = Date.now();
    document.querySelectorAll('.countdown[data-expires-at], .countdown[data-expires-in]').forEach(el=>{
      let ttl = 0;
      if (el.hasAttribute('data-expires-in')){
        const base = parseInt(el.getAttribute('data-expires-in'),10)||0;
        const t0 = parseInt(el.getAttribute('data-epoch0'),10)||0;
        ttl = base - Math.floor((now - t0)/1000);
      } else {
        const t = Date.parse(el.getAttribute('data-expires-at'));
        ttl = Math.floor((t - now)/1000);
      }
      if (ttl <= 0){
        el.textContent = 'expirada';
        el.closest('[data-note]')?.classList.add('note-expired');
      }else{
        el.textContent = fmtTTL(ttl);
      }
    });
  }
  tick(); setInterval(tick, 1000);
}
document.addEventListener('DOMContentLoaded', startCountdownLoop);

// Hook: cuando pintes las notas, pon el span countdown si no existe
function ensureCountdownForCard(card, note){
  if(!card) return;
  let meta = card.querySelector('.note-meta');
  if(!meta){
    meta = document.createElement('div');
    meta.className = 'note-meta';
    card.appendChild(meta);
  }
  if(!meta.querySelector('.countdown')){
    const cd = document.createElement('span');
    cd.className = 'countdown';
    if(note?.expires_at){ cd.setAttribute('data-expires-at', note.expires_at); }
    else if(note?.expires_in!=null){
      cd.setAttribute('data-expires-in', note.expires_in);
      cd.setAttribute('data-epoch0', Date.now());
    }
    meta.prepend(cd);
  }
}

// Observador: si se agregan tarjetas con datos, intenta decorarlas
const __observer = new MutationObserver(muts=>{
  muts.forEach(m=>{
    m.addedNodes.forEach(n=>{
      if(!(n instanceof Element)) return;
      if(n.matches?.('[data-note]')) ensureCountdownForCard(n, n.__note);
      n.querySelectorAll?.('[data-note]').forEach(x=>ensureCountdownForCard(x, x.__note));
    });
  });
});
document.addEventListener('DOMContentLoaded', ()=>{
  try{ __observer.observe(document.body,{childList:true,subtree:true}); }catch(e){}
});
"""
if "===== Countdown por nota" not in js:
    js += "\n" + inject_js
    ap.write_text(js, encoding="utf-8")
    print("✓ frontend/js/app.js: lógica de countdown añadida")
else:
    print("• frontend/js/app.js: countdown ya presente")

# ------- CSS del badge -------
cp = Path("frontend/css/styles.css")
css = cp.read_text(encoding="utf-8") if cp.exists() else ""
inject_css = """
/* Badge de cuenta regresiva */
.note-meta{display:flex;gap:.6rem;align-items:center;margin-top:.35rem;flex-wrap:wrap}
.countdown{background:#0ea5e9;color:#001024;font-weight:800;padding:.22rem .5rem;border-radius:.6rem;box-shadow:0 6px 18px rgba(14,165,233,.35);font-size:.85rem}
.note-expired{opacity:.6;filter:saturate(.7)}
"""
if ".countdown" not in css:
    css += "\n" + inject_css
    cp.write_text(css, encoding="utf-8")
    print("✓ frontend/css/styles.css: estilos de countdown añadidos")
else:
    print("• frontend/css/styles.css: estilos ya presentes")
PY

# Commit & push (desencadena deploy)
git add -A
git commit -m "feat(countdown): badge con tiempo restante (expires_in/at) + backend añade campos" || true
git push

echo "🚀 Enviado. Cuando Render termine, abre tu sitio con /?v=$(date +%s) para saltar caché."
