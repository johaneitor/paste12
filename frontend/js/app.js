class NotesApp {
  constructor() {
    this.main   = document.querySelector("main") || document.body;
    this.list   = document.getElementById("notes");
    this.pagNav = document.getElementById("pagination");
    this.form   = document.getElementById("form") || document.querySelector("form");
    this.btn    = document.getElementById("publish");

    this.page  = 1;
    this.pages = 1;
    this.seen  = new Set();

    // token persistente para limitar likes/reportes por persona
    this.token = localStorage.getItem("p12_token");
    if (!this.token) {
      try { this.token = crypto.randomUUID(); }
      catch { this.token = Math.random().toString(36).slice(2)+Date.now().toString(36); }
      localStorage.setItem("p12_token", this.token);
    }

    this.bind();
    this.load(1);
  }

  bind(){
    this.form?.addEventListener("submit",(e)=>{ e.preventDefault(); return false; });
    this.btn?.addEventListener("click",()=> this.publish());

    // Clicks dentro de la lista (like, menú, reportar, compartir)
    this.list?.addEventListener("click",(e)=>{
      const likeBtn = e.target.closest(".like-btn");
      const menuBtn = e.target.closest(".menu-btn");
      const report  = e.target.closest(".menu-item.report");
      const share   = e.target.closest(".menu-item.share");
      const li = e.target.closest("li[data-id]");

      if (likeBtn && li) return this.like(li.dataset.id);
      if (menuBtn && li) return this.toggleMenu(li, menuBtn);
      if (report && li)  return this.report(li.dataset.id, li);
      if (share && li)   return this.share(li.dataset.id, li.querySelector(".note-text")?.innerText || "");
    });

    // clic fuera: cerrar menús
    document.addEventListener("click",(e)=>{
      if (!e.target.closest(".note-actions")) {
        document.querySelectorAll(".note .menu").forEach(m=>m.setAttribute("hidden",""));
        document.querySelectorAll(".note .menu-btn[aria-expanded=true]").forEach(b=>b.setAttribute("aria-expanded","false"));
      }
    });
  }

  async publish(){
    const tx = this.form.querySelector("#text");
    const dl = this.form.querySelector("#duration");
    const text = (tx?.value || "").trim();
    if (!text) return;

    let hours = parseInt(dl?.value ?? "168", 10);
    if (!Number.isFinite(hours) || hours<1 || hours>24*28) hours=168;

    const r = await fetch("/api/notes", {
      method:"POST",
      headers: { "Content-Type":"application/json" },
      body: JSON.stringify({ text, expire_hours: hours })
    });
    if (!r.ok){ alert("No se pudo publicar"); return; }
    tx.value = "";
    await this.load(1);
    window.scrollTo({ top: (this.list?.offsetTop||0)-10, behavior:"smooth" });
  }

  async like(id){
    const r = await fetch(`/api/notes/${id}/like`, { method:"POST", headers:{ "X-Client-Token": this.token }});
    const j = await r.json().catch(()=>({}));
    const el = this.list.querySelector(`li[data-id="${id}"] .likes-count`);
    if (el && typeof j.likes === "number") el.textContent = j.likes;
  }

  async report(id, li){
    const menu = li.querySelector(".menu");
    menu?.setAttribute("hidden","");

    const r = await fetch(`/api/notes/${id}/report`, { method:"POST", headers:{ "X-Client-Token": this.token }});
    const j = await r.json().catch(()=>({}));

    if (j.deleted) {
      li.remove();
      return;
    }
    // feedback visual: deshabilitar reportar
    const reportItem = li.querySelector(".menu-item.report");
    if (reportItem) {
      reportItem.textContent = "🚩 Reportado";
      reportItem.setAttribute("disabled","true");
      reportItem.classList.add("disabled");
    }
  }

  async share(id, text){
    const url = `${location.origin}/?n=${id}`;
    const payload = { title: "Nota #"+id, text: text.slice(0,140), url };
    if (navigator.share) {
      try { await navigator.share(payload); return; } catch(e){}
    }
    // Fallback: copiar al portapapeles y abrir opciones rápidas (X/WhatsApp)
    try{ await navigator.clipboard.writeText(`${text}\n${url}`); alert("✅ Enlace copiado"); }catch(e){}
    const tw = "https://twitter.com/intent/tweet?text="+encodeURIComponent(`${text}\n${url}`);
    const wa = "https://wa.me/?text="+encodeURIComponent(`${text}\n${url}`);
    window.open(tw,"_blank"); setTimeout(()=>window.open(wa,"_blank"), 400);
  }

  toggleMenu(li, btn){
    const menu = li.querySelector(".menu");
    const open = !menu.hasAttribute("hidden");
    document.querySelectorAll(".note .menu").forEach(m=>m.setAttribute("hidden",""));
    document.querySelectorAll(".note .menu-btn").forEach(b=>b.setAttribute("aria-expanded","false"));
    if (!open) { menu.removeAttribute("hidden"); btn.setAttribute("aria-expanded","true"); }
  }

  async load(page=1){
    const r = await fetch(`/api/notes?page=${page}`);
    const j = await r.json().catch(()=>({notes:[], total_pages:1}));
    this.page  = page;
    this.pages = j.total_pages || 1;
    this.render(j.notes || []);
  }

  render(items){
    /* in-feed ads */ 
    const isLocal = ['localhost','127.0.0.1'].some(h=>location.hostname.startsWith(h));
    this.list.innerHTML = items.map(n=>`
      <li class="note" data-id="${n.id}">
        <div class="note-actions">
          <button class="menu-btn" aria-haspopup="true" aria-expanded="false" title="Opciones">⋮</button>
          <div class="menu" hidden>
            <button type="button" class="menu-item report">🚩 Reportar</button>
            <button type="button" class="menu-item share">🔗 Compartir</button>
          </div>
        </div>
        <div class="note-text">${this.escape(n.text)}</div>
        <div class="note-meta">
          <button type="button" class="like-btn">❤️ Like</button>
          <span class="counters">👍 <span class="likes-count">${n.likes||0}</span> ·
          👁️ <span class="views-count">${n.views||0}</span></span>
        </div>
      </li>`).join("");
    if (!isLocal) {
      // Inserta slot después de cada 6ª nota
      const lis = Array.from(this.list.querySelectorAll('li.note'));
      lis.forEach((li,i)=>{
        if ((i+1)%6===0) {
          const ad = document.createElement('div');
          ad.className = 'ad-slot infeed';
          ad.innerHTML = `
          <ins class="adsbygoogle" style="display:block"
               data-ad-client=""
               data-ad-slot=""
               data-ad-format="fluid"
               data-ad-layout-key="-fg+5n+6t-1j-5u"
               data-full-width-responsive="true"></ins>
          <script>(adsbygoogle=window.adsbygoogle||[]).push({});</script>`;
          li.after(ad);
        }
      });
    }

    // paginación
    this.pagNav.innerHTML = "";
    for(let p=1;p<=this.pages;p++){
      const b=document.createElement("button");
      b.textContent=p;
      if(p===this.page) b.disabled=true;
      b.addEventListener("click",()=>this.load(p));
      this.pagNav.appendChild(b);
    }

    // vistas (una vez por render)
    this.list.querySelectorAll("li[data-id]").forEach(li=>{
      const id = li.dataset.id;
      if(this.seen.has(id)) return;
      this.seen.add(id);
      fetch(`/api/notes/${id}/view`, { method:"POST", headers:{ "X-Client-Token": this.token }})
        .then(r=>r.json()).then(j=>{
          const el = li.querySelector(".views-count");
          if (el && j && typeof j.views === "number") el.textContent = j.views;
        }).catch(()=>{});
    });
  }

  escape(s){ const d=document.createElement("div"); d.textContent=s; return d.innerHTML.replace(/\n/g,"<br>"); }
}
document.addEventListener("DOMContentLoaded", ()=> new NotesApp());


// ====== GENERADOR DE HISTORIAS (1080x1920) ======
function wrapText(ctx, text, x, y, maxWidth, lineHeight) {
  const words = text.split(/\s+/); let line = ""; const lines = [];
  for (let n=0;n<words.length;n++){
    const test = line + words[n] + " ";
    if (ctx.measureText(test).width > maxWidth && n>0) { lines.push(line.trim()); line = words[n] + " "; }
    else line = test;
  }
  lines.push(line.trim());
  lines.forEach((ln,i)=>ctx.fillText(ln, x, y + i*lineHeight));
  return y + (lines.length-1)*lineHeight;
}

function drawRoundedRect(ctx, x, y, w, h, r){
  ctx.beginPath();
  ctx.moveTo(x+r, y);
  ctx.arcTo(x+w, y, x+w, y+h, r);
  ctx.arcTo(x+w, y+h, x, y+h, r);
  ctx.arcTo(x, y+h, x, y, r);
  ctx.arcTo(x, y, x+w, y, r);
  ctx.closePath();
}

async function createStoryImage(text, photoFile=null){
  const c = document.getElementById('story-canvas'); const ctx = c.getContext('2d');
  // Fondo: foto (cover) o degradado
  if (photoFile){
    const img = await new Promise(res=>{
      const i=new Image(); i.onload=()=>res(i); i.src=URL.createObjectURL(photoFile);
    });
    // cover
    const scale = Math.max(c.width/img.width, c.height/img.height);
    const w = img.width*scale, h = img.height*scale;
    const x = (c.width - w)/2, y = (c.height - h)/2;
    ctx.drawImage(img, x, y, w, h);
  } else {
    const g = ctx.createLinearGradient(0,0,0,c.height);
    g.addColorStop(0, "#111827");
    g.addColorStop(1, "#0ea5a4");
    ctx.fillStyle = g; ctx.fillRect(0,0,c.width,c.height);
  }
  // Panel de nota
  const box = {x:90, y:340, w:900, h:1240, r:36};
  ctx.fillStyle = "rgba(255,255,255,0.86)";
  drawRoundedRect(ctx, box.x, box.y, box.w, box.h, box.r); ctx.fill();

  // Texto
  ctx.fillStyle = "#0f172a";
  ctx.font = "48px system-ui, -apple-system, Segoe UI, Roboto, Arial";
  ctx.textBaseline = "top";
  const maxW = box.w - 80;
  wrapText(ctx, text.trim().slice(0, 600), box.x+40, box.y+40, maxW, 62);

  // Marca
  ctx.font = "bold 64px system-ui, -apple-system, Segoe UI, Roboto, Arial";
  ctx.fillStyle = "#f472b6";
  ctx.fillText("Paste12", 90, 230);

  // Watermark
  ctx.font = "28px system-ui, -apple-system, Segoe UI, Roboto, Arial";
  ctx.fillStyle = "rgba(17,24,39,.85)";
  ctx.fillText("paste12", 90, 1860);

  return await new Promise(res=> c.toBlob(b=>res(b), "image/png"));
}

async function shareOrDownload(blob){
  const file = new File([blob], "paste12_story.png", {type:"image/png"});
  if (navigator.canShare && navigator.canShare({files:[file]})) {
    await navigator.share({files:[file], title:"Paste12", text:""});
  } else {
    // descarga
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = "paste12_story.png"; document.body.appendChild(a);
    a.click(); a.remove(); URL.revokeObjectURL(url);
    alert("📸 Imagen generada. Si no se descargó automáticamente, mantén pulsado para guardar.");
  }
}

// UI handlers
(function(){
  const btn = document.getElementById("story-make");
  const file = document.getElementById("story-photo");
  if (!btn) return;
  // tap: genera con o sin foto (si ya hay seleccionada)
  btn.addEventListener("click", async ()=>{
    const txt = document.getElementById("text")?.value || "";
    if (!txt.trim()){ alert("Escribe una nota primero 😉"); return; }
    const blob = await createStoryImage(txt, file.files[0] || null);
    await shareOrDownload(blob);
  });
  // long-press: abrir selector de foto
  let t; btn.addEventListener("touchstart", ()=>{ t=setTimeout(()=>file.click(),600); }, {passive:true});
  ["touchend","touchcancel","mouseleave"].forEach(ev=>btn.addEventListener(ev, ()=>clearTimeout(t)));
})();


// === Share nativo: sin popups ===
async function shareNative(text, url){
  try{
    if(navigator.share){
      await navigator.share({title:'Paste12', text, url});
      return;
    }
  }catch(e){}
  try{
    await navigator.clipboard.writeText(`${text}\n${url}`);
    showToast('🔗 Enlace copiado');
  }catch(e){
    showToast('🔗 Copia manual: ' + url);
  }
}
function showToast(msg){
  const t=document.createElement('div');
  t.textContent=msg;
  t.style.cssText='position:fixed;left:50%;bottom:24px;transform:translateX(-50%);background:rgba(0,0,0,.8);color:#fff;padding:10px 14px;border-radius:12px;z-index:9999;font-size:14px';
  document.body.appendChild(t); setTimeout(()=>t.remove(),1400);
}
// Interceptor global: cualquier click en .share, .share-twitter o [data-share]
document.addEventListener('click', async (ev)=>{
  const el = ev.target.closest('[data-share], .share, .share-twitter');
  if(!el) return;
  ev.preventDefault(); ev.stopPropagation();
  const card = el.closest('[data-note]') || document;
  const text = (el.getAttribute('data-text') 
               || (card.querySelector('.note-text')?.textContent ?? '')).trim() || document.title;
  const url  = el.getAttribute('data-url') || location.origin;
  await shareNative(text, url);
}, true);


// === IG Story Share (1080x1920) ===
async function makeStoryCanvas(text, bgUrl){
  const W=1080, H=1920;
  const c=document.createElement('canvas'); c.width=W; c.height=H;
  const ctx=c.getContext('2d');

  // Fondo degradado
  const g=ctx.createLinearGradient(0,0,0,H);
  g.addColorStop(0,'#0f172a'); g.addColorStop(1,'#1e293b');
  ctx.fillStyle=g; ctx.fillRect(0,0,W,H);

  // Imagen de fondo opcional
  if(bgUrl){
    try{
      const img=new Image(); img.crossOrigin='anonymous'; img.src=bgUrl;
      await new Promise((res,rej)=>{ img.onload=res; img.onerror=rej; });
      const scale=Math.max(W/img.width, H/img.height);
      const w=img.width*scale, h=img.height*scale;
      ctx.globalAlpha=0.35;
      ctx.drawImage(img,(W-w)/2,(H-h)/2,w,h);
      ctx.globalAlpha=1;
    }catch(e){}
  }

  // Marco/logo simple
  ctx.strokeStyle='rgba(255,255,255,.25)'; ctx.lineWidth=12;
  ctx.strokeRect(36,36,W-72,H-72);

  // Texto
  const pad=84, maxW=W-pad*2;
  ctx.fillStyle='#fff';
  ctx.textBaseline='top';
  let fontSize=64;
  ctx.font=`700 ${fontSize}px system-ui, -apple-system, Segoe UI, Roboto, Ubuntu`;
  // Ajuste simple a ancho
  while(fontSize>34 && ctx.measureText(text).width>maxW){
    fontSize-=2; ctx.font=`700 ${fontSize}px system-ui, -apple-system, Segoe UI, Roboto, Ubuntu`;
  }
  // Partir líneas
  function wrap(t){
    const words=t.split(/\s+/); const lines=[]; let cur='';
    for(const w of words){
      const test=(cur?cur+' ':'')+w;
      if(ctx.measureText(test).width>maxW){ lines.push(cur); cur=w; }
      else cur=test;
    }
    if(cur) lines.push(cur); return lines;
  }
  const lines = wrap(text.trim().slice(0,500));
  const startY = 420 - Math.min(240, (lines.length*fontSize*1.25)/2);
  lines.forEach((ln,i)=>{
    ctx.fillText(ln, pad, startY + i*fontSize*1.25);
  });

  // Marca
  ctx.font='600 32px system-ui,-apple-system,Roboto';
  ctx.fillStyle='rgba(255,255,255,.85)';
  ctx.fillText('paste12.com', pad, H-72);
  return c;
}

async function shareIGStory(text, bgUrl){
  const canvas = await makeStoryCanvas(text, bgUrl);
  const blob = await new Promise(r=>canvas.toBlob(r,'image/png',0.95));
  const file = new File([blob], 'paste12-story.png', {type:'image/png', lastModified:Date.now()});

  // Web Share con archivos (Android Chrome/Edge soportan)
  try{
    if(navigator.canShare && navigator.canShare({files:[file]})){
      await navigator.share({files:[file], title:'Paste12', text});
      return;
    }
  }catch(e){}

  // Fallback: descarga + intenta abrir Instagram
  const url = URL.createObjectURL(blob);
  const a=document.createElement('a'); a.href=url; a.download='paste12-story.png'; a.click();
  setTimeout(()=>{ location.href='instagram://story-camera'; }, 450);
  showToast('📸 Se descargó la historia. Ábrela en Instagram → Historia.');
}

// Botón en cada nota
function injectIGButtons(){
  const list = document.querySelectorAll('[data-note]:not([data-ig])');
  list.forEach(card=>{
    const txtEl = card.querySelector('.note-text, [data-text]');
    const bar = card.querySelector('.note-actions') || card;
    const btn = document.createElement('button');
    btn.type='button';
    btn.className='btn-ig-story';
    btn.textContent='Historias IG';
    btn.title='Compartir en historias de Instagram';
    btn.addEventListener('click', async (ev)=>{
      ev.preventDefault(); ev.stopPropagation();
      const text = (txtEl?.textContent || txtEl?.getAttribute?.('data-text') || document.title).trim();
      await shareIGStory(text);
    }, {passive:false});
    bar.appendChild(btn);
    card.setAttribute('data-ig','1');
  });
}
document.addEventListener('DOMContentLoaded', ()=>{ try{ injectIGButtons(); }catch(e){} });

// También responder a clicks de elementos existentes con clases/data
document.addEventListener('click', async (ev)=>{
  const el = ev.target.closest('[data-ig-story], .share-ig');
  if(!el) return;
  ev.preventDefault(); ev.stopPropagation();
  const card = el.closest('[data-note]') || document;
  const text = (el.getAttribute('data-text') 
               || (card.querySelector('.note-text')?.textContent ?? '')).trim() || document.title;
  await shareIGStory(text);
}, true);


// ===== Countdown por nota (días/horas/min/seg) =====
function fmtTTL(s){
  s = Math.max(0, Math.floor(s));
  const d = Math.floor(s/86400);
  s -= d*86400;
  const h = Math.floor(s/3600);
  s -= h*3600;
  const m = Math.floor(s/60);
  const x = s - m*60;
  if (d>0) return `${d}d ${h}h`;
  if (h>0) return `${h}h ${m}m`;
  if (m>0) return `${m}m ${x}s`;
  return `${x}s`;
}
function startCountdownLoop(){
  function tick(){
    const now = Date.now();
    document.querySelectorAll('.countdown[data-expires-at], .countdown[data-expires-in]').forEach(el=>{
      let ttl = 0;
      if (el.hasAttribute('data-expires-in')){
        const base = parseInt(el.getAttribute('data-expires-in'),10)||0;
        const t0 = parseInt(el.getAttribute('data-epoch0'),10)||0;
        ttl = base - Math.floor((now - t0)/1000);
      } else {
        const t = Date.parse(el.getAttribute('data-expires-at'));
        ttl = Math.floor((t - now)/1000);
      }
      if (ttl <= 0){
        el.textContent = 'expirada';
        el.closest('[data-note]')?.classList.add('note-expired');
      }else{
        el.textContent = fmtTTL(ttl);
      }
    });
  }
  tick(); setInterval(tick, 1000);
}
document.addEventListener('DOMContentLoaded', startCountdownLoop);

// Hook: cuando pintes las notas, pon el span countdown si no existe
function ensureCountdownForCard(card, note){
  if(!card) return;
  let meta = card.querySelector('.note-meta');
  if(!meta){
    meta = document.createElement('div');
    meta.className = 'note-meta';
    card.appendChild(meta);
  }
  if(!meta.querySelector('.countdown')){
    const cd = document.createElement('span');
    cd.className = 'countdown';
    if(note?.expires_at){ cd.setAttribute('data-expires-at', note.expires_at); }
    else if(note?.expires_in!=null){
      cd.setAttribute('data-expires-in', note.expires_in);
      cd.setAttribute('data-epoch0', Date.now());
    }
    meta.prepend(cd);
  }
}

// Observador: si se agregan tarjetas con datos, intenta decorarlas
const __observer = new MutationObserver(muts=>{
  muts.forEach(m=>{
    m.addedNodes.forEach(n=>{
      if(!(n instanceof Element)) return;
      if(n.matches?.('[data-note]')) ensureCountdownForCard(n, n.__note);
      n.querySelectorAll?.('[data-note]').forEach(x=>ensureCountdownForCard(x, x.__note));
    });
  });
});
document.addEventListener('DOMContentLoaded', ()=>{
  try{ __observer.observe(document.body,{childList:true,subtree:true}); }catch(e){}
});
