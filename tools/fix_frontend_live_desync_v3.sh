#!/usr/bin/env bash
set -euo pipefail

# Localiza el index.html (frontend/ o raíz)
HTML=""
for p in ./frontend/index.html ./index.html; do
  [[ -f "$p" ]] && { HTML="$p"; break; }
done
[[ -n "$HTML" ]] || { echo "ERR: no se encontró index.html"; exit 1; }

python - "$HTML" <<'PY'
import sys,re

path = sys.argv[1]
src  = open(path,'r',encoding='utf-8',errors='ignore').read()

def ensure_adsense(s:str)->str:
    if 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-' in s:
        return s
    tag = ('<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js'
           '?client=ca-pub-9479870293204581" crossorigin="anonymous"></script>')
    return re.sub(r'(</head>)', tag + r'\n\1', s, count=1, flags=re.I)

def ensure_cache_guard(s:str)->str:
    if 'id="p12-cache-guard"' in s:
        return s
    guard = r'''<script id="p12-cache-guard">
(function(){
  try{
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

def ensure_stats_block(s:str)->str:
    if re.search(r'<span\s+class="views"', s):
        return s
    inj = '<div id="p12-stats" class="stats"><span class="views" data-views="0">👁️ <b>0</b></span><span class="likes" data-likes="0">❤️ <b>0</b></span><span class="reports" data-reports="0">🚩 <b>0</b></span></div>'
    return re.sub(r'(</body>)', inj + r'\n\1', s, count=1, flags=re.I)

def ensure_card_fix(s:str)->str:
    if 'id="p12-card-fix-v3"' in s:
        return s
    js = r'''<script id="p12-card-fix-v3">
(function(){
  if (window.__p12CardFixV3) return; window.__p12CardFixV3 = true;

  function ensureSpans(art){
    if (!art) return;
    var meta = art.querySelector('.meta') || art;
    if (!meta) return;
    if (!meta.querySelector('.views')){
      var span = document.createElement('span');
      span.className='views';
      span.innerHTML='👁️ <b>0</b>';
      meta.insertBefore(span, meta.firstChild);
    }
    if (!meta.querySelector('.likes')){
      var s = document.createElement('span');
      s.className='likes';
      s.innerHTML='❤ <b>0</b>';
      meta.insertBefore(s, meta.firstChild);
    }
  }

  function bumpViews(art){
    var b = art && art.querySelector('.views b');
    if (b){
      var n = parseInt(b.textContent||'0',10)||0;
      b.textContent = String(n+1);
    }
  }

  var io = ('IntersectionObserver' in window) ? new IntersectionObserver(function(entries){
    entries.forEach(function(e){
      if (e.isIntersecting){
        var art=e.target, id=art.getAttribute('data-id');
        if (id){
          try{ fetch('/api/notes/'+id+'/view', {method:'POST'}).catch(function(){}); }catch(_){}
        }
        bumpViews(art);
        try{ io.unobserve(art); }catch(_){}
      }
    });
  }, {rootMargin:'0px 0px -60% 0px', threshold:0.2}) : null;

  function watch(){
    document.querySelectorAll('article.note').forEach(function(art){
      ensureSpans(art);
      if (io) try{ io.observe(art); }catch(_){}
    });
  }

  var mo = new MutationObserver(function(ms){
    var changed=false;
    ms.forEach(function(m){
      m.addedNodes && m.addedNodes.forEach(function(n){
        if (n.nodeType===1 && ( (n.matches && n.matches('article.note')) || (n.querySelector && n.querySelector('article.note')) )){
          changed=true;
        }
      });
    });
    if (changed) watch();
  });

  try{ mo.observe(document.documentElement,{childList:true,subtree:true}); }catch(_){}
  try{ document.addEventListener('DOMContentLoaded', watch); }catch(_){}
  try{ window.addEventListener('load', watch); }catch(_){}
  try{ setTimeout(watch, 0); }catch(_){}
})();
</script>'''
    return re.sub(r'(</body>)', js + r'\n\1', s, count=1, flags=re.I)

src = ensure_adsense(src)
src = ensure_cache_guard(src)
src = ensure_stats_block(src)
src = ensure_card_fix(src)

open(path,'w',encoding='utf-8').write(src)
print("OK: patched", path)
PY

# sanity mínima
grep -q 'p12-card-fix-v3' "$HTML"
grep -q 'p12-cache-guard' "$HTML"
grep -q '<span class="views"' "$HTML" || true  # el block global puede existir o lo creará el patch
echo "✔ Frontend parchado en: $HTML"
