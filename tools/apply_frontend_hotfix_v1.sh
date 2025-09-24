#!/usr/bin/env bash
set -euo pipefail
edit(){ f="$1"; [ -f "$f" ] || return 0
  ts="$(date -u +%Y%m%d-%H%M%SZ)"
  bak="${f}.pre_hotfix_${ts}.bak"; cp -f "$f" "$bak"
  echo "• backup -> $bak"

  tmp="$(mktemp)"; cat "$f" > "$tmp"

  # 1) CSS para esconder el banner (si aparece)
  if ! grep -q "/* hotfix-banner-hide */" "$tmp"; then
    awk '1; END{
      print "<style>/* hotfix-banner-hide */#deploy-stamp-banner{display:none!important}</style>"
    }' "$tmp" > "$tmp.1" && mv "$tmp.1" "$tmp"
    echo "• CSS anti-banner inyectado"
  fi

  # 2) Suavizar el truncador (si existe summary-enhancer, subir a 140 chars)
  if grep -q "summary-enhancer" "$tmp"; then
    sed -E 's/(const MAX\s*=\s*)20;/\1140;/g' "$tmp" > "$tmp.1" && mv "$tmp.1" "$tmp"
    echo "• summary MAX=140"
  fi

  # 3) Cliente ligero: validar ≥12, fallback FORM, paginado unificado + botón
  #    Se inserta al final, idempotente por id=hotfix-client-v1
  if ! grep -q 'id="hotfix-client-v1"' "$tmp"; then
    cat >> "$tmp" <<'EOF'
<script id="hotfix-client-v1">
(()=>{'use strict';
const $=s=>document.querySelector(s);
const api=p=> (p.startsWith('/')?p:'/api/'+p);

// Estado de paginación
let nextURL=null;
function setMoreVisible(v){ let b=document.getElementById('p12-hotfix-more');
  if(!b){ b=document.createElement('button'); b.id='p12-hotfix-more'; b.type='button';
    b.textContent='Cargar más'; b.style.cssText='display:block;margin:12px auto;padding:.6rem 1rem;border-radius:10px;border:1px solid #e5e7eb;background:#fff;';
    const list=$('#list')||document.body; list.after(b);
    b.onclick=()=>{ if(nextURL) fetchPage(nextURL); };
  }
  b.style.display = v ? '' : 'none';
}

function esc(s){return (s||'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));}
function renderItem(it){
  const text = it.text || it.content || it.summary || '';
  return `
    <article class="note" data-id="${it.id}">
      <div data-text="1">${esc(text)||'(sin texto)'}</div>
      <div class="meta">#${it.id} · ❤ ${it.likes??0} · 👁 ${it.views??0}
        <button class="act like">❤</button>
        <button class="act more">⋯</button>
      </div>
      <div class="menu hidden">
        <button class="share">Compartir</button>
        <button class="report">Reportar 🚩</button>
      </div>
    </article>`;
}
function appendItems(items){
  const root = $('#list') || (function(){ const d=document.createElement('section'); d.id='list'; document.body.appendChild(d); return d; })();
  const html = (items||[]).map(renderItem).join('');
  const div = document.createElement('div'); div.innerHTML = html;
  root.append(...div.children);
}
async function fetchPage(url){
  try{
    const r=await fetch(url,{headers:{'Accept':'application/json'}});
    const j=await r.json();
    appendItems(Array.isArray(j)?j:(j.items||[]));
    nextURL=null;
    const link=r.headers.get('Link')||r.headers.get('link');
    if(link){ const m=/<([^>]+)>;\s*rel="?next"?/i.exec(link); if(m) nextURL=m[1]; }
    if(!nextURL){
      try{ const xn=JSON.parse(r.headers.get('X-Next-Cursor')||'null');
           if(xn&&xn.cursor_ts&&xn.cursor_id){ nextURL=`/api/notes?cursor_ts=${encodeURIComponent(xn.cursor_ts)}&cursor_id=${xn.cursor_id}`; }
      }catch(_){}
    }
    setMoreVisible(!!nextURL);
  }catch(_){ /* silencio */ }
}

function validateText(s){ return (s||'').trim().length>=12; }
function flash(ok,msg){
  const el = $('#msg') || (function(){ const d=document.createElement('div'); d.id='msg'; document.body.prepend(d); return d; })();
  el.className = ok?'ok':'error'; el.textContent = msg;
  setTimeout(()=>{ el.className='hidden'; el.textContent=''; }, 2000);
}

async function publish(ev){
  ev && ev.preventDefault && ev.preventDefault();
  const t = ($('#text')?.value||'').trim();
  const ttl= parseInt($('#ttl')?.value||'',10);
  if(!validateText(t)){ flash(false,'Escribí un poco más (≥ 12 caracteres).'); return; }
  const body={ text: t }; if(Number.isFinite(ttl)&&ttl>0) body.ttl_hours=ttl;

  // JSON primero
  let r=null, j=null;
  try{
    r=await fetch(api('notes'),{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify(body)});
  }catch(_){}
  if(!r || !r.ok){
    // FALLBACK FORM
    const fd = new URLSearchParams(); fd.set('text',t); if(body.ttl_hours) fd.set('ttl_hours',String(body.ttl_hours));
    try{ r=await fetch(api('notes'),{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','Accept':'application/json'},body:fd}); }catch(_){}
  }
  try{ j = await r.json(); }catch(_){ j=null; }
  if(!r || !r.ok || !j || j.ok===false){ flash(false, (j&&j.error)||('Error HTTP '+(r&&r.status))); return; }
  // Insertar primero
  const it = j.item || {id:j.id, text:t, likes:j.likes||0, views:0, timestamp:new Date().toISOString()};
  const root = $('#list') || (function(){ const d=document.createElement('section'); d.id='list'; document.body.appendChild(d); return d; })();
  const c = document.createElement('div'); c.innerHTML = renderItem(it); root.prepend(c.firstElementChild);
  $('#text') && ($('#text').value=''); $('#ttl') && ($('#ttl').value='');
  flash(true,'Publicado ✅');
}

// Delegación acciones
document.addEventListener('click', async (e)=>{
  const like = e.target.closest && e.target.closest('button.like');
  const more = e.target.closest && e.target.closest('button.more');
  const share= e.target.closest && e.target.closest('button.share');
  const rpt  = e.target.closest && e.target.closest('button.report');
  const art  = e.target.closest && e.target.closest('article.note');
  const id   = art&&art.getAttribute('data-id');

  try{
    if(like && id){
      const r=await fetch(api(`notes/${id}/like`),{method:'POST'}); const j=await r.json().catch(()=>({}));
      if(j && typeof j.likes!=='undefined'){ const m=art.querySelector('.meta'); if(m) m.innerHTML = m.innerHTML.replace(/❤\s*\d+/, '❤ '+j.likes); }
    }else if(more && art){
      art.querySelector('.menu')?.classList.toggle('hidden');
    }else if(share && id){
      const url = `${location.origin}/?id=${id}`;
      if(navigator.share){ await navigator.share({title:`Nota #${id}`, url}); }
      else { await navigator.clipboard.writeText(url); flash(true,'Link copiado'); }
      art.querySelector('.menu')?.classList.add('hidden');
    }else if(rpt && id){
      const r=await fetch(api(`notes/${id}/report`),{method:'POST'}); const j=await r.json().catch(()=>({}));
      if(j?.removed){ art.remove(); flash(true,'Nota eliminada por reportes'); }
      else { flash(true,'Reporte enviado'); }
      art.querySelector('.menu')?.classList.add('hidden');
    }
  }catch(_){}
}, {capture:true});

// Arranque: pag 1 y botón
window.addEventListener('DOMContentLoaded',()=>{
  // publica: click y Ctrl/Cmd+Enter
  const btn = document.getElementById('send'); if(btn){ btn.addEventListener('click', publish, {capture:true}); }
  const ta  = document.getElementById('text'); if(ta){ ta.addEventListener('keydown',(e)=>{ if(e.key==='Enter'&&(e.ctrlKey||e.metaKey)) publish(e);}); }

  fetchPage('/api/notes?limit=10');
});
})();
</script>
EOF
    echo "• hotfix cliente inyectado"
  fi

  mv "$tmp" "$f"
  echo "OK: $f"
}

edit backend/static/index.html
edit frontend/index.html
edit index.html
