import re, sys, pathlib, textwrap
P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
changed = []

# 0) asegurar import os
if not re.search(r'^\s*import\s+os\b', s, flags=re.M):
    s = re.sub(r'^(import[^\n]*\n)', r'\1import os\n', s, count=1, flags=re.M)
    changed.append("import os")

# 1) middleware final que fuerza "/" desde el bridge (con no-store y X-Index-Source)
if "def _root_force_mw(" not in s:
    mw_def = r"""

# --- middleware final: fuerza '/' desde el bridge si FORCE_BRIDGE_INDEX está activo ---
def _root_force_mw(inner):
    def _mw(environ, start_response):
        path   = environ.get("PATH_INFO", "") or ""
        method = (environ.get("REQUEST_METHOD", "GET") or "GET").upper()
        _force = os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")
        if _force and path in ("/","/index.html") and method in ("GET","HEAD"):
            status, headers, body = _serve_index_html()
            # Garantizar no-store y marcar fuente
            headers = [(k, v) for (k, v) in headers if k.lower() != "cache-control"]
            headers += [
                ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("X-Index-Source", "bridge"),
            ]
            return _finish(start_response, status, headers, body, method)
        return inner(environ, start_response)
    return _mw
"""
    s += mw_def
    changed.append("inject _root_force_mw")

# 2) envolver app con el middleware final (si no está)
if "app = _root_force_mw(app)" not in s:
    m_last = None
    for m in re.finditer(r'^\s*app\s*=\s*.+$', s, flags=re.M):
        m_last = m
    if m_last:
        s = s[:m_last.end()] + "\napp = _root_force_mw(app)\n" + s[m_last.end():]
    else:
        s += "\napp = _root_force_mw(app)\n"
    changed.append("wrap app with _root_force_mw")

# 3) localizar bloque de _serve_index_html con lookahead hasta próxima def o EOF
m = re.search(r"^def\s+_serve_index_html\(\):\s*(?P<body>.*?)(?=^\s*def\s+\w+\(|\Z)",
              s, flags=re.S | re.M)
if not m:
    print("no encontré _serve_index_html() — nada que parchear dentro del index")
else:
    body = m.group("body")

    # 3a) reordenar candidatos priorizando backend/static/index.html
    def repl_candidates(match):
        return textwrap.dedent("""\
            candidates = [override] if override else [
                os.path.join(_REPO_DIR, "backend", "static", "index.html"),
                os.path.join(_REPO_DIR, "public", "index.html"),
                os.path.join(_REPO_DIR, "frontend", "index.html"),
                os.path.join(_REPO_DIR, "index.html"),
            ]
        """)
    body2, n_cand = re.subn(
        r"""(?m)^\s*candidates\s*=\s*\[(?:[^\]]+)\]""",
        repl_candidates, body, count=1
    )
    if n_cand:
        changed.append("reorder index candidates")
    else:
        body2 = body  # no cambió, seguir igual

    # 3b) asegurar Cache-Control no-store en returns (archivo real + html embebido)
    body3, n1 = re.subn(
        r"""return\s+_html\(\s*200\s*,\s*(body\.decode\([^\)]*\))\s*,\s*f"\{ctype\};\s*charset=utf-8"\s*\)""",
        r"""status, headers, body = _html(200, \1, f"{ctype}; charset=utf-8")
            headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"] + [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")]
            return status, headers, body""",
        body2
    )
    body4, n2 = re.subn(
        r"""return\s+_html\(\s*200\s*,\s*html\s*\)""",
        r"""status, headers, body = _html(200, html)
            headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"] + [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")]
            return status, headers, body""",
        body3
    )
    if n1 or n2:
        changed.append(f"no-store on index returns (file={n1}, inline={n2})")

    # aplicar reemplazo del bloque completo si hubo cambios
    if (body4 != body):
        s = s[:m.start("body")] + body4 + s[m.end("body"):]

if changed:
    P.write_text(s, encoding="utf-8")
    print("patched:", ", ".join(changed))
else:
    print("no changes")
