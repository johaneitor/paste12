#!/usr/bin/env bash
set -euo pipefail

HTML="${1:-frontend/index.html}"
CID="${2:-ca-pub-9479870293204581}"

[[ -f "$HTML" ]] || { echo "ERROR: no existe $HTML"; exit 2; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="${HTML}.${TS}.reconcile.bak"
cp -f "$HTML" "$BAK"
echo "[reconcile] Backup: $BAK"

python - <<'PY' "$HTML" "$CID"
import io, sys, re, os
p=sys.argv[1]; cid=sys.argv[2]
s=io.open(p,'r',encoding='utf-8',errors='ignore').read()
orig=s

def insert_before(tag, needle, block):
    i = s.lower().find(needle)
    if i==-1:
        j = s.lower().find(tag)
        if j!=-1:
            return s[:j] + block + s[j:]
    return s

def remove_script_containing(snippet):
    global s
    low=s.lower(); sn=snippet.lower()
    pos=low.find(sn)
    if pos==-1: return
    # buscar <script ...> más cercano hacia atrás
    start=low.rfind("<script",0,pos)
    if start==-1: return
    # buscar cierre </script> desde pos
    end=low.find("</script>",pos)
    if end==-1: return
    end += len("</script>")
    s = s[:start] + s[end:]

def ensure_meta_adsense():
    global s
    if 'google-adsense-account' not in s.lower():
        blk='  <meta name="google-adsense-account" content="'+cid+'">\\n'
        s = insert_before('</head>','<meta', blk) or s

def ensure_js_adsense():
    global s
    if 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' not in s:
        blk='  <script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client='+cid+'" crossorigin="anonymous"></script>\\n'
        s = insert_before('</head>','</head>', blk) or s

def fix_sw_nuke():
    global s
    # eliminar bloque roto (el que tiene ".then(rs=>Promise.all(" sin llamada)
    if ".then(rs=>Promise.all" in s and "navigator.serviceworker.getregistrations" not in s.lower():
        remove_script_containing(".then(rs=>Promise.all")
    # inyectar bloque correcto si no está
    if "sw-nuke" not in s.lower():
        blk = """<script>
(function(){
  try{
    var q=new URLSearchParams(location.search);
    if(q.has('nosw')||q.has('nukesw')){
      if(navigator.serviceWorker && navigator.serviceWorker.getRegistrations){
        navigator.serviceWorker.getRegistrations()
          .then(function(rs){ return Promise.all(rs.map(function(r){ return r.unregister(); })); })
          .then(function(){ if(window.caches && caches.keys){ return caches.keys().then(function(ks){ return Promise.all(ks.map(function(k){ return caches.delete(k); })); }); } })
          .finally(function(){ console.log('[sw-nuke] done'); });
      }
    }
  }catch(e){}
})();
</script>
"""
        s = insert_before('</head>','</head>', blk) or s

def fix_like_report_urls():
    global s
    # corregir /api/notes${id}/like -> /api/notes/${id}/like (y report)
    s = s.replace("/api/notes${id}/like","/api/notes/${id}/like")
    s = s.replace("/api/notes${id}/report","/api/notes/${id}/report")

def ensure_views_span():
    global s
    if 'class="views"' not in s and "class='views'" not in s:
        sec = """<section id="p12-stats" class="stats" style="margin-top:1rem;opacity:.88">
  <span class="views">0</span> views ·
  <span class="likes">0</span> likes ·
  <span class="reports">0</span> reports
</section>
"""
        # insertar antes de </main> si existe, sino al final del body
        low=s.lower()
        j=low.find("</main>")
        if j!=-1:
            s = s[:j] + sec + s[j:]
        else:
            jb=low.find("</body>")
            if jb!=-1:
                s = s[:jb] + sec + s[jb:]

def ensure_footer_links():
    global s
    low=s.lower()
    need_terms = 'href="/terms"' not in low
    need_priv  = 'href="/privacy"' not in low
    if not (need_terms or need_priv): return
    # si no hay </footer>, crear uno antes de </body>
    if "</footer>" not in low:
        footer = """<footer style="margin-top:2rem;opacity:.85">
  <a href="/terms">Términos y Condiciones</a> ·
  <a href="/privacy">Política de Privacidad</a>
</footer>
"""
        s2 = insert_before('</body>','</body>', footer)
        if s2: 
            s = s2
            return
    # hay footer: reforzar dentro
    if need_terms:
        s = re.sub(r'(</footer>)', '  <a href="/terms">Términos y Condiciones</a>\\n\\1', s, flags=re.I)
    if need_priv:
        s = re.sub(r'(</footer>)', '  <a href="/privacy">Política de Privacidad</a>\\n\\1', s, flags=re.I)

def remove_duplicate_publish_blocks():
    global s
    # remover fallback antiguo
    if 'id="p12-publish-fallback"' in s or "id='p12-publish-fallback'" in s:
        remove_script_containing('p12-publish-fallback')
    # remover p12-submit-v3
    if 'p12-submit-v3' in s:
        remove_script_containing('p12-submit-v3')
    # remover publishNote() suelto
    if 'function publishNote' in s:
        remove_script_containing('function publishNote')

def strip_after_html_end():
    global s
    low=s.lower()
    j=low.find("</html>")
    if j!=-1:
        # ¿hay algo después? si contiene <script, lo recortamos (ese trailing es inválido)
        tail = s[j+7:]
        if "<script" in tail.lower():
            s = s[:j+7]

# aplicar reparaciones
ensure_meta_adsense()
ensure_js_adsense()
fix_sw_nuke()
fix_like_report_urls()
ensure_views_span()
ensure_footer_links()
remove_duplicate_publish_blocks()
strip_after_html_end()

# higiene
s = re.sub(r'\n{3,}', '\n\n', s)

if s!=orig:
    io.open(p,'w',encoding='utf-8').write(s)
    print("mod: index reconciliado")
else:
    print("INFO: no hubo cambios (ya estaba OK)")
PY

echo "[reconcile] OK"
