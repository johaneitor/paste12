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
<script id="p12-client-template" data-ver="1">
(()=>{const $=s=>document.querySelector(s),$$=s=>Array.from(document.querySelectorAll(s));
async function unregisterSW(){try{if("serviceWorker"in navigator){(await navigator.serviceWorker.getRegistrations()).forEach(r=>r.unregister())}}catch{}}

const host=(location.origin||"").replace(/\/$/,"");
const feed = document.querySelector('[data-feed], #notes, .notes, #list, main, #root, body');
if(!feed){console.warn("[p12] no feed root; abort"); return;}

let templateCard=null;
let seen=new Set();
function scanExisting(){
  // busca IDs ya visibles (heursticas: data-note-id, o "#123" en texto)
  $$('[data-note-id]').forEach(el=>{const v=Number(el.getAttribute('data-note-id')); if(Number.isFinite(v)) seen.add(v)});
  $$('*').forEach(el=>{
    const s=(el.textContent||"").trim();
    const m=/#\s?(\d{1,10})\b/.exec(s);
    if(m){const id=Number(m[1]); if(Number.isFinite(id)) seen.add(id);}
  });
}
function guessTemplate(){
  // candidata: primer hijo “card-like”: mucho texto / botones
  const kids=Array.from(feed.children).filter(e=>!/^(SCRIPT|STYLE)$/.test(e.tagName));
  let cand = kids.find(e=> (e.querySelector('button,a') || (e.textContent||'').trim().length>10) );
  if(!cand && kids.length) cand=kids[0];
  if(cand){ templateCard=cand.cloneNode(true); }
}
scanExisting(); guessTemplate();

function findNth(el, sels){ for(const s of sels){ const n=el.querySelector(s); if(n) return n; } return null; }

function fillCard(card, it){
  try{ card.setAttribute('data-note-id', it.id); }catch{}
  // Texto principal
  const textNode = findNth(card, ['[data-text]', '.text', '.content', 'p', 'div']);
  if(textNode){ textNode.textContent = it.text ?? it.title ?? ''; }
  // Metadatos (#id, exp, likes)
  const meta = findNth(card, ['[data-meta]', '.meta', '.foot', '.muted', 'small']);
  if(meta){
    const parts = [`#${it.id}`];
    const L = (it.likes ?? 0);
    parts.push(`likes:${L}`);
    if(it.expires_at) parts.push(`exp:${it.expires_at}`);
    meta.textContent = parts.join(' · ');
  }
  // Botón like
  let likeBtn = Array.from(card.querySelectorAll('button,a')).find(b=>/❤️|like/i.test((b.textContent||'')));
  if(!likeBtn){
    likeBtn = document.createElement('button');
    likeBtn.type='button';
    likeBtn.textContent=`❤️ ${it.likes??0}`;
    likeBtn.style.cssText='padding:.3rem .6rem;border:1px solid #eee;border-radius:8px;background:#fff;cursor:pointer;margin-right:6px';
    const bar = findNth(card, ['.p12-actions', '.actions', '.toolbar']) || card.appendChild(document.createElement('div'));
    bar.className = bar.className || 'p12-actions';
    bar.style.cssText = bar.style.cssText || 'display:flex;gap:8px;margin-top:10px;align-items:center;flex-wrap:wrap';
    bar.prepend(likeBtn);
  }
  likeBtn.addEventListener('click', async (ev)=>{
    ev.preventDefault(); likeBtn.disabled=true;
    try{
      const r=await fetch(`/api/notes/${it.id}/like`,{method:'POST',credentials:'include'});
      const d=await r.json().catch(()=>({}));
      const L = (d && (d.likes??it.likes)) ?? ((Number((likeBtn.textContent||'').replace(/\D+/g,''))||0)+1);
      likeBtn.textContent=`❤️ ${L}`;
    }catch{}finally{likeBtn.disabled=false;}
  }, {once:false});

  // Botón report
  let reportBtn = Array.from(card.querySelectorAll('button,a')).find(b=>/🚩|report/i.test((b.textContent||'')));
  if(!reportBtn){
    reportBtn = document.createElement('button');
    reportBtn.type='button';
    reportBtn.textContent="🚩 Reportar";
    reportBtn.style.cssText='padding:.3rem .6rem;border:1px solid #eee;border-radius:8px;background:#fff;cursor:pointer;margin-right:6px';
    const bar = findNth(card, ['.p12-actions', '.actions', '.toolbar']) || card.appendChild(document.createElement('div'));
    bar.className = bar.className || 'p12-actions';
    bar.style.cssText = bar.style.cssText || 'display:flex;gap:8px;margin-top:10px;align-items:center;flex-wrap:wrap';
    bar.append(reportBtn);
  }
  reportBtn.addEventListener('click', async (ev)=>{
    ev.preventDefault();
    if(!confirm('¿Reportar esta nota?')) return;
    reportBtn.disabled=true;
    try{
      const r=await fetch(`/api/notes/${it.id}/report`,{method:'POST',credentials:'include'});
      const d=await r.json().catch(()=>({}));
      if(d && d.removed){
        card.replaceChildren(Object.assign(document.createElement('div'),{textContent:'Nota ocultada por reportes.', style:'color:#b00'}));
      }else{
        const rep = d?.reports ?? 0;
        reportBtn.textContent = `🚩 Reportar (${rep})`;
      }
    }catch{}finally{reportBtn.disabled=false;}
  }, {once:false});

  // Botón share
  let shareBtn = Array.from(card.querySelectorAll('button,a')).find(b=>/🔗|share|compart/i.test((b.textContent||'')));
  if(!shareBtn){
    shareBtn = document.createElement('button');
    shareBtn.type='button';
    shareBtn.textContent="🔗 Compartir";
    shareBtn.style.cssText='padding:.3rem .6rem;border:1px solid #eee;border-radius:8px;background:#fff;cursor:pointer';
    const bar = findNth(card, ['.p12-actions', '.actions', '.toolbar']) || card.appendChild(document.createElement('div'));
    bar.className = bar.className || 'p12-actions';
    bar.style.cssText = bar.style.cssText || 'display:flex;gap:8px;margin-top:10px;align-items:center;flex-wrap:wrap';
    bar.append(shareBtn);
  }
  shareBtn.addEventListener('click', async (ev)=>{
    ev.preventDefault();
    const url = `${location.origin}/api/notes/${it.id}`;
    const text = it.text || `Nota #${it.id}`;
    try{
      if(navigator.share){ await navigator.share({title:`Nota #${it.id}`, text, url}); }
      else{
        await navigator.clipboard.writeText(url);
        const old=shareBtn.textContent; shareBtn.textContent="✅ Copiado";
        setTimeout(()=>shareBtn.textContent=old,1400);
      }
    }catch{}
  }, {once:false});

  return card;
}

function renderItems(items, {append=true}={}){
  for(const it of (items||[])){
    if(seen.has(Number(it.id))) continue;
    seen.add(Number(it.id));
    let card = templateCard ? templateCard.cloneNode(true) : document.createElement('div');
    card = fillCard(card, it);
    if(append) feed.append(card); else feed.prepend(card);
  }
}

const moreBtn=(()=>{ let b=document.getElementById('p12-more');
  if(!b){ b=document.createElement('button'); b.id='p12-more'; b.type='button'; b.textContent='Cargar más';
    b.style.cssText='margin:12px 0; padding:.6rem 1rem; border-radius:10px; border:1px solid #ddd; background:#fff; cursor:pointer; display:none';
    feed.after(b);
  } return b; })();

let nextUrl=null;
async function fetchPage(url){
  const res=await fetch(url,{credentials:"include"});
  const data=await res.json().catch(()=>({ok:false,error:"json"}));
  if(!res.ok){throw new Error(data?.error||("HTTP "+res.status));}
  renderItems(data.items||[], {append:true});
  // next
  nextUrl=null; const link=res.headers.get("Link")||res.headers.get("link");
  if(link){const m=/<([^>]+)>;\s*rel="?next"?/i.exec(link); if(m) nextUrl=m[1];}
  if(!nextUrl){
    try{const xn=JSON.parse(res.headers.get("X-Next-Cursor")||"null");
        if(xn&&xn.cursor_ts&&xn.cursor_id){nextUrl=`/api/notes?cursor_ts=${encodeURIComponent(xn.cursor_ts)}&cursor_id=${xn.cursor_id}`}}
    catch{}
  }
  moreBtn.style.display=nextUrl?"":"none";
}

function pickTextarea(){return document.querySelector('textarea[name=text], #text, textarea[placeholder], textarea');}
function pickTTL(){return document.querySelector('select[name=hours], select[name=ttl], input[name=ttl_hours], select');}

async function publish(ev){
  if(ev&&ev.preventDefault)ev.preventDefault();
  const ta=pickTextarea(); const ttlSel=pickTTL();
  const text=(ta?.value||"").trim(); if(!text){alert("Escribe algo primero"); return;}
  const payload={text}; if(ttlSel){const v=Number(ttlSel.value||ttlSel.getAttribute("value")||12); if(Number.isFinite(v)&&v>0) payload.ttl_hours=v;}
  const res=await fetch("/api/notes",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(payload),credentials:"include"});
  const data=await res.json().catch(()=>({ok:false,error:"json"}));
  if(!res.ok || data?.ok===false){throw new Error(data?.error||("HTTP "+res.status));}
  try{ta.value="";}catch{}
  const it=data.item||{id:data.id,text:payload.text,likes:data.likes,expires_at:data.expires_at};
  let card = templateCard ? templateCard.cloneNode(true) : document.createElement('div');
  card = fillCard(card, it);
  feed.prepend(card);
}

function bindPublish(){
  const form=document.querySelector("form");
  if(form){form.addEventListener("submit",e=>publish(e).catch(err=>alert("Error publicando: "+err.message)));}
  const btn=Array.from(document.querySelectorAll("button, input[type=submit]")).find(b=>/publicar|enviar/i.test((b.textContent||b.value||"")));
  if(btn && !btn.form){btn.addEventListener("click",e=>publish(e).catch(err=>alert("Error publicando: "+err.message)));}
}

function start(){
  unregisterSW(); bindPublish();
  // No reemplazamos lo ya renderizado; sólo anexamos siguientes páginas
  fetchPage("/api/notes?limit=10").catch(e=>console.warn("Error cargando más notas:", e.message));
}
moreBtn.addEventListener("click",()=>{ if(nextUrl) fetchPage(nextUrl).catch(()=>{}); });
if(document.readyState==="loading"){document.addEventListener("DOMContentLoaded",start);}else{start();}
})();
</script>
'''.strip()+"\n"

def inject(html: str) -> str:
    # Reemplaza si ya existe nuestro script
    m = re.search(r'(<script[^>]*id="p12-client-template"[^>]*>)(.*?)(</script>)', html, flags=re.I|re.S)
    if m:
        def repl(_m): return m.group(1) + "\n" + SCRIPT.split(">",1)[1]
        return re.sub(r'(<script[^>]*id="p12-client-template"[^>]*>)(.*?)(</script>)', repl, html, flags=re.I|re.S, count=1)
    # Si existe el viejo p12-min-client, lo reemplazamos para evitar doble render
    m2 = re.search(r'(<script[^>]*id="p12-min-client"[^>]*>)(.*?)(</script>)', html, flags=re.I|re.S)
    if m2:
        def repl2(_m): return SCRIPT
        return re.sub(r'(<script[^>]*id="p12-min-client"[^>]*>)(.*?)(</script>)', repl2, html, flags=re.I|re.S, count=1)
    # Inserta antes de </body> preservando cierre (usar función para evitar escapes en replacement)
    if re.search(r'</body\s*>', html, flags=re.I):
        return re.sub(r'</body\s*>', lambda m: SCRIPT + m.group(0), html, flags=re.I, count=1)
    # fallback: al final
    return html.rstrip() + "\n" + SCRIPT

def patch_one(p: pathlib.Path):
    html = p.read_text(encoding="utf-8")
    out  = inject(html)
    if out == html:
        print(f"OK: {p} ya tenía el cliente (sin cambios)")
        return
    bak = p.with_suffix(".html.client_template.bak")
    if not bak.exists():
        shutil.copyfile(p, bak)
    p.write_text(out, encoding="utf-8")
    print(f"patched: cliente template-driven en {p} | backup={bak.name}")

for t in targets:
    patch_one(t)
print("OK.")
