#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ts=$(date +%s)

HTML="frontend/index.html"
JS="frontend/js/app.js"
CSS="frontend/css/styles.css"

cp -p "$HTML" "$HTML.bak.$ts" 2>/dev/null || true
cp -p "$JS"   "$JS.bak.$ts"   2>/dev/null || true

# 1) Forzar script con ruta absoluta y cache-buster + form seguro
python - <<'PY'
from pathlib import Path, re, time
p = Path("frontend/index.html")
h = p.read_text()

# <form id="form" action="#" method="post">
h = re.sub(r'<form[^>]*id="form"[^>]*>',
           '<form id="form" action="#" method="post" class="card" style="padding:16px;border-radius:16px">',
           h, count=1)

# Reemplazar/asegurar el script al final del body, con defer y cache-buster
h = re.sub(r'<script[^>]*src="[^"]*js/app\.js[^"]*"[^>]*></script>',
           '', h)  # limpiamos el existente
h = h.replace('</body>',
              f'\n<script src="/js/app.js?v={int(time.time())}" defer></script>\n</body>')

Path("frontend/index.html").write_text(h)
print("✓ index.html: form seguro + script defer absoluto")
PY

# 2) app.js robusto (no revienta si faltan nodos; siempre previene submit)
cat > "$JS" <<'JS'
class NotesApp {
  constructor() {
    // elementos (crear si faltan)
    this.main = document.querySelector("main") || document.body;
    this.list = document.getElementById("notes");
    if (!this.list) { this.list = document.createElement("ul"); this.list.id="notes"; this.list.className="notes"; this.main.appendChild(this.list); }
    this.pagNav = document.getElementById("pagination");
    if (!this.pagNav) { this.pagNav = document.createElement("nav"); this.pagNav.id="pagination"; this.main.appendChild(this.pagNav); }
    this.form = document.getElementById("form") || document.querySelector("form");

    this.page  = 1;
    this.pages = 1;
    this.seen  = new Set();

    // token persistente para limitar likes por persona
    this.token = localStorage.getItem('p12_token');
    if (!this.token) {
      try { this.token = crypto.randomUUID(); }
      catch(e){ this.token = Math.random().toString(36).slice(2)+Date.now().toString(36); }
      localStorage.setItem('p12_token', this.token);
    }

    this.bindEvents();
    this.load(1);
  }

  bindEvents() {
    if (this.form) {
      this.form.addEventListener("submit", (e) => {
        e.preventDefault();
        this.publish().catch(()=>alert("Error al publicar"));
      });
    }
    this.list.addEventListener("click", (e) => {
      const btn = e.target.closest(".like-btn");
      if (!btn) return;
      const li = btn.closest("li[data-id]");
      if (!li) return;
      this.like(li.dataset.id);
    });
  }

  async publish() {
    const textarea = this.form.querySelector("textarea");
    const sel = this.form.querySelector("[name=expire_hours]") || this.form.querySelector("#duration");
    const text = (textarea?.value || "").trim();
    let hours = parseInt(sel?.value ?? "168", 10);
    if (!Number.isFinite(hours) || hours < 1 || hours > 24*28) hours = 168;

    const r = await fetch("/api/notes", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({ text, expire_hours: hours })
    });
    if (!r.ok) throw new Error("publish failed");
    if (textarea) textarea.value = "";
    this.load(1);
  }

  async like(id) {
    const r = await fetch(`/api/notes/${id}/like`, { method: "POST", headers: { "X-Client-Token": this.token }});
    if (!r.ok) return;
    const j = await r.json().catch(()=>({}));
    const li = this.list.querySelector(`li[data-id="${id}"]`);
    const span = li?.querySelector(".likes-count");
    if (span && typeof j.likes === "number") span.textContent = j.likes;
  }

  async load(page=1) {
    this.page = page;
    const r = await fetch(`/api/notes?page=${page}`);
    const j = await r.json().catch(()=>({notes:[], total_pages:1}));
    this.pages = j.total_pages || 1;
    this.render(j.notes || []);
  }

  render(items) {
    this.list.innerHTML = items.map(n => `
      <li class="note" data-id="${n.id}">
        <div class="note-text">${this.escape(n.text)}</div>
        <div class="note-meta">
          <button type="button" class="like-btn">❤️ Like</button>
          <span class="counters">👍 <span class="likes-count">${n.likes||0}</span> ·
          👁️ <span class="views-count">${n.views||0}</span></span>
        </div>
      </li>
    `).join("");

    // paginación
    this.pagNav.innerHTML = "";
    for (let p=1; p<=this.pages; p++){
      const b=document.createElement("button");
      b.textContent=p;
      if(p===this.page) b.disabled=true;
      b.addEventListener("click",()=>this.load(p));
      this.pagNav.appendChild(b);
    }

    // contar vistas una sola vez por render
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

  escape(s){
    const d=document.createElement("div");
    d.textContent=s;
    return d.innerHTML.replace(/\n/g,"<br>");
  }
}

document.addEventListener("DOMContentLoaded", ()=>{ try{ window.p12=new NotesApp(); }catch(e){ console.error(e); } });
JS

# 3) estilos mínimos por si faltan
grep -q ".notes .note" "$CSS" || cat >> "$CSS" <<'CSS'
.notes .note{background:rgba(0,0,0,.15);border-radius:16px;padding:12px;margin:10px 0}
.note-text{white-space:pre-wrap;word-break:break-word}
.note-meta{display:flex;justify-content:space-between;align-items:center;margin-top:.4rem}
.like-btn{background:#ff00ff;color:#fff;border:none;border-radius:.6rem;padding:.35rem .7rem;cursor:pointer}
CSS

# 4) Reinicio
pkill -f waitress 2>/dev/null || true
source venv/bin/activate
python run.py &
echo "🚀 Reiniciado. Si aún ves ?expire_hour en la URL, fuerza recarga (limpia caché)."
