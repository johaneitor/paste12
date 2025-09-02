import re, pathlib
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")

# Busca el bloque que maneja "/" ó "/index.html" (GET/HEAD) y llama a _serve_index_html()
pat = r'(\n\s*if\s*\(?.*?path\s+in\s+\("/","/index\.html"\)\s+and\s+method\s+in\s+\("GET","HEAD"\)\)?:\s*\n\s*status,\s*headers,\s*body\s*=\s*_serve_index_html\(\)\s*\n)(\s*return\s+_finish\(\s*start_response\s*,\s*status\s*,\s*headers\s*,\s*body\s*,\s*method\s*\))'
inj = (
    "    # inject Cache-Control no-store en raíz\n"
    "    headers = [(k,v) for (k,v) in headers if k.lower()!=\"cache-control\"] + "
    "[(\"Cache-Control\",\"no-store, no-cache, must-revalidate, max-age=0\")]\n"
)
ns, n = re.subn(pat, r"\1"+inj+r"\2", s, flags=re.S)

# Si no encontró el patrón anterior, no tocamos nada (evita falsos positivos).
if n:
    p.write_text(ns, encoding="utf-8")
    print(f"patched root no-store: {n} lugar(es)")
else:
    print("root branch no encontrada (quizás ya estaba o difiere el formato)")
