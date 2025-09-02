import re, sys, pathlib
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")

# localizamos la definición de _serve_index_html()
m = re.search(r"def\s+_serve_index_html\(\):\n", s)
if not m:
    print("no encontré _serve_index_html()")
    sys.exit(1)

inject = r'''
    # Si FORCE_BRIDGE_INDEX está activo, devolvemos un index pastel inline
    if (os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")):
        _html_pastel = """<!doctype html>
<html lang="es"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Notas</title>
<style>
  :root{
    --bg:#fffdfc; --fg:#24323f; --muted:#6b7a86;
    --teal:#8fd3d0; /* turquesa pastel (token para check) */
    --peach:#ffb38a; --pink:#f9a3c7; --card:#ffffff; --ring: rgba(36,50,63,.15);
  }
  *{box-sizing:border-box} body{margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:linear-gradient(180deg,var(--bg),#fff);color:var(--fg)}
  header{position:sticky;top:0;z-index:10;background:linear-gradient(90deg,var(--teal),var(--peach),var(--pink));color:#17323a;padding:16px 20px;box-shadow:0 2px 12px var(--ring)}
  h1{margin:0;font-size:clamp(20px,3.2vw,28px)} .container{max-width:860px;margin:20px auto;padding:0 16px}
  .card{background:var(--card);border:1px solid #eee;border-radius:16px;padding:14px;box-shadow:0 4px 20px var(--ring)}
  textarea,input[type="text"]{width:100%;padding:12px 14px;border-radius:12px;border:1px solid #e6eef2;outline:none;font-size:16px;background:#fff;color:var(--fg)}
  textarea:focus,input:focus{border-color:#b5dfe0;box-shadow:0 0 0 4px rgba(143,211,208,.25)}
  .row{display:flex;gap:10px;margin-top:10px}
  .btn{appearance:none;border:0;border-radius:12px;padding:12px 16px;font-weight:600;cursor:pointer;background:linear-gradient(90deg,var(--teal),var(--peach));color:#14333a;box-shadow:0 6px 18px var(--ring)}
  .list{margin-top:18px;display:grid;gap:12px}
  .note{background:#fff;border:1px solid #eef2f5;border-radius:14px;padding:12px 14px}
  .note .meta{color:var(--muted);font-size:12px;margin-top:6px}
  .menu{margin-top:8px} .hidden{display:none} .error{color:#9a2b2b;margin-top:8px} .ok{color:#0a6f57;margin-top:8px}
  footer{margin:40px 0 28px;color:var(--muted);text-align:center;font-size:14px}
  footer a{color:#0b7c8a;text-decoration:underline}
</style>
</head>
<body>
  <header><h1>Notas</h1></header>
  <main class="container">
    <section class="card">
      <label for="text" style="font-weight:600;">Escribe tu nota…</label>
      <textarea id="text" rows="3" placeholder="Escribe tu nota…"></textarea>
      <div class="row">
        <input id="ttl" type="text" inputmode="numeric" pattern="[0-9]*" placeholder="Horas (12 por defecto)">
        <button id="send" class="btn">Publicar</button>
      </div>
      <div id="msg" class="hidden"></div>
    </section>
    <section class="list" id="list"></section>
    <footer>
      <span>Usamos cookies/localStorage (p.ej., para contar vistas).</span><br/>
      <a href="/terms">Términos y Condiciones</a> · <a href="/privacy">Política de Privacidad</a>
    </footer>
  </main>
<script>
const $ = (s)=>document.querySelector(s);
const api = (p)=> (p.startsWith('/')?p:'/api/'+p);
function fmtDate(iso){ try{ return new Date(iso).toLocaleString(); }catch(_){ return iso } }
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
    </article>`;
}
function renderList(items){ $('#list').innerHTML = (items||[]).map(renderItem).join('') || '<div class="note">No hay notas aún.</div>'; }
async function load(){ try{ const r=await fetch(api('notes')); const j=await r.json(); renderList(Array.isArray(j)?j:(j.items||[])); }catch(e){ $('#list').innerHTML='<div class="note">Error cargando notas.</div>'; } }
async function publish(){
  const text = $('#text').value.trim(); const ttlh = parseInt($('#ttl').value.trim()||'');
  if(!text){ flash('Escribí algo antes de publicar', false); return }
  try{
    const body = { text }; if(Number.isFinite(ttlh) && ttlh>0) body.ttl_hours = ttlh;
    const r = await fetch(api('notes'), { method:'POST', headers:{'Content-Type':'application/json','Accept':'application/json'}, body: JSON.stringify(body)});
    const j = await r.json(); if(!r.ok || !j.ok) throw new Error(j.error||'error');
    $('#text').value=''; $('#ttl').value=''; flash('Publicado ✅', true);
    const it = j.item || null; if(it){ const cur=$('#list').innerHTML; $('#list').innerHTML = renderItem(it)+cur; } else { load(); }
  }catch(e){ flash('No se pudo publicar', false); }
}
function flash(msg, ok){ const el=$('#msg'); el.className = ok?'ok':'error'; el.textContent = msg; setTimeout(()=>{ el.className='hidden'; el.textContent=''; }, 2000); }
$('#send').addEventListener('click', publish);
$('#text').addEventListener('keydown', (e)=>{ if(e.key==='Enter' && (e.ctrlKey||e.metaKey)){ publish(); }});
window.addEventListener('DOMContentLoaded', ()=>{ const u = new URL(location.href); const pre=u.searchParams.get('text'); if(pre){ $('#text').value = pre; } load(); });
</script>
</body></html>"""
        status, headers, body = _html(200, _html_pastel)
        headers = list(headers) + [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")]
        return status, headers, body
'''
# Insertamos el bloque justo después del encabezado de la función
s2 = s[:m.end()] + inject + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("patched: pastel inline en _serve_index_html() con no-store cuando FORCE_BRIDGE_INDEX=1")
