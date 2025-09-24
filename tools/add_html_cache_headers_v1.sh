#!/usr/bin/env bash
set -euo pipefail

FILE="contract_shim.py"
[[ -f "$FILE" ]] || { echo "ERROR: falta $FILE"; exit 1; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="$FILE.$TS.htmlnocache.bak"
cp -f "$FILE" "$BAK"
echo "[nocache] Backup: $BAK"

python - <<'PY'
import io, re
p="contract_shim.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

if "class HtmlNoCacheMiddleware" not in s:
    s += """

class HtmlNoCacheMiddleware:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        headers_holder = []
        def sr(status, headers, exc_info=None):
            headers_holder[:] = headers
            return start_response(status, headers, exc_info)
        body_iter = self.app(environ, sr)

        # content-type puede venir en headers_holder
        ct = None
        for k,v in headers_holder:
            if k.lower()=="content-type":
                ct=v; break
        is_html = ct and ("text/html" in ct.lower())
        if is_html:
            # forzar revalidación de HTML
            new=[]
            have_cc=False
            for k,v in headers_holder:
                if k.lower()=="cache-control":
                    have_cc=True
                    new.append((k,"no-cache, must-revalidate"))
                else:
                    new.append((k,v))
            if not have_cc:
                new.append(("Cache-Control","no-cache, must-revalidate"))
            headers_holder[:] = new
        return body_iter
"""

# envolver "application" si existe
if re.search(r'\\bapplication\\s*=', s):
    if "HtmlNoCacheMiddleware(application)" not in s:
        s = re.sub(r'(\\bapplication\\s*=\\s*[^\\n]+)', r'\\1\napplication = HtmlNoCacheMiddleware(application)', s, count=1)
else:
    # si no existe "application", intentar "app"
    if re.search(r'\\bapp\\s*=', s) and "HtmlNoCacheMiddleware(app)" not in s:
        s = re.sub(r'(\\bapp\\s*=\\s*[^\\n]+)', r'\\1\napp = HtmlNoCacheMiddleware(app)', s, count=1)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[nocache] middleware añadido/activado")
else:
    print("[nocache] ya estaba aplicado")
PY

python -m py_compile contract_shim.py && echo "[nocache] py_compile OK"
echo "Listo."
