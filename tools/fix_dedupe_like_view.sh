#!/usr/bin/env bash
set -Eeuo pipefail

backup(){ [ -f "$1" ] && cp -f "$1" "$1.bak.$(date +%s)" || true; }

echo "→ Backups"
backup backend/models.py
backup backend/routes.py

# 1) models.py: dejar UNA sola definición de LikeLog y UNA de ViewLog
python - <<'PY'
from pathlib import Path
import re

p = Path("backend/models.py")
s = p.read_text(encoding="utf-8")

# Asegurar que tenemos 'date' si lo usan
s = re.sub(r"from datetime import datetime(?!, date)", "from datetime import datetime, date", s)

def dedupe(src: str, cls: str) -> str:
    # Busca bloques class <Cls>(db.Model): ... hasta próxima class o EOF
    pat = re.compile(rf"(\nclass {cls}\(db\.Model\):[\s\S]*?)(?=\nclass\s|\Z)", re.M)
    blocks = list(pat.finditer(src))
    if len(blocks) <= 1:
        return src
    # Conserva el primer bloque y elimina el resto
    keep = blocks[0].group(1)
    src = pat.sub("", src)  # borra todos
    if keep not in src:
        if not src.endswith("\n"): src += "\n"
        src += keep
    return src

for cls in ("LikeLog", "ViewLog"):
    s = dedupe(s, cls)

p.write_text(s, encoding="utf-8")
print("models.py: deduplicados LikeLog/ViewLog")
PY

# 2) routes.py: normalizar import (sin duplicados)
python - <<'PY'
from pathlib import Path
import re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# Reemplaza la primera línea de import por la correcta
s = re.sub(
    r"from backend\.models import[^\n]+",
    "from backend.models import Note, ReportLog, LikeLog, ViewLog",
    s,
    count=1
)

p.write_text(s, encoding="utf-8")
print("routes.py: import normalizado (Note, ReportLog, LikeLog, ViewLog)")
PY

# 3) create_all seguro
python - <<'PY'
from backend import create_app
from backend.models import db
app = create_app()
with app.app_context():
    db.create_all()
print("create_all() OK")
PY

# 4) restart rápido local (dev)
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
LOG="${PREFIX:-/data/data/com.termux/files/usr}/tmp/paste12_server.log"
mkdir -p "$(dirname "$LOG")"
nohup python - <<'PY' >"$LOG" 2>&1 & disown || true
from backend import create_app
app = create_app()
app.run(host="0.0.0.0", port=8000)
PY
sleep 2

echo "→ Smokes:"
echo -n "health="; curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/api/health
echo -n "notes_get="; curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/api/notes

# 5) commit
git add backend/models.py backend/routes.py
git commit -m "fix(models/routes): deduplicar ViewLog y normalizar imports; esquema estable para likes/vistas únicas" || true
echo "✓ Listo. Sube con: git push origin main"
