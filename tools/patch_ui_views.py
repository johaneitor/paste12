#!/usr/bin/env python3
import re, sys, pathlib, shutil, datetime

HTML = pathlib.Path("backend/static/index.html")
if not HTML.exists():
    print("ERROR: backend/static/index.html no existe"); sys.exit(1)

raw = HTML.read_text(encoding="utf-8")

# 0) Si ya está el marcador, no hacemos nada.
if "view-observer:start" in raw:
    print("ya estaba parchado (view-observer presente)")
    sys.exit(0)

# 1) Backup
ts = datetime.datetime.utcnow().strftime("%Y%m%d_%H%M%S")
bakdir = pathlib.Path("tools/backups/backend/static"); bakdir.mkdir(parents=True, exist_ok=True)
bak = bakdir / f"index.html.{ts}.bak"
shutil.copy2(HTML, bak)

s = raw

# 2) Asegurar que cada nota tenga data-id y un span .views (si falta, reemplazamos renderItem())
pat_render = re.compile(r'function\s+renderItem\s*\(\s*it\s*\)\s*\{.*?\}\s*', re.S)
want_render = r"""
function renderItem(it){
  const text = it.text || it.content || it.summary || '';
  return `
    <article class="note" data-id="${it.id}">
      <div>${text ? text.replace(/</g,'&lt;') : '(sin texto)'}</div>
      <div class="meta">
        #${it.id ?? '-'} · ${fmtDate(it.timestamp)}
        · <button class="act like">❤ ${it.likes ?? 0}</button>
        · <span class="views">👁️ ${it.views ?? 0}</span>
        · <button class="act more">⋯</button>
      </div>
      <div class="menu hidden">
        <button class="share">Compartir</button>
        <button class="report">Reportar 🚩</button>
      </div>
    </article>
  `;
}
""".strip()

if pat_render.search(s):
    # Reemplazo conservador: sólo si falta data-id o .views
    need_replace = ('data-id="${it.id}"' not in s) or ('.views' not in s)
    if need_replace:
        s = pat_render.sub(want_render + "\n", s)
else:
    # Si no encontramos la función, la inyectamos antes del primer "function renderList" o al final del <script>
    s = re.sub(r'(function\s+renderList\s*\()', want_render + "\n\n\\1", s)

# 3) Inyectar el view-observer (buscamos el cierre </script> o </body>)
observer_js = r"""
/* view-observer:start */
(function(){
  try{
    const seen = new Set();
    // Cargar vistos previos (limitar a 500 ids para no crecer sin control)
    try {
      (JSON.parse(localStorage.getItem('seen_views')||'[]')||[]).slice(-500).forEach(id=>seen.add(String(id)));
    } catch(_) {}
    const save = () => {
      try { localStorage.setItem('seen_views', JSON.stringify([...seen].slice(-500))); } catch(_){}
    };

    // Fingerprint simple para backend (opcional)
    const fp = (navigator.userAgent||'') + '|' + (navigator.language||'') + '|' +
               (Intl.DateTimeFormat().resolvedOptions().timeZone||'');

    const obs = new IntersectionObserver((entries)=>{
      entries.forEach(async (entry)=>{
        if (!entry.isIntersecting) return;
        const el = entry.target;
        const id = (el.getAttribute('data-id')||'').trim();
        if (!id || seen.has(id)) { obs.unobserve(el); return; }
        seen.add(id); save();
        try{
          const res = await fetch(api('notes/'+id+'/view'), {method:'POST', headers:{'X-FP': fp}});
          let j = {};
          try { j = await res.json(); } catch(_){}
          if (res.ok && (j.ok || j.id)) {
            const span = el.querySelector('.views');
            if (span) {
              const m = /(\d+)/.exec(span.textContent||'0'); const cur = m?parseInt(m[1],10):0;
              span.textContent = '👁️ ' + (cur+1);
            }
          }
        }catch(_){}
        obs.unobserve(el);
      });
    }, {root: null, threshold: 0.6});

    function attach(){
      document.querySelectorAll('article.note[data-id]').forEach(el=>{
        if (!el.dataset.observing) { el.dataset.observing = '1'; obs.observe(el); }
      });
    }
    const list = document.getElementById('list');
    if (list) {
      const mo = new MutationObserver(attach);
      mo.observe(list, {childList:true});
    }
    // Primera pasada
    attach();
  }catch(_){}
})();
/* view-observer:end */
""".strip()

# Insertar antes de </body>, o como último <script>
if '</body>' in s:
    s = s.replace('</body>', f'<script>\n{observer_js}\n</script>\n</body>')
elif '</html>' in s:
    s = s.replace('</html>', f'<script>\n{observer_js}\n</script>\n</html>')
else:
    s += f'\n<script>\n{observer_js}\n</script>\n'

HTML.write_text(s, encoding="utf-8")
print(f"patched OK. backup: {bak}")
