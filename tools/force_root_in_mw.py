import re, pathlib

p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")

# 0) asegurar 'import os' en cabecera
if not re.search(r'^\s*import\s+os\b', s, flags=re.M):
    s = re.sub(r'^(import[^\n]*\n)', r'\1import os\n', s, count=1, flags=re.M)

# 1) localizar def _middleware(...) y def _app(...) anidada, e inyectar un early-return para "/"
m = re.search(r'(^def\s+_middleware\s*\(.*?\):\s*\n)(\s*)def\s+_app\s*\(.*?\):', s, flags=re.S|re.M)
if not m:
    print("no-match: _middleware/_app")
else:
    indent = m.group(2) + "    "  # indent dentro de _app
    inject = (
        f"\n{indent}# FORCE_BRIDGE_INDEX: servir '/' desde el bridge\n"
        f"{indent}try:\n"
        f"{indent}    _force = os.getenv('FORCE_BRIDGE_INDEX','').strip().lower() in ('1','true','yes','on')\n"
        f"{indent}except Exception:\n"
        f"{indent}    _force = False\n"
        f"{indent}if _force:\n"
        f"{indent}    _p = environ.get('PATH_INFO','') or ''\n"
        f"{indent}    _m = (environ.get('REQUEST_METHOD','GET') or 'GET').upper()\n"
        f"{indent}    if _p in ('/','/index.html') and _m in ('GET','HEAD'):\n"
        f"{indent}        status, headers, body = _serve_index_html()\n"
        f"{indent}        headers = [(k,v) for (k,v) in headers if k.lower()!='cache-control']\n"
        f"{indent}        headers += [\n"
        f"{indent}            ('Cache-Control','no-store, no-cache, must-revalidate, max-age=0'),\n"
        f"{indent}            ('X-Index-Source','bridge'),\n"
        f"{indent}        ]\n"
        f"{indent}        return _finish(start_response, status, headers, body, _m)\n"
    )
    s = s[:m.end()] + inject + s[m.end():]
    p.write_text(s, encoding="utf-8")
    print("patched: early-return '/' dentro de _app()")
