#!/usr/bin/env python3
import sys, re, json, pathlib, urllib.request

if len(sys.argv) < 2:
    print("uso: audit_frontend_inline_js.py https://host"); sys.exit(2)
BASE = sys.argv[1].rstrip("/")
def fetch(url):
    with urllib.request.urlopen(url) as r:
        return r.read().decode("utf-8", "ignore")

html = fetch(f"{BASE}/index.html")
# Si /index.html falla, probamos /
if not html.strip():
    html = fetch(f"{BASE}/")

# Extrae <script> inline (sin src=)
scripts = re.findall(r'<script\\b(?![^>]*\\bsrc=)[^>]*>(.*?)</script>', html, re.I|re.S)
print(f"== Inline scripts detectados: {len(scripts)}")

def scan(txt: str):
    hits = {}
    # endpoints
    apis = re.findall(r'(/api/[a-zA-Z0-9_\\-./?=&]+)', txt)
    if apis: hits["api_paths"] = sorted(set(apis))
    # fetch("..."), axios("..."), new Request("...")
    urls = re.findall(r'\\b(fetch|axios|Request)\\s*\\(\\s*[\'"]([^\'"]+)[\'"]', txt)
    if urls: hits["http_calls"] = sorted(set(u for _,u in urls))
    # paginación
    if re.search(r'cursor_(ts|id)', txt, re.I): hits["uses_keyset"] = True
    if re.search(r'offset\\s*=', txt, re.I): hits["uses_offset"] = True
    if re.search(r'X-Next-Cursor', txt, re.I): hits["reads_xnext"] = True
    # like/report antiguos
    if re.search(r'/api/like(\\?|$)', txt): hits["legacy_like"] = True
    if re.search(r'/api/note(\\?|/)', txt): hits["legacy_note"] = True
    return hits

all_hits = []
for i, block in enumerate(scripts, 1):
    h = scan(block)
    print(f"-- script[{i}] --")
    if h:
        print(json.dumps(h, ensure_ascii=False, indent=2))
        all_hits.append(h)
    else:
        print("(sin hallazgos)")

print("\\n== Resumen ==")
agg = {"legacy_like": False, "legacy_note": False, "uses_offset": False, "uses_keyset": False, "reads_xnext": False}
for h in all_hits:
    for k in list(agg):
        if h.get(k): agg[k] = True
print(json.dumps(agg, ensure_ascii=False, indent=2))
if agg["legacy_like"] or agg["legacy_note"] or agg["uses_offset"]:
    print("\\nRecomendación: activar/confirmar shims de compat en backend.")
else:
    print("\\nNo se ven patrones legacy evidentes en JS inline.")
