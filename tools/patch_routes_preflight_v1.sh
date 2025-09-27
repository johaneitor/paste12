#!/usr/bin/env bash
set -euo pipefail
f="backend/routes.py"
[ -f "$f" ] || { echo "[routes] No existe $f"; exit 1; }
cp -f "$f" "$f.$(date -u +%Y%m%d-%H%M%SZ).bak"

python - <<'PY'
import io, sys, re, pathlib
p = pathlib.Path("backend/routes.py")
t = p.read_text(encoding="utf-8")

# 1) Reemplazar decoradores inexistentes @api_bp.options(...) por route(..., methods=["OPTIONS"])
t = re.sub(r'@api_bp\.options\(([^)]*)\)', r'@api_bp.route(\1, methods=["OPTIONS"])', t)

# 2) Asegurar imports necesarios
if "from flask import" in t:
    if "make_response" not in t:
        t = t.replace("from flask import", "from flask import make_response,")
else:
    t = "from flask import Blueprint, request, jsonify, make_response\n" + t

# 3) Asegurar handler OPTIONS /api/notes con headers CORS
block_notes = '''
@api_bp.route("/api/notes", methods=["OPTIONS"])
def _p12_notes_options():
    resp = make_response("", 204)
    h = resp.headers
    h["Access-Control-Allow-Origin"] = "*"
    h["Access-Control-Allow-Methods"] = "GET, POST, HEAD, OPTIONS"
    h["Access-Control-Allow-Headers"] = "Content-Type"
    h["Access-Control-Max-Age"] = "86400"
    return resp
'''
if "def _p12_notes_options" not in t:
    t += "\n" + block_notes

# 4) Asegurar handler OPTIONS catch-all /api/*
block_any = '''
@api_bp.route("/api/<path:_rest>", methods=["OPTIONS"])
def _p12_any_options(_rest):
    resp = make_response("", 204)
    h = resp.headers
    h["Access-Control-Allow-Origin"] = "*"
    h["Access-Control-Allow-Methods"] = "GET, POST, HEAD, OPTIONS"
    h["Access-Control-Allow-Headers"] = "Content-Type"
    h["Access-Control-Max-Age"] = "86400"
    return resp
'''
if "def _p12_any_options" not in t:
    t += "\n" + block_any

p.write_text(t, encoding="utf-8")
print("[routes] preflight parcheado")
PY

# Compila
python -m py_compile backend/routes.py
echo "[routes] py_compile OK"
