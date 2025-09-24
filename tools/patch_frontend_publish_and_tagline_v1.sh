#!/usr/bin/env bash
set -euo pipefail
HTML="frontend/index.html"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }
cp -f "$HTML" "frontend/index.$TS.publishfix.bak"
echo "[fe] Backup: frontend/index.$TS.publishfix.bak"

python - <<'PY'
import io,re
p="frontend/index.html"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

# 1) Quitar subtítulo duplicado: si existen #tagline-rot y #tagline, borramos el <p id="tagline"> (dejamos rotador).
s=re.sub(r'\s*<p[^>]*id=["\']tagline["\'][^>]*>.*?</p>', '', s, flags=re.I|re.S)

# 2) Inyectar parche JS al final: publish con múltiples endpoints + ocultar duplicados + matar SW si ?debug|?nosw
patch = r"""
<script id="p12-publish-fallback">
(()=>{ if (window.__P12_PATCH_PUBLISH__) return; window.__P12_PATCH_PUBLISH__=true;
  // matar SW si debug/nosw (no rompe si no hay)
  try{const q=new URLSearchParams(location.search);
      if((q.has('debug')||q.has('nosw'))&&'serviceWorker'in navigator){
        navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister()));
        if (window.caches && caches.keys) caches.keys().then(ks=>ks.forEach(k=>caches.delete(k)));
      }}catch(_){}

  // Si quedaron dos subtítulos por HTML legacy, mantén solo el rotador
  try{var rot=document.getElementById('tagline-rot'), p=document.getElementById('tagline'); if(rot&&p){ p.remove(); }}catch(_){}

  function esc(t){return (t||'').toString(); }
  function pickTA(){ return document.querySelector('textarea[name=text], #text, textarea'); }
  function pickTTL(){return document.querySelector('input[name=ttl_hours], #ttl, select[name=ttl_hours], select');}
  function msg(ok,txt){
    var el=document.getElementById('msg'); if(!el){el=document.createElement('div'); el.id='msg'; document.body.prepend(el);}
    el.className = ok?'ok':'error'; el.textContent = txt; setTimeout(()=>{el.className='hidden'; el.textContent='';}, 2500);
  }

  async function tryPost(url, body){
    // intento JSON
    try{
      let r = await fetch(url,{method:'POST',credentials:'include',
                               headers:{'Content-Type':'application/json','Accept':'application/json'},
                               body:JSON.stringify(body)});
      if (r.ok) return await r.json().catch(()=>null);
      if (r.status!==405 && r.status!==404) throw new Error(String(r.status));
    }catch(_){}
    // intento FORM
    try{
      const fd = new URLSearchParams(); fd.set('text', body.text); if(body.ttl_hours) fd.set('ttl_hours', String(body.ttl_hours));
      let r = await fetch(url,{method:'POST',credentials:'include',
                               headers:{'Content-Type':'application/x-www-form-urlencoded','Accept':'application/json'},
                               body:fd});
      if (r.ok) return await r.json().catch(()=>null);
    }catch(_){}
    return null;
  }

  async function publishPatched(ev){
    ev && ev.preventDefault && ev.preventDefault();
    const ta=pickTA(), ttl=pickTTL();
    const text=(ta?.value||'').trim(); if (text.length<12){ msg(false,'Escribí un poco más (≥ 12 caracteres).'); return; }
    const v=parseInt(ttl?.value||'',10); const body={text}; if(Number.isFinite(v)&&v>0) body.ttl_hours=v;

    // cascada de endpoints (cubre backends viejos/nuevos)
    const ENDS=['/api/notes','/api/notes/publish','/api/publish','/api/note','/api/notes/create'];
    let j=null;
    for (const u of ENDS){ j = await tryPost(u, body); if (j && (j.ok!==false) ) break; }

    if(!j || j.ok===false){ msg(false, (j&&j.error)||'Error HTTP 405/404'); return; }

    // inyectar la nota arriba si vino id
    try{
      const FEED=document.querySelector('#list,.list,[data-feed]')||document.body;
      const id = j.id || (j.item && j.item.id);
      const likes = j.likes || (j.item && j.item.likes) || 0;
      const html = '<article class="note" data-id="'+esc(id)+'">'+
                   '<div data-text="1">'+esc(body.text)+'</div>'+
                   '<div class="meta">#'+esc(id)+' · ❤ '+esc(likes)+' · 👁 0</div></article>';
      const wrap=document.createElement('div'); wrap.innerHTML=html; FEED.prepend(wrap.firstElementChild);
    }catch(_){}
    if(ta) ta.value=''; if(ttl) ttl.value='';
    msg(true,'Publicado ✅');
  }

  // Re-bind: botón y Ctrl/Cmd+Enter
  window.addEventListener('DOMContentLoaded', ()=>{
    const btn=document.getElementById('send'); if(btn){ btn.addEventListener('click', publishPatched, {capture:true}); }
    const ta=pickTA(); if(ta){ ta.addEventListener('keydown', e=>{ if(e.key==='Enter'&&(e.ctrlKey||e.metaKey)) publishPatched(e); }); }
  }, {once:true});
})();</script>
"""
# inyectar antes de </body> si no existe aún
if "p12-publish-fallback" not in s:
    s = s.replace("</body>", patch + "\n</body>")

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[fe] parche aplicado")
else:
    print("[fe] nada que hacer (ya estaba)")
PY

echo "[fe] Listo."
