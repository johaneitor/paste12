#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# Backups
for f in frontend/index.html frontend/js/app.js; do
  [ -f "$f" ] && cp -p "$f" "$f.bak.$ts" || true
done

# 1) Neutraliza enlaces a Twitter intent en el HTML (si existieran)
if [ -f frontend/index.html ]; then
  python - <<'PY'
from pathlib import Path, re
p = Path("frontend/index.html")
s = p.read_text(encoding="utf-8")
s2 = re.sub(r'href="https://twitter\.com/intent/tweet[^"]*"',
            'href="#" data-share="1"', s)
if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print("✓ index.html: enlaces de Twitter neutralizados")
else:
    print("• index.html: sin enlaces de Twitter o ya neutralizados")
PY
fi

# 2) Añade manejador de share nativo en app.js y bloquea popups
mkdir -p frontend/js
touch frontend/js/app.js
python - <<'PY'
from pathlib import Path
p = Path("frontend/js/app.js")
code = p.read_text(encoding="utf-8")

# Elimina window.open a intent/tweet si existiera
import re
code2 = re.sub(r'window\.open\(\s*[\'"]https://twitter\.com/intent/tweet[^;]+;?\s*\)', 
               '/* popup twitter eliminado */', code)

# Inyecta utilidades de share si aún no están
inject = r"""
// === Share nativo: sin popups ===
async function shareNative(text, url){
  try{
    if(navigator.share){
      await navigator.share({title:'Paste12', text, url});
      return;
    }
  }catch(e){}
  try{
    await navigator.clipboard.writeText(`${text}\n${url}`);
    showToast('🔗 Enlace copiado');
  }catch(e){
    showToast('🔗 Copia manual: ' + url);
  }
}
function showToast(msg){
  const t=document.createElement('div');
  t.textContent=msg;
  t.style.cssText='position:fixed;left:50%;bottom:24px;transform:translateX(-50%);background:rgba(0,0,0,.8);color:#fff;padding:10px 14px;border-radius:12px;z-index:9999;font-size:14px';
  document.body.appendChild(t); setTimeout(()=>t.remove(),1400);
}
// Interceptor global: cualquier click en .share, .share-twitter o [data-share]
document.addEventListener('click', async (ev)=>{
  const el = ev.target.closest('[data-share], .share, .share-twitter');
  if(!el) return;
  ev.preventDefault(); ev.stopPropagation();
  const card = el.closest('[data-note]') || document;
  const text = (el.getAttribute('data-text') 
               || (card.querySelector('.note-text')?.textContent ?? '')).trim() || document.title;
  const url  = el.getAttribute('data-url') || location.origin;
  await shareNative(text, url);
}, true);
"""
if "=== Share nativo: sin popups ===" not in code2:
    code2 += "\n" + inject

if code2 != code:
    p.write_text(code2, encoding="utf-8")
    print("✓ app.js: popup de Twitter removido y share nativo añadido")
else:
    print("• app.js: ya estaba el share nativo")
PY

# 3) Commit y push (desencadena deploy)
git add -A
git commit -m "ux: eliminar popup de Twitter y usar Web Share/copia" || true
git push
echo "🚀 Cambios enviados. Tras el deploy en Render, recarga con /?v=$(date +%s)"
