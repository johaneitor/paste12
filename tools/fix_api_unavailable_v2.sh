#!/usr/bin/env bash
set -euo pipefail
P="backend/__init__.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$P" ]] || { echo "ERROR: falta $P"; exit 1; }
cp -f "$P" "$P.$TS.bak"
echo "[api-unavailable-fix] Backup: $P.$TS.bak"

python - <<'PY'
import io, re, sys, pathlib
p = pathlib.Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# Asegurar import jsonify
if not re.search(r'^\s*from\s+flask\s+import\s+.*\bjsonify\b', s, re.M):
    # si hay from flask import ..., mézclalo; si no, crea uno
    m = re.search(r'^\s*from\s+flask\s+import\s+([^\n]+)$', s, re.M)
    if m:
        imp = m.group(0)
        if 'jsonify' not in m.group(1):
            s = s.replace(imp, imp.rstrip()+", jsonify")
    else:
        # Inserta después de otros imports de flask si existen
        after = re.search(r'^\s*import\s+flask[^\n]*$', s, re.M)
        insert_at = after.end() if after else 0
        s = s[:insert_at] + ("\n" if insert_at else "") + "from flask import jsonify\n" + s[insert_at:]

# Reemplazar cuerpo de _api_unavailable para no referenciar 'e'
pat = re.compile(r'^(?P<i>\s*)def\s+_api_unavailable\s*\(\s*\)\s*:\s*\n(?P<body>(?:\s+.*\n)+)', re.M)
m = pat.search(s)
if m:
    indent = m.group('i')
    new_body = indent + "def _api_unavailable():\n" \
               + indent + "    return jsonify(error=\"API routes not loaded\"), 503\n"
    s = s[:m.start()] + new_body + s[m.end():]
else:
    # si no existe, crearlo al final
    s += "\n\ndef _api_unavailable():\n    return jsonify(error=\"API routes not loaded\"), 503\n"

p.write_text(s, encoding="utf-8")
print("[api-unavailable-fix] aplicado")
PY

python -m py_compile backend/__init__.py && echo "[api-unavailable-fix] py_compile OK"
