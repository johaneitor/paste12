#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# Backups
[ -f frontend/index.html ] && cp -p frontend/index.html "frontend/index.html.bak.$ts" || true
[ -f frontend/css/styles.css ] && cp -p frontend/css/styles.css "frontend/css/styles.css.bak.$ts" || true

mkdir -p frontend/js

# 1) JS del menú ⋯ (Compartir + Reportar)
cat > frontend/js/actions_menu.js <<'JS'
(function(){
  // ===== Utils =====
  function noteUrl(id){ return `${location.origin}/#n-${id}`; }

  async function copyToClipboard(text){
    try{ await navigator.clipboard.writeText(text); return true; }
    catch(_){
      const ta = document.createElement('textarea');
      ta.value = text; ta.style.position='fixed'; ta.style.top='-1000px';
      document.body.appendChild(ta); ta.select();
      const ok = document.execCommand('copy'); document.body.removeChild(ta);
      return ok;
    }
  }

  function toast(msg){
    let t = document.getElementById('toast-p12');
    if(!t){
      t = document.createElement('div'); t.id='toast-p12';
      Object.assign(t.style, {
        position:'fixed', left:'50%', bottom:'16px', transform:'translateX(-50%) translateY(10px)',
        background:'#111a', color:'#fff', padding:'10px 14px', borderRadius:'10px',
        backdropFilter:'blur(6px)', zIndex:'9999', fontSize:'14px', opacity:'0',
        transition:'opacity .2s, transform .2s'
      });
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.style.opacity='1'; t.style.transform='translateX(-50%) translateY(0)';
    setTimeout(()=>{ t.style.opacity='0'; t.style.transform='translateX(-50%) translateY(10px)'; }, 1500);
  }

  async function shareNote(id){
    const url = noteUrl(id);
    if (navigator.share && (!navigator.canShare || navigator.canShare({url}))){
      try { await navigator.share({title:'Paste12', text:'Mira esta nota', url}); return; }
      catch(e){/* cancelado → fallback a copiar */}
    }
    const ok = await copyToClipboard(url);
    toast(ok ? 'Enlace copiado' : `Copia manual: ${url}`);
  }

  async function reportNote(id, card){
    try{
      const res = await fetch(`/api/notes/${id}/report`, {method:'POST', headers:{'Content-Type':'application/json'}});
      const j = await res.json();
      if (j.deleted){
        // Borrar del DOM
        card?.remove();
        toast('La nota fue eliminada por reportes');
      } else if (j.already_reported){
        toast('Ya reportaste esta nota');
      } else {
        toast(`Reporte enviado (${j.reports}/5)`);
      }
    }catch(e){
      console.warn('report failed', e);
      toast('No se pudo reportar');
    }
  }

  // ===== DOM helpers =====
  function getIdFromCard(card){
    return card.getAttribute('data-note')
      || card.getAttribute('data-note-id')
      || (card.dataset ? (card.dataset.note || card.dataset.id) : null)
      || null;
  }

  function ensureAnchorId(card, id){
    if (!card.id) card.id = 'n-'+id;
  }

  function ensureMenu(card, id){
    if (card.querySelector('.p12-menu-wrap')) return;

    // contenedor absoluto arriba-dcha
    const wrap = document.createElement('div');
    wrap.className = 'p12-menu-wrap';
    wrap.innerHTML = `
      <button type="button" class="p12-menu-btn" aria-label="Opciones">⋯</button>
      <div class="p12-menu" hidden>
        <button type="button" class="p12-share">Compartir</button>
        <button type="button" class="p12-report">Reportar</button>
      </div>`;
    card.style.position = card.style.position || 'relative';
    card.appendChild(wrap);

    const btn = wrap.querySelector('.p12-menu-btn');
    const menu = wrap.querySelector('.p12-menu');
    const share = wrap.querySelector('.p12-share');
    const report = wrap.querySelector('.p12-report');

    btn.addEventListener('click', (e)=>{
      e.stopPropagation();
      const v = menu.hasAttribute('hidden');
      document.querySelectorAll('.p12-menu').forEach(m=>m.setAttribute('hidden',''));
      if (v) menu.removeAttribute('hidden'); else menu.setAttribute('hidden','');
    });

    share.addEventListener('click', (e)=>{ e.stopPropagation(); menu.setAttribute('hidden',''); shareNote(id); });
    report.addEventListener('click', (e)=>{ e.stopPropagation(); menu.setAttribute('hidden',''); reportNote(id, card); });

    // cerrar al clicar fuera
    document.addEventListener('click', ()=> menu.setAttribute('hidden',''));
  }

  function process(container){
    container.querySelectorAll('[data-note], [data-note-id], .note-card, article, li').forEach(card=>{
      const id = getIdFromCard(card);
      if (!id) return;
      ensureAnchorId(card, id);
      ensureMenu(card, id);
    });
  }

  document.addEventListener('DOMContentLoaded', ()=>{
    const container = document.getElementById('notes')
      || document.querySelector('[data-notes]')
      || document.querySelector('#list')
      || document.querySelector('main')
      || document.body;

    process(container);
    const mo = new MutationObserver(()=>process(container));
    mo.observe(container, {childList:true, subtree:true});
    console.log('[actions_menu] listo (⋯ → Compartir/Reportar sin popups)');
  });
})();
JS

# 2) CSS básico del menú ⋯
if ! grep -q '.p12-menu-wrap' frontend/css/styles.css 2>/dev/null; then
cat >> frontend/css/styles.css <<'CSS'

/* --- Menú ⋯ en cada tarjeta --- */
.p12-menu-wrap{ position:absolute; top:8px; right:8px; }
.p12-menu-btn{ border:0; background:#13233f; color:#fff; width:28px; height:28px; border-radius:8px; cursor:pointer; line-height:1; font-size:18px; }
.p12-menu-btn:hover{ filter:brightness(1.1); }
.p12-menu{ position:absolute; top:34px; right:0; background:#0b1530; color:#fff; border:1px solid #2a3c68; border-radius:10px; overflow:hidden; min-width:160px; box-shadow:0 6px 20px #0007; }
.p12-menu button{ display:block; width:100%; text-align:left; padding:10px 12px; background:transparent; border:0; color:#fff; cursor:pointer; }
.p12-menu button:hover{ background:#17325b; }
CSS
fi

# 3) Inyectar script en index.html (al final del <body>)
if ! grep -q 'js/actions_menu.js' frontend/index.html; then
  perl -0777 -pe 's#</body>#  <script src="js/actions_menu.js?v='"$ts"'"></script>\n</body>#i' -i frontend/index.html
fi

# 4) Verificación rápida de sintaxis backend
python -m compileall -q backend

# 5) Commit + push → Render redeploy
git add frontend/js/actions_menu.js frontend/index.html frontend/css/styles.css
git commit -m "feat(ui): menú ⋯ en tarjetas con Compartir (nativo/copia) y Reportar (1 por persona, borra al 5º)" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "✅ Menú ⋯ listo. Refresca con /?v=$ts para limpiar caché."
