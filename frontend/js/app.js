// paste12 — frontend estable (paginación + dedupe + vistas 1x)
// Singleton boot
if (window.__P12_BOOTED__) { /* ya iniciado */ } else { window.__P12_BOOTED__ = true; }

window.P12 = window.P12 || {};
P12.page = 1;
P12.loading = false;
P12.renderedIds = new Set();   // para dedupe de tarjetas
P12.viewedOnce  = new Set();   // para POST /view 1x
P12.infAttached = false;       // para listener de scroll único

function fmtRemaining(sec){
  sec = Math.max(0, parseInt(sec||0,10));
  const d = Math.floor(sec/86400); sec%=86400;
  const h = Math.floor(sec/3600);  sec%=3600;
  const m = Math.floor(sec/60);
  if(d>0) return `${d}d ${h}h`;
  if(h>0) return `${h}h ${m}m`;
  return `${m}m`;
}

class NotesApp {
  constructor() {
    this.listEl = document.querySelector('#feed') || document.body;
    this.footer = document.querySelector('#feed-end') || (() => {
      const el = document.createElement('div');
      el.id = 'feed-end';
      el.style.cssText = 'text-align:center; padding:16px; opacity:.7;';
      this.listEl.after(el);
      return document.getElementById('feed-end');
    })();
    // arranque: cargar page 1 una sola vez
    this.load(1);
  }

  async load(page=1){
    if(P12.loading) return;
    P12.loading = true;
    try {
      const r = await fetch(`/api/notes?page=${page}`, { headers:{ "Accept":"application/json" }});
      const d = await r.json();
      const notes   = d.notes || [];
      const hasMore = !!d.has_more;

      if (page===1){ (document.querySelector('#feed')||document.body).innerHTML=''; P12.renderedIds.clear(); }

      // render + vistas idempotentes
      for (const n of notes) {
        if (P12.renderedIds.has(n.id)) continue; // DEDUPE POR ID
        P12.renderedIds.add(n.id);

        const card = document.createElement('div');
        card.className = 'note-card';
        card.dataset.id = n.id;
        card.innerHTML = `
          <div class="note-text"></div>
          <div class="note-meta">
            <button type="button" class="like-btn">❤️</button>
            <span class="likes-count">${n.likes || 0}</span>
            <span class="views-count">${n.views || 0}</span>
            <span class="remaining"></span>
          </div>
        `;
        card.querySelector('.note-text').textContent = n.text || '';
        if (typeof n.remaining === 'number') {
          card.querySelector('.remaining').textContent = fmtRemaining(n.remaining);
        }
        this.listEl.appendChild(card);

        // /view una sola vez por sesión/navegación
        if (!P12.viewedOnce.has(n.id)) {
          P12.viewedOnce.add(n.id);
          fetch(`/api/notes/${n.id}/view`, { method:'POST' })
            .then(r=>r.json())
            .then(j=>{
              const el = card.querySelector('.views-count');
              if (el && j && typeof j.views === 'number') el.textContent = j.views;
            }).catch(()=>{});
        }

        // like
        const likeBtn = card.querySelector('.like-btn');
        likeBtn.addEventListener('click', async ()=>{
          try {
            const rr = await fetch(`/api/notes/${n.id}/like`, { method:'POST' });
            const jj = await rr.json();
            const lc = card.querySelector('.likes-count');
            if (lc && jj && typeof jj.likes === 'number') lc.textContent = jj.likes;
          } catch {}
        }, { once:false });
      }

      if (hasMore === true) {
      P12.page = page + 1;
      if (window.attachInfiniteScroll) attachInfiniteScroll();
    } else {
      if (window.detachInfiniteScroll) detachInfiniteScroll();
    } else {
        this.footer.textContent = 'Fin del feed';
      }
    } catch (e) {
      console.error('load error', e);
    } finally {
      P12.loading = false;
    }
  }
}

// Scroll infinito — se adjunta UNA sola vez
function attachInfiniteScroll(cb){
  if (P12.infAttached) return;
  P12.infAttached = true;
  let ticking = false;

  window.addEventListener('scroll', () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      const nearBottom = (window.innerHeight + window.scrollY) >= (document.body.offsetHeight - 400);
      if (nearBottom && !P12.loading) cb();
      ticking = false;
    });
  }, { passive:true });
}

// Eliminar shims viejos que llamaban load dos veces
try { delete window.P12App; } catch {}
try { delete window.load;   } catch {}

// Boot
document.addEventListener('DOMContentLoaded', () => {
  if (!window.__P12_APP__) window.__P12_APP__ = new NotesApp();
});
