#!/usr/bin/env bash
set -euo pipefail
HTML="frontend/index.html"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }
cp -f "$HTML" "$HTML.$TS.bak"
echo "[backup] $HTML.$TS.bak"

python - <<'PY'
import io, re
p="frontend/index.html"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

# 1) unificar endpoint EXACTO
s=re.sub(r'/api/notes/?', '/api/notes', s)

# 2) eliminar subtítulos duplicados obvios (ej. dos h2/h3 iguales consecutivos)
s=re.sub(r'(<h2[^>]*>[^<]+</h2>)\\s*\\1', r'\\1', s, flags=re.I)
s=re.sub(r'(<h3[^>]*>[^<]+</h3>)\\s*\\1', r'\\1', s, flags=re.I)

# 3) insertar/actualizar JS de submit robusto (idempotente)
marker="// p12-submit-v3"
if marker not in s:
    s=s.replace("</body>", f"""
<script>
{marker}
(function() {{
  const API = "/api/notes"; // sin trailing slash
  function toast(msg) {{
    const el = document.querySelector('#p12-error') || (function(){{
      const d=document.createElement('div'); d.id='p12-error'; d.style.color='#b00';
      d.style.marginTop='8px'; document.querySelector('form')?.appendChild(d); return d;
    }})(); el.textContent = msg;
  }}
  async function submitNote(ev) {{
    ev && ev.preventDefault();
    const ta = document.querySelector('textarea'); if (!ta) return;
    const hoursSel = document.querySelector('select'); 
    const hours = parseInt(hoursSel?.value || '12') || 12;
    const payload = {{ text: ta.value.trim(), hours }};
    if (!payload.text) return toast("Escribe algo primero");
    // intento JSON
    try {{
      let r = await fetch(API, {{
        method: "POST", mode: "cors", redirect: "follow", credentials: "omit",
        headers: {{ "Content-Type": "application/json" }},
        body: JSON.stringify(payload)
      }});
      if (r.status===201) {{ ta.value=""; toast(""); return; }}
      if (r.status===405 || r.status===415) throw new Error("retry-form");
      if (!r.ok) throw new Error("HTTP "+r.status);
    }} catch(e) {{
      // fallback FORM
      try {{
        const fd = new FormData(); fd.set("text", payload.text); fd.set("hours", String(hours));
        let r = await fetch(API, {{ method:"POST", body: fd }});
        if (r.status===201) {{ ta.value=""; toast(""); return; }}
        throw new Error("HTTP "+r.status);
      }} catch(e2) {{ toast("Error "+e2.message); }}
    }}
  }}
  document.querySelector('form')?.addEventListener('submit', submitNote);
  document.querySelector('#p12-submit')?.addEventListener('click', submitNote);
}})();
</script>
</body>""")

# 4) asegurar enlaces legales en footer (si faltan)
if re.search(r'href=["\\\']/terms', s, re.I) is None or re.search(r'href=["\\\']/privacy', s, re.I) is None:
    s=re.sub(r'</body>', """
<footer style="margin-top:2rem;opacity:.85">
  <a href="/terms">Términos y Condiciones</a> · <a href="/privacy">Política de Privacidad</a>
</footer>
</body>""", s, flags=re.I)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s); print("[index] parche aplicado")
else:
    print("[index] ya estaba OK")
PY

echo "Hecho."
