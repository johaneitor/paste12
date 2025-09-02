import re, io, sys, pathlib

p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")

# Solo parcheamos dentro de _serve_index_html()
m = re.search(r"(?s)def _serve_index_html\(\):\n(.*?)(?=\n#|\n\w|$)", s)
if not m:
    print("no encontré _serve_index_html()")
    sys.exit(1)

block = m.group(1)

# 1) Cuando sirve un archivo real (usa body.decode(...) y content-type dinámico)
pat1 = r"""return\s+_html\(\s*200\s*,\s*(body\.decode\([^\)]*\))\s*,\s*f"\{ctype\};\s*charset=utf-8"\s*\)"""
rep1 = r"""status, headers, body = _html(200, \1, f"{ctype}; charset=utf-8")
                headers = list(headers) + [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")]
                return status, headers, body"""
block2, n1 = re.subn(pat1, rep1, block)

# 2) Cuando arma el HTML embebido (return _html(200, html))
pat2 = r"""return\s+_html\(\s*200\s*,\s*html\s*\)"""
rep2 = r"""status, headers, body = _html(200, html)
            headers = list(headers) + [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")]
            return status, headers, body"""
block3, n2 = re.subn(pat2, rep2, block2)

if n1==0 and n2==0:
    print("ya estaba parcheado o no hizo match")
else:
    s2 = s[:m.start(1)] + block3 + s[m.end(1):]
    p.write_text(s2, encoding="utf-8")
    print(f"patched: pat1={n1}, pat2={n2}")
