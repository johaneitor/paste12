#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# Backups
for f in frontend/js/app.js frontend/css/styles.css; do
  [ -f "$f" ] && cp -p "$f" "$f.bak.$ts" || true
done
mkdir -p frontend/js frontend/css
touch frontend/js/app.js

python - <<'PY'
from pathlib import Path
p = Path("frontend/js/app.js")
code = p.read_text(encoding="utf-8")

inject = r"""
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
"""
if "=== IG Story Share (1080x1920) ===" not in code:
    code += "\n" + inject
    p.write_text(code, encoding="utf-8")
    print("✓ app.js: añadido compartir en historias de Instagram")
else:
    print("• app.js: IG story ya presente")
PY

# Un poco de estilo para el botón
cat >> frontend/css/styles.css <<'CSS'

/* Botón Historias IG */
.btn-ig-story{
  margin-left:.5rem; margin-top:.25rem;
  padding:.45rem .7rem; border-radius:10px;
  border:none; background:#e11d48; color:#fff;
  box-shadow:0 6px 18px rgba(225,29,72,.35);
  font-weight:700; letter-spacing:.2px;
}
.btn-ig-story:active{ transform:translateY(1px); }
CSS

# Commit y push
git add -A
git commit -m "feat(share): opción 'Compartir en historias de Instagram' con Web Share + fallback" || true
git push
echo "🚀 Cambios enviados. Tras el deploy, recarga con /?v=$(date +%s)"
