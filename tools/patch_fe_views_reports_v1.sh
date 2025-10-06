#!/usr/bin/env bash
set -euo pipefail
IDX="backend/static/index.html"
test -f "$IDX" || IDX="static/index.html"
test -f "$IDX" || IDX="public/index.html"
test -f "$IDX" || { echo "ERROR: no encontré index.html"; exit 1; }

# Idempotencia
grep -q '/* p12-fe-ext v1 */' "$IDX" && { echo "Ya aplicado"; exit 0; }

tmp="$(mktemp)"
awk '
/<\/head>/ && !done {
  print "  <script>";
  print "  /* p12-fe-ext v1 */";
  print "  (function(){";
  print "    const seen = new Set();";
  print "    const inflight = new Set();";
  print "    const debounce = (fn,ms)=>{ let t; return (...a)=>{ clearTimeout(t); t=setTimeout(()=>fn(...a),ms); }; };";
  print "    async function postJson(u, body){";
  print "      try {";
  print "        const r = await fetch(u,{method:\"POST\",headers:{\"Content-Type\":\"application/json\"},body: JSON.stringify(body||{})});";
  print "        const ct=(r.headers.get(\"content-type\")||\"\").toLowerCase();";
  print "        const isJson = ct.includes(\"application/json\");";
  print "        return {ok:r.ok,status:r.status,json: isJson? await r.json().catch(()=>null):null};";
  print "      } catch(e){ return {ok:false,status:0,json:null}; }";
  print "    }";
  print "    // VISTAS: una vez por sesión y por nota (al entrar al viewport)";
  print "    window.p12MarkView = async function(id){";
  print "      if(!id || seen.has(id)) return;";
  print "      seen.add(id);";
  print "      await postJson(`/api/notes/${id}/view`, {});";
  print "    }";
  print "    // REPORT: no eliminar hasta que el backend diga removed=true";
  print "    window.p12Report = async function(id, onRemoved){";
  print "      if(!id) return;";
  print "      const key = \"report:\"+id;";
  print "      if(inflight.has(key)) return;";
  print "      inflight.add(key);";
  print "      try {";
  print "        const r = await postJson(`/api/notes/${id}/report`, {});";
  print "        if(r.json && r.json.removed){ onRemoved && onRemoved(); }";
  print "        else { alert(\"Reporte enviado. Se requiere consenso (3) para remover.\"); }";
  print "      } finally { inflight.delete(key); }";
  print "    }";
  print "    // OBSERVER para marcar vistas al entrar al viewport";
  print "    const io = (\"IntersectionObserver\" in window) ? new IntersectionObserver((ents)=>{";
  print "      ents.forEach(e=>{ if(e.isIntersecting){ const id=e.target.getAttribute(\"data-note-id\"); if(id){ window.p12MarkView(id); io.unobserve(e.target); }} });";
  print "    }, {rootMargin:\"0px\", threshold:0.2}) : null;";
  print "    window.p12ObserveNote = function(el){ if(io && el) io.observe(el); }";
  print "  })();";
  print "  </script>";
  done=1;
}
{ print }' "$IDX" > "$tmp" && mv "$tmp" "$IDX"
echo "OK: FE vistas/report (debounce + in-flight) inyectado en $IDX"
