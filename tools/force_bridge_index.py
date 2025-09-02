import re, sys, pathlib
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")

# Busca el bloque del index amigable
pat = r'(# raíz amigable.*?\n)\s*if\s+is_fallback\s+and\s+path\s+in\s+\("/",\s*"/index\.html"\)\s+and\s+method\s+in\s+\("GET","HEAD"\):'
rep = r'\1if (is_fallback or os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")) and path in ("/","/index.html") and method in ("GET","HEAD"):'

ns, n = re.subn(pat, rep, s, flags=re.MULTILINE)
if n:
    p.write_text(ns, encoding="utf-8")
    print("patched: FORCE_BRIDGE_INDEX soportado en /")
else:
    print("ya estaba parcheado o no se encontró el patrón")
