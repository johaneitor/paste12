#!/usr/bin/env python3
import pathlib, re, sys, shutil
IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("ERROR: backend/static/index.html no existe"); sys.exit(2)
html = IDX.read_text(encoding="utf-8")
bak = IDX.with_suffix(".html.bak")

SCRIPT_ID = "ttl-cap-js"
BLOCK = f"""<!-- TTL-CAP-BEGIN -->
<script id="{SCRIPT_ID}">
(function(){
  if (window.__ttlCapInstalled) return; window.__ttlCapInstalled = 1;
  var MAX = parseInt(document.documentElement.getAttribute('data-max-ttl-hours')||'2160',10) || 2160;
  function clampField(inp){
    if(!inp) return;
    var v = parseInt(inp.value||'12',10); if(isNaN(v)) v = 12;
    if(v<1) v = 1; if(v>MAX) v = MAX; inp.value = v;
    try{
      var ph = inp.getAttribute('placeholder')||'';
      if (ph.indexOf('(máx.') === -1) inp.setAttribute('placeholder',(ph?ph+' ':'')+'(máx. '+MAX+')');
      if (!inp.max) inp.setAttribute('max', String(MAX));
      if (!inp.min) inp.setAttribute('min', '1');
    }catch(_){}
  }
  function findHours(root){
    return root.querySelector('[name="hours"], #hours, #ttl_hours');
  }
  document.addEventListener('submit', function(e){
    try{ clampField(findHours(e.target || document)); }catch(_){}
  }, true);
  // al cargar
  try{ clampField(findHours(document)); }catch(_){}
})();
</script>
<!-- TTL-CAP-END -->
"""
changed = False

# Quitar bloque previo por marcas (idempotente)
html2 = re.sub(r"<!-- TTL-CAP-BEGIN -->.*?<!-- TTL-CAP-END -->", "", html, flags=re.S)
if html2 != html:
    html = html2
    changed = True

# Inyectar una sola vez (antes de </body> si existe)
if SCRIPT_ID not in html:
    if re.search(r"</body>", html, flags=re.I):
        html = re.sub(r"</body>", BLOCK + "\n</body>", html, count=1, flags=re.I)
    else:
        html += "\n" + BLOCK
    changed = True

if not changed:
    print("OK: TTL UI cap ya presente"); sys.exit(0)

if not bak.exists(): shutil.copyfile(IDX, bak)
IDX.write_text(html, encoding="utf-8")
print("patched: TTL UI cap inyectado (idempotente)")
