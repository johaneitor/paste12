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
SCRIPT = f"""
<!-- p12 debug bootstrap -->
<script id="{TAG_ID}">
(() => {{
  try {{
    // Sólo activo con ?debug=1
    const p = new URLSearchParams(location.search);
    if (!p.has('debug')) return;

    // 1) mata service workers viejos
    if ('serviceWorker' in navigator) {{
      navigator.serviceWorker.getRegistrations()
        .then(rs => rs.forEach(r => r.unregister()))
        .catch(()=>{});
    }}

    // 2) UI mínima de diagnóstico
    const box = document.createElement('div');
    box.style.cssText = 'position:fixed;right:12px;bottom:12px;padding:10px 12px;background:#111;color:#fff;font:12px/1.4 system-ui;border-radius:10px;box-shadow:0 4px 14px rgba(0,0,0,.3);max-width:42ch;z-index:99999';
    box.innerHTML = '<b>p12 debug</b><div id="p12d"></div>';
    document.body.appendChild(box);
    const log = (k,v) => {{
      const el = document.createElement('div');
      el.textContent = k + ': ' + v;
      box.querySelector('#p12d').appendChild(el);
    }};

    // 3) checks rápidos
    fetch('/api/health').then(r => log('health', r.status)).catch(()=>log('health', 'ERR'));

    fetch('/api/deploy-stamp')
      .then(r => r.json()).then(j => {{
        const c = (j.deploy?.commit || j.commit || '').slice(0,7);
        const d = (j.deploy?.date || j.date || '');
        log('deploy', c + ' @ ' + d);
      }}).catch(()=>log('deploy', 'ERR'));

    fetch('/api/notes?limit=3', {{headers:{{'Accept':'application/json'}}}})
      .then(r => r.json()).then(j => {{
        const n = Array.isArray(j) ? j.length : (j.items?.length ?? 0);
        log('notes', n + ' items');
      }}).catch(()=>log('notes', 'ERR'));

    // 4) hint visual
    box.title = 'Este panel sólo aparece con ?debug=1';
  }} catch (e) {{}}
}})();
</script>
"""

for W in CAND:
    html = W.read_text(encoding="utf-8")
    if TAG_ID in html:
        print(f"OK: {W} ya tiene el bootstrap (no se cambia)")
        continue

    # Insertar antes de </body> o al final
    if re.search(r'</body\s*>', html, flags=re.I):
        new_html = re.sub(r'</body\s*>', SCRIPT + '\n</body>', html, flags=re.I)
    else:
        new_html = html + "\n" + SCRIPT + "\n"

    bak = W.with_suffix(".debug_bootstrap.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(new_html, encoding="utf-8")
    print(f"patched: debug bootstrap inyectado en {W} | backup={bak.name}")
