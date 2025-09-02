import re, pathlib

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

changed = False

# 0) asegurar 'import os' en cabecera
if not re.search(r'^\s*import\s+os\b', s, flags=re.M):
    s = re.sub(r'^(import[^\n]*\n)', r'\1import os\n', s, count=1, flags=re.M)
    changed = True

# 1) localizar def _middleware(...) y la línea de def _app(...) anidada
m = re.search(r'(^def\s+_middleware\s*\(.*?\):\s*\n)(\s*)def\s+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*', s, flags=re.M|re.S)
if not m:
    print("no-match: _middleware/_app")
else:
    indent_app = m.group(2) + "    "  # indent dentro de _app
    # si ya existe nuestro bloque, no lo duplicamos
    probe_span = s[m.end(): m.end()+500]
    if "X-Index-Source" not in probe_span and "FORCE_BRIDGE_INDEX" not in probe_span:
        inject = (
            "\n"
            f"{indent_app}# FORCE_BRIDGE_INDEX: servir '/' desde el bridge\n"
            f"{indent_app}try:\n"
            f"{indent_app}    _force = os.getenv('FORCE_BRIDGE_INDEX','').strip().lower() in ('1','true','yes','on')\n"
            f"{indent_app}except Exception:\n"
            f"{indent_app}    _force = False\n"
            f"{indent_app}if _force:\n"
            f"{indent_app}    _p = environ.get('PATH_INFO','') or ''\n"
            f"{indent_app}    _m = (environ.get('REQUEST_METHOD','GET') or 'GET').upper()\n"
            f"{indent_app}    if _p in ('/','/index.html') and _m in ('GET','HEAD'):\n"
            f"{indent_app}        status, headers, body = _serve_index_html()\n"
            f"{indent_app}        # no-store y marca de fuente\n"
            f"{indent_app}        headers = [(k,v) for (k,v) in headers if k.lower()!='cache-control']\n"
            f"{indent_app}        headers += [\n"
            f"{indent_app}            ('Cache-Control','no-store, no-cache, must-revalidate, max-age=0'),\n"
            f"{indent_app}            ('X-Index-Source','bridge'),\n"
            f"{indent_app}        ]\n"
            f"{indent_app}        return _finish(start_response, status, headers, body, _m)\n"
        )
        s = s[:m.end()] + inject + s[m.end():]
        changed = True

if changed:
    P.write_text(s, encoding="utf-8")
    print("patched: early-return '/' en _app + import os (si faltaba)")
else:
    print("no changes")
