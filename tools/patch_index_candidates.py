import re, sys, pathlib, textwrap
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")

m = re.search(r"def\s+_serve_index_html\(\):\s*(.*?)\n\s*#|def\s+\w+\(", s, flags=re.S)
if not m:
    print("no encontré _serve_index_html()"); sys.exit(1)

block = m.group(1)

# Cambiamos el orden de 'candidates = [...]'
pat = r"""candidates\s*=\s*\[(?:[^\]]+)\]"""
rep = textwrap.dedent("""\
    candidates = [override] if override else [
        os.path.join(_REPO_DIR, "backend", "static", "index.html"),
        os.path.join(_REPO_DIR, "public", "index.html"),
        os.path.join(_REPO_DIR, "frontend", "index.html"),
        os.path.join(_REPO_DIR, "index.html"),
    ]
""")

new_block, n = re.subn(pat, rep, block)
if n == 0:
    print("no se pudo reordenar candidates (quizá ya está)"); sys.exit(0)

s2 = s[:m.start(1)] + new_block + s[m.end(1):]
p.write_text(s2, encoding="utf-8")
print("patched: candidates en _serve_index_html() ahora prioriza backend/static/index.html")
