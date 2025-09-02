import re, sys, pathlib

p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")

# Asegurar import os al tope
if not re.search(r'^\s*import\s+os\b', s, flags=re.M):
    s = re.sub(r'^(import [^\n]+\n)', r'\1import os\n', s, count=1, flags=re.M)

# Encontrar _middleware(...) y su _app(...)
m = re.search(r"def\s+_middleware\s*\(\s*inner_app.*?\):\s*\n(\s*)def\s+_app\s*\(\s*environ,\s*start_response\s*\):", s)
if not m:
    print("no encontré _middleware/_app"); sys.exit(1)
indent = m.group(1) + "    "  # indent de _app

# Anchor: luego de asignar path/method[/qs]
anchor_pat = (
    r"(\n\s*path\s*=\s*environ\.get\(\"PATH_INFO\".*?\)\s*"
    r"\n\s*method\s*=\s*environ\.get\(\"REQUEST_METHOD\".*?\.upper\(\)\s*"
    r"(?:\n\s*qs\s*=\s*environ\.get\(\"QUERY_STRING\".*?\)\s*)?)"
)

inject = f"""
{indent}# --- FORCE_BRIDGE_INDEX: servir index pastel en "/" incluso si no hay fallback ---
{indent}_force = os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")
{indent}if (_force or is_fallback) and path in ("/", "/index.html") and method in ("GET","HEAD"):
{indent}    status, headers, body = _serve_index_html()
{indent}    # Asegurar Cache-Control no-store y marcar la fuente del index
{indent}    headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"]
{indent}    headers += [("Cache-Control","no-store, no-cache, must-revalidate, max-age=0"),
{indent}               ("X-Index-Source","bridge")]
{indent}    return _finish(start_response, status, headers, body, method)
"""

s2, n = re.subn(anchor_pat, r"\1"+inject, s, flags=re.S)
if n:
    p.write_text(s2, encoding="utf-8")
    print("patched: root '/' servido por bridge + no-store + X-Index-Source")
else:
    print("no se encontró el anchor; quizá ya estaba aplicado")
