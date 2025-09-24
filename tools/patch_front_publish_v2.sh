#!/usr/bin/env bash
set -euo pipefail

HTML="frontend/index.html"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }
ts="$(date -u +%Y%m%d-%H%M%SZ)"
cp -f "$HTML" "${HTML}.${ts}.pubfix.bak"
echo "[front] Backup: ${HTML}.${ts}.pubfix.bak"

python - <<'PY'
import io,re
p="frontend/index.html"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

# 1) Normalizar handler publish() (JSON primero y fallback a FORM)
pattern=r'function\s+publishNote\s*\([\s\S]*?\}\s*\}'
code="""
function publishNote() {
  const text = (document.querySelector('#note')||{}).value || '';
  const hoursSel = document.querySelector('#hours');
  const hours = hoursSel ? (parseInt(hoursSel.value||'12',10)||12) : 12;
  const err = document.querySelector('#err') || (function(){
    const e=document.createElement('div'); e.id='err'; e.style.margin='8px 0'; e.style.color='#b00';
    (document.querySelector('form')||document.body).prepend(e); return e;
  })();

  const endpoint = '/api/notes';
  const common = {mode:'cors', cache:'no-store'};

  const tryJSON = fetch(endpoint, {
    ...common,
    method:'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({ text, hours })
  });

  function show(e, status, body){
    err.textContent = (status?`Error HTTP ${status}`:'') + (body?` — ${body}`:'');
  }

  return tryJSON.then(async r=>{
    if(r.ok){ err.textContent=''; location.reload(); return; }
    // fallback a form
    const fd = new FormData(); fd.set('text', text); fd.set('hours', String(hours));
    const r2 = await fetch(endpoint, { ...common, method:'POST', body: fd });
    if(r2.ok){ err.textContent=''; location.reload(); return; }
    show(null, r.status||r2.status, (await r.text().catch(()=>'')) || (await r2.text().catch(()=>'')));
  }).catch(async e=>{
    show(e, 0, (e&&e.message)||'falló la red');
  });
}
"""
if re.search(pattern,s):
    s=re.sub(pattern,code,s,flags=re.S)
elif "publishNote()" in s:
    # insertar función
    s=s.replace("publishNote()", "publishNote()")
    s += "\n<script>\n"+code+"\n</script>\n"
else:
    s += "\n<script>\n"+code+"\n</script>\n"

# 2) Botón publicar que llame a publishNote()
s=re.sub(r'onclick\s*=\s*"[^\"]*publishNote\(\)[^\"]*"', 'onclick="publishNote()"', s)

# 3) Eliminar service worker viejo
s=re.sub(r'.*serviceWorker.*\n','',s)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[front] publish y SW parcheados")
else:
    print("[front] Ya estaba OK")
PY

echo "Listo."
