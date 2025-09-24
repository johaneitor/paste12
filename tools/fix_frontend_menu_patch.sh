#!/usr/bin/env bash
set -Eeuo pipefail

# === detectar carpeta estática ===
choose_static_dir() {
  for d in frontend public static dist build; do
    if [ -d "$d" ]; then echo "$d"; return; fi
  done
  echo "public"
}
STATIC_DIR="$(choose_static_dir)"
mkdir -p "$STATIC_DIR/js" "$STATIC_DIR/css"

# === asegurar archivos base ===
[ -f "$STATIC_DIR/index.html" ] || echo "<!doctype html><title>paste12</title><ul id='notes'></ul><script src='/js/app.js?v=1'></script>" > "$STATIC_DIR/index.html"
[ -f "$STATIC_DIR/js/app.js" ] || echo "(function(){})();" > "$STATIC_DIR/js/app.js"
[ -f "$STATIC_DIR/css/styles.css" ] || echo "" > "$STATIC_DIR/css/styles.css"

# === parchear JS (imports correctos) ===
python - <<'PY'
from pathlib import Path
import re

root = Path(".")
# localizar app.js
for base in ["frontend", "public", "static", "dist", "build"]:
    p = root / base / "js" / "app.js"
    if p.exists():
        break
else:
    p = root / "public" / "js" / "app.js"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("(function(){})();", encoding="utf-8")

js = p.read_text(encoding="utf-8")

menu_helpers = r"""
function noteLink(id){
  try { return location.origin + "/?note=" + id; } catch { return "/?note="+id; }
}
async function reportNote(id){
  try{
    const res = await fetch(`/api/notes/${id}/report`, {method: 'POST'});
    const data = await res.json();
    if (data.deleted){
      const el = document.getElementById(`note-${id}`);
      if (el) el.remove();
      toast('Nota eliminada por reportes (5/5)');
    }else if (data.already_reported){
      toast('Ya reportaste esta nota');
    }else if (data.ok){
      toast(`Reporte registrado (${data.reports}/5)`);
    }else{
      alert('No se pudo reportar: ' + (data.detail||''));
    }
  }catch(e){ alert('Error de red al reportar'); }
}
async function shareNote(id){
  const url = noteLink(id);
  if (navigator.share){
    try{ await navigator.share({title:'Nota #' + id, url}); return; }catch(e){}
  }
  try{
    await navigator.clipboard.writeText(url);
    toast('Enlace copiado');
  }catch(e){
    prompt('Copia este enlace:', url);
  }
}
function toast(msg){
  let t = document.getElementById('toast');
  if (!t){
    t = document.createElement('div');
    t.id='toast';
    t.style.cssText='position:fixed;left:50%;bottom:18px;transform:translateX(-50%);background:#111a;color:#eaf2ff;padding:10px 14px;border-radius:10px;border:1px solid #253044;z-index:9999';
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.style.opacity='1';
  setTimeout(()=>{ t.style.opacity='0'; }, 1800);
}
"""

# insertar helpers si no están
if "function reportNote(" not in js:
    js = menu_helpers + "\n" + js

# reemplazar render del <li> para incluir el menú ⋯
js = re.sub(
    r"li\.innerHTML\s*=\s*`[^`]*`;",
    """li.innerHTML = `
      <div class="row">
        <div class="txt">\${n.text ?? ''}</div>
        <button class="more" aria-label="Más opciones" onclick="this.nextElementSibling.classList.toggle('open')">⋯</button>
        <div class="menu">
          <button onclick="reportNote(\${n.id})">Reportar</button>
          <button onclick="shareNote(\${n.id})">Compartir</button>
        </div>
      </div>
      <div class="meta">
        <span>id #\${n.id}</span>
        <span> · </span>
        <span>\${fmtISO(n.timestamp)}</span>
        <span> · expira: \${fmtISO(n.expires_at)}</span>
      </div>`;""",
    js
)

# asegurar id en cada li
js = re.sub(
    r"const li = document\.createElement\('li'\);\s*li\.className\s*=\s*'note';",
    "const li = document.createElement('li');\nli.className='note';\nli.id = `note-${n.id}`;",
    js
)

# scroll a ?note=<id>
if "URLSearchParams" not in js:
    js += """
(function(){
  try{
    const params = new URLSearchParams(location.search);
    const h = params.get('note');
    if (h){
      const el = document.getElementById('note-' + h);
      if (el) el.scrollIntoView({behavior:'smooth', block:'center'});
    }
  }catch(e){}
})();
"""

p.write_text(js, encoding="utf-8")
print("app.js parcheado correctamente:", p)
PY

# === añadir CSS del menú ⋯ ===
CSS_FILE=""
for d in frontend public static dist build; do
  if [ -f "$d/css/styles.css" ]; then CSS_FILE="$d/css/styles.css"; break; fi
done
[ -z "$CSS_FILE" ] && CSS_FILE="public/css/styles.css"

cat >> "$CSS_FILE" <<'CSS'

/* menú ⋯ */
.note .row{display:flex; gap:8px; align-items:flex-start}
.note .row .txt{flex:1}
.note .more{background:#1c2431;border:1px solid #273249;color:#dfeaff;border-radius:8px;cursor:pointer;padding:0 10px;height:28px}
.note .more + .menu{display:none;position:absolute;z-index:10;transform:translateY(30px);right:0;background:#0f141d;border:1px solid #273249;border-radius:10px;min-width:140px}
.note .more + .menu.open{display:block}
.note .more + .menu button{display:block;width:100%;text-align:left;padding:8px 10px;background:transparent;border:0;color:#eaf2ff}
.note .more + .menu button:hover{background:#141c28}
#toast{transition:opacity .25s ease}
CSS

# === reiniciar y smokes básicos ===
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="$PREFIX/tmp/paste12_server.log"
pkill -f "python .*run\.py" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2
echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "notes=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/notes)"

# === commit & push ===
git add "$STATIC_DIR/js/app.js" "$CSS_FILE"
git commit -m "feat(ui): menú ⋯ con Reportar/Compartir; fix imports patch"
git push origin main || true

echo "OK. Refrescá la web (o redeploy en Render si querés forzar assets)."
