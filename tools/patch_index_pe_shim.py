#!/usr/bin/env python3
import pathlib, sys, shutil, re

cands = [p for p in (
    "backend/static/index.html",
    "frontend/index.html",
    "index.html",
) if pathlib.Path(p).exists()]

if not cands:
    print("✗ no encontré index.html (backend/static, frontend o raíz)")
    sys.exit(2)

TAG_ID = "pe-shim-p12"
SCRIPT = r"""
<!-- p12 PE shim (solo ?pe=1) -->
<script id="pe-shim-p12">
(function(){
  try {
    var p = new URLSearchParams(location.search);
    if (!p.has('pe')) return;

    var root = document.createElement('div');
    root.style.cssText = 'margin:16px;padding:12px;border:1px dashed #aaa;border-radius:10px;background:#fafafa';
    root.innerHTML = '<b>PE shim</b> — listado mínimo de /api/notes';
    var list = document.createElement('div');
    list.style.cssText = 'margin-top:8px;font:14px system-ui';
    root.appendChild(list);
    (document.body || document.documentElement).appendChild(root);

    fetch('/api/notes?limit=5',{headers:{'Accept':'application/json'}})
      .then(function(r){ return r.json(); })
      .then(function(j){
        var items = (j && j.items) || [];
        if (!items.length) { list.textContent = '(sin items)'; return; }
        var ul = document.createElement('ul');
        items.forEach(function(it){
          var li = document.createElement('li');
          li.textContent = '#'+it.id+': '+(it.text || it.summary || '(sin texto)');
          ul.appendChild(li);
        });
        list.appendChild(ul);
      })
      .catch(function(){ list.textContent = 'error cargando'; });
  } catch (_e) {}
})();
</script>
"""

for path in cands:
    W = pathlib.Path(path)
    html = W.read_text(encoding="utf-8")

    if TAG_ID in html:
        print(f"OK: {W} ya tiene PE shim (no se cambia)")
        continue

    if re.search(r'</body\s*>', html, flags=re.I):
        new_html = re.sub(r'</body\s*>', SCRIPT + '\n</body>', html, flags=re.I)
    else:
        new_html = html + "\n" + SCRIPT + "\n"

    bak = W.with_suffix(".pe_shim.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(new_html, encoding="utf-8")
    print(f"patched: PE shim inyectado en {W} | backup={bak.name}")
