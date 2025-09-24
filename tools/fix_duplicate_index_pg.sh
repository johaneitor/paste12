#!/usr/bin/env bash
set -Eeuo pipefail
FILE="backend/models.py"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="$PREFIX/tmp/paste12_server.log"

# Backup
cp -f "$FILE" "$FILE.bak.$(date +%s)" 2>/dev/null || true

# 1) Eliminar cualquier Index(...) que referencie author_fp (o un Index suelto al final)
python - <<'PY'
from pathlib import Path
import re
p = Path("backend/models.py")
s = p.read_text(encoding="utf-8")

# Quitar líneas Index("ix_notes_author_fp", ...) o cualquier Index(... author_fp ...)
s = re.sub(r'^\s*Index\([^)]*author_fp[^)]*\)\s*\n?', '', s, flags=re.M)

# (Opcional) si quedó doble salto innecesario, compactar
s = re.sub(r'\n{3,}', '\n\n', s)

p.write_text(s, encoding="utf-8")
print("Index(author_fp) explícito eliminado.")
PY

# 2) Validar sintaxis
python -m py_compile backend/models.py || { echo "❌ models.py inválido"; exit 1; }

# 3) Reiniciar servidor local y smokes
pkill -f "python .*run\.py" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "notes_get=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/notes)"
echo "notes_post=$(curl -sS -o /dev/null -w '%{http_code}' \
  -H 'Content-Type: application/json' -d '{\"text\":\"nota idx fix\",\"hours\":24}' \
  http://127.0.0.1:8000/api/notes)"

# 4) Commit & push
git add backend/models.py tools/fix_duplicate_index_pg.sh
git commit -m "fix(models): elimina Index('ix_notes_author_fp'); dejar solo Column(index=True) para evitar duplicados en create_all"
git push origin main || true

echo "Listo. Ahora redeploy en Render."
