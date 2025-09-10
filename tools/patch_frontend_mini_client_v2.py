#!/usr/bin/env python3
import re, sys, pathlib, shutil

# 1) elegir index.html existente (orden de preferencia)
candidates = [
    pathlib.Path("backend/static/index.html"),
    pathlib.Path("frontend/index.html"),
    pathlib.Path("index.html"),
]
target = None
for p in candidates:
    if p.exists():
        target = p; break
if not target:
    print("✗ No encontré index.html (backend/static, frontend/ o raíz)"); sys.exit(2)

html = target.read_text(encoding="utf-8")
norm = html.replace("\r\n","\n").replace("\r","\n")

START = "<!-- MINI-CLIENT v2 START -->"
END   = "<!-- MINI-CLIENT v2 END -->"

# 2) si ya está aplicado, salimos
if START in norm and END in norm:
    print(f"OK: mini-cliente ya está aplicado en {target}")
    sys.exit(0)

# 3) snippet JS (sin backslashes problemáticos en re.sub)
JS = r"""
<!-- MINI-CLIENT v2 START -->
<script>
(() => {
  'use strict';

  // ===== util =====
  const qs = new URLSearchParams(location.search);
  const DEBUG = qs.has('debug');
  const KILL_SW = qs.has('nosw') || qs.has('pe') || qs.has('debug');

  // Killer SW opcional (para evitar el banner de "nueva versión")
  if (KILL_SW && 'serviceWorker' in navigator) {
    try {
      navigator.serviceWorker.getRegistrations().then(rs => rs.forEach(r => r.unregister()));
      if (window.caches && caches.keys) caches.keys().then(keys => keys.forEach(k => caches.delete(k)));
      if (DEBUG) console.log('[mini] SW unregistered, caches cleared');
    } catch(e) { /* noop */ }
  }

  const BASE = '';
  const FEED_SEL = '[data-notes],[data-feed],#notes,#feed';
  const TEXTAREA_SEL = 'textarea[name="text"], textarea#text, textarea';
  const HOURS_SEL = 'select[name="hours"], select#hours, select';

  const $ = (sel, ctx=document) => ctx.querySelector(sel);
  const $$= (sel, ctx=document) => Array.from(ctx.querySelectorAll(sel));
  const esc = s => (s ?? '').toString().replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

  // ===== contenedores =====
  let feed = $(FEED_SEL);
  if (!feed) {
    feed = document.createElement('div');
    feed.id = 'feed';
    // intentamos ubicarlo antes del footer legal si existe
    const legal = $$('a[href*="terminos"],a[href*="términos"],a[href*="privacy"],a[href*="privacidad"]')[0];
    (legal && legal.parentElement ? legal.parentElement : document.body).prepend(feed);
  }

  // Si no hay formulario visible, armamos uno mínimo (progresivo)
  let txt = $(TEXTAREA_SEL);
  let hoursSel = $(HOURS_SEL);
  let publishBtn = $('[data-publish], button#publish');

  if (!txt || !publishBtn) {
    const box = document.createElement('div');
    box.style.margin = '12px 0';
    box.innerHTML = `
      <div class="mini-publish" style="display:grid; gap:8px; padding:12px; border-radius:8px; box-shadow:0 1px 4px rgba(0,0,0,.08); background:#fff;">
        <textarea rows="3" placeholder="Escribe tu nota…" style="width:100%; padding:10px; border-radius:8px; border:1px solid #ddd;" data-mini-text></textarea>
        <div style="display:flex; gap:8px; align-items:center; flex-wrap:wrap;">
          <select data-mini-hours style="padding:8px; border-radius:8px; border:1px solid #ddd;">
            ${[1,6,12,24,48,72].map(h => `<option value="${h}" ${h===12?'selected':''}>${h} h</option>`).join('')}
          </select>
          <button data-mini-publish style="padding:.6rem 1rem; border-radius:12px; border:0; background:#0ea5e9; color:#fff; font-weight:600;">Publicar</button>
          <span data-mini-status style="margin-left:6px; color:#666; font-size:.9rem;"></span>
        </div>
      </div>`;
    feed.before(box);
    txt = $('[data-mini-text]', box);
    hoursSel = $('[data-mini-hours]', box);
    publishBtn = $('[data-mini-publish]', box);
  }

  // ===== estado de paginación =====
  let nextURL = null;
  let loading = false;

  // ===== render =====
  function renderActions(item) {
    const id = item.id;
    const likes = item.likes ?? 0;
    const views = item.views ?? 0;
    return `
      <div class="mini-actions" style="display:flex; gap:10px; align-items:center; flex-wrap:wrap; margin-top:6px;">
        <button class="mini-like" data-id="${id}" style="padding:6px 10px; border:1px solid #e5e7eb; border-radius:10px; background:#fff;">❤️ <span data-like-count>${likes}</span></button>
        <span title="vistas" style="opacity:.7;">👁️ ${views}</span>
        <button class="mini-report" data-id="${id}" style="padding:6px 10px; border:1px solid #fee2e2; border-radius:10px; background:#fff;">🚩 Reportar</button>
        <button class="mini-share" data-id="${id}" style="padding:6px 10px; border:1px solid #e5e7eb; border-radius:10px; background:#fff;">🔗 Compartir</button>
      </div>`;
  }
  function renderItem(item) {
    const ts = item.timestamp ? new Date(item.timestamp.replace(' ','T')).toLocaleString() : '';
    return `
      <article class="mini-card" data-id="${item.id}" style="background:#fff; border:1px solid #eee; border-radius:14px; padding:12px; margin:12px 0;">
        <header style="font-size:.85rem; color:#6b7280; display:flex; gap:10px; align-items:center; flex-wrap:wrap;">
          <span>#${item.id ?? ''}</span>
          ${ts ? `<time>${esc(ts)}</time>` : ''}
        </header>
        <div class="mini-text" style="margin-top:6px; white-space:pre-wrap;">${esc(item.text ?? '')}</div>
        ${renderActions(item)}
      </article>`;
  }
  function upsertHandlers(scope=document) {
    // like
    $$('.mini-like', scope).forEach(btn => {
      btn.onclick = async () => {
        const id = btn.getAttribute('data-id');
        try {
          const res = await fetch(`${BASE}/api/notes/${id}/like`, {method:'POST', credentials:'include'});
          const j = await res.json();
          if (j && typeof j.likes !== 'undefined') btn.querySelector('[data-like-count]').textContent = j.likes;
        } catch(e) { console.warn('like failed', e); }
      };
    });
    // report
    $$('.mini-report', scope).forEach(btn => {
      btn.onclick = async () => {
        const id = btn.getAttribute('data-id');
        btn.disabled = true;
        try {
          const res = await fetch(`${BASE}/api/notes/${id}/report`, {method:'POST', credentials:'include'});
          await res.json();
          btn.textContent = '✅ Reportado';
        } catch(e) { btn.disabled = false; }
      };
    });
    // share
    $$('.mini-share', scope).forEach(btn => {
      btn.onclick = async () => {
        const id = btn.getAttribute('data-id');
        const url = new URL(location.href); url.hash = `note-${id}`;
        if (navigator.share) {
          try { await navigator.share({title:'Paste12', text:`#${id}`, url: url.toString()}); } catch {}
        } else {
          try { await navigator.clipboard.writeText(url.toString()); btn.textContent = '📋 Copiado'; setTimeout(()=>btn.textContent='🔗 Compartir',1200); } catch {}
        }
      };
    });
  }

  // ===== cargar página =====
  function parseNextFromHeaders(res) {
    const link = res.headers.get('Link') || res.headers.get('link');
    if (!link) return null;
    // formato: </api/notes?cursor_ts=...&cursor_id=...>; rel="next"
    const m = link.match(/<([^>]+)>;\s*rel="?next"?/i);
    return m ? m[1] : null;
  }
  async function fetchPage(url) {
    loading = true;
    try {
      const res = await fetch(url, {credentials:'include'});
      const j = await res.json().catch(()=>({}));
      const items = (j && j.items) ? j.items : [];
      // si no viene en body, probamos Link header
      nextURL = (j && j.next && j.next.cursor_ts && j.next.cursor_id)
        ? `/api/notes?cursor_ts=${encodeURIComponent(j.next.cursor_ts)}&cursor_id=${j.next.cursor_id}`
        : parseNextFromHeaders(res);
      // render
      const frag = document.createElement('div');
      frag.innerHTML = items.map(renderItem).join('');
      feed.appendChild(frag);
      upsertHandlers(frag);
      // botón "cargar más"
      ensureLoadMore();
    } catch(e) {
      console.warn('fetchPage failed', e);
      ensureLoadMore(true);
    } finally {
      loading = false;
    }
  }
  function ensureLoadMore(error=false) {
    let btn = $('#mini-load-more');
    if (btn) btn.remove();
    if (!nextURL) return;
    btn = document.createElement('button');
    btn.id = 'mini-load-more';
    btn.textContent = error ? 'Reintentar' : 'Cargar más';
    btn.style.cssText = 'display:block;margin:12px auto;padding:.6rem 1rem;border-radius:12px;border:1px solid #e5e7eb;background:#fff;';
    btn.onclick = () => { if (!loading) fetchPage(BASE + nextURL); };
    feed.appendChild(btn);
  }

  // ===== publicar =====
  async function publish() {
    const status = $('[data-mini-status]') || document.createElement('span');
    const text = (txt && txt.value || '').trim();
    const hours = (hoursSel && parseInt(hoursSel.value,10)) || 12;
    if (!text) { if (status) status.textContent = 'Escribí algo.'; return; }
    // Intento JSON y fallback a form-urlencoded
    try {
      let res = await fetch(`${BASE}/api/notes`, {
        method: 'POST',
        credentials: 'include',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({text, hours})
      });
      if (!res.ok) throw new Error('json fail');
      var j = await res.json();
    } catch(_) {
      const body = new URLSearchParams({text, hours: String(hours)}).toString();
      const res2 = await fetch(`${BASE}/api/notes`, {
        method: 'POST',
        credentials: 'include',
        headers: {'Content-Type':'application/x-www-form-urlencoded'},
        body
      });
      if (!res2.ok) {
        const t = await res2.text();
        if (status) status.textContent = 'No se pudo enviar nota.';
        throw new Error('publish failed: ' + t);
      }
      var j = await res2.json();
    }
    // Prepend nueva nota
    const item = (j && j.item) ? j.item : j;
    if (item && item.id) {
      const first = document.createElement('div');
      first.innerHTML = renderItem(item);
      feed.prepend(first.firstElementChild);
      upsertHandlers(feed);
      if (txt) txt.value = '';
      if (status) status.textContent = '¡Publicada!';
      setTimeout(()=>{ if (status) status.textContent = ''; }, 1500);
    }
  }
  if (publishBtn) publishBtn.addEventListener('click', e => { e.preventDefault(); publish(); });

  // ===== boot =====
  fetchPage('/api/notes?limit=10');
})();
</script>
<!-- MINI-CLIENT v2 END -->
"""

# 4) insertar justo antes de </body>; si no hay </body>, al final
out = norm
idx = re.search(r'</body\s*>', norm, flags=re.I)
if idx:
    pos = idx.start()
    out = norm[:pos] + "\n" + JS + "\n" + norm[pos:]
else:
    out = norm + "\n" + JS + "\n"

bak = target.with_suffix(target.suffix + ".mini_client_v2.bak")
if not bak.exists():
    shutil.copyfile(target, bak)

target.write_text(out, encoding="utf-8")
print(f"patched: mini-cliente v2 insertado en {target} | backup={bak.name}")
