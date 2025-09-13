#!/usr/bin/env bash
set -euo pipefail
stamp="$(date -u +%Y%m%d-%H%M%SZ)"
insert_js() {
  f="$1"
  [ -f "$f" ] || return 0
  # Backup una vez
  bak="${f}.p12_v8.${stamp}.bak"
  cp -f "$f" "$bak"

  # Si ya está inyectado, salir
  if grep -q 'id="p12-mini-client-v8"' "$f"; then
    echo "→ $f ya tiene mini-client v8 (skip) | backup=$(basename "$bak")"
    return 0
  fi

  # Asegura meta marcador seguro (no molesta si ya está)
  if ! grep -qi 'name="p12-safe-shim"' "$f"; then
    awk 'BEGIN{ins=0} {print} /<head[^>]*>/ && !ins { print "<meta name=\"p12-safe-shim\" content=\"1\">"; ins=1 }' "$f" > "$f.__tmp" && mv "$f.__tmp" "$f"
  fi

  JS='
<script id="p12-mini-client-v8">
/* P12 MINI-CLIENT v8 — safe, reversible, idempotente.
   Se activa solo si no existe UI previa. */
(function(){
  const hasApp = !!(document.querySelector("#app,[data-app]") || window.P12App);
  if (hasApp) return;

  // Unregister SW si ?nosw=1
  try{
    const q = new URLSearchParams(location.search);
    if (q.get("nosw")==="1" && "serviceWorker" in navigator){
      navigator.serviceWorker.getRegistrations?.().then(rs => rs.forEach(r=>r.unregister())).catch(()=>{});
    }
  }catch(e){}

  // UI mínima
  const root = document.createElement("div");
  root.id = "p12-app";
  root.style.cssText = "max-width:680px;margin:22px auto;padding:0 12px;font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;line-height:1.35";
  root.innerHTML = `
    <h1 style="font-size:18px;margin:0 0 12px">Paste12 — modo seguro</h1>
    <form id="p12-form" style="display:flex;gap:8px;margin:0 0 10px">
      <input id="p12-input" name="text" required minlength="15" placeholder="Escribe una nota…" style="flex:1;padding:10px;border:1px solid #ccc;border-radius:8px" />
      <button type="submit" style="padding:10px 14px;border:0;border-radius:8px;background:#111;color:#fff;cursor:pointer">Publicar</button>
    </form>
    <div id="p12-feed"></div>
    <div style="margin:12px 0">
      <button id="p12-more" style="padding:10px 14px;border:1px solid #ccc;border-radius:8px;background:#fff;cursor:pointer">Ver más</button>
    </div>
    <meta name="p12-v8" content="1">
  `;
  document.body.appendChild(root);

  const FEED = document.getElementById("p12-feed");
  const BTN_MORE = document.getElementById("p12-more");
  const FORM = document.getElementById("p12-form");
  const INPUT = document.getElementById("p12-input");

  const BASE = location.origin;
  let nextURL = null;
  const viewed = new Set();

  function noteTpl(it){
    const id = it.id;
    const text = (it.text||"").replace(/</g,"&lt;").replace(/>/g,"&gt;");
    const ts = it.timestamp?.replace("T"," ").replace("Z","");
    return `
      <article class="note" data-id="${id}" style="border:1px solid #eee;border-radius:10px;padding:12px;margin:10px 0">
        <div style="white-space:pre-wrap">${text}</div>
        <div style="display:flex;gap:10px;align-items:center;color:#555;margin-top:8px;font-size:13px">
          <span>${ts||""}</span>
          <span>·</span>
          <button class="btn-like" data-id="${id}" style="border:0;background:transparent;color:#06c;cursor:pointer">❤️ <span class="c-like">${it.likes||0}</span></button>
          <button class="btn-share" data-id="${id}" style="border:0;background:transparent;color:#06c;cursor:pointer">Compartir</button>
          <a class="btn-open" href="${BASE}/?id=${id}" style="color:#06c">Abrir</a>
        </div>
      </article>`;
  }

  function setNextFromHeaders(resp){
    const link = resp.headers.get("Link") || "";
    const m = link.match(/<([^>]+)>;\s*rel="next"/i);
    nextURL = m ? m[1] : null;
    return nextURL;
  }

  async function listFirst(){
    const resp = await fetch(\`\${BASE}/api/notes?limit=10\`);
    const data = await resp.json();
    FEED.innerHTML = (data.items||[]).map(noteTpl).join("") || "<p>No hay notas aún.</p>";
    setNextFromHeaders(resp);
    attachViewsOnce();
  }

  async function listMore(){
    if (!nextURL) return;
    const resp = await fetch(nextURL);
    const data = await resp.json();
    const html = (data.items||[]).map(noteTpl).join("");
    FEED.insertAdjacentHTML("beforeend", html);
    setNextFromHeaders(resp);
    attachViewsOnce();
  }

  async function publish(text){
    // 1) JSON
    const j = await fetch(\`\${BASE}/api/notes\`, {
      method:"POST",
      headers:{"Content-Type":"application/json"},
      body: JSON.stringify({text})
    });
    if (j.ok){
      const r = await j.json();
      FEED.insertAdjacentHTML("afterbegin", noteTpl(r.item||{}));
      INPUT.value="";
      attachViewsOnce();
      return true;
    }
    // 2) Fallback FORM
    const f = await fetch(\`\${BASE}/api/notes\`, {
      method:"POST",
      headers:{"Content-Type":"application/x-www-form-urlencoded"},
      body: new URLSearchParams({text})
    });
    if (f.ok){
      const r = await f.json();
      FEED.insertAdjacentHTML("afterbegin", noteTpl(r.item||{}));
      INPUT.value="";
      attachViewsOnce();
      return true;
    }
    return false;
  }

  async function like(id, btn){
    const r = await fetch(\`\${BASE}/api/notes/\${id}/like\`, {method:"POST"});
    const d = await r.json();
    if (d && d.ok){
      const span = btn.querySelector(".c-like");
      if (span) span.textContent = d.likes;
    }
  }

  async function view(id){
    if (viewed.has(id)) return;
    viewed.add(id);
    try{ await fetch(\`\${BASE}/api/notes/\${id}/view\`, {method:"POST"}); }catch(_){}
  }

  function attachViewsOnce(){
    // Dispara view una vez, cuando entra al viewport 70%
    const io = new IntersectionObserver((ents)=>{
      ents.forEach(e=>{
        if (e.isIntersecting){
          const id = e.target.getAttribute("data-id");
          if (id) view(id);
          io.unobserve(e.target);
        }
      });
    }, {threshold:0.7});
    document.querySelectorAll(".note[data-id]").forEach(n=>io.observe(n));
  }

  // Delegación de botones
  document.addEventListener("click", (ev)=>{
    const t = ev.target.closest("button, a");
    if (!t) return;

    // like
    if (t.classList.contains("btn-like")){
      ev.preventDefault();
      const id = t.getAttribute("data-id");
      if (id) like(id, t);
    }

    // compartir
    if (t.classList.contains("btn-share")){
      ev.preventDefault();
      const id = t.getAttribute("data-id");
      const url = \`\${BASE}/?id=\${id}\`;
      if (navigator.share){
        navigator.share({title:"Nota", url}).catch(()=>{});
      } else {
        navigator.clipboard?.writeText(url).catch(()=>{});
        t.textContent = "Copiado ✓"; setTimeout(()=>t.textContent="Compartir", 1200);
      }
    }

    // “Ver más”
    if (t.id === "p12-more"){
      ev.preventDefault();
      listMore();
    }
  });

  // Publicar
  FORM.addEventListener("submit", async (e)=>{
    e.preventDefault();
    const text = INPUT.value.trim();
    if (text.length < 15){ INPUT.focus(); return; }
    await publish(text);
  });

  // Modo nota única si ?id=
  try{
    const q = new URLSearchParams(location.search);
    const id = q.get("id") || q.get("note");
    if (id && /^[0-9]+$/.test(id)){
      // Limpia feed y muestra solo la nota
      const r = await fetch(\`\${BASE}/api/notes/\${id}\`);
      if (r.ok){
        const d = await r.json();
        FEED.innerHTML = noteTpl(d.item||{id, text:"(no encontrada)"});
        BTN_MORE.style.display = "none";
        attachViewsOnce();
      }
    } else {
      listFirst();
    }
  }catch(_){
    listFirst();
  }
})();
</script>'

  # Insertar justo antes de </body>
  # (si no existe </body>, lo añade al final)
  if grep -qi '</body' "$f"; then
    sed -e "s#</body>#$JS\n</body>#I" "$f" > "$f.__inj" || { echo "sed falló en $f"; exit 1; }
    mv -f "$f.__inj" "$f"
  else
    echo "$JS" >> "$f"
  fi
  echo "→ Inyectado mini-client v8 en $f | backup=$(basename "$bak")"
}

edited=0
for p in backend/static/index.html frontend/index.html; do
  [ -f "$p" ] && insert_js "$p" && edited=1 || true
done

if [ "$edited" = "0" ]; then
  echo "✗ No se encontró ningún index.html que tocar."
  exit 2
fi
