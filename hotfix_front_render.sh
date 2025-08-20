#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# Backups mínimos
[ -f frontend/index.html ] && cp -p frontend/index.html frontend/index.html.bak.$ts || true

# 1) Crear/actualizar hotfix.js (no pisa app.js; corre sólo si la lista está vacía)
cat > frontend/js/hotfix.js <<'JS'
(function(){
  function fmtCountdown(expISO){
    if(!expISO) return "";
    const now = Date.now();
    const ms  = Date.parse(expISO) - now;
    const s = Math.max(0, Math.floor(ms/1000));
    const d = Math.floor(s/86400), r1 = s - d*86400;
    const h = Math.floor(r1/3600), r2 = r1 - h*3600;
    const m = Math.floor(r2/60), x = r2 - m*60;
    if (d>0) return `${d}d ${h}h`;
    if (h>0) return `${h}h ${m}m`;
    if (m>0) return `${m}m ${x}s`;
    return `${x}s`;
  }

  function startCountdownLoop(){
    function tick(){
      document.querySelectorAll('.countdown[data-expires-at]').forEach(el=>{
        const iso = el.getAttribute('data-expires-at');
        el.textContent = fmtCountdown(iso);
        const ttl = (Date.parse(iso) - Date.now())/1000;
        el.classList.toggle('danger', ttl<=3600);
        el.classList.toggle('warn', ttl<=86400 && ttl>3600);
        el.title = `Expira: ${new Date(iso).toLocaleString()}`;
      });
    }
    tick(); setInterval(tick, 1000);
  }

  async function api(path, opts){
    const r = await fetch(path, Object.assign({headers:{'Content-Type':'application/json'}}, opts||{}));
    if(!r.ok) throw new Error(`HTTP ${r.status}`);
    return r.json();
  }

  function buildCard(n){
    const art = document.createElement('article');
    art.className = 'note-card';
    art.setAttribute('data-note', n.id);
    art.innerHTML = `
      <div class="note-body">${(n.text||"").replace(/</g,"&lt;")}</div>
      <div class="note-meta">
        <span class="countdown" data-expires-at="${n.expires_at||""}"></span>
        <div class="spacer"></div>
        <button class="btn-like" data-id="${n.id}" aria-label="Me gusta">❤️ <b>${n.likes||0}</b></button>
        <span class="views" title="Vistas">👁️ ${(n.views||0)}</span>
      </div>
    `;
    const btn = art.querySelector('.btn-like');
    btn.addEventListener('click', async (ev)=>{
      ev.preventDefault();
      try{
        const j = await api(`/api/notes/${n.id}/like`, {method:'POST'});
        btn.querySelector('b').textContent = j.likes ?? (parseInt(btn.querySelector('b').textContent||'0',10)+1);
      }catch(e){ console.warn('like failed', e); }
    });
    return art;
  }

  async function loadAndRender(page=1){
    try{
      const data = await api(`/api/notes?page=${page}`);
      const items = Array.isArray(data.items)? data.items : (Array.isArray(data.notes)? data.notes : []);
      const list = document.getElementById('notes') || document.querySelector('[data-notes], #list, main');
      if(!list) return;
      list.innerHTML = '';
      items.forEach(n => list.appendChild(buildCard(n)));
      if(items.length>0) startCountdownLoop();
      console.log(`[hotfix] renderizadas ${items.length} notas`);
    }catch(e){
      console.warn('[hotfix] fallo cargando notas', e);
    }
  }

  function wireForm(){
    const form = document.getElementById('form') || document.querySelector('form[data-note-form]');
    if(!form) return;
    form.addEventListener('submit', async (ev)=>{
      try{
        const t = (form.querySelector('textarea, [name="text"]')||{}).value?.trim() || '';
        if(!t) return;
        ev.preventDefault();
        const hoursSel = form.querySelector('[name="duration"], [name="hours"]');
        let body = { text: t };
        if (hoursSel) {
          const v = hoursSel.value || hoursSel.getAttribute('value') || '';
          body.duration = v; // el backend acepta "12h","1d","7d"
        }
        await api('/api/notes', {method:'POST', body: JSON.stringify(body)});
        (form.querySelector('textarea, [name="text"]')||{}).value = '';
        await loadAndRender(1);
      }catch(e){ console.warn('[hotfix] submit fallo', e); }
    }, {once:true});
  }

  // Sólo corre si la lista está vacía después de que cargó la página (no pisa tu app.js)
  document.addEventListener('DOMContentLoaded', ()=>{
    const list = document.getElementById('notes') || document.querySelector('[data-notes], #list, main');
    setTimeout(()=>{
      if (!list) return;
      const empty = !list.children || list.children.length===0;
      if (empty) {
        console.log('[hotfix] lista vacía: aplicando renderer alternativo');
        wireForm();
        loadAndRender(1);
      } else {
        console.log('[hotfix] lista no vacía: no se aplica');
      }
    }, 400);
  });
})();
JS

# 2) Asegurar que hotfix.js se carga al final del body con un cache-buster
if ! grep -q 'js/hotfix.js' frontend/index.html; then
  # Inserta antes de </body>
  perl -0777 -pe 's#</body>#  <script src="js/hotfix.js?v='"$ts"'"></script>\n</body>#i' -i frontend/index.html
fi

# 3) CSS mínimo por si las tarjetas no tienen estilos visibles
if ! grep -q '.note-card' frontend/css/styles.css 2>/dev/null; then
  cat >> frontend/css/styles.css <<'CSS'

/* --- hotfix tarjetas --- */
.note-card{
  background:#0b1020; border:1px solid #243055; border-radius:14px;
  padding:14px; margin:10px 0; box-shadow:0 4px 18px rgba(0,0,0,.25);
}
.note-body{ white-space:pre-wrap; line-height:1.4; font-size:16px; color:#e9ecff; }
.note-meta{ display:flex; align-items:center; gap:10px; margin-top:8px; font-size:12px; color:#b9c1ff; }
.note-meta .spacer{ flex:1 }
.btn-like{ border:0; background:#1f2a4a; color:#fff; padding:6px 10px; border-radius:10px; cursor:pointer }
.btn-like:hover{ filter:brightness(1.1) }
.countdown{ background:#223361; padding:2px 8px; border-radius:999px; }
.countdown.warn{ background:#f59e0b; color:#1a0f00; }
.countdown.danger{ background:#ef4444; color:#fff; }
CSS
fi

# 4) Commit y push (forza redeploy en Render)
git add frontend/index.html frontend/js/hotfix.js frontend/css/styles.css
git commit -m "hotfix(frontend): render seguro de notas si app.js no pinta; like + countdown + estilos mínimos" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "✅ Hotfix aplicado y subido. Tras el deploy, abre tu sitio con /?v=$(date +%s) para saltar caché."
