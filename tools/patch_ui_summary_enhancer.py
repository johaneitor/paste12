#!/usr/bin/env python3
import pathlib, re, shutil

IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("ERROR: no existe backend/static/index.html"); exit(2)

s = IDX.read_text(encoding="utf-8")
changed = False

# CSS suave (idempotente)
if "/* summary-enhancer */" not in s:
    css = """
<style>/* summary-enhancer */
.summary-more-btn{font:inherit;font-size:.9em;border:none;background:transparent;color:#0b6;cursor:pointer;padding:0;margin-left:.25rem}
.summary-more-btn:hover{text-decoration:underline}
</style>
"""
    s = s.replace("</head>", css + "\n</head>")
    changed = True

# Script (idempotente)
if "id=\"summary-enhancer\"" not in s:
    js = r"""
<script id="summary-enhancer">
(function(){
  const FEED_SEL = '[data-feed], #feed, .notes, .list, body'; // fallback amplio
  const CARD_SEL = '[data-note-id], .note, .card';
  const TEXT_SEL = 'p, .text, .note-text, [data-text]';
  const MAX = 20;

  function truncate(t, n){ if(!t) return ""; return (t.length<=n)?t:(t.slice(0,n)+'…'); }

  function decorateCard(card){
    if(card.dataset.summaryDecorated==="1") return;
    const tid = card.getAttribute("data-note-id") || card.getAttribute("data-id") || "";
    // encontrar el contenedor de texto más plausible
    const el = card.querySelector(TEXT_SEL);
    if(!el) return;
    // guardar texto completo si no existe
    if(!el.dataset.full){
      el.dataset.full = el.textContent || "";
    }
    // si ya hay summary del backend, úsalo; si no, lo generamos
    const backendSummary = card.getAttribute("data-summary") || el.getAttribute("data-summary");
    const full = el.dataset.full;
    const summary = backendSummary || truncate(full, MAX);

    // si no hace falta ver más, no agregamos botón
    const needMore = full.length > summary.length;
    el.textContent = summary;

    // botón ver más/menos
    let btn = card.querySelector(".summary-more-btn");
    if(!btn && needMore){
      btn = document.createElement("button");
      btn.className = "summary-more-btn";
      btn.type = "button";
      btn.textContent = "Ver más";
      el.insertAdjacentElement("afterend", btn);
      btn.addEventListener("click", (ev)=>{
        const expanded = btn.getAttribute("data-expanded")==="1";
        if(expanded){
          el.textContent = backendSummary || truncate(full, MAX);
          btn.textContent = "Ver más";
          btn.setAttribute("data-expanded","0");
        }else{
          el.textContent = full;
          btn.textContent = "Ver menos";
          btn.setAttribute("data-expanded","1");
        }
      });
    }
    card.dataset.summaryDecorated = "1";
  }

  function scan(){
    const root = document.querySelector(FEED_SEL) || document.body;
    root.querySelectorAll(CARD_SEL).forEach(decorateCard);
  }

  // Primera pasada
  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", scan);
  }else{
    scan();
  }

  // Observer para nuevos items
  const mo = new MutationObserver((muts)=>{
    let need=false;
    for(const m of muts){
      if(m.addedNodes && m.addedNodes.length){ need=true; break; }
    }
    if(need) scan();
  });
  try{
    mo.observe(document.body, {childList:true, subtree:true});
  }catch(e){}
})();
</script>
"""
    s = s.replace("</body>", js + "\n</body>")
    changed = True

if not changed:
    print("OK: UI summary enhancer ya estaba"); exit(0)

bak = IDX.with_suffix(".html.bak")
if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(s, encoding="utf-8")
print("patched: UI summary enhancer + CSS (backup creado)")
