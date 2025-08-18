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
