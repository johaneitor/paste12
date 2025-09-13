#!/usr/bin/env python3
import re, pathlib, shutil, sys

FILES = [pathlib.Path("backend/static/index.html"), pathlib.Path("frontend/index.html")]
JS = r"""<script id="p12-safe-shim-v8">
(()=>{try{
  const Q = new URLSearchParams(location.search);
  // nosw: desregistrar SW y limpiar caches
  if (Q.has('nosw') && 'serviceWorker' in navigator) {
    navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister()));
    if (window.caches) { caches.keys().then(ks=>ks.forEach(k=>caches.delete(k))); }
  }

  const escapeHtml = s=>String(s).replace(/[&<>"]/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[ch]));
  const api = {
    list: async (url='/api/notes?limit=10')=>{
      const r = await fetch(url, {credentials:'include'});
      const link = r.headers.get('Link')||'';
      const data = await r.json().catch(()=>({ok:false}));
      return {data, link};
    },
    create: async (text)=>{
      let res = await fetch('/api/notes',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})});
      if (res.status===400) {
        res = await fetch('/api/notes',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({text}).toString()});
      }
      return res;
    },
    like: (id)=>fetch(`/api/notes/${id}/like`,{method:'POST'}).then(r=>r.json()).catch(()=>null),
    view: (id)=>fetch(`/api/notes/${id}/view`,{method:'POST'}).catch(()=>{}),
    get:  (id)=>fetch(`/api/notes/${id}`).then(r=>r.json()).catch(()=>null),
    nextFromLink: (link)=>{
      const m = /<([^>]+)>;\s*rel="next"/.exec(link||''); return m? m[1]: null;
    }
  };

  const feedHost = document.querySelector('[data-feed], #feed, main, body') || document.body;
  let feed = document.querySelector('#p12-feed');
  if (!feed) { feed = document.createElement('div'); feed.id = 'p12-feed'; feedHost.appendChild(feed); }

  const makeCard = (it)=>{
    const el = document.createElement('article');
    el.className = 'note-card';
    el.setAttribute('data-id', it.id);
    el.innerHTML = `
      <div class="note-body">${escapeHtml(it.text||'')}</div>
      <div class="note-meta">
        <button data-act="like" aria-label="Me gusta">❤️ <span class="likes">${it.likes||0}</span></button>
        <button data-act="share" aria-label="Compartir">🔗</button>
        <button data-act="report" aria-label="Reportar">🚩</button>
      </div>`;
    return el;
  };

  const renderList = (items, append=false)=>{
    if (!append) feed.innerHTML = '';
    const frag = document.createDocumentFragment();
    (items||[]).forEach(it=> frag.appendChild(makeCard(it)));
    feed.appendChild(frag);
    observeViews(feed);
  };

  // Vistas con IO y de-duplicación
  const seen = new Set();
  function observeViews(root){
    if (!('IntersectionObserver' in window)) return;
    const io = new IntersectionObserver(entries=>{
      entries.forEach(e=>{
        if (e.isIntersecting){
          const id = e.target.getAttribute('data-id');
          if (id && !seen.has(id)) { seen.add(id); api.view(id); }
        }
      })
    }, {rootMargin:'0px 0px -25% 0px', threshold:0.25});
    root.querySelectorAll('article.note-card').forEach(el=>io.observe(el));
  }

  // Delegación de eventos (like/share/report)
  document.addEventListener('click', async ev=>{
    const btn = ev.target.closest('[data-act]');
    if (!btn) return;
    const act = btn.getAttribute('data-act');
    const card = btn.closest('article.note-card');
    const id = card && card.getAttribute('data-id');

    if (act==='like' && id){
      btn.disabled = true;
      try {
        const r = await api.like(id);
        const sp = card.querySelector('.likes');
        if (r && sp && r.likes!=null) sp.textContent = r.likes;
      } finally { btn.disabled=false; }
    } else if (act==='share' && id){
      const url = `${location.origin}/?id=${id}`;
      if (navigator.share) { navigator.share({url}).catch(()=>{}); }
      else {
        try { await navigator.clipboard?.writeText(url); btn.textContent='✓'; setTimeout(()=>btn.textContent='🔗',1200); } catch {}
      }
    } else if (act==='report' && id){
      try { await fetch(`/api/notes/${id}/report`, {method:'POST'}); btn.textContent='🚩✓'; } catch {}
    }
  }, {passive:true});

  // Publicar con fallback
  const form = document.querySelector('form#publish, form[action*="/api/notes"]');
  if (form){
    form.addEventListener('submit', async (ev)=>{
      ev.preventDefault();
      const fd = new FormData(form);
      const text = (fd.get('text')||'').toString();
      if (!text || text.trim().length<20) { alert('Texto muy corto'); return; }
      const res = await api.create(text);
      const data = await res.json().catch(()=>null);
      if (res.ok && data && data.item){ renderList([data.item], true); form.reset(); }
    }, {once:false});
  }

  // Nota única o feed con paginado
  const noteId = Q.get('id');
  if (noteId){
    document.head.insertAdjacentHTML('beforeend','<meta name="p12-single" content="1">');
    api.get(noteId).then(j=>{
      if (j && j.ok && j.item) renderList([j.item], false);
    });
  } else {
    api.list('/api/notes?limit=10').then(({data, link})=>{
      if (data && data.ok && Array.isArray(data.items)) {
        renderList(data.items, false);
        let next = api.nextFromLink(link);
        let lm = document.querySelector('#p12-more');
        if (!lm){ lm = document.createElement('button'); lm.id='p12-more'; lm.textContent='Ver más'; feedHost.appendChild(lm); }
        lm.onclick = async ()=>{
          if (!next){ lm.disabled=true; return; }
          lm.disabled = true;
          const {data, link} = await api.list(next);
          if (data && data.ok && data.items?.length) renderList(data.items, true);
          next = api.nextFromLink(link);
          lm.disabled = false;
          if (!next){ lm.textContent='No hay más'; lm.disabled=true; }
        };
      }
    });
  }

  // Marcador de auditoría
  document.head.insertAdjacentHTML('beforeend','<meta name="p12-safe-shim" content="v8">');
} catch(e){ console.warn('p12-safe-shim-v8 error', e); }})();
</script>"""

def inject(path: pathlib.Path):
    if not path.exists(): return False, "no existe"
    html = path.read_text(encoding="utf-8", errors="ignore")
    if 'id="p12-safe-shim-v8"' in html:
        return True, "ya estaba"
    bak = path.with_suffix(path.suffix + ".p12_v8.bak")
    if not bak.exists():
        shutil.copyfile(path, bak)
    # Inserta antes de </body> si existe, o al final
    if re.search(r'</body\s*>', html, flags=re.I):
        new = re.sub(r'</body\s*>', JS + "\n</body>", html, flags=re.I, count=1)
    else:
        new = html + "\n" + JS + "\n"
    path.write_text(new, encoding="utf-8")
    return True, f"inyectado | backup={bak.name}"

changed = False
for f in FILES:
    ok, msg = inject(f)
    print(f"{f}: {msg}")
    changed = changed or ("inyectado" in msg)

if not changed:
    sys.exit(0)
