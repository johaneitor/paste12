#!/usr/bin/env bash
set -Eeuo pipefail
f="frontend/js/app.js"
[ -f "$f" ] || { echo "❌ No existe $f"; exit 1; }
cp "$f" "$f.bak.$(date +%s)"

python - <<'PY'
import re, time, sys, pathlib
p = pathlib.Path("frontend/js/app.js")
code = p.read_text(encoding="utf-8")

changed = False

# 1) Dedupe estricto dentro del loop for (const n of notes) { … }
pat_loop = re.compile(r'(for\s*\(\s*const\s+n\s+of\s+notes\s*\)\s*\{\s*)', re.S)
if not re.search(r'P12\.renderedIds\.has\s*\(\s*n\.id\s*\)', code):
    code, n = pat_loop.subn(r'\1\n      if (P12.renderedIds.has(n.id)) continue;\n      P12.renderedIds.add(n.id);\n', code, count=1)
    changed |= bool(n)

# 2) Limpiar feed y set cuando page===1
#    Si ya existe un bloque, lo normalizamos; si no, lo inyectamos tras listEl.
pat_clean_block = re.compile(r'if\s*\(\s*page\s*===\s*1\s*\)\s*\{.*?\}', re.S)
norm_clean = "if (page===1){ (document.querySelector('#feed')||document.body).innerHTML=''; P12.renderedIds.clear(); }"
if pat_clean_block.search(code):
    code = pat_clean_block.sub(norm_clean, code)
    changed = True
else:
    pat_listel = re.compile(r"(const\s+listEl\s*=\s*document\.querySelector\([^)]+\)\s*\|\|\s*document\.body\s*;)")
    if pat_listel.search(code) and "P12.renderedIds.clear()" not in code:
        code = pat_listel.sub(r"\1\n    " + norm_clean, code, count=1)
        changed = True

# 3) Infinite scroll sólo si has_more === true; si no, detach
pat_inf = re.compile(r'if\s*\(\s*hasMore\s*\)\s*\{.*?\}', re.S)
repl_inf = """if (hasMore === true) {
      P12.page = page + 1;
      if (window.attachInfiniteScroll) attachInfiniteScroll();
    } else {
      if (window.detachInfiniteScroll) detachInfiniteScroll();
    }"""
if pat_inf.search(code):
    code = pat_inf.sub(repl_inf, code)
    changed = True

if changed:
    p.write_text(code, encoding="utf-8")
    print("✓ app.js parcheado (dedupe + limpieza + infinite scroll seguro)")
else:
    print("ℹ️ No se hicieron cambios (quizá ya estaba aplicado).")
PY

# 4) Cache-bust en index.html para forzar que los clientes bajen el JS nuevo
idx="frontend/index.html"
cp "$idx" "$idx.bak.$(date +%s)"
ts=$(date +%s)
sed -i "s|/js/app.js[^\"']*|/js/app.js?v=$ts|g" "$idx"
sed -i "s|/css/styles.css[^\"']*|/css/styles.css?v=$ts|g" "$idx"
echo "✓ Cache-bust aplicado en index.html"
