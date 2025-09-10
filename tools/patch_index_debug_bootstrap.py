#!/usr/bin/env python3
import pathlib, sys, shutil, re

CAND = [pathlib.Path(p) for p in (
    "backend/static/index.html",
    "frontend/index.html",
    "index.html",
) if pathlib.Path(p).exists()]

if not CAND:
    print("✗ no encontré index.html en backend/static, frontend o raíz")
    sys.exit(2)

TAG_ID = "debug-bootstrap-p12"

SCRIPT_TEMPLATE = r"""
<!-- p12 debug bootstrap -->
<script id="__TAG__">
(function () {
  try {
    var p = new URLSearchParams(location.search);
    if (!p.has('debug')) return;

    // 1) Desregistrar SW antiguos (no rompe si no hay)
    if ('serviceWorker' in navigator) {
      try {
        navigator.serviceWorker.getRegistrations().then(function(rs){
          rs.forEach(function(r){ r.unregister(); });
        });
      } catch (_e) {}
    }

    // 2) UI mínima de diagnóstico
    function addBox() {
      var box = document.createElement('div');
      box.style.cssText = 'position:fixed;right:12px;bottom:12px;padding:10px 12px;background:#111;color:#fff;font:12px/1.4 system-ui;border-radius:10px;box-shadow:0 4px 14px rgba(0,0,0,.3);max-width:42ch;z-index:99999';
      box.innerHTML = '<b>p12 debug</b><div id="p12d"></div>';
      document.body.appendChild(box);
      return box.querySelector('#p12d');
    }
    function log(k,v){
      var el = document.createElement('div');
      el.textContent = k + ': ' + v;
      root.appendChild(el);
    }

    var root = addBox();

    // 3) checks rápidos
    fetch('/api/health').then(function(r){ log('health', r.status); }).catch(function(){ log('health','ERR'); });

    fetch('/api/deploy-stamp')
      .then(function(r){ return r.json(); })
      .then(function(j){
        var c = ((j && j.deploy && j.deploy.commit) || j.commit || '').slice(0,7);
        var d = ((j && j.deploy && j.deploy.date)   || j.date   || '');
        log('deploy', c + ' @ ' + d);
      })
      .catch(function(){ log('deploy','ERR'); });

    fetch('/api/notes?limit=3', {headers:{'Accept':'application/json'}})
      .then(function(r){ return r.json(); })
      .then(function(j){
        var n = (Array.isArray(j) ? j.length : ((j && j.items && j.items.length) || 0));
        log('notes', n + ' items');
      })
      .catch(function(){ log('notes','ERR'); });

  } catch (_e) {}
})();
</script>
"""

for W in CAND:
    html = W.read_text(encoding="utf-8")
    if TAG_ID in html:
        print(f"OK: {W} ya tiene el bootstrap (no se cambia)")
        continue

    script = SCRIPT_TEMPLATE.replace("__TAG__", TAG_ID)

    if re.search(r'</body\s*>', html, flags=re.I):
        new_html = re.sub(r'</body\s*>', script + '\n</body>', html, flags=re.I)
    else:
        new_html = html + "\n" + script + "\n"

    bak = W.with_suffix(".debug_bootstrap.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(new_html, encoding="utf-8")
    print(f"patched: debug bootstrap inyectado en {W} | backup={bak.name}")
