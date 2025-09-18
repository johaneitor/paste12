#!/usr/bin/env python3
import sys, re, pathlib, shutil

CANDIDATES = [
    pathlib.Path("backend/static/index.html"),
    pathlib.Path("public/index.html"),
    pathlib.Path("frontend/index.html"),
    pathlib.Path("index.html"),
]

BANNER = """\
<!-- deploy-stamp-banner -->
<script>
(function(){
  var elId = "deploy-stamp-banner";
  if (document.getElementById(elId)) return; // idempotente

  function h(tag, attrs, text){ var e=document.createElement(tag);
    if(attrs){ for(var k in attrs){ e.setAttribute(k, attrs[k]); } }
    if(text){ e.textContent=text; } return e; }

  function show(stamp){
    var bar = h("div", {id: elId, style:
      "position:fixed;left:16px;right:16px;bottom:16px;padding:12px 16px;"+
      "background:#111;color:#fff;border-radius:12px;box-shadow:0 6px 20px rgba(0,0,0,.25);"+
      "font:14px/1.4 system-ui, -apple-system, Segoe UI, Roboto, sans-serif;"+
      "display:flex;gap:12px;align-items:center;z-index:99999;"});
    var msg = h("div", null, "Nueva versión disponible. Actualiza para ver los últimos cambios.");
    var btn = h("button", {style:
      "margin-left:auto;background:#00b894;color:#fff;border:0;border-radius:8px;padding:8px 12px;cursor:pointer;"+
      "font-weight:600;"}, "Actualizar");
    btn.onclick = function(){
      try { localStorage.setItem("deployStamp", stamp || ""); } catch(_) {}
      location.reload(true);
    };
    var x = h("button",{style:"margin-left:8px;background:#333;color:#fff;border:0;border-radius:8px;padding:8px 12px;cursor:pointer;"},"Cerrar");
    x.onclick=function(){ bar.remove(); };
    bar.appendChild(msg); bar.appendChild(btn); bar.appendChild(x);
    document.body.appendChild(bar);
  }

  function same(a,b){return String(a||"").trim()===String(b||"").trim();}

  fetch("/api/deploy-stamp",{credentials:"include"}).then(function(r){return r.json();}).then(function(j){
    var cur = (j && (j.stamp||j.commit||"")) || "";
    var prev = ""; try { prev = localStorage.getItem("deployStamp")||""; } catch(_) {}
    if(!same(cur, prev) && cur){ show(cur); }
  }).catch(function(_e){ /* silencioso */ });
})();
</script>
"""

def patch(path: pathlib.Path) -> bool:
    if not path.exists(): return False
    html = path.read_text(encoding="utf-8")
    if "deploy-stamp-banner" in html:
        print(f"OK: banner ya presente en {path}"); return True
    m = re.search(r"</body\\s*>", html, re.I)
    if m:
        out = html[:m.start()] + "\\n" + BANNER + "\\n" + html[m.start():]
    else:
        out = html + "\\n" + BANNER + "\\n"
    bak = path.with_suffix(path.suffix + ".bak")
    if not bak.exists(): shutil.copyfile(path, bak)
    path.write_text(out, encoding="utf-8")
    print(f"patched: banner agregado en {path} | backup={bak.name}")
    return True

done = False
for p in CANDIDATES:
    if patch(p): done = True
if not done:
    print("✗ no encontré index.html en rutas conocidas. Crea uno en ./public/index.html y vuelve a correr.")
    sys.exit(1)
print("✓ listo")
