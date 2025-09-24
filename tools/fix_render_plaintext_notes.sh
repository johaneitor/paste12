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

# backup suave
[ -f "$STATIC_DIR/js/app.js" ] && cp -f "$STATIC_DIR/js/app.js" "$STATIC_DIR/js/app.js.bak.$(date +%s)" || true

# === sobrescribir app.js con render seguro (DOM API; sin template literals) ===
cat > "$STATIC_DIR/js/app.js" <<'JS'
(function(){
  const $status = document.getElementById('status') || (()=>{const s=document.createElement('span');s.id='status';document.body.appendChild(s);return s;})();
  const $list = document.getElementById('notes') || (()=>{const u=document.createElement('ul');u.id='notes';document.body.appendChild(u);return u;})();
  const $form = document.getElementById('noteForm');

  function fmtISO(s){ try{ return new Date(s).toLocaleString(); }catch(_){ return s||''; } }

  function toast(msg){
    let t = document.getElementById('toast');
    if(!t){
      t = document.createElement('div');
      t.id='toast';
      t.style.cssText='position:fixed;left:50%;bottom:18px;transform:translateX(-50%);background:#111a;color:#eaf2ff;padding:10px 14px;border-radius:10px;border:1px solid #253044;z-index:9999;transition:opacity .25s ease';
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.style.opacity='1';
    setTimeout(()=>{ t.style.opacity='0'; }, 1800);
  }

  function noteLink(id){
    try{ return location.origin + '/?note=' + id; }catch(_){ return '/?note='+id; }
  }

  async function reportNote(id){
    try{
      const res = await fetch('/api/notes/'+id+'/report', { method: 'POST' });
      const data = await res.json();
      if(data.deleted){
        const el = document.getElementById('note-'+id);
        if(el) el.remove();
        toast('Nota eliminada por reportes (5/5)');
      }else if(data.already_reported){
        toast('Ya reportaste esta nota');
      }else if(data.ok){
        toast('Reporte registrado ('+(data.reports||0)+'/5)');
      }else{
        alert('No se pudo reportar: '+(data.detail||''));
      }
    }catch(e){ alert('Error de red al reportar'); }
  }

  async function shareNote(id){
    const url = noteLink(id);
    if(navigator.share){
      try{ await navigator.share({ title: 'Nota #'+id, url }); return; }catch(_){}
    }
    try{ await navigator.clipboard.writeText(url); toast('Enlace copiado'); }
    catch(_){ window.prompt('Copia este enlace', url); }
  }

  function renderNote(n){
    const li = document.createElement('li');
    li.className = 'note';
    li.id = 'note-'+n.id;

    // fila principal
    const row = document.createElement('div');
    row.className = 'row';

    const txt = document.createElement('div');
    txt.className = 'txt';
    txt.textContent = String(n.text ?? '');

    const more = document.createElement('button');
    more.className = 'more';
    more.setAttribute('aria-label','Más opciones');
    more.textContent = '⋯';

    const menu = document.createElement('div');
    menu.className = 'menu';

    // items de menú
    const btnReport = document.createElement('button');
    btnReport.textContent = 'Reportar';
    btnReport.addEventListener('click', (ev)=>{ ev.stopPropagation(); menu.classList.remove('open'); reportNote(n.id); });

    const btnShare = document.createElement('button');
    btnShare.textContent = 'Compartir';
    btnShare.addEventListener('click', (ev)=>{ ev.stopPropagation(); menu.classList.remove('open'); shareNote(n.id); });

    menu.appendChild(btnReport);
    menu.appendChild(btnShare);

    more.addEventListener('click', (ev)=>{
      ev.stopPropagation();
      menu.classList.toggle('open');
    });

    row.appendChild(txt);
    row.appendChild(more);
    row.appendChild(menu);

    const meta = document.createElement('div');
    meta.className = 'meta';
    meta.appendChild(document.createTextNode('id #'+n.id+' · '+fmtISO(n.timestamp)+' · expira: '+fmtISO(n.expires_at)));

    li.appendChild(row);
    li.appendChild(meta);
    return li;
  }

  async function fetchNotes(){
    $status.textContent = 'cargando…';
    try{
      const res = await fetch('/api/notes?page=1');
      const data = await res.json();
      $list.innerHTML = '';
      data.forEach(n => $list.appendChild(renderNote(n)));
      $status.textContent = 'ok';
    }catch(e){
      console.error(e);
      $status.textContent = 'error cargando';
    }
  }

  // click fuera cierra menús
  document.addEventListener('click', ()=> {
    document.querySelectorAll('.note .menu.open').forEach(el => el.classList.remove('open'));
  });

  if($form){
    $form.addEventListener('submit', async (ev)=>{
      ev.preventDefault();
      const fd = new FormData($form);
      try{
        const res = await fetch('/api/notes', { method:'POST', body: fd });
        if(!res.ok) throw new Error('HTTP '+res.status);
        await fetchNotes();
        $form.reset();
        const h = document.getElementById('hours'); if(h) h.value = 24;
      }catch(e){
        alert('No se pudo publicar la nota: '+e.message);
      }
    });
  }

  // scroll a ?note=ID si viene en la URL
  try{
    const params = new URLSearchParams(location.search);
    const id = params.get('note');
    if(id){
      setTimeout(()=>{
        const el = document.getElementById('note-'+id);
        if(el) el.scrollIntoView({behavior:'smooth', block:'center'});
      }, 150);
    }
  }catch(_){}

  fetchNotes();
})();
JS

# CSS mínimo para el menú (si falta)
CSS_FILE=""
for d in frontend public static dist build; do
  if [ -f "$d/css/styles.css" ]; then CSS_FILE="$d/css/styles.css"; break; fi
done
[ -z "$CSS_FILE" ] && CSS_FILE="$STATIC_DIR/css/styles.css"

grep -q ".note .more" "$CSS_FILE" 2>/dev/null || cat >> "$CSS_FILE" <<'CSS'

/* menú ⋯ */
.note .row{display:flex; gap:8px; align-items:flex-start; position:relative}
.note .row .txt{flex:1}
.note .more{background:#1c2431;border:1px solid #273249;color:#dfeaff;border-radius:8px;cursor:pointer;padding:0 10px;height:28px}
.note .more + .menu{display:none;position:absolute;z-index:10;transform:translateY(30px);right:0;background:#0f141d;border:1px solid #273249;border-radius:10px;min-width:140px}
.note .more + .menu.open{display:block}
.note .more + .menu button{display:block;width:100%;text-align:left;padding:8px 10px;background:transparent;border:0;color:#eaf2ff}
.note .more + .menu button:hover{background:#141c28}
#toast{transition:opacity .25s ease}
CSS

# bump de versión en index.html para evitar caché (v=2)
if [ -f "$STATIC_DIR/index.html" ]; then
  sed -i -E 's#/js/app\.js\?v=[^"]*#/js/app.js?v=2#g' "$STATIC_DIR/index.html" || true
fi

# reinicio local rápido
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="$PREFIX/tmp/paste12_server.log"
pkill -f "python .*run\.py" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "notes=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/notes)"

# commit & push
git add "$STATIC_DIR/js/app.js" "$CSS_FILE" "$STATIC_DIR/index.html"
git commit -m "fix(ui): render de notas vía DOM (evita literales ${...}); menú ⋯ funcional"
git push origin main || true

echo "✓ Listo. Actualizá el sitio; si no ves cambios, hacé Clear build cache & deploy en Render."
