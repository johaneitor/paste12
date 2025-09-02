import re, pathlib
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")

# Insertar 'Cache-Control: no-store' entre la línea que llama _serve_index_html()
# y el return _finish(...) dentro del handler de raíz.
rep = r'\1    headers = list(headers) + [("Cache-Control","no-store, no-cache, must-revalidate, max-age=0")]\n\2'

# Intento 1: con el comentario "raíz amigable" presente
pat1 = r'(\n\s*# raíz amigable.*?\n\s*if\s*\(.*?path\s+in\s+\("/","/index\.html"\)\s+and\s+method\s+in\s+\("GET","HEAD"\):\s*\n\s*status,\s*headers,\s*body\s*=\s*_serve_index_html\(\)\s*\n)(\s*return\s+_finish\(start_response,\s*status,\s*headers,\s*body,\s*method\))'
ns, n = re.subn(pat1, rep, s, flags=re.S)

# Intento 2: sin depender del comentario
if n == 0:
    pat2 = r'(\n\s*if\s*\(.*?path\s+in\s+\("/","/index\.html"\)\s+and\s+method\s+in\s+\("GET","HEAD"\):\s*\n\s*status,\s*headers,\s*body\s*=\s*_serve_index_html\(\)\s*\n)(\s*return\s+_finish\(start_response,\s*status,\s*headers,\s*body,\s*method\))'
    ns, n = re.subn(pat2, rep, s, flags=re.S)

if n:
    p.write_text(ns, encoding="utf-8")
    print("patched: root Cache-Control no-store")
else:
    print("pattern not found (quizás ya estaba)")
