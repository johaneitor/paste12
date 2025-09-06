#!/usr/bin/env python3
import re, pathlib, sys, shutil
IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("✗ backend/static/index.html no existe"); sys.exit(2)
html = IDX.read_text(encoding="utf-8")
bak = IDX.with_suffix(".html.bak")
changed = False

# 1) Hook JS idempotente justo antes de </body>
snippet = r"""
<script id="max-pages-guard">
(function(){
  if (window.__MAX_PAGES_GUARD__) return; window.__MAX_PAGES_GUARD__=true;
  const MAX_PAGES = 200;
  let pageCount = 1;
  // Exponer contador por si la UI ya tiene su propio loader
  window.PASTE12_MAX_PAGES = MAX_PAGES;
  window.PASTE12_pageCount = () => pageCount;

  // Interceptar clicks en botones "más" comunes
  function guardMore(evt){
    if (pageCount >= MAX_PAGES) {
      evt && evt.preventDefault();
      console.warn("Max pages reached:", MAX_PAGES);
      const b = evt && evt.currentTarget;
      if (b) { b.setAttribute('disabled',''); b.textContent = "Límite de páginas (200)"; }
      return false;
    }
    pageCount++;
    return true;
  }
  // Delegación: botones con clase .act.more (heurística presente en la UI)
  document.addEventListener('click', function(e){
    const el = e.target.closest && e.target.closest('.act.more');
    if (!el) return;
    if (!guardMore(e)) return;
  }, true);

  // Interceptar fetch de “siguiente página” si el frontend usa fetch()
  const _fetch = window.fetch;
  window.fetch = function(url, init){
    try{
      if (typeof url === 'string' && /\/api\/notes\?/.test(url)) {
        if (pageCount >= MAX_PAGES) {
          return Promise.resolve(new Response(JSON.stringify({ok:false,error:"max_pages_reached"}),{
            status: 429, headers: {'Content-Type':'application/json'}
          }));
        }
        pageCount++;
      }
    }catch(_){}
    return _fetch.apply(this, arguments);
  };
})();
</script>
""".strip()

if "id=\"max-pages-guard\"" not in html:
    html = re.sub(r"</body>", snippet + "\n</body>", html, flags=re.I)
    changed = True

if not changed:
    print("OK: guard UI de 200 páginas ya presente"); sys.exit(0)

if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(html, encoding="utf-8")
print("patched: UI max pages guard (200) — backup creado")
