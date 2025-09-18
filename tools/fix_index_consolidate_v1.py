#!/usr/bin/env python3
import re, sys, pathlib, shutil

CANDIDATES = [pathlib.Path("backend/static/index.html"),
              pathlib.Path("frontend/index.html"),
              pathlib.Path("index.html")]

def norm(s:str)->str:
    return s.replace("\r\n","\n").replace("\r","\n")

def sanitize(html:str)->str:
    html = norm(html)

    # 0) Si hay múltiples <h2 id="tagline-rot">, deja UNO
    html = re.sub(r'((?:<h2[^>]*id=[\'"]tagline-rot[\'"][^>]*>\s*</h2>\s*){2,})',
                  lambda m: re.findall(r'<h2[^>]*id=[\'"]tagline-rot[\'"][^>]*>\s*</h2>', m.group(1), flags=re.I)[0],
                  html, flags=re.I)

    # 1) Mantén SOLO el primer <script id="p12-hotfix-v4"> ... </script>
    blocks = list(re.finditer(r'<script[^>]*id=[\'"]p12-hotfix-v4[\'"][^>]*>.*?</script>', html, flags=re.I|re.S))
    if len(blocks) > 1:
        keep = blocks[0].group(0)
        html = re.sub(r'<script[^>]*id=[\'"]p12-hotfix-v4[\'"][^>]*>.*?</script>',
                      '', html, flags=re.I|re.S)
        html = html.replace('</body>', keep + '\n</body>')

    # 2) Elimina el “mini-cliente” antiguo (busca script con renderList + load())
    def kill_legacy(m):
        body = m.group(0)
        if re.search(r'function\s+renderList\(', body) and re.search(r'\bload\(\)\s*;', body):
            return ''   # suprimir ese bloque
        return body
    html = re.sub(r'<script\b[^>]*>.*?</script>', kill_legacy, html, flags=re.S|re.I)

    # 3) Asegura hoja para ocultar el banner de deploy (idempotente)
    if '#deploy-stamp-banner{display:none' not in html:
        css = '<style>/* hotfix-banner-hide */#deploy-stamp-banner{display:none!important}</style>'
        html = html.replace('</head>', css + '\n</head>')

    # 4) TODO LO QUE ESTÁ *DESPUÉS* de </html> se descarta (causa texto visible)
    i = html.lower().rfind('</html>')
    if i != -1:
        html = html[:i+7]

    # 5) Asegura que el hotfix quede ANTES de </body> (si existe y no está ya)
    if 'id="p12-hotfix-v4"' in html and '</body>' in html:
        # ya está, no tocamos
        pass

    return html

def run_one(p: pathlib.Path):
    if not p.exists(): return False
    raw = p.read_text(encoding='utf-8')
    new = sanitize(raw)
    if new == raw:
        print(f"OK: {p} ya estaba consolidado")
        return False
    bak = p.with_suffix(p.suffix + ".consolidate_v1.bak")
    if not bak.exists():
        shutil.copyfile(p, bak)
    p.write_text(new, encoding='utf-8')
    print(f"patched: {p} | backup={bak.name}")
    return True

touched = False
for path in CANDIDATES:
    touched |= run_one(path)

if not touched:
    sys.exit(0)
