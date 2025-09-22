#!/usr/bin/env bash
set -euo pipefail

HTML=""
for p in ./frontend/index.html ./index.html; do
  [[ -f "$p" ]] && { HTML="$p"; break; }
done
[[ -n "$HTML" ]] || { echo "ERR: no se encontró index.html"; exit 1; }

tmp="$(mktemp)"
cp "$HTML" "$tmp"

python - <<'PY' "$HTML"
import io,sys,re,os
path=sys.argv[1]
src=open(path,'r',encoding='utf-8',errors='ignore').read()

def ensure_adsense(s):
    if 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-' in s:
        return s
    tag=('<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js'
         '?client=ca-pub-9479870293204581" crossorigin="anonymous"></script>')
    s=re.sub(r'(</head>)', tag + r'\n\\1', s, count=1, flags=re.I)
    return s

def replace_card_html(s):
    # Reemplazar function cardHTML(...) con versión que incluye spans
    pattern=r'function\\s+cardHTML\\s*\\([^)]*\\)\\s*\\{[\\s\\S]*?\\n\\}'
    new_js=r'''function cardHTML(it){
  const txt = it.text || it.content || it.summary || '';
  let short = txt, needMore=false;
  if (txt.length > 180){ short = txt.slice(0,160)+'…'; needMore=true; }
  return `
    <article class="note" data-id="${it.id}">
      <div class="text" data-text="1" data-full="${esc(txt)}">${esc(short)||'(sin texto)'}</div>
      <div class="meta">
        #${it.id}
        <span class="likes" data-likes="${it.likes??0}">❤ <b>${it.likes??0}</b></span>
        <span class="views" data-views="${it.views??0}">👁️ <b>${it.views??0}</b></span>
        <button class="act like" type="button">❤</button>
        <button class="act more" type="button">⋯</button>
      </div>
      <div class="menu ${needMore?'':'hidden'}">
        ${needMore?'<button class="expand" type="button">Ver más</button>':''}
        <button class="share"  type="button">Compartir</button>
        <button class="report" type="button">Reportar 🚩</button>
      </div>
    </article>`;
}'''
    return re.sub(pattern, new_js, s, count=1, flags=re.I)

def patch_like_handler(s):
    # Al hacer like, actualizar el <span.likes b>
    s=re.sub(
      r"if\\(j\\s*&&\\s*typeof\\s*j\\.likes!=='undefined'\\)\\{[\\s\\S]*?\\}",
      r"""if(j && typeof j.likes!=='undefined'){
        const b=art.querySelector('.likes b'); if(b){ b.textContent=String(j.likes); }
      }""",
      s, count=1)
    return s

def improve_view_observer(s):
    # Cuando llega /view, si hay .views b => ++; si no, intentar fallback
    s=re.sub(
      r"const\\s+span\\s*=\\s*el\\.querySelector\\('\\.views'\\);[\\s\\S]*?\\}",
      r"""const spanB = el.querySelector('.views b') || el.querySelector('.views');
            if (spanB) {
              const cur = parseInt((spanB.textContent||'0').match(/\\d+/)?.[0]||'0',10);
              spanB.textContent = String(cur+1);
            } else {
              const m = el.querySelector('.meta');
              if (m) {
                const mm = /(\d+)/.exec(m.textContent||'0');
                const cur = mm?parseInt(mm[1],10):0;
                m.innerHTML = m.innerHTML.replace(/👁️?\\s*<b>?\\d+<\\/?b>?/, '👁️ <b>'+String(cur+1)+'</b>');
              }
            }""",
      s, count=1)
    return s

def ensure_stats_block(s):
    # Asegura stats globales con <span class="views"> (si no está)
    if re.search(r'<span\\s+class="views"', s):
        return s
    inj = '<div id="p12-stats" class="stats"><span class="views" data-views="0">👁️ <b>0</b></span><span class="likes" data-likes="0">❤️ <b>0</b></span><span class="reports" data-reports="0">🚩 <b>0</b></span></div>'
    s=re.sub(r'(</body>)', inj + r'\n\1', s, count=1, flags=re.I)
    return s

def add_runtime_guard(s):
    if 'id="p12-cache-guard"' in s:
        return s
    guard = r'''<script id="p12-cache-guard">
(function(){
  try{
    // Si no vemos .views, es HTML viejo cacheado por SW. Desregistramos y recargamos con ?nosw=1
    if(!document.querySelector('span.views')){
      if('serviceWorker' in navigator){
        try{navigator.serviceWorker.getRegistrations().then(rs=>Promise.all(rs.map(r=>r.unregister())));}catch(_){}
      }
      if(!/([?&])nosw=1/.test(location.search)){
        var q = location.search ? location.search + '&nosw=1' : '?nosw=1';
        location.replace(location.pathname + q + location.hash);
      }
    }
  }catch(_){}
})();
</script>'''
    return re.sub(r'(</head>)', guard + r'\n\1', s, count=1, flags=re.I)

src = ensure_adsense(src)
src = replace_card_html(src)
src = patch_like_handler(src)
src = improve_view_observer(src)
src = add_runtime_guard(src)
src = ensure_stats_block(src)

open(path,'w',encoding='utf-8').write(src)
print("OK: patched", path)
PY

# sanity
grep -q '<span class="views"' "$HTML" || { echo "ERR: faltan spans .views"; exit 1; }
grep -q 'p12-cache-guard' "$HTML" || { echo "ERR: faltó cache-guard"; exit 1; }
echo "✔ Frontend parchado en: $HTML"
