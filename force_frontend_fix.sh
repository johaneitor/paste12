#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
ts=$(date +%s)

echo "🗂️  Backups .$ts"
mkdir -p frontend/js frontend/css
cp -p frontend/index.html frontend/index.html.bak.$ts 2>/dev/null || true
cp -p frontend/js/app.js frontend/js/app.js.bak.$ts 2>/dev/null || true
cp -p frontend/css/styles.css frontend/css/styles.css.bak.$ts 2>/dev/null || true
cp -p backend/__init__.py backend/__init__.py.bak.$ts 2>/dev/null || true

# 1) Desactivar scheduler en local (evita warnings)
python - <<'PY'
from pathlib import Path, re
p = Path("backend/__init__.py")
s = p.read_text()
# env gate para el scheduler
s = re.sub(r'(\s*sch\s*=\s*BackgroundScheduler[^\n]+\n\s*sch\.add_job[^\n]+\n\s*sch\.start\(\)\n)',
           r'    if not os.getenv("DISABLE_SCHEDULER"):\n\1', s, count=1)
p.write_text(s)
print("✓ backend/__init__.py: scheduler condicionado por DISABLE_SCHEDULER")
PY
export DISABLE_SCHEDULER=1

# 2) Logo embebido si existe
LOGO_B64=$(python - <<'PY'
import re,sys
from pathlib import Path
p=Path("frontend/index.html")
if p.exists():
    m=re.search(r'src="(data:image/(?:png|jpeg);base64,[^"]+)"', p.read_text())
    if m: print(m.group(1)); sys.exit(0)
print("")
PY
)

# 3) index.html — botón NO hace submit, script con cache-buster
cat > frontend/index.html <<HTML
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Paste12 — notas que desaparecen</title>
<link rel="stylesheet" href="/css/styles.css?v=$ts">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;600;700&display=swap" rel="stylesheet">
</head>
<body>
  <header class="hero">
    <div class="logo">
      ${LOGO_B64:+<img class="logo-img" alt="Logo" src="$LOGO_B64">}
    </div>
    <h1>Paste12</h1>
    <p class="playline">Haz un regalo • Dime un secreto • Reta a un amigo</p>
  </header>

  <main class="container">
    <form id="form" class="card" action="#" method="post" onsubmit="return false;">
      <textarea id="text" placeholder="Escribe tu nota…" rows="5" maxlength="500"></textarea>
      <div class="form-row">
        <label>Duración:
          <select name="expire_hours" id="duration">
            <option value="12">12 horas</option>
            <option value="24">1 día</option>
            <option value="168" selected>7 días</option>
            <option value="336">14 días</option>
            <option value="672">28 días</option>
          </select>
        </label>
        <button id="publish" type="button" class="primary">Publicar</button>
      </div>
    </form>

    <ul id="notes" class="notes"></ul>
    <nav id="pagination" class="pagination"></nav>
  </main>

  <footer class="legal">© 2025 Paste12 — Todos los derechos reservados · Este sitio es recreativo. No publiques datos sensibles.</footer>
  <script src="/js/app.js?v=$ts" defer></script>
</body>
</html>
HTML
echo "✓ index.html escrito"

# 4) app.js — frena GET y publica por fetch, render y likes/vistas
cat > frontend/js/app.js <<'JS'
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
JS
echo "✓ app.js escrito"

# 5) styles.css — look elegante
cat > frontend/css/styles.css <<'CSS'
:root{
  --bg1:#f9a1a1; --bg2:#f3b6b6; --card:rgba(0,0,0,.18); --text:#fff;
  --accent:#ff6b81; --accent2:#ff00ff; --shadow:0 10px 30px rgba(0,0,0,.25);
}
*{box-sizing:border-box}
body{margin:0;font-family:'Poppins',system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,'Helvetica Neue',Arial;color:var(--text);
     background:radial-gradient(1200px 800px at 20% -10%,var(--bg2),var(--bg1));min-height:100vh;}
.hero{text-align:center;padding:24px 16px 8px}
.logo-img{width:120px;image-rendering:pixelated;filter:drop-shadow(0 0 10px #30eaff) drop-shadow(0 0 5px #ff00ff)}
h1{font-size:2.6rem;margin:.2rem 0 .5rem;letter-spacing:.5px}
.playline{font-weight:600;opacity:.9;margin:-.2rem 0 1.2rem;text-shadow:0 0 8px #30eaff,0 0 4px #ff00ff}
.container{max-width:860px;margin:0 auto;padding:16px}
.card{background:var(--card);backdrop-filter:blur(8px);border-radius:20px;padding:14px;box-shadow:var(--shadow)}
textarea{width:100%;background:rgba(255,255,255,.08);color:#fff;border:1px solid rgba(255,255,255,.2);border-radius:12px;padding:12px;font:inherit;outline:none}
textarea::placeholder{color:#eee;opacity:.65}
.form-row{display:flex;align-items:center;gap:12px;justify-content:space-between;margin-top:10px}
select{border-radius:12px;padding:8px 12px;border:none;font:inherit}
.primary{background:linear-gradient(90deg,var(--accent),var(--accent2));color:#fff;border:none;padding:10px 16px;border-radius:12px;cursor:pointer;font-weight:700;box-shadow:0 6px 18px rgba(255,0,255,.35)}
.notes{list-style:none;padding:0;margin:18px 0 10px}
.note{background:var(--card);border-radius:18px;padding:12px 14px;margin:10px 0;box-shadow:var(--shadow)}
.note-text{white-space:pre-wrap;word-break:break-word}
.note-meta{display:flex;justify-content:space-between;align-items:center;margin-top:.4rem}
.like-btn{background:#ff00ff;color:#fff;border:none;border-radius:10px;padding:.35rem .7rem;cursor:pointer}
.pagination{display:flex;gap:6px;justify-content:center;margin:10px 0 40px}
.pagination button{border:none;padding:.4rem .7rem;border-radius:8px;cursor:pointer}
.pagination button[disabled]{opacity:.6}
footer.legal{margin:3rem auto 1rem;text-align:center;font-size:.9rem;opacity:.85}
CSS
echo "✓ styles.css escrito"

# 6) Reiniciar servidor con log propio
pkill -f waitress 2>/dev/null || true
: > .paste12.log
nohup env PYTHONUNBUFFERED=1 DISABLE_SCHEDULER=1 python run.py >> .paste12.log 2>&1 &
echo $! > .paste12.pid
sleep 1
echo "🟢 Server PID: $(cat .paste12.pid)"
echo "—— Últimas líneas de .paste12.log ——"
tail -n 30 .paste12.log
