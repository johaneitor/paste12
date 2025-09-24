#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

ROUTES="backend/routes.py"

echo "[+] Backup de routes.py"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)"

# 1) Eliminar definiciones antiguas de /api/notes (decoradores + funciones) para evitar choques
python - "$ROUTES" <<'PY'
import re, sys, io
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# borra bloque decorador+def de /api/notes (GET/POST) completo
pat = r'(?ms)@[\w\.]+\.route\([^)]*["\']/api/notes["\'][^)]*\)\s*def\s+\w+\s*\([^)]*\):.*?(?=^\s*def\s|\Z)'
s2 = re.sub(pat, '', s)

# limpieza de líneas en blanco múltiples
s2 = re.sub(r'\n{3,}', '\n\n', s2)

open(p,'w',encoding='utf-8').write(s2)
print("[OK] Borradas rutas antiguas de /api/notes si existían.")
PY

# 2) Asegurar import de la cápsula (registra las rutas nuevas sobre el mismo blueprint bp)
if ! grep -q 'import backend\.routes_notes' backend/routes.py; then
  echo >> backend/routes.py
  echo 'import backend.routes_notes  # registra /api/notes (capsulado)' >> backend/routes.py
  echo "[+] Añadido import backend.routes_notes"
fi

# 3) Compilación rápida para pillar errores
python -m py_compile backend/*.py backend/**/*.py run.py 2>/dev/null || true

echo "[✓] Cápsulas aplicadas. Reinicia y prueba."
