#!/usr/bin/env python3
import re, sys, shutil, pathlib

CANDIDATES = ["backend/static/index.html", "frontend/index.html"]

def read(p): return pathlib.Path(p).read_text(encoding="utf-8")
def write(p,s): pathlib.Path(p).write_text(s, encoding="utf-8")

def rm_nested_doc_in_script(s:str)->str:
    # elimina <script> <!doctype html ... </html> </script> (HTML entero metido en script)
    return re.sub(r"(?is)<script>\s*<!doctype html.*?</html>\s*</script>", "", s)

def truncate_after_first_html_close(s:str)->str:
    # si quedaron dos documentos pegados, quédate con el primero
    parts = re.split(r"(?i)</html>", s)
    if len(parts) >= 2:
        return parts[0] + "</html>"
    return s

def dedupe_by_id(s:str, sid:str, prefer_substr:str|None=None)->str:
    rx = re.compile(rf"(?is)<script[^>]*\bid=['\"]{re.escape(sid)}['\"][^>]*>.*?</script>")
    matches = list(rx.finditer(s))
    if len(matches) <= 1: return s
    # elige la ganadora
    winner = matches[0]
    if prefer_substr:
        for m in matches:
            seg = s[m.start():m.end()]
            if prefer_substr in seg:
                winner = m; break
    # reconstruye dejando solo winner
    out=[]; last=0
    for m in matches:
        if m is winner:
            out.append(s[last:m.end()]); last=m.end()
        else:
            out.append(s[last:m.start()]); last=m.start()
    out.append(s[last:])
    return "".join(out)

def patch_views_span(s:str)->str:
    # mete <span class="views">…</span> para que el observer actualice
    return re.sub(r"·\s*👁\s*\$\{it\.views\?\?0\}",
                  r"· <span class=\"views\">👁 ${it.views??0}</span>", s)

def ensure_single_note_mode(s:str)->str:
    # si existe el hotfix sin soporte ?id=, reemplaza el arranque por la versión con vista única
    pat = re.compile(r"(?s)window\.addEventListener\('DOMContentLoaded',\s*\(\)=>\{\s*fetchPage\('/api/notes\?limit=\d+'\);\s*\}\);\s*\}\)\(\);\s*</script>")
    if pat.search(s):
        repl = """window.addEventListener('DOMContentLoaded', ()=>{
  const q=new URLSearchParams(location.search);
  const pid=q.get('id');
  if(pid){
    (async()=>{
      try{
        const r=await fetch(`/api/notes/${encodeURIComponent(pid)}`,{headers:{'Accept':'application/json'},credentials:'include'});
        const j=await r.json().catch(()=>({}));
        const it=j&&j.item; const root=document.querySelector('#list,.list,[data-feed],#feed')||document.body;
        if(it){ root.innerHTML = (function(){const d=document.createElement('div'); d.innerHTML=cardHTML(it); return d.innerHTML;})();
                 document.title = `Nota #${it.id} – Paste12`; }
        else { root.innerHTML = '<article class="note"><div>(Nota no encontrada)</div></article>'; }
        const back=document.createElement('a'); back.href='/'; back.textContent='← Volver al feed';
        back.className='btn'; back.style.margin='12px auto'; root.after(back);
      }catch(_){}
    })();
    return; // no cargues el feed
  }
  fetchPage('/api/notes?limit=10');
});})();</script>"""
        s = pat.sub(repl, s)
    return s

def process(path:str)->bool:
    p = pathlib.Path(path)
    if not p.exists(): return False
    src = read(path)
    out = src

    # 1) limpiar HTML incrustado dentro de <script>
    out = rm_nested_doc_in_script(out)
    # 2) deduplicar scripts por id (preferir hotfix con modo ?id=)
    for sid, prefer in [
        ("p12-hotfix-v4", "const pid=q.get('id')"),
        ("summary-enhancer", None),
        ("max-pages-guard", None),
        ("debug-bootstrap-p12", None),
        ("pe-shim-p12", None),
    ]:
        out = dedupe_by_id(out, sid, prefer)
    # 3) asegurar <span class="views">…</span>
    out = patch_views_span(out)
    # 4) asegurar vista de nota única (?id=)
    out = ensure_single_note_mode(out)
    # 5) si quedaran dos documentos pegados, corta tras el primer </html>
    out = truncate_after_first_html_close(out)

    if out != src:
        bak = p.with_suffix(p.suffix + ".consolidate_v2.bak")
        if not bak.exists():
            shutil.copyfile(p, bak)
        write(path, out)
        print(f"patched: {path} (backup={bak.name})")
    else:
        print(f"OK: {path} sin cambios")
    return True

def main():
    any_done=False
    for f in CANDIDATES:
        try:
            ok=process(f)
            any_done = any_done or ok
        except Exception as e:
            print(f"✗ error en {f}: {e}", file=sys.stderr)
            sys.exit(1)
    if not any_done:
        print("✗ No encontré index.html en backend/static/ ni frontend/")
        sys.exit(2)

if __name__ == "__main__":
    main()
