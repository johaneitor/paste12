#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
ts=$(date +%s)
echo "🗂️ Backups .$ts"

# --- Respaldos ---
for f in backend/models.py backend/routes.py frontend/js/app.js frontend/css/styles.css; do
  [ -f "$f" ] && cp -p "$f" "$f.bak.$ts" || true
done

# --- 1) MODELS: agregar ReportLog si no existe ---
python - <<'PY'
from pathlib import Path
p = Path("backend/models.py")
code = p.read_text()

if "class ReportLog(" not in code:
    code += """

# --- Registro de reportes (1 por token y nota) ---
class ReportLog(db.Model):
    id           = db.Column(db.Integer, primary_key=True)
    note_id      = db.Column(db.Integer, db.ForeignKey('note.id'), nullable=False, index=True)
    fingerprint  = db.Column(db.String(64), nullable=False, index=True)
    created_at   = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    __table_args__ = (db.UniqueConstraint('note_id', 'fingerprint', name='uq_report_note_fp'),)
"""
    p.write_text(code)
    print("✓ backend/models.py: ReportLog añadido")
else:
    print("• backend/models.py: ReportLog ya existía")
PY

# --- 2) ROUTES: endpoint /api/notes/<id>/report + compartir no requiere backend ---
python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
code = p.read_text()

if "def report_note(" not in code:
    insert = """
@bp.post("/notes/<int:note_id>/report")
def report_note(note_id):
    token = request.headers.get("X-Client-Token") or request.remote_addr or "anon"
    if not token:
        return jsonify({"error":"missing token"}), 400
    note = Note.query.get_or_404(note_id)

    # ¿Ya reportó este token?
    from .models import ReportLog
    exists = ReportLog.query.filter_by(note_id=note.id, fingerprint=token).first()
    if exists:
        return jsonify({"reports": note.reports, "already": True})

    # Nuevo reporte
    rl = ReportLog(note_id=note.id, fingerprint=token)
    note.reports = (note.reports or 0) + 1
    db.session.add(rl)

    deleted = False
    # Si llega a 5, borrar la nota y sus logs
    if note.reports >= 5:
        # borrar logs relacionados y la nota
        ReportLog.query.filter_by(note_id=note.id).delete()
        try:
            from .models import LikeLog
            LikeLog.query.filter_by(note_id=note.id).delete()
        except Exception:
            pass
        db.session.delete(note)
        deleted = True
        db.session.commit()
        return jsonify({"deleted": True, "reports": 5})

    db.session.commit()
    return jsonify({"deleted": False, "reports": note.reports})
"""
    # lo pegamos al final del archivo
    code = code.rstrip() + "\n\n" + insert
    p.write_text(code)
    print("✓ backend/routes.py: /report añadido")
else:
    print("• backend/routes.py: /report ya existía")
PY

# --- 3) FRONTEND JS: menú 3 puntos (reportar/compartir) + handlers ---
cat > frontend/js/app.js <<'JS'
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
JS
echo "✓ frontend/js/app.js actualizado"

# --- 4) CSS: estilos del menú 3 puntos y dropdown, + pequeños retoques ---
cat >> frontend/css/styles.css <<'CSS'

/* --- Opciones por nota (3 puntos) --- */
.note{ position: relative; }
.note-actions{ position:absolute; top:8px; right:8px; }
.menu-btn{
  background: rgba(255,255,255,.15); color:#fff; border:none; border-radius:10px;
  width:32px; height:32px; cursor:pointer;
}
.menu{
  position:absolute; top:36px; right:0; min-width:160px;
  background: rgba(0,0,0,.85); color:#fff; border:1px solid rgba(255,255,255,.15);
  border-radius:12px; box-shadow:0 10px 24px rgba(0,0,0,.35); padding:6px;
  backdrop-filter: blur(8px);
}
.menu-item{
  width:100%; text-align:left; background:transparent; color:#fff; border:none;
  padding:8px 10px; border-radius:8px; cursor:pointer; display:block;
}
.menu-item:hover{ background: rgba(255,255,255,.1); }
.menu-item.disabled{ opacity:.6; cursor:not-allowed; }
CSS
echo "✓ frontend/css/styles.css: menú 3 puntos"

# --- 5) Reiniciar servidor (scheduler off en local) ---
pkill -f "python run.py" 2>/dev/null || true
pkill -f waitress 2>/dev/null || true
: > .paste12.log
source venv/bin/activate
nohup env PYTHONUNBUFFERED=1 DISABLE_SCHEDULER=1 python run.py >> .paste12.log 2>&1 &
echo "🟢 PID $!"
sleep 1
tail -n 40 .paste12.log
