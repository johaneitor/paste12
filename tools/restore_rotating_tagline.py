#!/usr/bin/env python3
import re, sys, pathlib, shutil

IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("✗ backend/static/index.html no existe"); sys.exit(2)
html = IDX.read_text(encoding="utf-8")
bak  = IDX.with_suffix(".html.bak")
changed = False

# (A) eliminar cualquier tagline fijo previamente inyectado (dedupe duro)
html2 = re.sub(r'<div\s+id="tagline"[^>]*>.*?</div>', '', html, flags=re.S|re.I)
if html2 != html: changed = True
html = html2

# (B) asegurar un único H2 dentro del <header> como rotador (id="tagline-rot")
#    - si ya hay un <h2 ... id="tagline-rot"> lo dejamos
#    - si hay un <h2> sin id dentro de header, le inyectamos id
#    - si no hay <h2>, lo creamos inmediatamente después del h1.brand
if not re.search(r'<h2[^>]*\bid="tagline-rot"\b', html, flags=re.I):
    # 1) header con h2 => agrega id
    def _inject_id(m):
        header = m.group(0)
        header2, n = re.subn(r'(<h2\b)(?![^>]*\bid=)', r'\1 id="tagline-rot"', header, count=1, flags=re.I)
        if n:
            return header2
        # 2) sin h2: crear tras h1.brand
        return re.sub(
            r'(<h1\b[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>.*?</h1>)',
            r'\1\n  <h2 id="tagline-rot"></h2>',
            header, count=1, flags=re.S|re.I
        )
    html2, n = re.subn(r'(<header\b[^>]*>.*?</header>)', _inject_id, html, flags=re.S|re.I)
    if n:
        if html2 != html: changed = True
        html = html2

# (C) inyectar (si falta) el script rotador, con guard idempotente
if "<!-- TAGLINE-ROTATOR -->" not in html:
    js = r"""
<!-- TAGLINE-ROTATOR -->
<script>
(function(){
  if (window.__taglineRotatorInstalled) return;
  window.__taglineRotatorInstalled = true;

  try {
    var el = document.getElementById('tagline-rot');
    if (!el) return;

    // Frases base (puedes editarlas aquí)
    var phrases = [
      "Reta a un amigo",
      "Dime un secreto",
      "Confiesa algo",
      "Manda un reto",
      "Anónimo o no, tú decides"
    ];

    // Si el H2 ya trae texto (por SSR), úsalo como primer valor
    var initial = (el.textContent || "").trim();
    if (initial && phrases.indexOf(initial) === -1) {
      phrases.unshift(initial);
    }

    var i = 0;
    function tick(){
      el.textContent = phrases[i];
      i = (i + 1) % phrases.length;
    }
    tick();
    // Evitar múltiple timers si el DOM se hidrata dos veces
    if (!el.dataset.rotStarted){
      el.dataset.rotStarted = "1";
      setInterval(tick, 3500);
    }
  } catch (e) {
    // silencio por seguridad
  }
})();
</script>
"""
    # insertar antes de </body>
    html2, n = re.subn(r'</body>', js + '\n</body>', html, count=1, flags=re.I)
    if n:
        html = html2; changed = True

if not changed:
    print("OK: rotador único ya presente"); sys.exit(0)

if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(html, encoding="utf-8")
print("patched: tagline rotativo único (backup .bak)")
