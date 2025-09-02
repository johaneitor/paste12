import re, sys, io
p = "wsgiapp/__init__.py"
s = open(p, 'r', encoding='utf-8').read()
pat = r'''(?m)
(if\s+is_fallback\s+and\s+path\s+in\s+\("/",\s*"/index\.html"\)\s+and\s+method\s+in\s+\("GET","HEAD"\):\s*\n
\s*status,\s*headers,\s*body\s*=\s*_serve_index_html\(\)\s*\n)
(\s*return\s+_finish\(start_response,\s*status,\s*headers,\s*body,\s*method\))
'''
rep = r'''\1    headers = list(headers) + [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")]\n    return _finish(start_response, status, headers, body, method)'''
ns, n = re.subn(pat, rep, s, flags=re.VERBOSE)
if n:
    open(p, 'w', encoding='utf-8').write(ns)
    print("patched")
else:
    print("pattern not found (maybe already patched)")

