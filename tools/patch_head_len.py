import re, pathlib
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")
pat = r"def _finish\(start_response, status, headers, body, method\):\n(.*?)\n\s*start_response\(status, headers\)\n\s*return \[body\]"
rep = (
    "def _finish(start_response, status, headers, body, method):\n"
    "    headers = list(headers) + [(\"X-WSGI-Bridge\", \"1\")]\n"
    "    if method == \"HEAD\":\n"
    "        # Asegurar Content-Length: 0 siempre\n"
    "        has_cl = False\n"
    "        new = []\n"
    "        for k,v in headers:\n"
    "            if k.lower()==\"content-length\":\n"
    "                has_cl = True\n"
    "                new.append((k, \"0\"))\n"
    "            else:\n"
    "                new.append((k, v))\n"
    "        if not has_cl:\n"
    "            new.append((\"Content-Length\",\"0\"))\n"
    "        start_response(status, new)\n"
    "        return [b\"\"]\n"
    "    start_response(status, headers)\n"
    "    return [body]"
)
ns, n = re.subn(pat, rep, s, flags=re.S)
if n:
    p.write_text(ns, encoding="utf-8")
    print("patched _finish(): HEAD -> Content-Length: 0")
else:
    print("ya estaba parcheado o no se encontró patrón")
