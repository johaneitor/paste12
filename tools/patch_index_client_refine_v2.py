#!/usr/bin/env python3
import re, sys, pathlib, shutil

CANDS = [pathlib.Path(p) for p in (
    "backend/static/index.html",
    "frontend/index.html",
    "index.html",
)]
targets = [p for p in CANDS if p.exists()]
if not targets:
    print("✗ No encontré index.html (backend/static/, frontend/, o raíz)."); sys.exit(2)

SCRIPT = r'''
<script id="p12-client-template" data-ver="2">
(()=>{const $$=(s,sc)=>Array.from((sc||document).querySelectorAll(s));const $=(s,sc)=> (sc||document).querySelector(s);

// --- 0) Bloquear SW + quitar banners de “Nueva versión disponible” ---
(async function killSW(){
  try{
    if("serviceWorker" in navigator){
      // Evitar nuevos registros
      try{navigator.serviceWorker.register = ()=>Promise.resolve({});}catch{}
      // Desregistrar existentes
      const regs = await navigator.serviceWorker.getRegistrations();
      for(const r of regs){ try{ await r.unregister(); }catch{} }
    }
  }catch{}
})();
function killUpdateBanners(){
  const BAD_TXT = [/nueva versión disponible/i, /actualiza para ver los últimos cambios/i, /update available/i];
  const nodes = $$('body *');
  for(const el of nodes){
    const t = (el.textContent||"").trim();
    if(!t) continue;
    if(BAD_TXT.some(rx=>rx.test(t))){
      // Quita el contenedor completo si es un toast/banner
      try{ el.closest('[role="alert"], .toast, .snackbar, .banner')?.remove(); }catch{}
      // O al menos ese nodo
      try{ el.remove(); }catch{}
    }
  }
}
killUpdateBanners();
new MutationObserver(()=>killUpdateBanners()).observe(document.documentElement,{childList:true,subtree:true});

// --- 1) Heurísticas para detectar items de nota y el feed correcto ---
function looksLikeNote(el){
  if(!el || !el.textContent) return false;
  const t = el.textContent;
  if(!/#\s?\d{1,10}\b/.test(t)) return false;       // meta tipo “#253”
  // Evita héroes: si contiene H1/H2 grande y no hay #id cerca, descartamos
  const hasHero = el.querySelector('h1,h2');
  if(hasHero && !el.querySelector('*:not(h1):not(h2)')) return false;
  return true;
}
function findFeed(){
  // Tomamos todos los contenedores que tengan ≥2 hijos que parezcan nota,
  // y nos quedamos con el de mayor “score”.
  let best=null, bestScore=0;
  const all = $$('main, [data-feed], #notes, .notes, #list, #root, body, .container, .content, .wrapper, .page');
  for(const cand of all){
    const kids = Array.from(cand.children||[]);
    let score=0;
    for(const ch of kids){ if(looksLikeNote(ch)) score++; }
    if(score>bestScore){ best=cand; bestScore=score; }
  }
  // Si no se encontró, fallback al body
  return best || document.body;
}
const feed = findFeed();
if(!feed){ console.warn("[p12] no feed; abort"); return; }

// --- 2) Elegir template real: primer hijo del feed que parezca nota ---
let templateCard = Array.from(feed.children||[]).find(looksLikeNote);
if(templateCard){ templateCard = templateCard.cloneNode(true); }
const seen = new Set();
// Marcar los ya renderizados para no duplicar
(Array.from(feed.querySelectorAll('[data-note-id]'))).forEach(el=>{
  const id = Number(el.getAttribute('data-note-id')); if(Number.isFinite(id)) seen.add(id);
});
(Array.from(feed.children||[])).forEach(el=>{
  const m=/#\s?(\d{1,10})\b/.exec(el.textContent||''); if(m){ const id=Number(m[1]); if(Number.isFinite(id)) seen.add(id); }
});

function findNth(el, sels){ for(const s of sels){ const n=el.querySelector(s); if(n) return n; } return null; }
function fillCard(card, it){
  try{ card.setAttribute('data-note-id', it.id); }catch{}
  // Texto
  const textNode = findNth(card, ['[data-text]', '.text', '.content', 'p', 'div']);
  if(textNode) textNode.textContent = it.text ?? it.title ?? '';
  // Meta
  const meta = findNth(card, ['[data-meta]', '.meta', '.foot', 'small', '.muted']);
  if(meta){
    const parts=[`#${it.id}`];
    const L = (it.likes ?? 0);
    parts.push(String(L));
    if(it.views != null) parts.push(String(it.views));
    meta.textContent = meta.textContent?.replace(/#\s?\d{1,10}.*/,'') || '';
    meta.textContent = `#${it.id} · ${new Date(it.timestamp||Date.now()).toLocaleString()} · ${L} `;
  }
  // Acciones (fallback si el template no trae)
  let bar = findNth(card, ['.p12-actions', '.actions', '.toolbar']);
  if(!bar){ bar = document.createElement('div'); bar.className='p12-actions';
    bar.style.cssText='display:flex;gap:8px;margin-top:10px;align-items:center;flex-wrap:wrap'; card.append(bar);
  }
  // LIKE
  let likeBtn = Array.from(card.querySelectorAll('button,a')).find(b=>/❤️|like/i.test((b.textContent||'')));
  if(!likeBtn){ likeBtn=document.createElement('button'); likeBtn.type='button'; likeBtn.textContent=`❤️ ${it.likes??0}`;
    likeBtn.style.cssText='padding:.3rem .6rem;border:1px solid #eee;border-radius:8px;background:#fff;cursor:pointer'; bar.prepend(likeBtn); }
  likeBtn.addEventListener('click', async (ev)=>{
    ev.preventDefault(); likeBtn.disabled=true;
    try{ const r=await fetch(`/api/notes/${it.id}/like`,{method:'POST',credentials:'include'});
         const d=await r.json().catch(()=>({})); const L=d?.likes ?? (it.likes??0)+1; likeBtn.textContent=`❤️ ${L}`;
    }catch{} finally{ likeBtn.disabled=false; }
  }, {once:false});
  // REPORT
  let repBtn = Array.from(card.querySelectorAll('button,a')).find(b=>/🚩|report/i.test((b.textContent||'')));
  if(!repBtn){ repBtn=document.createElement('button'); repBtn.type='button'; repBtn.textContent='🚩 Reportar';
    repBtn.style.cssText='padding:.3rem .6rem;border:1px solid #eee;border-radius:8px;background:#fff;cursor:pointer'; bar.append(repBtn); }
  repBtn.addEventListener('click', async (ev)=>{
    ev.preventDefault(); if(!confirm('¿Reportar esta nota?')) return; repBtn.disabled=true;
    try{ const r=await fetch(`/api/notes/${it.id}/report`,{method:'POST',credentials:'include'});
         const d=await r.json().catch(()=>({})); if(d?.removed){ card.replaceChildren(Object.assign(document.createElement('div'),{textContent:'Nota ocultada por reportes.',style:'color:#b00'})); }
         else if(d?.reports!=null){ repBtn.textContent=`🚩 Reportar (${d.reports})`; }
    }catch{} finally{ repBtn.disabled=false; }
  }, {once:false});
  // SHARE
  let shBtn = Array.from(card.querySelectorAll('button,a')).find(b=>/🔗|share|compart/i.test((b.textContent||'')));
  if(!shBtn){ shBtn=document.createElement('button'); shBtn.type='button'; shBtn.textContent='🔗 Compartir';
    shBtn.style.cssText='padding:.3rem .6rem;border:1px solid #eee;border-radius:8px;background:#fff;cursor:pointer'; bar.append(shBtn); }
  shBtn.addEventListener('click', async (ev)=>{
    ev.preventDefault(); const url=`${location.origin}/api/notes/${it.id}`; const text=it.text||`Nota #${it.id}`;
    try{ if(navigator.share){ await navigator.share({title:`Nota #${it.id}`, text, url}); }
         else{ await navigator.clipboard.writeText(url); const o=shBtn.textContent; shBtn.textContent='✅ Copiado'; setTimeout(()=>shBtn.textContent=o,1400); } }catch{}
  }, {once:false});
  return card;
}

function renderItems(items,{append=true}={}){
  for(const it of (items||[])){
    const id = Number(it?.id); if(!Number.isFinite(id) || seen.has(id)) continue;
    seen.add(id);
    let card = templateCard ? templateCard.cloneNode(true) : document.createElement('div');
    card = fillCard(card, it);
    append ? feed.append(card) : feed.prepend(card);
  }
}

const moreBtn = (()=>{ let b=document.getElementById('p12-more');
  if(!b){ b=document.createElement('button'); b.id='p12-more'; b.type='button'; b.textContent='Cargar más';
    b.style.cssText='margin:12px 0; padding:.6rem 1rem; border-radius:10px; border:1px solid #ddd; background:#fff; cursor:pointer; display:none';
    feed.after(b);
  } return b;
})();

let nextUrl=null;
async function fetchPage(url){
  const res=await fetch(url,{credentials:"include"}); const data=await res.json().catch(()=>({ok:false,error:"json"}));
  if(!res.ok){ console.warn("HTTP",res.status,data?.error); return; }
  renderItems(data.items||[], {append:true});
  // Next por Link:
  nextUrl=null; const link=res.headers.get("Link")||res.headers.get("link");
  if(link){ const m=/<([^>]+)>;\s*rel="?next"?/i.exec(link); if(m) nextUrl=m[1]; }
  // Next por X-Next-Cursor:
  if(!nextUrl){
    try{ const xn=JSON.parse(res.headers.get("X-Next-Cursor")||"null");
         if(xn&&xn.cursor_ts&&xn.cursor_id){ nextUrl=`/api/notes?cursor_ts=${encodeURIComponent(xn.cursor_ts)}&cursor_id=${xn.cursor_id}`; }
    }catch{}
  }
  moreBtn.style.display = nextUrl ? "" : "none";
}

function pickTextarea(){ return document.querySelector('textarea[name=text], #text, textarea'); }
function pickTTL(){ return document.querySelector('select[name=hours], select[name=ttl], input[name=ttl_hours], select'); }
async function publish(ev){
  if(ev&&ev.preventDefault) ev.preventDefault();
  const ta=pickTextarea(); const ttlSel=pickTTL();
  const text=(ta?.value||"").trim(); if(!text){ alert("Escribe algo primero"); return; }
  const payload={text}; if(ttlSel){ const v=Number(ttlSel.value||ttlSel.getAttribute("value")||12); if(Number.isFinite(v)&&v>0) payload.ttl_hours=v; }
  const res=await fetch("/api/notes",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(payload),credentials:"include"});
  const data=await res.json().catch(()=>({ok:false,error:"json"}));
  if(!res.ok || data?.ok===false){ alert("Error publicando: "+(data?.error||("HTTP "+res.status))); return; }
  try{ ta.value=""; }catch{}
  const it = data.item || {id:data.id,text:payload.text,likes:data.likes||0,timestamp:Date.now()};
  let card = templateCard ? templateCard.cloneNode(true) : document.createElement('div');
  card = fillCard(card, it);
  feed.prepend(card);
}

function bindPublish(){
  const form = document.querySelector("form");
  if(form) form.addEventListener("submit", e=>publish(e));
  const btn = Array.from(document.querySelectorAll("button, input[type=submit]"))
    .find(b=>/publicar|enviar/i.test((b.textContent||b.value||"")));
  if(btn && !btn.form) btn.addEventListener("click", e=>publish(e));
}

function start(){
  bindPublish();
  // Sólo añadimos páginas siguientes; mantenemos lo renderizado por el server
  fetchPage("/api/notes?limit=10").catch(()=>{});
}
document.addEventListener("DOMContentLoaded", start);
moreBtn.addEventListener("click", ()=>{ if(nextUrl) fetchPage(nextUrl).catch(()=>{}); });

})();
</script>
'''.strip()+"\n"

def inject(html: str) -> str:
    # Reemplaza si ya existe nuestro cliente (p12-client-template)
    if re.search(r'(<script[^>]*id="p12-client-template"[^>]*>)(.*?)(</script>)', html, flags=re.I|re.S):
        return re.sub(r'(<script[^>]*id="p12-client-template"[^>]*>)(.*?)(</script>)',
                      lambda m: SCRIPT, html, flags=re.I|re.S, count=1)
    # Si existe el viejo p12-min-client, lo reemplazamos
    if re.search(r'(<script[^>]*id="p12-min-client"[^>]*>)(.*?)(</script>)', html, flags=re.I|re.S):
        return re.sub(r'(<script[^>]*id="p12-min-client"[^>]*>)(.*?)(</script>)',
                      lambda m: SCRIPT, html, flags=re.I|re.S, count=1)
    # Insertar antes de </body>
    if re.search(r'</body\s*>', html, flags=re.I):
        return re.sub(r'</body\s*>', lambda m: SCRIPT + m.group(0), html, flags=re.I, count=1)
    return html.rstrip() + "\n" + SCRIPT

def patch_one(p: pathlib.Path):
    html = p.read_text(encoding="utf-8")
    out  = inject(html)
    if out == html:
        print(f"OK: {p} ya tenía el cliente (sin cambios)")
        return
    bak = p.with_suffix(".html.client_refine_v2.bak")
    if not bak.exists():
        shutil.copyfile(p, bak)
    p.write_text(out, encoding="utf-8")
    print(f"patched: cliente v2 (feed real + quita banner SW) en {p} | backup={bak.name}")

for t in targets:
    patch_one(t)
print("OK.")
