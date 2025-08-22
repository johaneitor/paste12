#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(pwd)"
ROUTES="${REPO_ROOT}/backend/routes.py"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER="http://127.0.0.1:8000"

mkdir -p "$TMPDIR"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)"

echo "➤ Reordenando imports en backend/routes.py"
python - <<'PY'
from pathlib import Path
p = Path("backend/routes.py")
src = p.read_text(encoding="utf-8").splitlines()

# 1) Header (shebang/comentarios/encoding) y docstring
i = 0
header = []
def is_header(l):
    s = l.strip()
    return s=="" or s.startswith("#") or s.startswith("#!") or s.startswith("# -*-")
while i < len(src) and is_header(src[i]):
    header.append(src[i]); i += 1

doc = []
if i < len(src) and src[i].lstrip().startswith(('"""',"'''")):
    q = src[i].lstrip()[:3]
    doc.append(src[i]); i += 1
    while i < len(src):
        doc.append(src[i])
        if src[i].strip().endswith(q):
            i += 1; break

body = src[i:]

# 2) Extraer TODOS los future imports y limpiar imports conflictivos
futures = []
rest = []
for ln in body:
    if ln.startswith("from __future__ import"):
        if ln not in futures:
            futures.append(ln)
    else:
        rest.append(ln)

# Eliminar duplicados de sha256 y Note para reinsertarlos en lugar correcto
rest = [ln for ln in rest if ln.strip() != "from hashlib import sha256"]
rest = [ln for ln in rest if not ln.strip().startswith("from backend.models import Note")]

# 3) Construir salida: header + doc + futures + (línea en blanco) + imports necesarios + resto
out = []
out.extend(header)
out.extend(doc)
out.extend(futures)
if futures: out.append("")  # separación limpia tras los futuros

# Reinsertar imports obligatorios inmediatamente después de los futuros
out.append("from hashlib import sha256")
out.append("from backend.models import Note")

# 4) Escribir
p.write_text("\n".join(out + rest) + "\n", encoding="utf-8")
print("OK: routes.py con futuros al tope y imports reubicados.")
PY

echo "➤ Reinicio limpio"
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1

nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smokes"
curl -sS -o /dev/null -w "health=%{http_code}\n" "$SERVER/api/health"
curl -sS -o /dev/null -w "notes_get=%{http_code}\n" "$SERVER/api/notes"
curl -sS -o /dev/null -w "notes_post=%{http_code}\n" -H "Content-Type: application/json" -d '{"text":"nota ok","hours":24}' "$SERVER/api/notes"

echo "➤ Mapper/columns de Note"
python - <<'PY'
from run import app
from backend.models import Note
with app.app_context():
    print("Note mapped cols:", [c.name for c in Note.__table__.columns])
PY

echo "ℹ️ Log en $LOG (usa: tail -n 160 \"$LOG\")"
