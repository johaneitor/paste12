#!/usr/bin/env bash
set -euo pipefail
add_shim() {
  local f="$1"; [ -f "$f" ] || return 0
  local bak="${f}.p12_v7_min.bak"; [ -f "$bak" ] || cp -f "$f" "$bak"

  # 0) meta marcador en <head>
  if ! grep -qi 'name="p12-v7"' "$f"; then
    sed -i '0,/<head[^>]*>/s//&\n  <meta name="p12-v7" content="1">/' "$f" || true
  fi

  # 1) inyecta shim antes de </body> si no existe
  if ! grep -q 'id="p12-cohesion-v7"' "$f"; then
    cat >> "$f" <<'EOF'
<script id="p12-cohesion-v7">
(()=>{try{
  const qs=new URLSearchParams(location.search);
  if(qs.get("nosw")==="1" && "serviceWorker" in navigator){
    navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister())).catch(()=>{});
  }
  const $=s=>document.querySelector(s), $$=s=>Array.from(document.querySelectorAll(s));
  const api = {
    json: (u,opts={})=>fetch(u, Object.assign({headers:{"Accept":"application/json"}},opts)),
    post: (u,body,ctype)=>fetch(u,{method:"POST",headers:{"Content-Type":ctype},body}),
  };
  async function publish(text){
    if(!text || text.trim().length<12) throw new Error("text_required");
    // intento JSON primero
    const r = await api.json("/api/notes",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({text})});
    if(r.ok){ return await r.json(); }
    // fallback a x-www-form-urlencoded
    const r2 = await api.post("/api/notes", new URLSearchParams({text}).toString(),"application/x-www-form-urlencoded");
    return await r2.json();
  }
  async function like(id){ const r=await api.post(`/api/notes/${id}/like`,"","text/plain"); return await r.json(); }
  async function view(id){ const r=await api.post(`/api/notes/${id}/view`,"","text/plain"); return await r.json(); }
  async function report(id){ const r=await api.post(`/api/notes/${id}/report`,"","text/plain"); return await r.json(); }
  async function list(url){
    const r=await api.json(url);
    const link=r.headers.get("Link"); let next=null;
    if(link){ const m=/<([^>]+)>\s*;\s*rel="next"/i.exec(link); if(m) next=m[1]; }
    const j=await r.json(); return {items:(j.items||[]), next};
  }
  function card(n){
    const id=n.id, t=(n.text||"").replace(/</g,"&lt;");
    return `<article class="note" data-id="${id}">
      <p class="text">${t}</p>
      <nav class="actions" data-id="${id}">
        <button data-action="like">❤️ <span class="v-like">${n.likes||0}</span></button>
        <button data-action="view">👁️ <span class="v-view">${n.views||0}</span></button>
        <button data-action="report">🚩</button>
        <a data-action="share" href="/?id=${id}" rel="noopener">Compartir</a>
      </nav>
    </article>`;
  }
  async function renderFeed(startUrl){
    const cont = document.getElementById("notes") || (function(){const d=document.createElement("div"); d.id="notes"; document.body.appendChild(d); return d;})();
    let url = startUrl, pages=0;
    const add = async () => {
      const {items,next}=await list(url);
      cont.insertAdjacentHTML("beforeend", items.map(card).join("") || "<p class='empty'>Sin notas</p>");
      url = next || null; pages++;
      const btn = $("#ver-mas") || (function(){const b=document.createElement("button"); b.id="ver-mas"; b.textContent="Ver más"; document.body.appendChild(b); return b;})();
      btn.style.display = url ? "inline-block" : "none";
      if(!btn._bound){ btn._bound=true; btn.addEventListener("click", e=>{ if(url){ add(); } }); }
      // observar vistas (una vez por nota)
      const io = new IntersectionObserver(ents=>{
        ents.forEach(en=>{
          if(en.isIntersecting){
            const a=en.target; const id=a.getAttribute("data-id");
            if(id && !a._viewed){ a._viewed=true; view(id).then(v=>{
              const s=a.querySelector(".v-view"); if(s) s.textContent = (v.views ?? +s.textContent || 0);
            }).catch(()=>{}); }
          }
        });
      },{rootMargin:"0px 0px -40% 0px"});
      $$(".note").forEach(n=>!n._io && (io.observe(n), n._io=io));
    };
    await add();
  }
  // delegación de acciones
  document.addEventListener("click", e=>{
    const a = e.target.closest("[data-action]");
    if(!a) return;
    const act = a.getAttribute("data-action");
    const holder = a.closest("[data-id]"); const id = holder && holder.getAttribute("data-id");
    if(act==="like" && id){ e.preventDefault(); like(id).then(d=>{ const s=holder.querySelector(".v-like"); if(s) s.textContent = d.likes ?? +s.textContent || 0; }).catch(()=>{}); }
    if(act==="view" && id){ e.preventDefault(); view(id).then(d=>{ const s=holder.querySelector(".v-view"); if(s) s.textContent = d.views ?? +s.textContent || 0; }).catch(()=>{}); }
    if(act==="report" && id){ e.preventDefault(); report(id).catch(()=>{}); }
    if(act==="share" && id){ /* dejar el href */ }
  });

  // publicar (si hay form#new-note o textarea#text)
  const form = document.querySelector("form#new-note") || document.body;
  function pickText(){ return (document.getElementById("text") && document.getElementById("text").value) || ""; }
  if(form && !form._p12){
    form._p12 = true;
    form.addEventListener("submit", async (e)=>{
      if(e.target && e.target.matches("form#new-note")) e.preventDefault();
      try{
        const t = pickText(); const r = await publish(t);
        if(r && r.item){ location.href='/?id='+r.item.id+'&nosw=1'; }
      }catch(err){ console.log("publish failed", err); }
    }, true);
  }

  // modo nota única: /?id=NNN
  const noteId = qs.get("id") || qs.get("note");
  if(noteId && /^\d+$/.test(noteId)){
    const ctn = document.getElementById("notes") || document.body;
    fetch(`/api/notes/${noteId}`).then(r=>r.json()).then(j=>{
      if(j && j.ok && j.item){ ctn.innerHTML = card(j.item); }
      else { ctn.innerHTML = "<p>No encontrada</p>"; }
    }).catch(()=>{});
  }else{
    renderFeed("/api/notes?limit=5").catch(()=>{});
  }
}catch(e){ console.log("p12 v7 shim err", e); }})();
</script>
EOF
  fi
  echo "OK: shim v7 mínimo en $f | backup=$(basename "$bak")"
}
[ -f backend/static/index.html ] && add_shim backend/static/index.html || true
[ -f frontend/index.html ] && add_shim frontend/index.html || true
