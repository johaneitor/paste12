#!/usr/bin/env python3
import re, sys, pathlib, shutil, datetime

P = pathlib.Path("backend/static/index.html")
if not P.exists():
    print("ERROR: no encuentro backend/static/index.html")
    sys.exit(1)

html = P.read_text(encoding="utf-8")
changed = []

# 0) backup reversible
ts = datetime.datetime.utcnow().strftime("%Y%m%d_%H%M%S")
bakdir = pathlib.Path("tools/backups/index"); bakdir.mkdir(parents=True, exist_ok=True)
bak = bakdir / f"index.html.{ts}.bak"
shutil.copy2(P, bak)

# 1) <title> → Paste12
new_title = "<title>Paste12</title>"
html2, n = re.subn(r"(?is)<title>.*?</title>", new_title, html, count=1)
if n:
    html = html2
    changed.append("title")
elif new_title not in html:
    # si no había <title>, lo insertamos dentro de <head>
    html2, n = re.subn(r"(?is)(<head[^>]*>)", r"\1\n" + new_title, html, count=1)
    if n:
        html = html2
        changed.append("title(insert)")

# 2) Header: h1 + tagline debajo
# Reemplazamos el contenido interno de <header>...</header> por nuestra marca y tagline.
header_block = r'''
  <header>
    <h1 class="brand">Paste12</h1>
    <p class="tagline" id="tagline">Reta a un amigo · Dime un secreto · Confiesa algo · Manda un reto · Anónimo o no, tú decides</p>
  </header>
'''.strip()

html2, n = re.subn(r"(?is)<header>.*?</header>", header_block, html, count=1)
if n:
    html = html2
    changed.append("header")
elif "<h1 class=\"brand\">Paste12</h1>" not in html:
    # Si no hay <header> (poco probable), lo inyectamos tras <body>
    html2, n = re.subn(r"(?is)(<body[^>]*>)", r"\1\n" + header_block, html, count=1)
    if n:
        html = html2
        changed.append("header(insert)")

# 3) CSS para .brand/.tagline (si no existen)
css_inject = """
  .brand{margin:0; font-size:clamp(22px,3.4vw,30px)}
  .tagline{margin:6px 0 0; font-size:14px; color:#17323a; font-weight:600; opacity:.9}
"""
if ".tagline" not in html or ".brand" not in html:
    html2, n = re.subn(r"(?is)(<style[^>]*>)", r"\1\n"+css_inject.strip()+"\n", html, count=1)
    if n:
        html = html2
        changed.append("css(tagline)")

# 4) Script liviano para rotar las frases
rotator = r"""
<script>
(function(){
  const el = document.getElementById('tagline');
  if(!el) return;
  const lines = [
    "Reta a un amigo",
    "Dime un secreto",
    "Confiesa algo",
    "Manda un reto",
    "Anónimo o no, tú decides"
  ];
  let i = Math.floor(Math.random()*lines.length);
  function set(){ el.textContent = lines[i]; i = (i+1) % lines.length; }
  set();
  setInterval(set, 5000);
})();
</script>
""".strip()

if "id=\"tagline\"" in html and "setInterval(set, 5000)" not in html:
    # insertamos antes del cierre de </body>
    html2, n = re.subn(r"(?is)</body>", rotator + "\n</body>", html, count=1)
    if n:
        html = html2
        changed.append("js(rotator)")

if not changed:
    print("nada que cambiar (ya estaba aplicado). Backup:", bak)
    sys.exit(0)

P.write_text(html, encoding="utf-8")
print("patched:", ", ".join(changed), "| backup:", bak)
