#!/usr/bin/env python3
import re, sys, pathlib, shutil

FILES = [pathlib.Path("backend/static/index.html"),
         pathlib.Path("frontend/index.html")]

def patch_views_api(html: str) -> str:
    # Inserta api() dentro del bloque /* view-observer:start */ si falta
    pat = r"(\/\* view-observer:start \*\/\s*\(\)\s*=>\s*\{\s*'use strict'|\/\* view-observer:start \*\/\s*\(function\(\)\{)"
    if not re.search(pat, html):
        return html
    if "const api=" in html or "function api(" in html:
        return html
    def inject(m):
        start = m.start()
        # Busca primera apertura del IIFE tras el marcador
        head = html[:start]
        tail = html[start:]
        # mete const api=...
        ins = "const api=p=> (p.startsWith('/')?p:'/api/'+p);\n    "
        return head + re.sub(r"try\s*\{", "try{\n    " + ins, tail, count=1)
    return re.sub(pat, lambda m: inject(m), html, count=1)

def patch_single_note(html: str) -> str:
    # Dentro del script id="p12-hotfix-v4", reemplazar el arranque por uno que respete ?id=
    # Buscamos la línea de arranque: window.addEventListener('DOMContentLoaded', ()=>{ fetchPage('/api/notes?limit=10'); });
    start_rx = (r"window\.addEventListener\(\s*['\"]DOMContentLoaded['\"]\s*,\s*\(\)\s*=>\s*\{\s*"
                r"fetchPage\([^;]+;\s*\}\s*\);\s*")
    if not re.search(start_rx, html):
        return html
    repl = (
        "window.addEventListener('DOMContentLoaded', ()=>{\n"
        "  const q=new URLSearchParams(location.search);\n"
        "  const pid=q.get('id');\n"
        "  if(pid){\n"
        "    (async()=>{\n"
        "      try{\n"
        "        const r=await fetch(`/api/notes/${encodeURIComponent(pid)}`,{headers:{'Accept':'application/json'},credentials:'include'});\n"
        "        const j=await r.json().catch(()=>({}));\n"
        "        const it=j&&j.item; const root=document.querySelector('#list,.list,[data-feed],#feed')||document.body;\n"
        "        if(it){ root.innerHTML = (function(){const d=document.createElement('div'); d.innerHTML=cardHTML(it); return d.innerHTML;})();\n"
        "                 document.title = `Nota #${it.id} – Paste12`; }\n"
        "        else { root.innerHTML = '<article class=\"note\"><div>(Nota no encontrada)</div></article>'; }\n"
        "        const back=document.createElement('a'); back.href='/'; back.textContent='← Volver al feed';\n"
        "        back.className='btn'; back.style.margin='12px auto'; root.after(back);\n"
        "      }catch(_){}\n"
        "    })();\n"
        "    return; // no cargues el feed\n"
        "  }\n"
        "  fetchPage('/api/notes?limit=10');\n"
        "});"
    )
    return re.sub(start_rx, repl, html, count=1)

def process(p: pathlib.Path):
    if not p.exists(): return False
    src = p.read_text(encoding="utf-8")
    out = patch_views_api(src)
    out = patch_single_note(out)
    if out == src: return False
    bak = p.with_suffix(p.suffix + ".views_share_single.bak")
    if not bak.exists():
        shutil.copyfile(p, bak)
    p.write_text(out, encoding="utf-8")
    print(f"patched {p} | backup={bak.name}")
    return True

changed = False
for f in FILES:
    try: changed = process(f) or changed
    except Exception as e:
        print(f"✗ error parcheando {f}: {e}")
        sys.exit(1)

if not changed:
    print("OK: no hubo nada que cambiar (ya estaba aplicado).")
