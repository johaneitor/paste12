#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ts=$(date +%s)
HTML="frontend/index.html"
JS="frontend/js/app.js"
CSS="frontend/css/styles.css"

# Backups
cp -p "$HTML" "$HTML.fix.$ts"
cp -p "$JS"   "$JS.fix.$ts"

echo "🗂️  Backups creados (*.fix.$ts)"

# 1) Limpiar el bloque viejo con likes/visitas incrustado al final del HTML
python - <<'PY'
from pathlib import Path, re
p = Path("frontend/index.html")
h = p.read_text()

# elimina el bloque que contiene id="likes-count" y su <script> adjunto
h = re.sub(r'\s*<div[^>]*>[^<]*?<span[^>]*id="views-count"[^>]*>.*?</script>\s*',
           '', h, flags=re.S)

# por si quedó algún resto simple (línea con “0 visitas” etc.)
h = re.sub(r'.*Me gusta.*$', '', h, flags=re.M)

p.write_text(h)
print("✓ index.html limpiado")
PY

# 2) Reescribir app.js con rendering correcto + eventos
cat > "$JS" <<'JS'
class NotesApp {
  constructor() {
    this.list   = document.getElementById("notes");
    this.pagNav = document.getElementById("pagination");
    this.form   = document.getElementById("form");
    this.page   = 1;
    this.pages  = 1;
    this.seen   = new Set(); // para contar vistas solo una vez por render

    this.bindEvents();
    this.load(1);
  }

  bindEvents() {
    if (this.form) {
      this.form.addEventListener("submit", async (e) => {
        e.preventDefault();
        const textarea = this.form.querySelector("textarea");
        const text = (textarea?.value || "").trim();

        // select puede llamarse expire_hours o duration; tomamos lo que exista
        const sel = this.form.querySelector("[name=expire_hours]") ||
                    this.form.querySelector("#duration");
        let hours = parseInt(sel?.value ?? "168", 10);
        if (!Number.isFinite(hours) || hours < 1 || hours > 24*28) hours = 168;

        const r = await fetch("/api/notes", {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify({ text, expire_hours: hours })
        });
        if (r.ok) {
          if (textarea) textarea.value = "";
          this.load(1);
        } else {
          const err = await r.json().catch(()=>({error:"Error"}));
          alert(err.error || "Error al publicar");
        }
      });
    }

    // Delegación para clicks de "Like"
    this.list?.addEventListener("click", async (e) => {
      const btn = e.target.closest(".like-btn");
      if (!btn) return;
      const li = btn.closest("li[data-id]");
      const id = li?.dataset.id;
      if (!id) return;

      const r = await fetch(`/api/notes/${id}/like`, { method: "POST" });
      if (r.ok) {
        const { likes } = await r.json();
        const el = li.querySelector(".likes-count");
        if (el) el.textContent = likes;
      }
    });
  }

  async load(page=1) {
    this.page = page;
    const r = await fetch(`/api/notes?page=${page}`);
    const j = await r.json();
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

    // Paginación
    this.pagNav.innerHTML = "";
    for (let p = 1; p <= this.pages; p++) {
      const b = document.createElement("button");
      b.textContent = p;
      if (p === this.page) b.disabled = true;
      b.addEventListener("click", () => this.load(p));
      this.pagNav.appendChild(b);
    }

    // Ping de vistas (una vez por nota por sesión de render)
    this.list.querySelectorAll("li[data-id]").forEach(li => {
      const id = li.dataset.id;
      if (this.seen.has(id)) return;
      this.seen.add(id);
      fetch(`/api/notes/${id}/view`, { method: "POST" })
        .then(r => r.json())
        .then(j => {
          const el = li.querySelector(".views-count");
          if (el && j && typeof j.views === "number") el.textContent = j.views;
        }).catch(()=>{});
    });
  }

  escape(s) {
    const d = document.createElement("div");
    d.textContent = s;
    return d.innerHTML.replace(/\n/g, "<br>");
  }
}

document.addEventListener("DOMContentLoaded", () => new NotesApp());
JS

# 3) CSS mínimo para la franja de meta (si faltara)
grep -q ".note-meta" "$CSS" || cat >> "$CSS" <<'CSS'

/* Meta de cada nota: like + contadores */
.note-meta{display:flex;justify-content:space-between;align-items:center;margin-top:.4rem}
.like-btn{background:#ff00ff;color:#fff;border:none;border-radius:.6rem;padding:.35rem .7rem;cursor:pointer;transition:transform .1s}
.like-btn:hover{transform:scale(1.06)}
CSS

# 4) Reiniciar servidor
pkill -f waitress 2>/dev/null || true
source venv/bin/activate
python run.py &
echo "🚀  Reiniciado. Recarga la página (borra caché si hace falta)."
