#!/usr/bin/env bash
set -euo pipefail

F="backend/models.py"
if [[ ! -f "$F" ]]; then
  echo "No existe $F"; exit 1
fi

python - <<'PY'
import io, re, sys
from pathlib import Path

p = Path("backend/models.py")
code = p.read_text(encoding="utf-8")

# 1) Asegurar import de sqlalchemy como sa
if "import sqlalchemy as sa" not in code:
    # Inserta tras los primeros imports de flask/sqlalchemy
    lines = code.splitlines()
    ins_at = 0
    for i, L in enumerate(lines[:40]):
        if re.search(r'from\s+flask_sqlalchemy\s+import|from\s+flask\s+import|import\s+flask_sqlalchemy|from\s+backend\s+import', L):
            ins_at = i + 1
    lines.insert(ins_at, "import sqlalchemy as sa")
    code = "\n".join(lines)

# 2) Detectar clase ViewLog
m_cls = re.search(r'class\s+ViewLog\s*\(.*?\):(.+?)(?:\nclass\s|\Z)', code, re.S)
if not m_cls:
    print("WARN: No se encontró class ViewLog; nada que parchear (quizás está en otro archivo).")
else:
    body = m_cls.group(1)
    has_day = re.search(r'\bday\s*=\s*db\.Column\(', body) is not None
    if not has_day:
        # Inserta 'day' después de 'view_date' si existe, o al comienzo del cuerpo
        new_body = body
        m_vd = re.search(r'(view_date\s*=\s*db\.Column\([^\n]+\)\s*\n)', body)
        ins = "    day = db.Column(db.Date, nullable=False, default=sa.func.current_date())\n"
        if m_vd:
            pos = m_vd.end()
            new_body = body[:pos] + ins + body[pos:]
        else:
            new_body = "\n" + ins + body
        # Reemplaza en el código
        code = code[:m_cls.start(1)] + new_body + code[m_cls.end(1):]
        print("OK: añadido ViewLog.day (Date, nullable=False, default=current_date())")
    else:
        print("OK: ViewLog.day ya existe; no cambio.")

p.write_text(code, encoding="utf-8")
PY

git add backend/models.py || true
git commit -m "fix(models): add ViewLog.day (Date, not null, default current_date)" || true
git push origin main
echo "✅ Push hecho. Cuando Render aplique el deploy, probamos /view."
