class NotesApp {
  constructor() {
    this.main   = document.querySelector("main") || document.body;
    this.list   = document.getElementById("notes");
    this.pagNav = document.getElementById("pagination");
    this.form   = document.getElementById("form");
    this.btn    = document.getElementById("publish");
    this.page   = 1;
    this.pages  = 1;
    this.seen   = new Set();
    this.token  = localStorage.getItem("p12_token");
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
    this.list?.addEventListener("click",(e)=>{
      const btn = e.target.closest(".like-btn"); if(!btn) return;
      const li  = btn.closest("li[data-id]");   if(!li)  return;
      this.like(li.dataset.id);
    });
  }
  async publish(){
    const tx = this.form.querySelector("#text");
    const dl = this.form.querySelector("#duration");
    const text = (tx?.value || "").trim();
    if(!text) return;
    let hours = parseInt(dl?.value ?? "168", 10);
    if(!Number.isFinite(hours) || hours<1 || hours>24*28) hours=168;
    const r = await fetch("/api/notes", {
      method:"POST",
      headers:{ "Content-Type":"application/json" },
      body: JSON.stringify({ text, expire_hours: hours })
    });
    if(!r.ok){ alert("No se pudo publicar"); return; }
    tx.value = "";
    await this.load(1);
    window.scrollTo({ top: (this.list?.offsetTop||0)-10, behavior:"smooth" });
  }
  async like(id){
    const r = await fetch(`/api/notes/${id}/like`, { method:"POST", headers:{ "X-Client-Token": this.token }});
    const j = await r.json().catch(()=>({}));
    const el = this.list.querySelector(`li[data-id="${id}"] .likes-count`);
    if(el && typeof j.likes === "number") el.textContent = j.likes;
  }
  async load(page=1){
    const r = await fetch(`/api/notes?page=${page}`);
    const j = await r.json().catch(()=>({notes:[], total_pages:1}));
    this.page  = page;
    this.pages = j.total_pages || 1;
    this.render(j.notes || []);
  }
  render(items){
    this.list.innerHTML = items.map(n=>`
      <li class="note" data-id="${n.id}">
        <div class="note-text">${this.escape(n.text)}</div>
        <div class="note-meta">
          <button type="button" class="like-btn">❤️ Like</button>
          <span class="counters">👍 <span class="likes-count">${n.likes||0}</span> ·
          👁️ <span class="views-count">${n.views||0}</span></span>
        </div>
      </li>`).join("");

    this.pagNav.innerHTML = "";
    for(let p=1;p<=this.pages;p++){
      const b=document.createElement("button");
      b.textContent = p;
      if(p===this.page) b.disabled = true;
      b.addEventListener("click",()=>this.load(p));
      this.pagNav.appendChild(b);
    }

    this.list.querySelectorAll("li[data-id]").forEach(li=>{
      const id = li.dataset.id;
      if(this.seen.has(id)) return;
      this.seen.add(id);
      fetch(`/api/notes/${id}/view`, { method:"POST", headers:{ "X-Client-Token": this.token }})
        .then(r=>r.json()).then(j=>{
          const el = li.querySelector(".views-count");
          if(el && j && typeof j.views==="number") el.textContent = j.views;
        }).catch(()=>{});
    });
  }
  escape(s){ const d=document.createElement("div"); d.textContent=s; return d.innerHTML.replace(/\n/g,"<br>"); }
}
document.addEventListener("DOMContentLoaded", ()=> new NotesApp());
