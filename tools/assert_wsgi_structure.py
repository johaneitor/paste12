#!/usr/bin/env python3
import re, sys, pathlib

W = pathlib.Path("wsgiapp/__init__.py")
S = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

m_app = re.search(r'(?m)^([ ]*)def[ ]+_app\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', S)
assert m_app, "no encontré def _app(environ, start_response)"
app_ws, app_base = m_app.group(1), len(m_app.group(1))
app_start = m_app.end()
# fin por dedent
end = len(S)
for m in re.finditer(r'(?m)^[ ]*\S', S[app_start:]):
    line = S[app_start+m.start():].split("\n",1)[0]
    indent = len(line) - len(line.lstrip(" "))
    if indent <= app_base:
        end = app_start+m.start(); break

body = S[app_start:end].splitlines()
def find_line(prefix: str):
    pat = re.compile(rf'^{re.escape(app_ws)}    {prefix}\s*=')
    for i,l in enumerate(body): 
        if pat.match(l): return i
    return -1

i_path   = find_line("path")
i_method = find_line("method")
i_qs     = find_line("qs")
assert min(i for i in (i_path,i_method,i_qs) if i>=0) >= 0, "faltan asignaciones path/method/qs"

# buscar if OPTIONS
i_opt = -1
pat_if = re.compile(rf'^{re.escape(app_ws)}    if\s+method\s*==\s*["\']OPTIONS["\']\s*and\s*path\.startswith\(["\']/api/["\']\)\s*:\s*$')
for i,l in enumerate(body):
    if pat_if.match(l): i_opt = i; break
assert i_opt >= 0, "no encontré handler OPTIONS"

assert i_opt > max(i_path,i_method,i_qs), "handler OPTIONS aparece antes de path/method/qs"

# return _app dentro de _middleware
m_mw = re.search(r'(?m)^([ ]*)def[ ]+_middleware\([^)]*\):\s*$', S)
assert m_mw, "no encontré def _middleware(...)"
mw_ws, mw_base = m_mw.group(1), len(m_mw.group(1))
mw_start = m_mw.end()
end_mw = len(S)
for m in re.finditer(r'(?m)^[ ]*\S', S[mw_start:]):
    line = S[mw_start+m.start():].split("\n",1)[0]
    indent = len(line) - len(line.lstrip(" "))
    if indent <= mw_base:
        end_mw = mw_start+m.start(); break
mw_body = S[mw_start:end_mw].splitlines()
assert any(l.strip()=="return _app" and (len(l)-len(l.lstrip(" ")))==mw_base+4 for l in mw_body), "faltó 'return _app' dentro de _middleware"

print("OK: estructura WSGI válida (preflight posicionado y return _app)")
