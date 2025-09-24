#!/usr/bin/env bash
set -euo pipefail
inject_into() {
  local F="$1"
  [ -f "$F" ] || return 0
  if grep -qi 'id="p12-cohesion-v7"' "$F"; then
    echo "OK: $F ya tiene v7"
    return 0
  fi
  cp "$F" "${F}.v7.bak"
  awk '
    BEGIN{IGNORECASE=1}
    /<\/body>/ && !done {
      print "<script id=\"p12-cohesion-v7\">";
      print "(function(){";
      print "  if(window.__P12_V7_INIT) return; window.__P12_V7_INIT=1;";
      print "  const QS = new URLSearchParams(location.search);";
      print "  if(QS.has(\"nosw\") && navigator.serviceWorker){ navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister())).catch(()=>{}); }";
      print "  const FEED = document.getElementById(\"feed\") || document.querySelector(\"[data-feed]\") || (function(){ const m=document.createElement(\"main\"); m.id=\"feed\"; document.body.appendChild(m); return m; })();";
      print "  const BTN_MORE = document.getElementById(\"load-more\") || (function(){ const b=document.createElement(\"button\"); b.id=\"load-more\"; b.textContent=\"Ver más\"; b.style.display=\"none\"; document.body.appendChild(b); return b; })();";
      print "  let nextHref=null;";
      print "  function getNextFromHeaders(h){ const link=(h.get? h.get(\"Link\"):null)||\"\"; const m=/<([^>]+)>;\\s*rel=\\\"next\\\"/i.exec(link); return m? m[1]:null; }";
      print "  async function apiList(url){ const r=await fetch(url,{credentials:\"include\"}); const j=await r.json(); if(!r.ok) throw new Error(j.error||\"list_fail\"); nextHref=getNextFromHeaders(r.headers)||null; return j.items||[]; }";
      print "  async function apiCreate(text){ text=(text||\"\").trim(); if(text.length<12) throw new Error(\"text_required\");";
      print "    try{ const r=await fetch(\"/api/notes\",{method:\"POST\",headers:{\"Content-Type\":\"application/json\"},body:JSON.stringify({text})}); if(r.ok) return (await r.json()).item;";
      print "    }catch(_){}";
      print "    const fd=new URLSearchParams(); fd.set(\"text\", text);";
      print "    const r2=await fetch(\"/api/notes\",{method:\"POST\",headers:{\"Content-Type\":\"application/x-www-form-urlencoded\"},body:fd.toString()}); if(!r2.ok) throw new Error(\"create_fail\"); return (await r2.json()).item; }";
      print "  async function apiAct(id,act){ const r=await fetch(`/api/notes/${id}/${act}`,{method:\"POST\"}); return r.json(); }";
      print "  function noteHTML(o){ const esc=s=>String(s||\"\").replace(/[&<>]/g,c=>({\"&\":\"&amp;\",\"<\":\"&lt;\",\">\":\"&gt;\"}[c]));";
      print "    return `<article class=\"note\" data-id=\"${o.id}\">`+";
      print "      `<div class=\"text\">${esc(o.text)}</div>`+";
      print "      `<div class=\"meta\"><button class=\"btn-like\" data-act=\"like\">❤️ ${o.likes||0}</button>`+";
      print "      `<button class=\"btn-view\" data-act=\"view\">👁️ ${o.views||0}</button>`+";
      print "      `<button class=\"btn-share\" data-act=\"share\">🔗 Compartir</button>`+";
      print "      `<button class=\"btn-report\" data-act=\"report\">🚩 Reportar</button></div>`+`</article>`;";
      print "  }";
      print "  function appendItems(items){ const frag=document.createDocumentFragment(); items.forEach(o=>{ const d=document.createElement(\"div\"); d.innerHTML=noteHTML(o); frag.appendChild(d.firstElementChild); }); FEED.appendChild(frag); rehookIO(); }";
      print "  FEED.addEventListener(\"click\", async (ev)=>{ const b=ev.target.closest(\"button[data-act]\"); if(!b) return; const a=b.dataset.act; const art=b.closest(\"article.note\"); const id=art?.dataset.id; if(!id) return;";
      print "    if(a===\"share\"){ const u=`${location.origin}/?id=${id}`; navigator.clipboard&&navigator.clipboard.writeText(u).catch(()=>{}); alert(\"Enlace copiado:\\n\"+u); return; }";
      print "    const j=await apiAct(id,a); if(j && art){ const like=art.querySelector(\".btn-like\"); const view=art.querySelector(\".btn-view\"); if(like) like.innerHTML=`❤️ ${j.likes??0}`; if(view) view.innerHTML=`👁️ ${j.views??0}`; }";
      print "  });";
      print "  let IO=null; function rehookIO(){ if(IO) IO.disconnect(); IO=new IntersectionObserver(es=>{ es.forEach(e=>{ const a=e.target; if(e.isIntersecting && !a.__v){ a.__v=1; const id=a.dataset.id; apiAct(id,\"view\").then(j=>{ const v=a.querySelector(\".btn-view\"); if(v) v.innerHTML=`👁️ ${j.views??0}`; }).catch(()=>{}); } }); },{threshold:0.5}); document.querySelectorAll(\"article.note\").forEach(n=>IO.observe(n)); window.__P12_V7_IO=IO; }";
      print "  async function loadFirst(){ const items=await apiList(\"/api/notes?limit=10\"); appendItems(items); BTN_MORE.style.display = nextHref? \"block\":\"none\"; }";
      print "  BTN_MORE.addEventListener(\"click\", async ()=>{ if(!nextHref) return; const items=await apiList(nextHref); appendItems(items); BTN_MORE.style.display = nextHref? \"block\":\"none\"; });";
      print "  // publish (si hay <form id=\"publish\">)"
      print "  const PUB=document.getElementById(\"publish\"); if(PUB){ PUB.addEventListener(\"submit\", async (ev)=>{ ev.preventDefault(); const t=(PUB.querySelector(\"textarea, input[name=text]\")||{}).value||\"\"; try{ const it=await apiCreate(t); FEED.insertAdjacentHTML(\"afterbegin\", noteHTML(it)); rehookIO(); PUB.reset&&PUB.reset(); }catch(e){ alert(\"No se pudo publicar\"); } }); }";
      print "  async function single(){ const sid=QS.get(\"id\")||QS.get(\"note\"); if(!sid) return false; try{ const r=await fetch(`/api/notes/${sid}`); const j=await r.json(); if(!j.ok) return false; document.head.insertAdjacentHTML(\"beforeend\",\"<meta name=\\\"p12-single\\\" content=\\\"1\\\">\"); FEED.innerHTML=\"\"; appendItems([j.item]); const back=document.createElement(\"a\"); back.href=\"/\"; back.textContent=\"← Volver al feed\"; back.style.display=\"inline-block\"; back.style.margin=\"12px 0\"; FEED.prepend(back); BTN_MORE.style.display=\"none\"; return true; }catch(_){ return false; } }";
      print "  (async function(){ if(!(await single())){ await loadFirst(); } })();";
      print "  // Marca visible para verificación"
      print "  const mk=document.createElement(\"div\"); mk.id=\"p12-v7-mark\"; mk.textContent=\"P12 COHESION V7\"; mk.style.position=\"fixed\"; mk.style.bottom=\"-9999px\"; mk.style.fontSize=\"0\"; document.body.appendChild(mk);";
      print "})();";
      print "</script>";
      print "</body>";
      done=1; next;
    }
    { print }
  ' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
  echo "patched: $F (backup: ${F}.v7.bak)"
}
TGTs=()
[ -f backend/static/index.html ] && TGTs+=(backend/static/index.html)
[ -f frontend/index.html ] && TGTs+=(frontend/index.html)
for f in "${TGTs[@]}"; do inject_into "$f"; done
echo "✓ listo"
