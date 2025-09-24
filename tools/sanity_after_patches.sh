#!/usr/bin/env bash
set -euo pipefail
python -m py_compile contract_shim.py
python - <<'PY'
import re,sys
p="frontend/index.html"
try:
    s=open(p,"r",encoding="utf-8").read()
    assert 'class="views"' in s, "Falta <span class=\"views\"> en HTML"
    assert 'id="shim-publish-fallback"' in s, "Falta shim publish"
    assert 'id="shim-parsenext-next-body"' in s, "Falta shim parseNext"
except FileNotFoundError:
    s=open("index.html","r",encoding="utf-8").read()
    assert 'class="views"' in s
    assert 'id="shim-publish-fallback"' in s
    assert 'id="shim-parsenext-next-body"' in s
print("OK: sanity HTML + contract_shim")
PY
echo "✓ Sanity ok"
