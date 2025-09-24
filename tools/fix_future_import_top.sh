#!/usr/bin/env bash
set -euo pipefail

f="backend/models.py"
[[ -f "$f" ]] || { echo "No existe $f"; exit 1; }

python - <<'PY'
import re
from pathlib import Path

p = Path("backend/models.py")
s = p.read_text(encoding="utf-8")

# Capturar docstring inicial si existe
m_doc = re.match(r'^(\s*(?P<doc>("""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'))\s*)', s)
prefix = m_doc.group(0) if m_doc else ""

# Extraer todas las líneas future-import en cualquier parte
future_lines = []
def repl(m):
    line = m.group(0)
    if line not in future_lines:
        future_lines.append(line.strip())
    return ""  # eliminar de su posición actual

body = re.sub(r'^\s*from\s+__future__\s+import\s+[^\n]+?\s*$',
              repl, s[len(prefix):], flags=re.M)

# Si no había ninguno, no tocar
if not future_lines:
    print("No se encontraron future-imports (nada que hacer).")
else:
    # Armar nuevo contenido: [docstring][future imports únicos][resto]
    new = prefix + "".join(fl + "\n" for fl in sorted(set(future_lines))) + body
    p.write_text(new, encoding="utf-8")
    print("Movidos future-imports al inicio de backend/models.py")
PY
