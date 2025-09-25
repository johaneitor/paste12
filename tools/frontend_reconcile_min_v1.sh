#!/usr/bin/env bash
set -euo pipefail
CID="${1:-ca-pub-XXXXXXXXXXXXXXX}"
HTML="frontend/index.html"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }
cp -f "$HTML" "$HTML.$TS.reconcile.bak"
python - <<PY
import io, re, sys
cid = sys.argv[1]
p = "frontend/index.html"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

# 1) Forzar un único <h1> (mantener el primero, bajar a <h2> los subsiguientes)
def dedup_h1(html: str) -> str:
    out = []
    seen = False
    i = 0
    while True:
        m = re.search(r"(?is)<h1\b[^>]*>(.*?)</h1>", html)
        if not m:
            out.append(html); break
        pre = html[:m.start()]
        body = m.group(0)
        post = html[m.end():]
        if not seen:
            out += [pre, body]
            seen = True
        else:
            # degradar a h2
            body2 = re.sub(r"(?i)</?h1", lambda _: ("<h2" if _.group(0).lower().startswith("<h1") else "</h2"), body)
            out += [pre, body2]
        html = post
        i += 1
        if i>50:  # safety
            out.append(html); break
    return "".join(out)

s = dedup_h1(s)

# 2) Asegurar <span class="views">
if not re.search(r'(?i)<span[^>]*\bclass=["\']?views\b', s):
    s = s.replace("</body>", '<span class="views" style="display:none">0</span>\n</body>') if "</body>" in s.lower() else (s + '\n<span class="views" style="display:none">0</span>\n')

# 3) AdSense meta
meta_pat = re.compile(r'(?i)<meta\s+name=["\']google-adsense-account["\']\s+content=["\']([^"\']+)["\']\s*/?>')
if meta_pat.search(s):
    s = meta_pat.sub(lambda m: m.group(0).replace(m.group(1), cid), s, count=1)
else:
    # insertar en <head>
    if re.search(r'(?i)</head>', s):
        s = re.sub(r'(?i)</head>', f'  <meta name="google-adsense-account" content="{cid}"/>\n</head>', s, count=1)
    else:
        s = f'<head><meta name="google-adsense-account" content="{cid}"/></head>\n{s}'

# 4) AdSense script asíncrono (evitar duplicados)
if not re.search(r'(?i)adsbygoogle\.js\?client=', s):
    tag = f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={cid}" crossorigin="anonymous"></script>'
    if re.search(r'(?i)</head>', s):
        s = re.sub(r'(?i)</head>', tag + "\n</head>", s, count=1)
    else:
        s = tag + "\n" + s

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("OK: index reconciliado")
else:
    print("INFO: index ya estaba OK")
PY "$CID"

echo "[reconcile] listo"
