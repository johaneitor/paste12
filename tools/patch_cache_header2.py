import pathlib, sys
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8").splitlines()

start = None
for i, line in enumerate(s):
    if ("if is_fallback" in line and
        'path in ("/", "/index.html")' in line and
        'method in ("GET","HEAD")' in line):
        start = i
        break

if start is None:
    print("guard not found"); sys.exit(0)

serve = None
for k in range(start, min(start+40, len(s))):
    if "_serve_index_html()" in s[k]:
        serve = k; break
if serve is None:
    print("serve_index line not found"); sys.exit(0)

ret = None
for k in range(serve, min(start+60, len(s))):
    if s[k].lstrip().startswith("return _finish("):
        ret = k; break
if ret is None:
    print("return not found"); sys.exit(0)

already = any("Cache-Control" in s[k] for k in range(serve, ret+1))
if already:
    print("already present"); sys.exit(0)

ret_indent = s[ret][:len(s[ret]) - len(s[ret].lstrip())]
ins = ret_indent + 'headers = list(headers) + [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")]'
s.insert(ret, ins)
p.write_text("\n".join(s) + "\n", encoding="utf-8")
print("injected")
